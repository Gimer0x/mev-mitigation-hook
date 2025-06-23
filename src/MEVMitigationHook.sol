// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core-hook/libraries/LPFeeLibrary.sol";

contract MEVMitigationHook is BaseHook {
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    
    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%
    uint24 public constant DYNAMIC_FEE = 15_000; // 1.5%

    mapping(uint256 => uint256) public lastBlockIdSwap;

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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
        uint24 fee = isOppositeDirectionSwap ? getFees() : BASE_FEE;
        lastBlockIdSwap[getPackedKey(tx.origin, key.toId(), params.zeroForOne)] = block.number;
        
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

    function getFees() internal pure  returns (uint24){
        //uint128 gasPrice = uint128(tx.gasprice);

        return DYNAMIC_FEE;
    }
}
