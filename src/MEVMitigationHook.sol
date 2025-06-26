// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {DataFeedsScript} from "lib/foundry-chainlink-toolkit/script/feeds/DataFeed.s.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core-hook/libraries/LPFeeLibrary.sol";
import {console2} from "forge-std/Script.sol";
import {StateLibrary} from "v4-core-hook/libraries/StateLibrary.sol";
import {PriceConsumerV3} from "src/utils/PriceConsumerV3.sol";

contract MEVMitigationHook is BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    PriceConsumerV3 public volatilityFeed;

    uint256 txFeeThreshold;
    
    // The default base fees we will charge
    uint24 public constant INITIAL_FEE = 300; // 0.03%
    uint24 public constant BASE_FEE = 5_000; // 0.5%
    uint24 public constant LOWER_PRICE_FEE = 6_000; // 0.5%
    
    uint24 public HIGH_VOLATILITY_FEE = 20_000; // 2.0%
    uint24 public MEDIUM_VOLATILITY_FEE = 15_000; // 1.5%
    uint24 public LOW_VOLATILITY_FEE = 10_000; // 1.0%
    uint24 public fee;

    mapping(uint256 => uint256) public lastBlockIdSwap;
    mapping(uint256 => uint256) public lastBlockPrice;
    mapping(uint256 => uint256) public currentBlock;

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager, address _feedAddress) BaseHook(_poolManager) {
        // Need to find a better value
        fee = INITIAL_FEE;
        txFeeThreshold = 10 gwei;

        // Link/USD 24hrs Volatility (Sepolia)
        volatilityFeed = PriceConsumerV3(_feedAddress);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal pure override returns (bytes4) {
        // Check if the pool has dynamic fee enabled.
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }
    
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        fee = INITIAL_FEE;
        bool direction = params.zeroForOne;
        PoolId poolId = key.toId();
        
        // Check possible frontrunning
        uint256 txPriorityFee = getTxPriorityFee();

        // frontrunning bots usually pay high tips to guarantee inclusion first.
        if (txFeeThreshold < txPriorityFee)
            fee += BASE_FEE;

        // Check possible backrunning
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        

        uint256 priceX96 = getPriceX96(sqrtPriceX96);
        if (!direction) {
            priceX96 = (uint256(1) << 192) / priceX96;
        }

        console2.logBytes32(bytes32(hookData));

        // improve this, consider n blocks?
        // Improving front running resistance of x*y=k market makers
        // https://ethresear.ch/t/improving-front-running-resistance-of-x-y-k-market-makers/1281
        if (currentBlock[uint256(PoolId.unwrap(poolId))] == block.number) {
            if (lastBlockPrice[getPriceKey(block.number, poolId, direction)] > priceX96)
                fee += LOWER_PRICE_FEE;
        } else {
            lastBlockPrice[getPriceKey(block.number, poolId, direction)] = priceX96;
            currentBlock[uint256(PoolId.unwrap(poolId))] = block.number;    
        }
        // Check possible Sandwich attack
        uint256 oppositeSwapKey = getPackedKey(tx.origin, poolId, !direction);
        bool isOppositeDirectionSwap = lastBlockIdSwap[oppositeSwapKey] == block.number;

        // We update the gas fee if an opposite direction swap in the same block is detected.
        // Increase fees when a high volatility period is detected.
        fee += isOppositeDirectionSwap ? getFees() : 0;
        lastBlockIdSwap[getPackedKey(tx.origin, poolId, direction)] = block.number;
        
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        
        return (
            this.beforeSwap.selector, 
            BeforeSwapDeltaLibrary.ZERO_DELTA, 
            feeWithFlag
        );
    }

    // This function converts input parameters into one 256-bit slot (gas-saving technique in Solidity). 
    function getPackedKey(address _sender, PoolId _poolId, bool _direction) internal pure returns (uint256) {
        return (uint256(uint160(_sender)) << 96) | (uint256(PoolId.unwrap(_poolId)) & ((1 << 96) - 1)) | (_direction ? 1 : 0);
    }

    function getPriceKey(uint256 _blockNumber, PoolId _poolId, bool _direction) internal pure returns (uint256) {
        return (_blockNumber << 96) | (uint256(PoolId.unwrap(_poolId)) & ((1 << 96) - 1)) | (_direction ? 1 : 0);
    }

    function getPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256 priceX96) {
        // square the sqrt price to get price with 2^192 scaling
        uint256 ratioX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        // downscale to 2^96 (standard Q96 fixed point)
        priceX96 = ratioX192 >> 96;
    }

    // Evaluate volatility and gas price
    function getFees() internal view returns (uint24){
        uint24 _fee;
        int256 volatility = volatilityFeed.getLatestRoundData();
       
        // This values are experimental for volatility, need to improve.
        if (volatility < 75){
            _fee = LOW_VOLATILITY_FEE;
        } else if (volatility >= 75 && volatility < 200) {
            // Normal range -> increase fee
            _fee = MEDIUM_VOLATILITY_FEE;
        } else if (volatility >= 200) {
            // High range -> max fee
            _fee = HIGH_VOLATILITY_FEE;
        }
        
        return _fee;
    }

    // EIP-1559: London Hardfork, adds a priority fee (tip) to incentivize validators
    function getTxPriorityFee() public view returns (uint256) {
        unchecked {
            return tx.gasprice - block.basefee;
        }
    }

}
