pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/MortarStakingTreasury.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MortarStakingTreasuryTest is Test {
    MortarStakingTreasury public treasury;
    MockERC20 public assetToken;
    address public owner;
    address public stakingContract;
    address public user;
    address public attacker;

    uint256 public initialTreasuryBalance = 1_000_000 * 10 ** 18; // 1 million tokens
    
    event StakingContractSet(address indexed oldContract, address indexed newContract);
    event TokensWithdrawn(address indexed to, uint256 amount);
    event TokensPulled(address indexed to, uint256 amount);

    function setUp() public {
        // Initialize addresses
        owner = address(this);
        stakingContract = address(0x123);
        user = address(0x456);
        attacker = address(0x789);

        // Deploy mock ERC20 token and mint tokens to the treasury
        assetToken = new MockERC20();
        assetToken.mint(address(this), initialTreasuryBalance);

        // Deploy the treasury contract
        treasury = new MortarStakingTreasury(address(assetToken));

        // Transfer tokens to the treasury contract
        assetToken.transfer(address(treasury), initialTreasuryBalance);

        // Set the staking contract address and expect event
        vm.expectEmit(true, true, false, false);
        emit StakingContractSet(address(0), stakingContract);
        treasury.setStakingContract(stakingContract);
    }

    // Test onlyOwner modifier for setStakingContract
    function testSetStakingContractByOwner() public {
        address newStakingContract = address(0xABC);
        
        vm.expectEmit(true, true, false, false);
        emit StakingContractSet(stakingContract, newStakingContract);
        treasury.setStakingContract(newStakingContract);
        
        assertEq(treasury.stakingContract(), newStakingContract);
    }

    function testFailSetStakingContractByNonOwner() public {
        vm.prank(attacker);
        treasury.setStakingContract(address(0xDEF));
    }

    // Test withdrawExcessTokens by owner
    function testWithdrawExcessTokensByOwner() public {
        uint256 withdrawAmount = 100_000 * 10 ** 18;
        uint256 ownerInitialBalance = assetToken.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensWithdrawn(owner, withdrawAmount);
        treasury.withdrawExcessTokens(owner, withdrawAmount);

        uint256 ownerFinalBalance = assetToken.balanceOf(owner);
        assertEq(ownerFinalBalance - ownerInitialBalance, withdrawAmount);
        assertEq(assetToken.balanceOf(address(treasury)), initialTreasuryBalance - withdrawAmount);
    }

    // Test withdrawExcessTokens with insufficient balance
    function testFailWithdrawExcessTokensInsufficientBalance() public {
        uint256 withdrawAmount = initialTreasuryBalance + 1;
        treasury.withdrawExcessTokens(owner, withdrawAmount);
    }

    // Test withdrawExcessTokens by non-owner
    function testFailWithdrawExcessTokensByNonOwner() public {
        vm.prank(attacker);
        treasury.withdrawExcessTokens(attacker, 10_000 * 10 ** 18);
    }

    // Test pullTokens by staking contract
    function testPullTokensByStakingContract() public {
        uint256 pullAmount = 200_000 * 10 ** 18;
        uint256 userInitialBalance = assetToken.balanceOf(user);

        vm.prank(stakingContract);
        vm.expectEmit(true, false, false, true);
        emit TokensPulled(user, pullAmount);
        treasury.pullTokens(user, pullAmount);

        uint256 userFinalBalance = assetToken.balanceOf(user);
        assertEq(userFinalBalance - userInitialBalance, pullAmount);
        assertEq(assetToken.balanceOf(address(treasury)), initialTreasuryBalance - pullAmount);
    }

    // Test pullTokens with insufficient balance
    function testFailPullTokensInsufficientBalance() public {
        uint256 pullAmount = initialTreasuryBalance + 1;
        vm.prank(stakingContract);
        treasury.pullTokens(user, pullAmount);
    }

    // Test pullTokens by non-staking contract
    function testFailPullTokensByNonStakingContract() public {
        vm.prank(attacker);
        treasury.pullTokens(user, 10_000 * 10 ** 18);
    }

    // Test setStakingContract to zero address
    function testFailSetStakingContractToZeroAddress() public {
        treasury.setStakingContract(address(0));
    }

    // Test multiple consecutive operations
    function testMultipleOperations() public {
        // Owner withdraws tokens
        uint256 ownerWithdrawAmount = 50_000 * 10 ** 18;
        vm.expectEmit(true, false, false, true);
        emit TokensWithdrawn(owner, ownerWithdrawAmount);
        treasury.withdrawExcessTokens(owner, ownerWithdrawAmount);

        // Staking contract pulls tokens
        uint256 stakingPullAmount = 150_000 * 10 ** 18;
        vm.prank(stakingContract);
        vm.expectEmit(true, false, false, true);
        emit TokensPulled(user, stakingPullAmount);
        treasury.pullTokens(user, stakingPullAmount);

        // Check balances
        uint256 expectedTreasuryBalance = initialTreasuryBalance - ownerWithdrawAmount - stakingPullAmount;
        assertEq(assetToken.balanceOf(address(treasury)), expectedTreasuryBalance);

        // Owner tries to set staking contract again
        address newStakingContract = address(0xAAA);
        vm.expectEmit(true, true, false, false);
        emit StakingContractSet(stakingContract, newStakingContract);
        treasury.setStakingContract(newStakingContract);
        assertEq(treasury.stakingContract(), newStakingContract);

        // Old staking contract should fail to pull tokens
        vm.prank(stakingContract);
        vm.expectRevert(MortarStakingTreasury.NotStakingContract.selector);
        treasury.pullTokens(user, 10_000 * 10 ** 18);

        // New staking contract pulls tokens
        uint256 finalPullAmount = 10_000 * 10 ** 18;
        vm.prank(newStakingContract);
        vm.expectEmit(true, false, false, true);
        emit TokensPulled(user, finalPullAmount);
        treasury.pullTokens(user, finalPullAmount);
    }
}