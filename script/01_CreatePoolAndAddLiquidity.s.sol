// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";

contract CreatePoolAndAddLiquidityScript is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////
    Currency arst = Currency.wrap(address(0x18D8dDa8237965d5855E45Fb55969320ba208970));
    uint24 lpFee = 500; // 0.50%
    int24 tickSpacing = 10;
    uint160 startingPrice;

    // --- liquidity position configuration --- //
    // Assume that the first token is ARST
    uint256 public token0Amount = 1000000e18;
    uint256 public token1Amount = 10000e6;

    // range of the position, must be a multiple of tickSpacing
    int24 tickLower;
    int24 tickUpper;
    /////////////////////////////////////

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        bytes memory hookData = new bytes(0);

        startingPrice = encodeSqrtRatioX96(token1Amount, token0Amount);

        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);

        tickLower = ((currentTick - 750 * tickSpacing) / tickSpacing) * tickSpacing;
        tickUpper = ((currentTick + 750 * tickSpacing) / tickSpacing) * tickSpacing;

        if (!(arst == currency0)) {
            (token0Amount, token1Amount) = (token1Amount, token0Amount);
        }
        
        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        // slippage limits
        uint256 amount0Max = token0Amount + 1;
        uint256 amount1Max = token1Amount + 1;

        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, deployerAddress, hookData
        );

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // Initialize Pool
        params[0] = abi.encodeWithSelector(positionManager.initializePool.selector, poolKey, startingPrice, hookData);

        // Mint Liquidity
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 3600
        );

        // If the pool is an ETH pair, native tokens are to be transferred
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;
        
        tokenApprovals();

        // Multicall to atomically create pool & add liquidity
        positionManager.multicall{value: valueToPass}(params);
        vm.stopBroadcast();
    }

    function encodeSqrtRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160 sqrtPriceX96) {
        require(amount0 > 0, "PriceMath: division by zero");
        // Multiply amount1 by 2^192 (left shift by 192) to preserve precision after the square root.
        uint256 ratioX192 = (amount1 << 192) / amount0;
        uint256 sqrtRatio = Math.sqrt(ratioX192);
        require(sqrtRatio <= type(uint160).max, "PriceMath: sqrt overflow");
        sqrtPriceX96 = uint160(sqrtRatio);
    }
}
