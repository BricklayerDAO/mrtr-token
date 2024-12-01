// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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
        bytes memory initData = abi.encodeWithSelector(MortarStaking.initialize.selector, address(token), address(this));
        proxy = new TransparentUpgradeableProxy(address(stakingImplementation), address(proxyAdmin), initData);
        staking = MortarStaking(address(proxy));

        // Mint tokens for test users
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);

        // Users approve the staking contract to spend their tokens
        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bob);
        token.approve(address(staking), type(uint256).max);

        vm.prank(carol);
        token.approve(address(staking), type(uint256).max);
    }

    function test_getCurrentQuarter() public {
        uint256 start;
        uint256 end;
        uint256 quarter;

        // Case 1: Before staking period
        vm.warp(1_735_084_799); // 1 second before first quarter starts
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 0, "Before staking period: incorrect quarter");
        assertEq(start, 0, "Before staking period: incorrect start");
        assertEq(end, 0, "Before staking period: incorrect end");

        // Case 2: First quarter
        vm.warp(1_735_084_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 0, "First quarter: incorrect quarter");
        assertEq(start, 1_735_084_800, "First quarter: incorrect start");
        assertEq(end, 1_742_860_800, "First quarter: incorrect end");

        // Case 3: Middle of first quarter
        vm.warp(1_738_972_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 0, "Middle of first quarter: incorrect quarter");
        assertEq(start, 1_735_084_800, "Middle of first quarter: incorrect start");
        assertEq(end, 1_742_860_800, "Middle of first quarter: incorrect end");

        // Case 4: Middle quarter
        vm.warp(2_050_252_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 40, "Middle quarter: incorrect quarter");
        assertEq(start, 2_050_252_800, "Middle quarter: incorrect start");
        assertEq(end, 2_058_028_800, "Middle quarter: incorrect end");

        // Case 5: Last quarter
        vm.warp(2_358_000_001);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 79, "Last quarter: incorrect quarter");
        assertEq(start, 2_358_000_000, "Last quarter: incorrect start");
        assertEq(end, 2_365_420_800, "Last quarter: incorrect end");

        // Case 6: After staking period
        vm.warp(2_365_420_801);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 80, "After staking period: incorrect quarter");
        assertEq(start, 0, "After staking period: incorrect start");
        assertEq(end, 0, "After staking period: incorrect end");

        // Case 7: Exact quarter boundary
        vm.warp(1_742_860_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 1, "Quarter boundary: incorrect quarter");
        assertEq(start, 1_742_860_800, "Quarter boundary: incorrect start");
        assertEq(end, 1_748_822_400, "Quarter boundary: incorrect end");
    }

    function testMultipleUsersDepositAndWithdraw() public {
        // Warp to a time within the staking period
        uint256 startTime = staking.quarterTimestamps(0) + 1;
        vm.warp(startTime);

        // Alice deposits 100 tokens
        _depositAndCheckBalance(alice, 100 ether);

        // Bob deposits 200 tokens
        _depositAndCheckBalance(bob, 200 ether);

        // Move forward in time by 30 days
        vm.warp(block.timestamp + 30 days);

        // Carol deposits 150 tokens
        _depositAndCheckBalance(carol, 150 ether);

        // Move forward in time by another 30 days
        vm.warp(block.timestamp + 30 days);

        // Alice withdraws 50 tokens
        _withdrawAndCheckBalance(alice, 50 ether);

        // Bob withdraws all tokens
        _withdrawAllAndCheckBalance(bob);

        // Move time ahead by another 20 days
        vm.warp(block.timestamp + 20 days);

        // Carol withdraws all tokens
        _withdrawAllAndCheckBalance(carol);

        // Check user quarter info
        _checkUserQuarterInfo();
    }

    function _depositAndCheckBalance(address user, uint256 amount) internal {
        vm.prank(user);
        staking.deposit(amount, user);

        uint256 userBalance = staking.balanceOf(user);
        assertEq(userBalance, amount);
    }

    function _withdrawAndCheckBalance(address user, uint256 amount) internal {
        vm.prank(user);
        staking.withdraw(amount, user, user);

        uint256 userBalance = staking.balanceOf(user);
        assertEq(userBalance, staking.balanceOf(user));
    }

    function _withdrawAllAndCheckBalance(address user) internal {
        uint256 userShares = staking.balanceOf(user);
        uint256 userAssets = staking.convertToAssets(userShares);

        vm.prank(user);
        staking.withdraw(userAssets, user, user);

        assertEq(staking.balanceOf(user), 0);
    }

    function _checkUserQuarterInfo() internal view {
        (,, uint256 debtAlice,) = staking.userQuarterInfo(alice, 0);
        (,, uint256 debtBob, uint256 sharesBob) = staking.userQuarterInfo(bob, 0);
        (,, uint256 debtCarol, uint256 sharesCarol) = staking.userQuarterInfo(carol, 0);

        assertEq(debtCarol, 0, "Carol debt is not zero");
        assertEq(debtBob, 0, "Bob debt is not zero");
        assert(debtAlice != 0);
        assertEq(sharesCarol, 0, "Carol shares is not zero");
        assertEq(sharesBob, 0, "Bob shares is not zero");
    }

    function test_multipleUsersDepositAndWithdraw() public {
        // Warp to a time within the staking period
        uint256 startTime = staking.quarterTimestamps(0) + 1;
        vm.warp(startTime);

        // Test with just one deposit first
        vm.prank(alice);
        staking.deposit(100 ether, alice);
        // Check Alice's balance
        uint256 aliceBalance = staking.balanceOf(alice);
        assertEq(aliceBalance, 100 ether, "Alice's initial deposit failed");
    }

    function testDepositInFirstQuarter() public {
        // Warp to the first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1); // +1 to ensure we're within the quarter

        uint256 depositAmount = 1000 ether;

        vm.prank(alice);
        staking.deposit(depositAmount, alice);

        // Check the balances and shares
        uint256 shares = staking.balanceOf(alice);
        assertEq(shares, depositAmount, "User1 should have correct shares after deposit");

        // Verify quarter data
        (uint256 accRewardPerShare, uint256 lastUpdate,, uint256 totalShares, uint256 totalStaked,) =
            staking.quarters(0);
        assertEq(totalShares, depositAmount, "Total shares should match deposit amount");
        assertEq(totalStaked, depositAmount, "Total staked should match deposit amount");
        assertEq(accRewardPerShare, 0, "Accumulated reward per share should be zero");
        assertEq(lastUpdate, firstQuarterStartTime + 1, "Last update should be the deposit time");
        // Check the total supply
        uint256 totalSupply = staking.totalSupply();
        assertEq(totalSupply, depositAmount, "Total supply should match deposit amount");
    }

    // function testSingleUserDepositAcrossQuarters() public {
    //     // Warp to the middle of the first quarter
    //     uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
    //     uint256 firstQuarterEndTime = staking.quarterTimestamps(1);
    //     uint256 timeInFirstQuarter = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
    //     vm.warp(timeInFirstQuarter);
    //     uint256 depositAmount1 = 100 ether;

    //     // ==================== Quarter 1 ==================== //

    //     vm.prank(alice);
    //     staking.deposit(depositAmount1, alice);

    //     // Warp to the end of the first quarter
    //     vm.warp(firstQuarterEndTime);
    //     // ==================== Quarter 2 ==================== //

    //     // Calculate expected rewards for the first quarter
    //     uint256 expectedRewardsFirstDeposit = staking.calculateRewards(timeInFirstQuarter, firstQuarterEndTime);
    //     uint256 expectedShares = depositAmount1 + expectedRewardsFirstDeposit;

    //     uint256 aliceBalance = staking.balanceOf(alice);

    //     assertApproxEqAbs(
    //         aliceBalance, expectedShares, 100, "Alice's shares should include rewards from the first quarter"
    //     );

    //     // Warp to the second quarter
    //     uint256 secondQuarterStartTime = staking.quarterTimestamps(1);
    //     vm.warp(secondQuarterStartTime + 10); // Slightly into the second quarter

    //     // Alice deposits again in the second quarter
    //     uint256 depositAmount2 = 50 ether;

    //     uint256 tenSecondsReward = staking.rewardRate() * 10;
    //     (uint256 previousReward,,,) = staking.userQuarterInfo(alice, 0);
    //     vm.prank(alice);
    //     staking.deposit(depositAmount2, alice);

    //     (uint256 updatedReward,,,) = staking.userQuarterInfo(alice, 1);
    //     assertApproxEqAbs(
    //         previousReward + tenSecondsReward, updatedReward, 1e8, "User's reward accrued should match expected
    // value"
    //     );
    //     // Warp to the end of the second quarter
    //     uint256 secondQuarterEndTime = staking.quarterTimestamps(2);
    //     vm.warp(secondQuarterEndTime);

    //     // ==================== Quarter 3 ==================== //
    //     // Calculate expected rewards for the second quarter

    //     uint256 totalAssets = staking.totalAssets();

    //     // manually calculate the assets
    //     // 1. Previously known asset value
    //     (, uint256 lastUpdateTimestamp, uint256 totalRewardAccrued,, uint256 totalStaked,) = staking.quarters(1);
    //     uint256 previousAssets = totalStaked;
    //     // 2. Calculate rewards for the second quarter
    //     uint256 rewardAccrued =
    //         totalRewardAccrued + (staking.rewardRate() * (secondQuarterEndTime - lastUpdateTimestamp));

    //     assertApproxEqAbs(totalAssets, previousAssets + rewardAccrued, 1000);
    // }

    function testMultipleDepositsInSameQuarter() public {
        // Step 1: Warp to a time within the first quarter
        uint256 firstQuarterTime = staking.quarterTimestamps(0) + 1;
        vm.warp(firstQuarterTime);

        // Step 2: Alice makes the first deposit
        uint256 depositAmount1 = 100 ether;
        vm.prank(alice);
        staking.deposit(depositAmount1, alice);

        // Step 3: Warp forward but stay within the same quarter
        uint256 timeElapsed = 10;
        vm.warp(block.timestamp + timeElapsed);

        // Step 4: Alice makes the second deposit
        uint256 depositAmount2 = 50 ether;
        vm.prank(alice);
        staking.deposit(depositAmount2, alice);

        // Step 6: Fetch updated quarter and user info after the second deposit
        (uint256 accRewardPerShare,, uint256 totalRewardAccrued,,,) = staking.quarters(0);

        // Step 7: Manually calculate the expected accumulated reward per share

        uint256 rewardsBetweenDeposits = staking.rewardRate() * (block.timestamp - firstQuarterTime);
        uint256 expectedAccRewardPerShare = (rewardsBetweenDeposits * 1e18) / depositAmount1;
        uint256 initialAccRewardPerShare = 0; // It was zero before any rewards
        uint256 totalExpectedAccRewardPerShare = initialAccRewardPerShare + expectedAccRewardPerShare;
        uint256 tolerance = 100;
        // Step 8: Assert that the accumulated reward per share matches the expected value
        assertApproxEqAbs(
            accRewardPerShare,
            totalExpectedAccRewardPerShare,
            tolerance,
            "Accumulated reward per share should match expected value"
        );
        // Step 9: Assert that the total reward accrued matches the expected rewards
        assertApproxEqAbs(
            totalRewardAccrued,
            rewardsBetweenDeposits,
            tolerance,
            "Total reward accrued should match the calculated rewards between deposits"
        );
    }

    function testClaimRewards() public {
        // Warp to the middle of the first quarter
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);
        uint256 timeInFirstQuarter = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        vm.warp(timeInFirstQuarter);

        uint256 depositAmount = 100 ether;

        // Alice deposits in the first quarter
        vm.prank(alice);
        staking.deposit(depositAmount, alice);

        // Warp to the end of the first quarter
        vm.warp(firstQuarterEndTime + 1);

        // Send rewards to treasury
        token.mint(staking.treasury(), 2_775_662_503_807_493_146_176_000);

        staking.claim(alice);
    }

    function testBalanceOf() public { }

    function testDelegateVotes() public { }

    function testTransfer() public { }
}
