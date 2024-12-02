// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title MRTR Token
 * @dev Implementation of the MRTR token with burnable and upgradable
 */
contract MRTRToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1 billion tokens with 18 decimals

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

    function burn(address _account, uint256 _amount) public onlyOwner {
        _burn(_account, _amount);
    }
}
