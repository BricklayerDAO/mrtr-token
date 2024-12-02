// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { MRTRToken } from "../src/MortarToken.sol";
import { MortarStaking } from "../src/MortarStaking.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployStaking is Script {
    function setUp() public { }

    function run() public {
        vm.broadcast();

        bytes memory data = abi.encodeWithSelector(
            MortarStaking.initialize.selector, vm.envAddress("MRTR_TOKEN"), vm.envAddress("ADMIN")
        );
        address implementation = address(new MortarStaking());
        address staking = address(new TransparentUpgradeableProxy(implementation, vm.envAddress("ADMIN"), data));

        console.log("Staking deployed at: %s", staking);
    }
}
