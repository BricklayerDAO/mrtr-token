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
    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);

    function setUp() public {
        token = new MockERC20();
        stakingImplementation = new MortarStaking();
        proxyAdmin = new ProxyAdmin(address(this));

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(MortarStaking.initialize.selector, address(token));
        proxy = new TransparentUpgradeableProxy(address(stakingImplementation), address(proxyAdmin), initData);
        staking = MortarStaking(address(proxy));

        // Mint tokens for test users
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);

        // Users approve the staking contract to spend their tokens
        vm.startPrank(alice);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function test_getCurrentQuarter() public {
        // Case 1: Before staking period
        vm.warp(1_735_084_799); // 1 second before first quarter starts
        (uint256 quarter, uint256 start, uint256 end) = staking.getCurrentQuarter();
        assertEq(quarter, 0, "Before staking period: incorrect quarter");
        assertEq(start, 0, "Before staking period: incorrect start");
        assertEq(end, 0, "Before staking period: incorrect end");

        // Case 2: First quarter
        vm.warp(1_735_084_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 1, "First quarter: incorrect quarter");
        assertEq(start, 1_735_084_800, "First quarter: incorrect start");
        assertEq(end, 1_742_860_800, "First quarter: incorrect end");

        // Case 3: Middle of first quarter
        vm.warp(1_738_972_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 1, "Middle of first quarter: incorrect quarter");
        assertEq(start, 1_735_084_800, "Middle of first quarter: incorrect start");
        assertEq(end, 1_742_860_800, "Middle of first quarter: incorrect end");

        // Case 4: Middle quarter
        vm.warp(2_050_252_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 41, "Middle quarter: incorrect quarter");
        assertEq(start, 2_050_252_800, "Middle quarter: incorrect start");
        assertEq(end, 2_058_028_800, "Middle quarter: incorrect end");

        // Case 5: Last quarter
        vm.warp(2_358_000_001);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 80, "Last quarter: incorrect quarter");
        assertEq(start, 2_358_000_000, "Last quarter: incorrect start");
        assertEq(end, 2_365_420_800, "Last quarter: incorrect end");

        // Case 6: After staking period
        vm.warp(2_365_420_801);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 0, "After staking period: incorrect quarter");
        assertEq(start, 0, "After staking period: incorrect start");
        assertEq(end, 0, "After staking period: incorrect end");

        // Case 7: Exact quarter boundary
        vm.warp(1_735_084_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 1, "Quarter boundary: incorrect quarter");
        assertEq(start, 1_735_084_800, "Quarter boundary: incorrect start");
        assertEq(end, 1_742_860_800, "Quarter boundary: incorrect end");
    }

    function test_multipleUsersDepositAndWithdraw() public {
        // Warp to a time within the staking period
        uint256 startTime = staking.quarterTimestamps(0) + 1;
        vm.warp(startTime);

        // Log initial state
        (uint256 currentQuarter, uint256 start, uint256 end) = staking.getCurrentQuarter();

        // Test with just one deposit first
        vm.startPrank(alice);
        staking.deposit(100 ether, alice);
        vm.stopPrank();

        // Check Alice's balance
        uint256 aliceBalance = staking.balanceOf(alice);
        assertEq(aliceBalance, 100 ether, "Alice's initial deposit failed");

        (,,, uint256 shares) = staking.userQuarterInfo(alice, 1);
        // Log state after first deposit
        (currentQuarter, start, end) = staking.getCurrentQuarter();
    }
}
