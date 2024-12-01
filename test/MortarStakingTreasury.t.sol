pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, IERC20Errors} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MortarStakingTreasury, Ownable} from "../src/MortarStakingTreasury.sol";

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
        owner = makeAddr("owner");

        // Deploy mock ERC20 token
        assetToken = new MockERC20();
        vm.label(address(assetToken), "Token");

        // Deploy the treasury contract
        treasury = new MortarStakingTreasury(assetToken, owner);
        vm.label(address(treasury), "Treasury");
    }

    function testAllowanceIsSetForDeployer() public view {
        assertEq(assetToken.allowance(address(treasury), address(this)), type(uint256).max);
    }

    function testWithdrawTokensByOwner(uint256 balance, uint256 withdrawAmount) public {
        balance = bound(balance, 1, type(uint256).max);
        withdrawAmount = bound(withdrawAmount, 1, balance);

        assetToken.mint(address(treasury), balance);

        vm.expectEmit(true, false, false, true);
        emit TokensWithdrawn(owner, withdrawAmount);
        vm.prank(owner);
        treasury.withdraw(owner, withdrawAmount);

        assertEq(assetToken.balanceOf(owner), withdrawAmount);
    }

    function testWithdrawTokensByNonOwner(address nonOwner, address receiver, uint256 withdrawAmount) public {
        vm.assume(nonOwner != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        treasury.withdraw(receiver, withdrawAmount);
    }

    // Test withdrawExcessTokens with insufficient balance
    function testInsufficientBalanceToWithdraw(uint256 balance, uint256 withdrawAmount) public {
        balance = bound(balance, 1, type(uint256).max - 1);
        withdrawAmount = bound(withdrawAmount, balance + 1, type(uint256).max);

        assetToken.mint(address(treasury), balance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(treasury), balance, withdrawAmount));
        vm.prank(owner);
        treasury.withdraw(owner, withdrawAmount);
    }
}