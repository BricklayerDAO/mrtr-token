// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title MRTR Token
 * @dev Implementation of the MRTR token with burnable and upgradable features.
 */
contract MRTRToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1 billion tokens with 18 decimals

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the initial token distribution.
     * @param stakingPool The address of the staking pool to receive tokens.
     * @param daoTreasury The address of the DAO treasury to receive tokens.
     * @param presalePool The address of the presale pool to receive tokens.
     * @param admin The address of the admin.
     */
    function initialize(
        address stakingPool,
        address daoTreasury,
        address presalePool,
        address admin
    )
        public
        initializer
    {
        __ERC20_init("Mortar", "MRTR");
        __Ownable_init(admin);

        // Initial token distribution
        _mint(stakingPool, 450_000_000 ether); // Staking Rewards Pool
        _mint(daoTreasury, 500_000_000 ether); // DAO Treasury Pool
        _mint(presalePool, 50_000_000 ether); // Presale Pool
    }

    /**
     * @dev Burns a specified amount of tokens from the specified account.
     * @param _account The address from which to burn tokens.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) public onlyOwner {
        _burn(_account, _amount);
    }
}
