// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MortarStakingTreasury is Ownable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable assetToken;

    // Events
    event TokensWithdrawn(address indexed to, uint256 amount);

    // Custom errors
    error ZeroAddress();
    error InvalidAmount();
    /**
     * @notice Initializes the treasury with an asset token
     * @param _assetToken The ERC20 token to be managed by this treasury
     */
    constructor(IERC20 _assetToken, address admin) Ownable(admin) {
        if (address(_assetToken) == address(0)) revert ZeroAddress();
        assetToken = _assetToken;
        
        assetToken.approve(msg.sender, type(uint256).max);
    }

    /**
     * @notice Withdraws tokens from the treasury
     * @param to Recipient address
     * @param amount Amount of tokens to withdraw
     * @dev Includes safety checks and emits TokensWithdrawn event
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        emit TokensWithdrawn(to, amount);
        assetToken.safeTransfer(to, amount);
    }
}
