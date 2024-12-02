// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MortarStaking.sol";
import "../src/MortarStakingTreasury.sol";
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
    MortarStakingTreasury public treasury;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);
    uint256 quarterLength = 81;
    // Helper struct to store quarter data

    struct QuarterData {
        uint256 APS;
        uint256 totalShares;
        uint256 totalStaked;
        uint256 generated;
    }

    // Helper struct to store user data
    struct UserData {
        uint256 rewards;
        uint256 debt;
        uint256 shares;
        uint256 balance;
    }

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Minted(address indexed user, uint256 shares, uint256 assets);

    function setUp() public {
        token = new MockERC20();
        treasury = new MortarStakingTreasury(address(token));
        stakingImplementation = new MortarStaking();
        proxyAdmin = new ProxyAdmin(address(this));

        // Encode initialization data
        bytes memory initData =
            abi.encodeWithSelector(MortarStaking.initialize.selector, address(token), address(treasury), address(this));
        proxy = new TransparentUpgradeableProxy(address(stakingImplementation), address(proxyAdmin), initData);
        staking = MortarStaking(address(proxy));

        // Setup treasury
        treasury.setStakingContract(address(proxy));

        // Mint tokens for test users
        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
        token.mint(carol, 1000 ether);
        // Mint 450M reward tokens for treasury
        token.mint(address(treasury), 450_000_000 ether);

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

    function testMintInFirstQuarter() public {
        // Warp to the first quarter start time
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1); // +1 to ensure we're within the quarter

        uint256 mintAmount = 1000 ether;

        vm.prank(alice);
        staking.mint(mintAmount, alice);

        // Manual calculations
        uint256 expectedShares = mintAmount;
        uint256 expectedRewards = 0;
        uint256 expectedDebt = 0;
        uint256 expectedLastUpdate = firstQuarterStartTime + 1;

        // Assert user data
        assertUserData(alice, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate, 0);

        // Assert quarter data
        uint256 expectedAPS = 0;
        uint256 expectedTotalShares = expectedShares;
        uint256 expectedTotalStaked = staking.convertToAssets(expectedShares);
        uint256 expectedGenerated = 0;

        assertQuarterData(0, expectedAPS, expectedTotalShares, expectedTotalStaked, expectedGenerated);
    }

    function testDepositInFirstQuarter() public {
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        uint256 depositAmount = 1000 ether;

        depositAtTimestamp(alice, depositAmount, firstQuarterStartTime + 1);

        // Manual calculations
        uint256 expectedShares = depositAmount;
        uint256 expectedRewards = 0;
        uint256 expectedDebt = 0;
        uint256 expectedLastUpdate = firstQuarterStartTime + 1;

        // Assert user data
        assertUserData(alice, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate, 0);

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
        depositAtTimestamp(alice, aliceDepositAmount, timeInFirstQuarter);

        // Bob deposits at (quarterTimestamps[1]/2) + 20, i.e., 20 seconds after alice
        uint256 bobDepositTimestamp = timeInFirstQuarter + 20;
        depositAtTimestamp(bob, bobDepositAmount, bobDepositTimestamp);

        // Calculate rewards generated during each period
        // Manual calculation of accumulated reward per share
        uint256 calculatedAccRps =
            (staking.rewardRate() * (bobDepositTimestamp - timeInFirstQuarter) * 1e18) / (aliceDepositAmount);
        uint256 calculatedBobRewardDebt = (calculatedAccRps * bobDepositAmount) / 1e18;
        assertQuarterData(
            0, calculatedAccRps, (aliceDepositAmount + bobDepositAmount), (aliceDepositAmount + bobDepositAmount), 0
        );
        assertUserData(bob, bobDepositAmount, 0, calculatedBobRewardDebt, bobDepositTimestamp, 0);

        // Warp to last quarter and Alice deposits again
        uint256 lastQuarterStartTime = staking.quarterTimestamps(quarterLength - 2);
        depositAtTimestamp(alice, 100 ether, lastQuarterStartTime);

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
        assertUserData(alice, staking.balanceOf(alice), 0, 0, lastQuarterStartTime, quarterLength - 2);
        assertQuarterData(quarterLength - 2, 0, staking.totalSupply(), staking.totalAssets(), 0);
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
        assertUserData(bob, bobMintAmount, 0, calculatedBobRewardDebt, bobMintTimestamp, 0);

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
        assertUserData(alice, aliceTotalShares, 0, 0, lastQuarterStartTime, lastQuarterIndex);

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
        // Manual calculations
        uint256 totalDeposit = depositAmount1 + depositAmount2;
        uint256 expectedShares = totalDeposit;
        uint256 expectedRewards = rewardsBetweenDeposits;
        uint256 expectedDebt = (totalExpectedAccRewardPerShare * totalDeposit) / 1e18;
        uint256 expectedLastUpdate = block.timestamp;

        // Assert final user data
        assertUserData(alice, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate, 0);
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

        // Manual calculations
        uint256 totalMintedShares = mintAmount1 + mintAmount2;
        uint256 expectedShares = totalMintedShares;
        uint256 expectedRewards = rewardsBetweenMints;
        uint256 expectedDebt = (totalExpectedAccRewardPerShare * totalMintedShares) / 1e18;
        uint256 expectedLastUpdate = block.timestamp;

        // Assert final user data
        assertUserData(alice, expectedShares, expectedRewards, expectedDebt, expectedLastUpdate, 0);

        // Assert total supply and assets
        assertEq(staking.totalSupply(), totalMintedShares, "Total supply incorrect");
        assertEq(staking.totalAssets(), staking.convertToAssets(totalMintedShares), "Total assets incorrect");
    }

    function testMintZeroAmount() public {
        // Attempt to mint zero shares
        vm.expectRevert(MortarStaking.CannotStakeZero.selector);
        vm.prank(alice);
        staking.mint(0, alice);
    }

    function testDepositZeroAmount() public {
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
        depositAtTimestamp(alice, aliceDepositAmount, aliceDepositTimestamp);

        // Bob deposits at his deposit timestamp
        depositAtTimestamp(bob, bobDepositAmount, bobDepositTimestamp);

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

    function testWithdrawInFirstQuarter() public {
        // Step 1: Warp to the first quarter start time + 1 second to ensure within the quarter
        uint256 firstQuarterStartTime = staking.quarterTimestamps(0);
        vm.warp(firstQuarterStartTime + 1);

        // Step 2: Alice deposits 1000 ether
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        staking.deposit(depositAmount, alice);

        // Step 3: Warp to the middle of the first quarter to accrue rewards
        uint256 firstQuarterEndTime = staking.quarterTimestamps(1);
        uint256 middleOfFirstQuarter = (firstQuarterStartTime + firstQuarterEndTime) / 2;
        vm.warp(middleOfFirstQuarter);

        // Step 4: Calculate expected rewards accrued up to this point
        uint256 timeElapsed = middleOfFirstQuarter - (firstQuarterStartTime + 1);
        uint256 rewardRate = staking.rewardRate();
        uint256 expectedRewards = rewardRate * timeElapsed;

        // Step 5: Alice withdraws 500 ether
        vm.prank(alice);
        staking.withdraw(500 ether, alice, alice);

        // Step 6: Calculate expected accumulated reward per share (APS)
        uint256 expectedAccRewardPerShare = (expectedRewards * 1e18) / depositAmount;

        // Step 7: Calculate Alice's accumulated reward and new reward debt
        uint256 accumulatedReward = (depositAmount * expectedAccRewardPerShare) / 1e18;
        uint256 expectedRewardAccrued = accumulatedReward; // Since initial rewardDebt is 0
        uint256 newShares = depositAmount - 500 ether; // Remaining shares after withdrawal
        uint256 expectedRewardDebt = (newShares * expectedAccRewardPerShare) / 1e18;

        // Step 8: Assert Alice's user data
        assertUserData(alice, newShares, expectedRewardAccrued, expectedRewardDebt, middleOfFirstQuarter, 0);
        // Step 9: Assert quarter data
        uint256 expectedTotalShares = newShares;
        uint256 expectedTotalStaked = expectedTotalShares; // Assuming 1:1 ratio
        uint256 expectedSharesGenerated = 0; // No shares generated yet
        assertQuarterData(
            0, expectedAccRewardPerShare, expectedTotalShares, expectedTotalStaked, expectedSharesGenerated
        );
        // Assert total supply and total assets
        assertEq(staking.totalAssets(), staking.convertToAssets(newShares), "Total assets incorrect");
        assertEq(staking.totalSupply(), newShares, "Total supply incorrect");
    }

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

    function testRedeemSingleUserSingleQuarter() public { }

    function testRedeemSingleUserMultipleQuarters() public { }

    function testRedeemMultipleUserMultipleQuarters() public { }

    function testRedeemAfterStakingEnds() public { }

    function testTransferSharesDuringStaking() public { }

    function transferAfterStakingEnds() public { }

    function testDelegateVotes() public { }

    function testQuarryYield() public { }

    function depositAndWithdrawMultipleUserAcrossQuarters() public { }

    function testTransferSharesAndPastVotes() public { }

    function testTransferSharesAndPastVotesWithoutInteractions() public { }

    function testTransferSharesAndPastVotesWithInteractions() public { }

    // ==================================== Helper Functions ===================================== //

    // Helper function to assert user data
    function assertUserData(
        address user,
        uint256 expectedShares,
        uint256 expectedRewards,
        uint256 expectedDebt,
        uint256 expectedLastUpdate,
        uint256 quarter
    )
        internal
    {
        (uint256 rewardAccrued, uint256 lastUpdate, uint256 rewardDebt, uint256 shares) =
            staking.userQuarterInfo(user, quarter);
        assertEq(shares, expectedShares, "User shares incorrect");
        assertApproxEqAbs(rewardAccrued, expectedRewards, 1e2, "User rewards incorrect");
        assertApproxEqAbs(rewardDebt, expectedDebt, 1e2, "User reward debt incorrec ");
        assertEq(lastUpdate, expectedLastUpdate, "User last update incorrect");
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
    {
        (uint256 APS,,, uint256 totalShares, uint256 totalStaked, uint256 generated) = staking.quarters(quarter);
        assertEq(APS, expectedAPS, "Accumulated reward per share incorrect");
        assertEq(totalShares, expectedTotalShares, "Total shares incorrect");
        assertEq(totalStaked, expectedTotalStaked, "Total staked incorrect");
        assertEq(generated, expectedGenerated, "Generated rewards incorrect");
    }

    // Helper function to deposit tokens at a specific timestamp
    function depositAtTimestamp(address user, uint256 amount, uint256 timestamp) internal {
        vm.warp(timestamp);
        vm.prank(user);
        staking.deposit(amount, user);
    }
}
