// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MortarToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MRTRTokenTest is Test {
    MRTRToken public implementation;
    MRTRToken public token;
    address public owner;
    address public stakingPool;
    address public daoTreasury;
    address public presalePool;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        stakingPool = makeAddr("stakingPool");
        daoTreasury = makeAddr("daoTreasury");
        presalePool = makeAddr("presalePool");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy implementation
        implementation = new MRTRToken();

        // Deploy proxy
        bytes memory initData =
            abi.encodeWithSelector(MRTRToken.initialize.selector, stakingPool, daoTreasury, presalePool);

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Get token instance
        token = MRTRToken(address(proxy));
    }

    function test_InitialSetup() public view {
        // Test token metadata
        assertEq(token.name(), "Mortar");
        assertEq(token.symbol(), "MRTR");
        assertEq(token.decimals(), 18);

        // Test distribution
        assertEq(token.balanceOf(stakingPool), 450_000_000 * 1e18);
        assertEq(token.balanceOf(daoTreasury), 500_000_000 * 1e18);
        assertEq(token.balanceOf(presalePool), 50_000_000 * 1e18);

        assertEq(token.totalSupply(), 1_000_000_000 * 1e18);
    }

    function test_Burn() public {
        // Send user1 some tokens
        vm.prank(stakingPool);
        token.transfer(user1, 1000 * 1e18);

        // Test burn
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(user1)));
        token.burn(user1, 500 * 1e18);
        vm.stopPrank();
        vm.prank(owner);
        token.burn(user1, 500 * 1e18);

        // Verify balance and total supply
        assertEq(token.balanceOf(user1), 500 * 1e18);
        assertEq(token.totalSupply(), 999_999_500 * 1e18);
    }

    function test_DoubleInitializationReverts() public {
        vm.expectRevert();
        token.initialize(stakingPool, daoTreasury, presalePool);
    }
}
