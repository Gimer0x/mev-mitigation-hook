// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "src/utils/MockERC20.sol";

import { console } from "forge-std/console.sol";

contract DeployTokens is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 token0 = new MockERC20("ARST", "ARST", 18, 1_000_000 ether);
        MockERC20 token1 = new MockERC20("USDC", "USDC", 6, 1_000_000 ether);

        console.log("Token 0 deployed at: ", address(token0));
        console.log("Token 1 deployed at: ", address(token1));              

        vm.stopBroadcast();
    }
}