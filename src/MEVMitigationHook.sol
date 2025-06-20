// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract MEVMitigationHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    uint24 constant BASE_FEE = 9_000; // 0.9%
    uint24 constant DYNAMIC_FEE = 36_000; // 3.6%

    mapping(uint256 => uint256) public lastBlockIdSwap;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
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
    
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 oppositeSwapKey = getPackedKey(tx.origin, key.toId(), !params.zeroForOne);

        bool isBothDirectionSwap = lastBlockIdSwap[oppositeSwapKey] == block.number;
        uint24 fee = isBothDirectionSwap ? DYNAMIC_FEE : BASE_FEE;
        lastBlockIdSwap[getPackedKey(tx.origin, key.toId(), params.zeroForOne)] = block.number;
        
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    // This function converts input parameters into one 256-bit slot (gas-saving technique in Solidity). 
    function getPackedKey(address _sender, PoolId _poolId, bool _direction) internal pure returns (uint256) {
        return (uint256(uint160(_sender)) << 96) | (uint256(PoolId.unwrap(_poolId)) & ((1 << 96) - 1)) | (_direction ? 1 : 0);
    }
}
