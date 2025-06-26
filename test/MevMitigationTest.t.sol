// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {LPFeeLibrary} from "v4-core-hook/libraries/LPFeeLibrary.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";
import {MEVMitigationHook} from "../src/MEVMitigationHook.sol";
import {MockV3Aggregator} from "./utils/MockV3Aggregator.sol";
import {PriceConsumerV3} from "../src/utils/PriceConsumerV3.sol";

contract MevMitigationTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    uint24 public constant INITIAL_FEE = 300; // 0.03%
    uint24 public constant BASE_FEE = 5_000; // 0.5%
    uint24 public constant LOWER_PRICE_FEE = 6_000; // 0.6%

    uint24 public HIGH_VOLATILITY_FEE = 20_000; // 2.0%
    uint24 public MEDIUM_VOLATILITY_FEE = 15_000; // 1.5%
    uint24 public LOW_VOLATILITY_FEE = 10_000; // 1.0%
    
    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    MockV3Aggregator public oracle;
    PriceConsumerV3 public consumer;

    MEVMitigationHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();
        oracle = new MockV3Aggregator(5, 89194);

        consumer = new PriceConsumerV3(
            address(oracle)
        );
        
        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_INITIALIZE_FLAG
            )
        );
        // Optionally set the gas price
        vm.txGasPrice(10 gwei);
        deployCodeTo("MEVMitigationHook.sol:MEVMitigationHook", abi.encode(poolManager, address(consumer)), flags);
        hook = MEVMitigationHook(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 10000e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function test_initialFee() view public {
        (,,, uint24 fee) = poolManager.getSlot0(poolId);
        assertEq(fee, 0);
    }

    function testFrontRunningFees() public {
        // positions were created in setup()
        assertEq(hook.fee(), INITIAL_FEE);
        
        // Perform a test swap //
        uint256 amountIn = 1e18;
        // Execute this transaction at a higher gas price.
        vm.txGasPrice(12 gwei);
        address sender = 0xDa058764580d50AA1cfdae93430583cd4CdFc98a;
        
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // This is Very bad, only for testing purposes.
            zeroForOne: true,
            poolKey: poolKey,
            hookData: abi.encode(sender),
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        assertEq(hook.fee(), INITIAL_FEE + BASE_FEE);
    }

    function testBackRunningMitigation() public {
        // positions were created in setup()
        assertEq(hook.fee(), INITIAL_FEE);
        
        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        vm.startPrank(alice);
        swapRouter.swapExactTokensForTokens({
            amountIn: 2,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(hook.fee(), INITIAL_FEE + LOWER_PRICE_FEE);
    }

    function testSandwichMitigation() public {
        // positions were created in setup()
        assertEq(hook.fee(), INITIAL_FEE);
        
        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        assertEq(hook.fee(), INITIAL_FEE);
        
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: false,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(hook.fee(), INITIAL_FEE + MEDIUM_VOLATILITY_FEE);
    }
}
