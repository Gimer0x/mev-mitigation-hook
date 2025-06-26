// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {console2} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {MEVMitigationHook} from "../src/MEVMitigationHook.sol";
import {PriceConsumerV3} from "../src/utils/PriceConsumerV3.sol";

/// @notice Mines the address and deploys the MEVMitigation.sol Hook contract
contract DeployHookScript is BaseScript {
    
    error HookDeploymentFailed();

    function run() public {
        // hook contracts must have specific flags encoded in the address

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_INITIALIZE_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(MEVMitigationHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        PriceConsumerV3 _consumer = new PriceConsumerV3(0x03121C1a9e6b88f56b27aF5cc065ee1FaF3CB4A9);
        MEVMitigationHook hook = new MEVMitigationHook{salt: salt}(poolManager, address(_consumer));
        vm.stopBroadcast();

        require(address(hook) == hookAddress, HookDeploymentFailed());
        console2.log("Hook Address: ", hookAddress);
    }
}
