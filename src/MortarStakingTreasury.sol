// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MortarStakingTreasury is Ownable {
    using SafeERC20 for IERC20;

    // State variables
    address public stakingContract;
    IERC20 public immutable assetToken;

    // Events
    event StakingContractSet(address indexed oldContract, address indexed newContract);
    event TokensWithdrawn(address indexed to, uint256 amount);
    event TokensPulled(address indexed to, uint256 amount);

    // Custom errors
    error ZeroAddress();
    error InvalidAmount();
    error NotStakingContract();

    /**
     * @notice Initializes the treasury with an asset token
     * @param _assetToken The ERC20 token to be managed by this treasury
     */
    constructor(address _assetToken) Ownable(msg.sender) {
        if (_assetToken == address(0)) revert ZeroAddress();
        assetToken = IERC20(_assetToken);
    }

    /**
     * @notice Modifier to restrict access to staking contract
     */
    modifier onlyStakingContract() {
        if (msg.sender != stakingContract) revert NotStakingContract();
        _;
    }

    /**
     * @notice Sets the address of the authorized staking contract
     * @param _stakingContract New staking contract address
     * @dev Emits StakingContractSet event
     */
    function setStakingContract(address _stakingContract) external onlyOwner {
        if (_stakingContract == address(0)) revert ZeroAddress();

        address oldContract = stakingContract;
        stakingContract = _stakingContract;

        emit StakingContractSet(oldContract, _stakingContract);
    }

    /**
     * @notice Withdraws excess tokens from the treasury
     * @param to Recipient address
     * @param amount Amount of tokens to withdraw
     * @dev Includes safety checks and emits TokensWithdrawn event
     */
    function withdrawExcessTokens(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        emit TokensWithdrawn(to, amount);
        assetToken.safeTransfer(to, amount);
    }

    /**
     * @notice Allows staking contract to pull tokens from treasury
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @dev Includes safety checks and emits TokensPulled event
     */
    function pullTokens(address to, uint256 amount) external onlyStakingContract {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        emit TokensPulled(to, amount);
        assetToken.safeTransfer(to, amount);
    }
}
