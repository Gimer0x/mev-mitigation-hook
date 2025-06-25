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

contract MEVMitigationHook is BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    DataFeedsScript public volatilityFeed;
    
    
    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%
    uint24 public constant DYNAMIC_FEE = 10_000; // 1.0%

    uint24 public HIGH_VOLATILITY_FEE = 15_000; // 1.5%
    uint24 public MEDIUM_VOLATILITY_FEE = 10_000; // 1.0%
    uint24 public LOW_VOLATILITY_FEE = 5_000; // 0.5%

    uint24 public fee;

    mapping(uint256 => uint256) public lastBlockIdSwap;

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        fee = BASE_FEE;

        // Link/USD 24hrs Volatility (Sepolia)
        volatilityFeed = DataFeedsScript(
            0x03121C1a9e6b88f56b27aF5cc065ee1FaF3CB4A9
        );
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
    
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 oppositeSwapKey = getPackedKey(tx.origin, key.toId(), !params.zeroForOne);

        bool isOppositeDirectionSwap = lastBlockIdSwap[oppositeSwapKey] == block.number;
        // We update the gas fee if an opposite direction swap in the same block is detected.
        fee = isOppositeDirectionSwap ? getFees() : BASE_FEE;
        lastBlockIdSwap[getPackedKey(tx.origin, key.toId(), params.zeroForOne)] = block.number;
        
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        console2.log(fee);
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

    // Evaluate volatility and gas price
    function getFees() internal returns (uint24){
        //uint128 gasPrice = uint128(tx.gasprice);
        // Low volatility fee
        fee = LOW_VOLATILITY_FEE;

        int256 volatility = getVolatility();

        // This values are experimental for volatility, need to improve.
        if (volatility >= 75 && volatility < 200) {
            // Normal range → enable trading
            fee = MEDIUM_VOLATILITY_FEE;
        }

        if (volatility >= 200) {
            fee = HIGH_VOLATILITY_FEE;
        }

        return fee;
    }

    function getVolatility() public view returns (int256 volatility) {
        (
            /* uint80 roundID */,
            int256 answer,
            /* uint256 startedAt */,
            /* uint256 updatedAt */,
            /* uint80 answeredInRound */
        ) = volatilityFeed.getLatestRoundData();

        uint8 feedDecimals = volatilityFeed.getDecimals();

        volatility = (answer * 100) / int256(10 ** uint256(feedDecimals));
    }

}
