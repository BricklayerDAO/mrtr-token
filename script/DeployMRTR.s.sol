// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "forge-std/Script.sol";
import { MRTRToken } from "../src/MortarToken.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMRTR is Script {
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public { }

    function run() public {
        vm.broadcast();

        bytes memory data = abi.encodeWithSelector(
            MRTRToken.initialize.selector,
            vm.envAddress("STAKING_POOL"),
            vm.envAddress("DAO_TREASURY"),
            vm.envAddress("PRESALE_POOL"),
            vm.envAddress("ADMIN")
        );
        address implementation = address(new MRTRToken());
        address token = address(new TransparentUpgradeableProxy(implementation, vm.envAddress("ADMIN"), data));

        console.log("MRTR Token deployed at: %s", token);
    }
}
