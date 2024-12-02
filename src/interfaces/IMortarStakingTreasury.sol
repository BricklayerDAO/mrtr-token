// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMortarStakingTreasury {
    function owner() external view returns (address);
    function stakingContract() external view returns (address);
    function assetToken() external view returns (address);

    /**
     * @dev Sets the address of the authorized staking contract.
     * Can only be called by the owner.
     */
    function setStakingContract(address _stakingContract) external;

    /**
     * @dev Allows the staking contract to pull tokens from the treasury.
     * Can only be called by the authorized staking contract.
     */
    function pullTokens(address to, uint256 amount) external;
}
