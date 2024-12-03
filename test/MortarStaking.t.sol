// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { MortarStaking } from "../src/MortarStaking.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MortarStakingTesting is Test {
    MortarStaking public staking;
    MockERC20 public token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    uint256 quarterLength = 81;

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Minted(address indexed user, uint256 shares, uint256 assets);

    function setUp() public {
        token = new MockERC20();
        vm.label(address(token), "token");

        address stakingImplementation = address(new MortarStaking());
        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(MortarStaking.initialize.selector, address(token), address(this));
        address proxy = address(new TransparentUpgradeableProxy(stakingImplementation, address(this), initData));
        staking = MortarStaking(proxy);
        vm.label(address(staking), "staking");
        vm.label(staking.treasury(), "treasury");

        // Mint tokens for test users
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);

        // Send rewards to treasury
        token.mint(staking.treasury(), 450_000_000 ether);

        // Users approve the staking contract to spend their tokens
        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);

        vm.prank(bob);
        token.approve(address(staking), type(uint256).max);

        vm.prank(carol);
        token.approve(address(staking), type(uint256).max);
    }

    function testGetCurrentQuarter() public {
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
        vm.warp(2_043_100_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 39, "Middle quarter: incorrect quarter");
        assertEq(start, 2_043_100_800, "Middle quarter: incorrect start");
        assertEq(end, 2_050_617_600, "Middle quarter: incorrect end");

        // Case 5: Last quarter
        vm.warp(2_358_720_001);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 79, "Last quarter: incorrect quarter");
        assertEq(start, 2_358_720_000, "Last quarter: incorrect start");
        assertEq(end, 2_366_236_800, "Last quarter: incorrect end");

        // Case 6: After staking period
        vm.warp(2_366_236_801);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 80, "After staking period: incorrect quarter");
        assertEq(start, 0, "After staking period: incorrect start");
        assertEq(end, 0, "After staking period: incorrect end");

        // Case 7: Exact quarter boundary
        vm.warp(1_742_860_800);
        (quarter, start, end) = staking.getCurrentQuarter();
        assertEq(quarter, 1, "Quarter boundary: incorrect quarter");
        assertEq(start, 1_742_860_800, "Quarter boundary: incorrect start");
        assertEq(end, 1_750_723_200, "Quarter boundary: incorrect end");
    }

    function testMintInFirstQuarter() public {
        // Warp to the first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1); // +1 to ensure we're within the quarter

        uint256 mintAmount = 1000 ether;

        vm.prank(alice);
        staking.mint(mintAmount, alice);

        // Expected calculations
        uint256 expectedShares = mintAmount;
        uint256 expectedRewards = 0;
        uint256 expectedDebt = 0;
        uint256 expectedLastUpdate = firstQuarterStartTime + 1;

        // Assert user data
        assertUserData(alice, 0, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate);

        // Assert quarter data
        uint256 expectedAPS = 0;
        uint256 expectedTotalShares = expectedShares;
        uint256 expectedTotalStaked = mintAmount;
        uint256 expectedGenerated = 0;

        assertQuarterData(0, expectedAPS, expectedTotalShares, expectedTotalStaked, expectedGenerated);
    }

    function testDepositInFirstQuarter() public {
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 depositAmount = 1000 ether;

        vm.warp(firstQuarterStartTime); // Warp to valid staking period
        vm.prank(alice);
        staking.deposit(depositAmount, alice);

        // Expected calculations
        uint256 expectedShares = depositAmount;
        uint256 expectedRewards = 0;
        uint256 expectedDebt = 0;
        uint256 expectedLastUpdate = firstQuarterStartTime;

        // Assert user data
        assertUserData(alice, 0, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate);

        // Assert quarter data
        uint256 expectedAPS = 0;
        uint256 expectedTotalShares = depositAmount;
        uint256 expectedTotalStaked = depositAmount;
        uint256 expectedGenerated = 0;

        assertQuarterData(0, expectedAPS, expectedTotalShares, expectedTotalStaked, expectedGenerated);
    }

    function testMultipleUsersDepositMultipleQuarters() public {
        // Warp to the middle of the first quarter

        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);
        uint256 timeInFirstQuarter = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;

        // Alice and Bob deposit at different times
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at (quarterTimestamps[1]/2)
        vm.warp(timeInFirstQuarter);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at (quarterTimestamps[1]/2) + 20, i.e., 20 seconds after alice
        uint256 bobDepositTimestamp = timeInFirstQuarter + 20;
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        // Calculate rewards generated during each period
        // Expected value calculation of accumulated reward per share
        uint256 calculatedAccRps =
            (staking.rewardRate() * (bobDepositTimestamp - timeInFirstQuarter) * 1e18) / (aliceDepositAmount);
        uint256 calculatedBobRewardDebt = (calculatedAccRps * bobDepositAmount) / 1e18;
        assertQuarterData(
            0, calculatedAccRps, (aliceDepositAmount + bobDepositAmount), (aliceDepositAmount + bobDepositAmount), 0
        );
        assertUserData(bob, 0, bobDepositAmount, 0, calculatedBobRewardDebt, bobDepositTimestamp);

        // Warp to last quarter and Alice deposits again
        uint256 lastQuarterStartTime = staking.quarterTimestamps(quarterLength - 2);

        // Alice deposit 100 ether
        vm.warp(lastQuarterStartTime);
        vm.prank(alice);
        staking.deposit(100 ether, alice);

        // Expected calculation of total shares for Quarter 0
        uint256 sharesInQuarter1 = aliceDepositAmount + bobDepositAmount;
        uint256 rewardsAfterBobDeposit = staking.rewardRate() * (firstQuarterEndTime - bobDepositTimestamp);
        calculatedAccRps += (rewardsAfterBobDeposit * 1e18) / sharesInQuarter1;
        uint256 totalRewardsQ0 = staking.rewardRate() * (firstQuarterEndTime - timeInFirstQuarter);

        // Assert quarter 0 data with expected calculations
        assertQuarterData(
            0,
            calculatedAccRps,
            (aliceDepositAmount + bobDepositAmount),
            (aliceDepositAmount + bobDepositAmount),
            totalRewardsQ0
        );
        // Assert user data for Alice and last quarter ( = 4)
        assertUserData(alice, quarterLength - 2, staking.balanceOf(alice), 0, 0, lastQuarterStartTime);
        assertQuarterData(quarterLength - 2, 0, staking.totalSupply(), staking.totalAssets(), 0);
        assert(staking.totalSupply() > staking.balanceOf(alice) + staking.balanceOf(bob));
    }

    function testMultipleUsersMintMultipleQuarters() public {
        // Warp to the middle of the first quarter
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);
        uint256 timeInFirstQuarter = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;

        // Alice and Bob mint at different times
        uint256 aliceMintAmount = 100 ether;
        uint256 bobMintAmount = 200 ether;

        // Alice mints at timeInFirstQuarter
        vm.warp(timeInFirstQuarter);
        vm.prank(alice);
        staking.mint(aliceMintAmount, alice);

        // Bob mints 20 seconds after Alice
        uint256 bobMintTimestamp = timeInFirstQuarter + 20;
        vm.warp(bobMintTimestamp);
        vm.prank(bob);
        staking.mint(bobMintAmount, bob);

        // Calculate rewards generated during each period
        uint256 rewardsBetweenMints = staking.rewardRate() * (bobMintTimestamp - timeInFirstQuarter);
        uint256 calculatedAccRps = (rewardsBetweenMints * 1e18) / aliceMintAmount;
        uint256 calculatedBobRewardDebt = (calculatedAccRps * bobMintAmount) / 1e18;

        // Assert quarter data
        assertQuarterData(
            0,
            calculatedAccRps,
            (aliceMintAmount + bobMintAmount),
            staking.convertToAssets(aliceMintAmount + bobMintAmount),
            0
        );

        // Assert Bob's user data
        assertUserData(bob, 0, bobMintAmount, 0, calculatedBobRewardDebt, bobMintTimestamp);

        // Warp to the last quarter and Alice mints again
        uint256 lastQuarterIndex = quarterLength - 2;
        uint256 lastQuarterStartTime = staking.quarterTimestamps(lastQuarterIndex);
        vm.warp(lastQuarterStartTime);
        vm.prank(alice);
        staking.mint(100 ether, alice);

        // Expected calculation of total shares for Quarter 0
        uint256 sharesInQuarter1 = aliceMintAmount + bobMintAmount;
        uint256 rewardsAfterBobMint = staking.rewardRate() * (firstQuarterEndTime - bobMintTimestamp);
        calculatedAccRps += (rewardsAfterBobMint * 1e18) / sharesInQuarter1;
        uint256 totalRewardsQ0 = staking.rewardRate() * (firstQuarterEndTime - timeInFirstQuarter);

        // Assert quarter 0 data with expected calculations
        assertQuarterData(
            0, calculatedAccRps, sharesInQuarter1, staking.convertToAssets(sharesInQuarter1), totalRewardsQ0
        );

        // Assert Alice's user data in the last quarter
        uint256 aliceTotalShares = staking.balanceOf(alice);
        assertUserData(alice, lastQuarterIndex, aliceTotalShares, 0, 0, lastQuarterStartTime);

        // Assert quarter data for the last quarter
        assertQuarterData(lastQuarterIndex, 0, staking.totalSupply(), staking.totalAssets(), 0);
    }

    function testMultipleDepositsInSameQuarter() public {
        // Warp to a time within the first quarter
        uint256 firstQuarterTime = staking.quarterTimestamps(0) + 1;
        vm.warp(firstQuarterTime);

        // Alice's first deposit
        uint256 depositAmount1 = 100 ether;
        vm.prank(alice);
        staking.deposit(depositAmount1, alice);

        // Warp forward within the same quarter
        uint256 timeElapsed = 10;
        vm.warp(block.timestamp + timeElapsed);

        // Alice's second deposit
        uint256 depositAmount2 = 50 ether;
        vm.prank(alice);
        staking.deposit(depositAmount2, alice);

        uint256 rewardsBetweenDeposits = staking.rewardRate() * (block.timestamp - firstQuarterTime);
        uint256 expectedAccRewardPerShare = (rewardsBetweenDeposits * 1e18) / depositAmount1;
        uint256 initialAccRewardPerShare = 0; // It was zero before any rewards
        uint256 totalExpectedAccRewardPerShare = initialAccRewardPerShare + expectedAccRewardPerShare;
        // Expected value calculations
        uint256 totalDeposit = depositAmount1 + depositAmount2;
        uint256 expectedShares = totalDeposit;
        uint256 expectedRewards = rewardsBetweenDeposits;
        uint256 expectedDebt = (totalExpectedAccRewardPerShare * totalDeposit) / 1e18;
        uint256 expectedLastUpdate = block.timestamp;

        // Assert final user data
        assertUserData(alice, 0, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate);
        assertEq(staking.totalSupply(), totalDeposit, "Total supply incorrect");
        assertEq(staking.totalAssets(), totalDeposit, "Total assets incorrect");
    }

    function testMultipleMintsInSameQuarter() public {
        // Warp to a time within the first quarter
        uint256 firstQuarterTime = staking.quarterTimestamps(0) + 1;
        vm.warp(firstQuarterTime);

        // Alice's first mint
        uint256 mintAmount1 = 100 ether;
        vm.prank(alice);
        staking.mint(mintAmount1, alice);

        // Warp forward within the same quarter
        uint256 timeElapsed = 10;
        vm.warp(block.timestamp + timeElapsed);

        // Alice's second mint
        uint256 mintAmount2 = 50 ether;
        vm.prank(alice);
        staking.mint(mintAmount2, alice);

        // Calculate rewards between mints
        uint256 rewardsBetweenMints = staking.rewardRate() * timeElapsed;
        uint256 expectedAccRewardPerShare = (rewardsBetweenMints * 1e18) / mintAmount1;
        uint256 totalExpectedAccRewardPerShare = expectedAccRewardPerShare;

        // Expected value calculations
        uint256 totalMintedShares = mintAmount1 + mintAmount2;
        uint256 expectedShares = totalMintedShares;
        uint256 expectedRewards = rewardsBetweenMints;
        uint256 expectedDebt = (totalExpectedAccRewardPerShare * totalMintedShares) / 1e18;
        uint256 expectedLastUpdate = block.timestamp;

        // Assert final user data
        assertUserData(alice, 0, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate);

        // Assert total supply and assets
        assertEq(staking.totalSupply(), totalMintedShares, "Total supply incorrect");
        assertEq(staking.totalAssets(), staking.convertToAssets(totalMintedShares), "Total assets incorrect");
    }

    function testMintZeroAmount() public {
        // Warp to first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime); // Warp to valid staking period

        // Now attempt to mint zero shares
        vm.expectRevert(MortarStaking.CannotStakeZero.selector);
        vm.prank(alice);
        staking.mint(0, alice);
    }

    function testDepositZeroAmount() public {
        // Warp to first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime); // Warp to valid staking period
        // Attempt to deposit zero assets
        vm.expectRevert(MortarStaking.CannotStakeZero.selector);
        vm.prank(alice);
        staking.deposit(0, alice);
    }

    function testMintOutsideStakingPeriod() public {
        // Warp to a time before the staking period
        uint256 beforeStakingStartTime = staking.quarterTimestamps(0) - 1;
        vm.warp(beforeStakingStartTime);

        // Attempt to mint shares
        vm.expectRevert(MortarStaking.InvalidStakingPeriod.selector);
        vm.prank(alice);
        staking.mint(100 ether, alice);
    }

    function testDepositOutsideStakingPeriod() public {
        // Warp to a time after the staking period
        uint256 afterStakingEndTime = staking.quarterTimestamps(quarterLength - 1) + 1;
        vm.warp(afterStakingEndTime);
        // Attempt to deposit assets
        vm.expectRevert(MortarStaking.InvalidStakingPeriod.selector);
        vm.prank(alice);
        staking.deposit(100 ether, alice);
    }

    function testDepositEventEmission() public {
        // Warp to the first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1);

        uint256 depositAmount = 1000 ether;

        // Expect the Deposited event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Deposited(alice, depositAmount, depositAmount); // assets and shares are equal in initial deposit

        vm.prank(alice);
        staking.deposit(depositAmount, alice);
    }

    function testMintEventEmission() public {
        // Warp to the first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1);

        uint256 mintAmount = 1000 ether;
        uint256 assetsRequired = staking.previewMint(mintAmount);

        // Expect the Minted event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, mintAmount, assetsRequired);

        vm.prank(alice);
        staking.mint(mintAmount, alice);
    }

    function testClaim() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20;

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        // Warp to the end of the first quarter and claim rewards
        vm.warp(firstQuarterEndTime);
        staking.claim(alice);
        staking.claim(bob);

        // Get the reward rate from the staking contract
        uint256 rewardRate = staking.rewardRate();

        // Calculate time periods
        uint256 timeAliceOnly = bobDepositTimestamp - aliceDepositTimestamp;
        uint256 timeBoth = firstQuarterEndTime - bobDepositTimestamp;

        // Calculate rewards generated during each period
        uint256 rewardsAliceOnly = rewardRate * timeAliceOnly;
        uint256 rewardsBoth = rewardRate * timeBoth;

        // Calculate Accumulated Reward Per Share (APS) at Bob's deposit
        uint256 APS1 = (rewardsAliceOnly * 1e18) / aliceDepositAmount;

        // Bob's initial reward debt
        uint256 bobRewardDebt = (APS1 * bobDepositAmount) / 1e18;

        // Total APS at the end of the quarter
        uint256 APS2 = APS1 + (rewardsBoth * 1e18) / (aliceDepositAmount + bobDepositAmount);

        // Calculate total rewards for Alice and Bob
        uint256 aliceTotalRewards = (APS2 * aliceDepositAmount) / 1e18;
        uint256 bobTotalRewards = ((APS2 * bobDepositAmount) / 1e18) - bobRewardDebt;

        // Expected final balances
        uint256 aliceExpectedBalance = aliceDepositAmount + aliceTotalRewards;
        uint256 bobExpectedBalance = bobDepositAmount + bobTotalRewards;

        // Get actual final balances from the staking contract
        uint256 aliceFinalBalance = staking.balanceOf(alice);
        uint256 bobFinalBalance = staking.balanceOf(bob);

        // Assert that the actual final balances match the expected balances
        assertApproxEqAbs(aliceFinalBalance, aliceExpectedBalance, 1e10, "Alice final balance incorrect");
        assertApproxEqAbs(bobFinalBalance, bobExpectedBalance, 1e10, "Bob final balance incorrect");
    }

    function testWithdrawInSameQuarter() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20;

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        uint256 APS = (staking.rewardRate() * (bobDepositTimestamp - aliceDepositTimestamp) * 1e18) / aliceDepositAmount;
        // Alice withdraws 50% of her shares and gets back 50 ether
        vm.prank(alice);
        staking.withdraw(aliceDepositAmount / 2, alice, alice);

        // Assert after alice first withdraw same quarter, same timestamp of Bob deposit
        {
            APS += (staking.rewardRate() * (bobDepositTimestamp - bobDepositTimestamp) * 1e18)
                / ((aliceDepositAmount / 2) + bobDepositAmount);
            uint256 aliceRewardAccumulated = (APS * (aliceDepositAmount)) / 1e18;
            uint256 expectedDebt = (APS * (aliceDepositAmount / 2)) / 1e18;

            assertUserData(
                alice, 0, (aliceDepositAmount / 2), aliceRewardAccumulated, expectedDebt, bobDepositTimestamp
            );
        }

        {
            uint256 aliceSecondWithdrawTimestamp = bobDepositTimestamp + 20;
            vm.warp(aliceSecondWithdrawTimestamp);

            MortarStaking.UserInfo memory aliceInfo = staking.userQuarterInfo(alice, 0);

            // Alice withdraws all of shares to Bob and gets back 50 ether
            vm.prank(alice);
            staking.withdraw(aliceDepositAmount / 2, bob, alice);
            MortarStaking.Quarter memory quarterData = staking.quarters(0);

            APS += (staking.rewardRate() * (aliceSecondWithdrawTimestamp - bobDepositTimestamp) * 1e18)
                / (bobDepositAmount + (aliceDepositAmount / 2));
            uint256 aliceRewards =
                aliceInfo.rewardAccrued + (APS * (aliceDepositAmount / 2) / 1e18) - aliceInfo.rewardDebt;

            assertUserData(alice, 0, 0, aliceRewards, 0, aliceSecondWithdrawTimestamp);
        }

        assertEq(staking.balanceOf(alice), 0, "Alice shares incorrect");
    }

    function testWithdrawInDifferentQuarter() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20;

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        uint256 APS = (staking.rewardRate() * (bobDepositTimestamp - aliceDepositTimestamp) * 1e18) / aliceDepositAmount;

        {
            // Warp to next quarter
            uint256 secondQuarterWithdrawTimestamp = firstQuarterEndTime;
            vm.warp(secondQuarterWithdrawTimestamp);
            vm.prank(alice);
            staking.withdraw(aliceDepositAmount / 2, alice, alice);

            uint256 bobRewardDebt = (APS * bobDepositAmount) / 1e18;

            APS += (staking.rewardRate() * (secondQuarterWithdrawTimestamp - bobDepositTimestamp) * 1e18)
                / (bobDepositAmount + aliceDepositAmount);

            MortarStaking.Quarter memory quarterInfo = staking.quarters(0);
            MortarStaking.UserInfo memory aliceInfo = staking.userQuarterInfo(alice, 0);

            uint256 aliceRewards = (APS * aliceDepositAmount) / 1e18;
            uint256 bobRewards = ((APS * bobDepositAmount) / 1e18) - bobRewardDebt;
            uint256 totaAliceSharesAfterWithdraw = aliceRewards + (aliceDepositAmount / 2);

            assertQuarterData(
                0,
                APS,
                (aliceDepositAmount + bobDepositAmount),
                (aliceDepositAmount + bobDepositAmount),
                (aliceRewards + bobRewards)
            );

            assertUserData(alice, 1, totaAliceSharesAfterWithdraw, 0, 0, secondQuarterWithdrawTimestamp);
            assertEq(staking.balanceOf(alice), totaAliceSharesAfterWithdraw, "Alice shares incorrect");
        }
    }

    function testRedeemInSameQuarter() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20;

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        uint256 APS = (staking.rewardRate() * (bobDepositTimestamp - aliceDepositTimestamp) * 1e18) / aliceDepositAmount;
        // Alice redeems 50% of her shares
        uint256 aliceRedeemShares = aliceDepositAmount / 2;
        vm.prank(alice);
        staking.redeem(aliceRedeemShares, alice, alice);

        // Assert after Alice's first redeem in the same quarter
        {
            APS += (staking.rewardRate() * (bobDepositTimestamp - bobDepositTimestamp) * 1e18)
                / ((aliceDepositAmount / 2) + bobDepositAmount);
            uint256 aliceRewardAccumulated = (APS * (aliceDepositAmount)) / 1e18;
            uint256 expectedDebt = (APS * (aliceDepositAmount / 2)) / 1e18;

            assertUserData(
                alice, 0, (aliceDepositAmount / 2), aliceRewardAccumulated, expectedDebt, bobDepositTimestamp
            );
        }

        {
            uint256 aliceSecondRedeemTimestamp = bobDepositTimestamp + 20;
            vm.warp(aliceSecondRedeemTimestamp);

            MortarStaking.UserInfo memory aliceInfo = staking.userQuarterInfo(alice, 0);

            // Alice redeems all of her remaining shares to Bob
            uint256 aliceRemainingShares = aliceDepositAmount / 2;
            vm.prank(alice);
            staking.redeem(aliceRemainingShares, bob, alice);
            MortarStaking.Quarter memory quarterData = staking.quarters(0);

            APS += (staking.rewardRate() * (aliceSecondRedeemTimestamp - bobDepositTimestamp) * 1e18)
                / (bobDepositAmount + (aliceDepositAmount / 2));
            uint256 aliceRewards =
                aliceInfo.rewardAccrued + (APS * (aliceDepositAmount / 2) / 1e18) - aliceInfo.rewardDebt;

            assertUserData(alice, 0, 0, aliceRewards, 0, aliceSecondRedeemTimestamp);
        }

        assertEq(staking.balanceOf(alice), 0, "Alice shares incorrect");
    }

    function testRedeemInDifferentQuarter() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2;
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20;

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        uint256 APS = (staking.rewardRate() * (bobDepositTimestamp - aliceDepositTimestamp) * 1e18) / aliceDepositAmount;

        {
            // Warp to next quarter
            uint256 secondQuarterRedeemTimestamp = firstQuarterEndTime;
            vm.warp(secondQuarterRedeemTimestamp);
            vm.prank(alice);
            uint256 aliceRedeemShares = aliceDepositAmount / 2;
            staking.redeem(aliceRedeemShares, alice, alice);

            uint256 bobRewardDebt = (APS * bobDepositAmount) / 1e18;

            APS += (staking.rewardRate() * (secondQuarterRedeemTimestamp - bobDepositTimestamp) * 1e18)
                / (bobDepositAmount + aliceDepositAmount);

            MortarStaking.Quarter memory quarterInfo = staking.quarters(0);
            MortarStaking.UserInfo memory aliceInfo = staking.userQuarterInfo(alice, 0);

            uint256 aliceRewards = (APS * aliceDepositAmount) / 1e18;
            uint256 bobRewards = ((APS * bobDepositAmount) / 1e18) - bobRewardDebt;
            uint256 totalAliceSharesAfterRedeem = aliceRewards + (aliceDepositAmount / 2);

            assertQuarterData(
                0,
                APS,
                (aliceDepositAmount + bobDepositAmount),
                (aliceDepositAmount + bobDepositAmount),
                (aliceRewards + bobRewards)
            );

            assertUserData(alice, 1, totalAliceSharesAfterRedeem, 0, 0, secondQuarterRedeemTimestamp);
            assertEq(staking.balanceOf(alice), totalAliceSharesAfterRedeem, "Alice shares incorrect");
        }
    }

    function testTransferInWithinStakingPeriod() public {
        // Define the first quarter's start and end times
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp = firstQuarterStartTime + (firstQuarterEndTime - firstQuarterStartTime) / 2; // Middle
            // of the quarter
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20; // 20 seconds after Alice

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        // Warp to the end of the first quarter and claim rewards
        vm.warp(firstQuarterEndTime);

        // Transfer 50% of Alice's shares to Bob
        uint256 aliceShares = staking.balanceOf(alice);
        uint256 transferAmount = aliceShares / 2;

        vm.prank(alice);
        staking.transfer(bob, transferAmount);

        // Get the reward rate from the staking contract
        uint256 rewardRate = staking.rewardRate();

        // Calculate time periods
        uint256 timeAliceOnly = bobDepositTimestamp - aliceDepositTimestamp;
        uint256 timeBoth = firstQuarterEndTime - bobDepositTimestamp;

        // Calculate rewards generated during each period
        uint256 rewardsAliceOnly = rewardRate * timeAliceOnly;
        uint256 rewardsBoth = rewardRate * timeBoth;

        // Calculate Accumulated Reward Per Share (APS) at Bob's deposit
        uint256 APS1 = (rewardsAliceOnly * 1e18) / aliceDepositAmount;

        // Bob's initial reward debt
        uint256 bobRewardDebt = (APS1 * bobDepositAmount) / 1e18;

        // Total APS at the end of the quarter
        uint256 APS2 = APS1 + (rewardsBoth * 1e18) / (aliceDepositAmount + bobDepositAmount);

        // Calculate total rewards for Alice and Bob
        uint256 aliceTotalRewards = (APS2 * aliceDepositAmount) / 1e18;
        uint256 bobTotalRewards = ((APS2 * bobDepositAmount) / 1e18) - bobRewardDebt;

        // Expected final balances
        uint256 aliceExpectedBalance = aliceDepositAmount + aliceTotalRewards;
        uint256 bobExpectedBalance = bobDepositAmount + bobTotalRewards;

        uint256 aliceAfterTransferShares = aliceExpectedBalance - transferAmount;
        uint256 bobAfterTransferShares = bobExpectedBalance + transferAmount;

        assertEq(staking.balanceOf(alice), aliceAfterTransferShares, "Alice shares incorrect");
        assertEq(staking.balanceOf(bob), bobAfterTransferShares, "Bob shares incorrect");
    }

    function testTransferAfterStakingPeriod() public {
        // Define the first quarter's start and end times
        uint256 stakingEndTime = staking.quarterTimestamps(quarterLength - 1);

        // Calculate deposit timestamps
        uint256 aliceDepositTimestamp =
            staking.quarterTimestamps(0) + (staking.quarterTimestamps(1) - staking.quarterTimestamps(0)) / 2; // Middle
            // of the quarter
        uint256 bobDepositTimestamp = aliceDepositTimestamp + 20; // 20 seconds after Alice

        // Define deposit amounts
        uint256 aliceDepositAmount = 100 ether;
        uint256 bobDepositAmount = 200 ether;

        // Alice deposits at her deposit timestamp
        vm.warp(aliceDepositTimestamp);
        vm.prank(alice);
        staking.deposit(aliceDepositAmount, alice);

        // Bob deposits at his deposit timestamp
        vm.warp(bobDepositTimestamp);
        vm.prank(bob);
        staking.deposit(bobDepositAmount, bob);

        // Warp to the end of the first quarter and claim rewards
        vm.warp(stakingEndTime);

        // Transfer 50% of Alice's shares to Bob
        uint256 transferAmount = staking.balanceOf(alice) / 2;

        vm.prank(alice);
        staking.claim(alice);

        MortarStaking.UserInfo memory aliceInfo = staking.userQuarterInfo(alice, quarterLength - 2);
        uint256 aliceShareBalance = staking.balanceOf(alice);

        // Run Transfer
        vm.prank(alice);
        staking.transfer(bob, transferAmount);

        // Assert no state updates after staking period
        assertUserData(
            alice, quarterLength - 2, aliceInfo.shares, aliceInfo.rewardAccrued, aliceInfo.rewardDebt, stakingEndTime
        );
        assertUserData(alice, quarterLength - 1, aliceShareBalance, 0, 0, stakingEndTime);
        // More assertions for Quarter and Bob's 2nd last quarter
    }

    function testRedeemSingleUserSingleQuarter() public { }

    function testRedeemSingleUserMultipleQuarters() public { }

    function testRedeemMultipleUserMultipleQuarters() public { }

    function testRedeemAfterStakingEnds() public { }

    function testQuarryYield() public { }

    function testDepositFromStartToEnd() public { } // Check if 450M rewards are distributed, match totalSupply() and
        // balanceOf()

    function depositAndWithdrawMultipleUserAcrossQuarters() public { }

    // ==================================== Helper Functions ===================================== //

    // Helper function to assert user data
    function assertUserData(
        address user,
        uint256 quarter,
        uint256 expectedShares,
        uint256 expectedRewards,
        uint256 expectedDebt,
        uint256 expectedLastUpdate
    )
        internal
        view
    {
        MortarStaking.UserInfo memory info = staking.userQuarterInfo(user, quarter);
        assertEq(info.shares, expectedShares, "User shares incorrect");
        assertApproxEqAbs(info.rewardAccrued, expectedRewards, 1e2, "User rewards incorrect");
        assertApproxEqAbs(info.rewardDebt, expectedDebt, 1e2, "User reward debt incorrect");
        assertEq(info.lastUpdateTimestamp, expectedLastUpdate, "User last update incorrect");
    }

    // Helper function to assert quarter data
    function assertQuarterData(
        uint256 quarter,
        uint256 expectedAPS,
        uint256 expectedTotalShares,
        uint256 expectedTotalStaked,
        uint256 expectedGenerated
    )
        internal
        view
    {
        MortarStaking.Quarter memory quarterData = staking.quarters(quarter);
        assertEq(quarterData.accRewardPerShare, expectedAPS, "Accumulated reward per share incorrect");
        assertEq(quarterData.totalShares, expectedTotalShares, "Total shares incorrect");
        assertEq(quarterData.totalStaked, expectedTotalStaked, "Total staked incorrect");
        assertApproxEqAbs(quarterData.sharesGenerated, expectedGenerated, 1e3, "Generated rewards incorrect");
    }
}
