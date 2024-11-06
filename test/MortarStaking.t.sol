// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/MortarStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MortarStakingTesting is Test {
    MortarStaking public stakingImplementation;
    MortarStaking public staking;
    MockERC20 public token;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    function setUp() public {
        token = new MockERC20();
        stakingImplementation = new MortarStaking();
        proxyAdmin = new ProxyAdmin(address(this));
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(MortarStaking.initialize.selector, address(token));
        proxy = new TransparentUpgradeableProxy(address(stakingImplementation), address(proxyAdmin), initData);
        staking = MortarStaking(address(proxy));
    }

    function test_getCurrentQuarter_BeforeStakingPeriod() public {
        vm.warp(1_735_084_799); // 1 second before first quarter starts

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();
        assertEq(quarter, -1);
        assertEq(start, 0);
        assertEq(end, 0);
    }

    function test_getCurrentQuarter_FirstQuarter() public {
        vm.warp(1_735_084_800);

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, 0);
        assertEq(start, 1_735_084_800);
        assertEq(end, 1_742_860_800);
    }

    function test_getCurrentQuarter_MiddleOfFirstQuarter() public {
        vm.warp(1_738_972_800);

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, 1);
        assertEq(start, 1_735_084_800);
        assertEq(end, 1_742_860_800);
    }

    function test_getCurrentQuarter_LastQuarter() public {
        vm.warp(2_358_000_001); 

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, 80);
        assertEq(start, 2_358_000_000);
        assertEq(end, 2_365_420_800);
    }

    function test_getCurrentQuarter_AfterStakingPeriod() public {
        vm.warp(2_365_420_801); 

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, -1);
        assertEq(start, 0);
        assertEq(end, 0);
    }

    function test_getCurrentQuarter_ExactQuarterBoundary() public {
        vm.warp(1_735_084_800); // Exact end of Q1/start of Q2

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, 0);
        assertEq(start, 1_735_084_800);
        assertEq(end, 1_742_860_800);
    }

    function test_getCurrentQuarter_MiddleQuarter() public {
        vm.warp(2_050_252_800);

        (int256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        assertEq(quarter, 40);
        assertEq(start, 2_042_832_000);
        assertEq(end, 2_050_252_800);
    }
}
