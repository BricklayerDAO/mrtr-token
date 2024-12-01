// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/console.sol";
import { IMortarStakingTreasury } from "./interfaces/IMortarStakingTreasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { VotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MortarStaking is
    Initializable,
    ERC4626Upgradeable,
    VotesUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    struct Quarter {
        uint256 accRewardPerShare; // Scaled by PRECISION
        uint256 lastUpdateTimestamp;
        uint256 totalRewardAccrued;
        uint256 totalShares;
        uint256 totalStaked;
        uint256 sharesGenerated;
    }

    struct UserInfo {
        uint256 rewardAccrued;
        uint256 lastUpdateTimestamp;
        uint256 rewardDebt;
        uint256 shares;
    }

    // Constants
    uint256 private constant TOTAL_REWARDS = 450_000_000 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant CLAIM_PERIOD = 30 days;
    bytes32 public constant QUARRY_ROLE = keccak256("QUARRY_ROLE");

    // Custom Errors
    error InvalidStakingPeriod();
    error CannotStakeZero();
    error ZeroAddress();
    error CannotWithdrawZero();
    error CannotRedeemZero();
    error UnclaimedQuarryRewardsAssetsLeft();
    error ClaimPeriodNotOver();
    error ClaimPeriodOver();
    error QuarryRewardsAlreadyClaimed();

    // Events
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Minted(address indexed user, uint256 shares, uint256 assets);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event Redeemed(address indexed user, uint256 shares, uint256 assets);
    event RewardDistributed(uint256 quarter, uint256 reward);
    event QuarryRewardsAdded(uint256 amount, uint256 distributionTimestamp);
    event QuarryRewardsClaimedQuarryRewards(address indexed user, uint256 amount);
    event UnclaimedQuarryRewardsQuarryRewardsRetrieved(uint256 amount);

    // State Variables
    uint256 public rewardRate;
    uint256 public lastProcessedQuarter;
    IMortarStakingTreasury public treasury;

    // Mappings
    mapping(uint256 => Quarter) public quarters;
    mapping(address => mapping(uint256 => UserInfo)) public userQuarterInfo;
    mapping(address => uint256) public userLastProcessedQuarter;

    // Array of quarter end timestamps
    uint256[] public quarterTimestamps;

    // Quary data
    uint256 public lastQuaryRewards;
    uint256 public distributionTimestamp;
    uint256 public claimedQuarryRewards;
    mapping(address => uint256) public lastQuarryClaimedTimestamp;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given asset.
     * @param _asset The ERC20 asset to be staked.
     */
    function initialize(IERC20 _asset, IMortarStakingTreasury _treasury, address _admin) external initializer {
        __ERC4626_init(_asset);
        __ERC20_init("XMortar", "xMRTR");
        __Votes_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        // Grant admin role to the admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        // Set treasury contract
        treasury = _treasury;
        // Initialize reward rate
        uint256 totalDuration = quarterTimestamps[quarterTimestamps.length - 1] - quarterTimestamps[0];
        rewardRate = TOTAL_REWARDS / totalDuration;
    }

    /**
     * @notice Deposits assets and stakes them, receiving shares in return.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256) {
        if (assets == 0) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        (uint256 currentQuarter,,) = getCurrentQuarter();
        if (!_isStakingAllowed()) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter);
        _processPendingRewards(receiver, currentQuarter);
        uint256 shares = super.deposit(assets, receiver);
        _afterDepositOrMint(assets, shares, receiver, currentQuarter);
        emit Deposited(receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Mints shares by depositing the equivalent assets.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        if (shares == 0) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        (uint256 currentQuarter,,) = getCurrentQuarter();
        if (!_isStakingAllowed()) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter);
        _processPendingRewards(receiver, currentQuarter);

        uint256 assets = super.mint(shares, receiver);
        _afterDepositOrMint(assets, shares, receiver, currentQuarter);

        emit Minted(receiver, shares, assets);
        return assets;
    }

    /**
     * @notice Withdraws staked assets by burning shares.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        if (assets == 0) revert CannotWithdrawZero();
        if (receiver == address(0)) revert ZeroAddress();

        (uint256 currentQuarter,,) = getCurrentQuarter();

        _updateQuarter(currentQuarter);
        _processPendingRewards(owner, currentQuarter);

        uint256 shares = super.withdraw(assets, receiver, owner);
        _afterWithdrawOrRedeem(assets, shares, owner, currentQuarter);

        emit Withdrawn(owner, assets, shares);
        return shares;
    }

    /**
     * @notice Redeems shares to withdraw the equivalent staked assets.
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        if (shares == 0) revert CannotRedeemZero();
        if (receiver == address(0)) revert ZeroAddress();

        (uint256 currentQuarter,,) = getCurrentQuarter();
        if (!_isStakingAllowed()) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter);
        _processPendingRewards(owner, currentQuarter);

        uint256 assets = super.redeem(shares, receiver, owner);
        _afterWithdrawOrRedeem(assets, shares, owner, currentQuarter);

        emit Redeemed(owner, shares, assets);
        return assets;
    }

    /**
     * @notice Transfers tokens and updates rewards for sender and receiver.
     */
    function transfer(
        address to,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20)
        nonReentrant
        returns (bool)
    {
        (uint256 currentQuarter,,) = getCurrentQuarter();

        _updateQuarter(currentQuarter);

        _processPendingRewards(msg.sender, currentQuarter);
        _processPendingRewards(to, currentQuarter);
        _afterTransfer(msg.sender, to, amount, currentQuarter);

        bool success = super.transfer(to, amount);
        return success;
    }

    /**
     * @notice Transfers tokens on behalf of another address and updates rewards.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20)
        nonReentrant
        returns (bool)
    {
        (uint256 currentQuarter,,) = getCurrentQuarter();

        _updateQuarter(currentQuarter);
        _processPendingRewards(from, currentQuarter);
        _processPendingRewards(to, currentQuarter);

        bool success = super.transferFrom(from, to, amount);
        _afterTransfer(from, to, amount, currentQuarter);

        return success;
    }

    /**
     * @notice Handles post-deposit or mint actions.
     */
    function _afterDepositOrMint(uint256 assets, uint256 shares, address receiver, uint256 currentQuarter) private {
        UserInfo storage _userInfo = userQuarterInfo[receiver][currentQuarter];
        Quarter storage _quarter = quarters[currentQuarter];

        _userInfo.shares += shares;
        _userInfo.rewardDebt = Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION);
        _userInfo.lastUpdateTimestamp = block.timestamp;

        _quarter.totalShares += shares;
        _quarter.totalStaked += assets;
    }

    /**
     * @notice Handles post-withdraw or redeem actions.
     */
    function _afterWithdrawOrRedeem(uint256 assets, uint256 shares, address owner, uint256 currentQuarter) private {
        UserInfo storage _userInfo = userQuarterInfo[owner][currentQuarter];
        Quarter storage _quarter = quarters[currentQuarter];

        _userInfo.shares -= shares;
        _userInfo.rewardDebt = Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION);
        _userInfo.lastUpdateTimestamp = block.timestamp;

        _quarter.totalShares -= shares;
        _quarter.totalStaked -= assets;
    }

    /**
     * @dev Handles post-transfer actions.
     */
    function _afterTransfer(address from, address to, uint256 amount, uint256 currentQuarter) internal {
        Quarter storage _quarter = quarters[currentQuarter];

        UserInfo storage senderInfo = userQuarterInfo[from][currentQuarter];
        senderInfo.shares -= amount;
        senderInfo.rewardDebt = Math.mulDiv(senderInfo.shares, _quarter.accRewardPerShare, PRECISION);
        senderInfo.lastUpdateTimestamp = block.timestamp;

        UserInfo storage recipientInfo = userQuarterInfo[to][currentQuarter];
        recipientInfo.shares += amount;
        recipientInfo.rewardDebt = Math.mulDiv(recipientInfo.shares, _quarter.accRewardPerShare, PRECISION);
        recipientInfo.lastUpdateTimestamp = block.timestamp;
    }

    function _updateQuarter(uint256 currentQuarterIndex) internal {
        // If all quarters are already processed, return
        if (lastProcessedQuarter == 80) return;

        Quarter storage _quarter = quarters[currentQuarterIndex];

        // Step 1: Process previous quarters if any that are unprocessed and update the current quarter with the
        // updated data
        for (uint256 i = lastProcessedQuarter; i < currentQuarterIndex;) {
            Quarter storage pastQuarter = quarters[i];
            uint256 quarterEndTime = quarterTimestamps[i + 1];

            if (pastQuarter.totalShares > 0) {
                // 1. Calculate rewards accrued since the last update to the end of the quarter
                uint256 rewardsAccrued = calculateRewards(pastQuarter.lastUpdateTimestamp, quarterEndTime);
                pastQuarter.totalRewardAccrued += rewardsAccrued;

                // 2. Calculate accRewardPerShare BEFORE updating totalShares to prevent dilution
                pastQuarter.accRewardPerShare += Math.mulDiv(rewardsAccrued, PRECISION, pastQuarter.totalShares);

                // 3. Convert rewards to shares and mint them
                uint256 newShares = convertToShares(pastQuarter.totalRewardAccrued);
                pastQuarter.sharesGenerated = newShares;
                // Mint the shares and pull reward tokens from the treasury
                _mint(address(this), newShares);
                treasury.pullTokens(address(this), pastQuarter.totalRewardAccrued);
                // Update the next quarter's totalShares and totalStaked
                quarters[i + 1].totalShares = pastQuarter.totalShares + newShares;
                quarters[i + 1].totalStaked = pastQuarter.totalStaked + pastQuarter.totalRewardAccrued;
            }

            pastQuarter.lastUpdateTimestamp = quarterEndTime;
            quarters[i + 1].lastUpdateTimestamp = quarterEndTime;
            unchecked {
                i++;
            }
        }

        // Step 2: When the previous quarters are processed and the shares and other relevant data are updated for the
        // current quarter
        // Then calculate the accRewardPerShare
        if (_quarter.totalShares > 0) {
            uint256 rewards = calculateRewards(_quarter.lastUpdateTimestamp, block.timestamp);
            _quarter.totalRewardAccrued += rewards;
            _quarter.accRewardPerShare += Math.mulDiv(rewards, PRECISION, _quarter.totalShares);
        }

        // current quarter updates
        lastProcessedQuarter = currentQuarterIndex;
        _quarter.lastUpdateTimestamp = block.timestamp;
    }

    /// @notice Gives quarter index data for the current timestamp
    function getCurrentQuarter() public view returns (uint256 index, uint256 start, uint256 end) {
        return getQuarter(block.timestamp);
    }

    /// @dev Binary search to get the quarter index, start timestamp and end timestamp
    function getQuarter(uint256 timestamp) public view returns (uint256 index, uint256 start, uint256 end) {
        uint256 left = 0;
        uint256[] memory arr = quarterTimestamps;
        uint256 right = arr.length - 1;

        // Binary search implementation
        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (timestamp < arr[mid]) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

        // Check if we're in a valid staking period
        if (timestamp >= arr[0] && timestamp < arr[arr.length - 1]) {
            uint256 quarterIndex = left > 0 ? left - 1 : 0;
            return (quarterIndex, arr[quarterIndex], arr[quarterIndex + 1]);
        }

        if (timestamp >= arr[arr.length - 1]) {
            return (arr.length - 1, 0, 0);
        }

        return (0, 0, 0);
    }

    /// @notice calculate the rewards for the given duration
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        if (start > end) return 0;
        uint256 rewards = rewardRate * (end - start);
        return rewards;
    }

    // Convert the rewards to shares
    function _processPendingRewards(address user, uint256 currentQuarter) internal {
        uint256 lastProcessed = userLastProcessedQuarter[user];
        if (lastProcessed == 80) return;

        uint256 userShares = userQuarterInfo[user][lastProcessed].shares;
        uint256 initialShares = userShares;

        for (uint256 i = lastProcessed; i < currentQuarter; i++) {
            UserInfo storage userInfo = userQuarterInfo[user][i];
            Quarter memory quarter = quarters[i];

            if (userShares > 0) {
                // Calculate the pending rewards: There is precision error of 1e-18
                uint256 accumulatedReward = Math.mulDiv(userShares, quarter.accRewardPerShare, PRECISION);
                userInfo.rewardAccrued += accumulatedReward - userInfo.rewardDebt;
                userInfo.rewardDebt = accumulatedReward;
                if (userInfo.rewardAccrued > 0) {
                    // Convert the rewards to shares
                    uint256 newShares =
                        Math.mulDiv(userInfo.rewardAccrued, quarter.sharesGenerated, quarter.totalRewardAccrued);
                    userQuarterInfo[user][i + 1].shares = userInfo.shares + newShares;
                    userShares += newShares;
                }
            }
            uint256 endTimestamp = quarterTimestamps[i + 1];
            userInfo.lastUpdateTimestamp = endTimestamp;
        }

        // Transfer shares to the user
        _transfer(address(this), user, userShares - initialShares);

        // Update the current quarter's user data with the last updated quarter's data
        UserInfo storage currentUserInfo = userQuarterInfo[user][currentQuarter];

        // @dev userShares = currentUserInfo.shares
        if (userShares > 0) {
            uint256 accReward = Math.mulDiv(userShares, quarters[currentQuarter].accRewardPerShare, PRECISION);
            currentUserInfo.rewardAccrued += accReward - currentUserInfo.rewardDebt;
            currentUserInfo.rewardDebt = accReward;
        }

        currentUserInfo.lastUpdateTimestamp = block.timestamp;
        userLastProcessedQuarter[user] = currentQuarter;
    }

    /**
     * @notice Override the totalAssets to return the total assets staked in the contract
     */
    function totalAssets() public view virtual override returns (uint256) {
        // TODO: Remove quarry assets
        return super.totalAssets() - (lastQuaryRewards - claimedQuarryRewards);
    }

    /// @dev override _getVotingUnits to return the balance of the user
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return balanceOf(account);
    }

    function claim(address account) external {
        (uint256 index,,) = getCurrentQuarter();
        _updateQuarter(index);
        _processPendingRewards(account, index);
    }

    function addQuarryRewards(uint256 amount) external onlyRole(QUARRY_ROLE) {
        if (claimedQuarryRewards != lastQuaryRewards) {
            revert UnclaimedQuarryRewardsAssetsLeft();
        }
        lastQuaryRewards = amount;
        claimedQuarryRewards = 0;
        distributionTimestamp = block.timestamp;

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        emit QuarryRewardsAdded(amount, distributionTimestamp);
    }

    function claimQuarryRewards() external {
        if (block.timestamp > distributionTimestamp + CLAIM_PERIOD) {
            revert ClaimPeriodOver();
        }
        if (lastQuarryClaimedTimestamp[msg.sender] >= distributionTimestamp) {
            revert QuarryRewardsAlreadyClaimed();
        }

        uint256 userShares = getPastVotes(msg.sender, distributionTimestamp);
        uint256 totalShares = getPastTotalSupply(distributionTimestamp);
        uint256 rewards = Math.mulDiv(userShares, lastQuaryRewards, totalShares);

        if (rewards > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), msg.sender, rewards);
            claimedQuarryRewards += rewards;
        }
        lastQuarryClaimedTimestamp[msg.sender] = distributionTimestamp;
        emit QuarryRewardsClaimedQuarryRewards(msg.sender, rewards);
    }

    function retrieveUnclaimedQuarryRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (block.timestamp <= distributionTimestamp + CLAIM_PERIOD) {
            revert ClaimPeriodNotOver();
        }
        uint256 unclaimedQuarryRewards = lastQuaryRewards - claimedQuarryRewards;
        claimedQuarryRewards = lastQuaryRewards;
        SafeERC20.safeTransfer(IERC20(asset()), msg.sender, unclaimedQuarryRewards);
        emit UnclaimedQuarryRewardsQuarryRewardsRetrieved(unclaimedQuarryRewards);
    }

    function _isStakingAllowed() public view returns (bool) {
        return
            block.timestamp >= quarterTimestamps[0] && block.timestamp < quarterTimestamps[quarterTimestamps.length - 1];
    }
}
