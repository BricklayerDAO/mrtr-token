// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MortarStaking is Initializable, ERC4626Upgradeable, ERC20VotesUpgradeable, ReentrancyGuardUpgradeable {
    // Constants
    uint256 private constant TOTAL_REWARDS = 450_000_000 ether;
    uint256 private constant PRECISION = 1e18;

    // Custom Errors
    error InvalidStakingPeriod();
    error CannotStakeZero();
    error ZeroAddress();
    error CannotWithdrawZero();
    error CannotRedeemZero();

    // State Variables
    uint256 public rewardRate;
    uint256 public lastProcessedQuarter;

    struct Quarter {
        uint256 accRewardPerShare; // Scaled by PRECISION
        uint256 lastUpdateTimestamp;
        uint256 totalRewardAccrued;
        uint256 totalShares;
        uint256 totalStaked;
    }

    struct UserInfo {
        uint256 rewardAccrued;
        uint256 lastUpdateTimestamp;
        uint256 rewardDebt;
        uint256 shares;
    }

    // Mappings
    mapping(uint256 => Quarter) public quarters;
    mapping(address => mapping(uint256 => UserInfo)) public userQuarterInfo;
    mapping(address => uint256) public userLastProcessedQuarter;

    // Array of quarter end timestamps
    uint256[] public quarterTimestamps;

    // Events
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Minted(address indexed user, uint256 shares, uint256 assets);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event Redeemed(address indexed user, uint256 shares, uint256 assets);
    event RewardDistributed(uint256 quarter, uint256 reward);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given asset.
     * @param _asset The ERC20 asset to be staked.
     */
    function initialize(IERC20 _asset) external initializer {
        __ERC4626_init(_asset);
        __ERC20_init("XMortar", "xMRTR");
        __ERC20Votes_init();
        __ReentrancyGuard_init();

        // Quarter is open set of the time period
        // E.g., (1_735_084_800 + 1) to (1_742_860_800 - 1) is first quarter
        quarterTimestamps = [
            1_735_084_800, // Quarter 1 start
            1_742_860_800, // Quarter 1 end
            1_748_822_400, // Quarter 2 end
            1_759_180_800, // Quarter 3 end
            1_766_601_600, // Quarter 4 end
            1_774_377_600, // Quarter 5 end
            1_782_067_200, // Quarter 6 end
            1_790_697_600, // Quarter 7 end
            1_798_118_400, // Quarter 8 end
            1_805_894_400, // Quarter 9 end
            1_813_584_000, // Quarter 10 end
            1_822_214_400, // Quarter 11 end
            1_829_635_200, // Quarter 12 end
            1_837_411_200, // Quarter 13 end
            1_845_100_800, // Quarter 14 end
            1_853_731_200, // Quarter 15 end
            1_861_152_000, // Quarter 16 end
            1_868_928_000, // Quarter 17 end
            1_876_617_600, // Quarter 18 end
            1_885_248_000, // Quarter 19 end
            1_892_668_800, // Quarter 20 end
            1_900_444_800, // Quarter 21 end
            1_908_134_400, // Quarter 22 end
            1_916_764_800, // Quarter 23 end
            1_924_185_600, // Quarter 24 end
            1_931_961_600, // Quarter 25 end
            1_939_651_200, // Quarter 26 end
            1_948_281_600, // Quarter 27 end
            1_955_702_400, // Quarter 28 end
            1_963_478_400, // Quarter 29 end
            1_971_168_000, // Quarter 30 end
            1_979_798_400, // Quarter 31 end
            1_987_219_200, // Quarter 32 end
            1_994_995_200, // Quarter 33 end
            2_002_684_800, // Quarter 34 end
            2_011_315_200, // Quarter 35 end
            2_018_736_000, // Quarter 36 end
            2_026_512_000, // Quarter 37 end
            2_034_201_600, // Quarter 38 end
            2_042_832_000, // Quarter 39 end
            2_050_252_800, // Quarter 40 end
            2_058_028_800, // Quarter 41 end
            2_065_718_400, // Quarter 42 end
            2_074_348_800, // Quarter 43 end
            2_081_769_600, // Quarter 44 end
            2_089_545_600, // Quarter 45 end
            2_097_235_200, // Quarter 46 end
            2_105_865_600, // Quarter 47 end
            2_113_286_400, // Quarter 48 end
            2_121_062_400, // Quarter 49 end
            2_128_752_000, // Quarter 50 end
            2_137_382_400, // Quarter 51 end
            2_144_803_200, // Quarter 52 end
            2_152_579_200, // Quarter 53 end
            2_160_268_800, // Quarter 54 end
            2_168_899_200, // Quarter 55 end
            2_176_320_000, // Quarter 56 end
            2_184_096_000, // Quarter 57 end
            2_191_785_600, // Quarter 58 end
            2_200_416_000, // Quarter 59 end
            2_207_836_800, // Quarter 60 end
            2_215_612_800, // Quarter 61 end
            2_223_302_400, // Quarter 62 end
            2_231_932_800, // Quarter 63 end
            2_239_353_600, // Quarter 64 end
            2_247_129_600, // Quarter 65 end
            2_254_819_200, // Quarter 66 end
            2_263_449_600, // Quarter 67 end
            2_270_870_400, // Quarter 68 end
            2_278_646_400, // Quarter 69 end
            2_286_336_000, // Quarter 70 end
            2_294_966_400, // Quarter 71 end
            2_302_387_200, // Quarter 72 end
            2_310_163_200, // Quarter 73 end
            2_317_852_800, // Quarter 74 end
            2_326_483_200, // Quarter 75 end
            2_333_904_000, // Quarter 76 end
            2_341_680_000, // Quarter 77 end
            2_349_369_600, // Quarter 78 end
            2_358_000_000, // Quarter 79 end
            2_365_420_800 // Quarter 80 end
        ];
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

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

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

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

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

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

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

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

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
        if (to == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter);
        _processPendingRewards(msg.sender, currentQuarter);
        _processPendingRewards(to, currentQuarter);

        bool success = super.transfer(to, amount);
        _afterTransfer(msg.sender, to, amount, currentQuarter);

        emit Transfer(msg.sender, to, amount);
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
        if (to == address(0)) revert ZeroAddress();
        if (from == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter);
        _processPendingRewards(from, currentQuarter);
        _processPendingRewards(to, currentQuarter);

        bool success = super.transferFrom(from, to, amount);
        _afterTransfer(from, to, amount, currentQuarter);

        emit Transfer(from, to, amount);
        return success;
    }

    /**
     * @notice Handles post-deposit or mint actions.
     */
    function _afterDepositOrMint(uint256 assets, uint256 shares, address receiver, uint256 currentQuarter) private {
        UserInfo storage _userInfo = userQuarterInfo[receiver][currentQuarter];
        Quarter storage _quarter = quarters[currentQuarter];

        uint256 accruedReward =
            Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION) - _userInfo.rewardDebt;
        _userInfo.rewardAccrued += accruedReward;

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

        uint256 accruedReward =
            Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION) - _userInfo.rewardDebt;
        _userInfo.rewardAccrued += accruedReward;

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
        uint256 accruedReward =
            Math.mulDiv(senderInfo.shares, _quarter.accRewardPerShare, PRECISION) - senderInfo.rewardDebt;

        senderInfo.rewardAccrued += accruedReward;
        senderInfo.shares -= amount;
        senderInfo.rewardDebt = Math.mulDiv(senderInfo.shares, _quarter.accRewardPerShare, PRECISION);
        senderInfo.lastUpdateTimestamp = block.timestamp;

        UserInfo storage recipientInfo = userQuarterInfo[to][currentQuarter];
        accruedReward =
            Math.mulDiv(recipientInfo.shares, _quarter.accRewardPerShare, PRECISION) - recipientInfo.rewardDebt;

        recipientInfo.rewardAccrued += accruedReward;
        recipientInfo.shares += amount;
        recipientInfo.rewardDebt = Math.mulDiv(recipientInfo.shares, _quarter.accRewardPerShare, PRECISION);
        recipientInfo.lastUpdateTimestamp = block.timestamp;
    }

    function _updateQuarter(uint256 currentQuarterIndex) internal {
        Quarter storage _quarter = quarters[currentQuarterIndex];

        // Step 1: Process previous quarters if any that are unprocessed and update the current quarter with the
        // updated data
        for (uint256 i = lastProcessedQuarter; i < currentQuarterIndex;) {
            Quarter storage pastQuarter = quarters[i];
            uint256 quarterEndTime = quarterTimestamps[i + 1];

            // 1. Calculate rewards accrued since the last update to the end of the quarter
            uint256 rewardsAccrued = calculateRewards(pastQuarter.lastUpdateTimestamp, quarterEndTime);
            pastQuarter.totalRewardAccrued += rewardsAccrued;

            // 2. Calculate accRewardPerShare BEFORE updating totalShares to prevent dilution
            if (pastQuarter.totalShares > 0) {
                pastQuarter.accRewardPerShare =
                    Math.mulDiv(pastQuarter.totalRewardAccrued, PRECISION, pastQuarter.totalShares);
            } else {
                pastQuarter.accRewardPerShare = 0;
            }

            // 3. Convert rewards to shares based on the current totalShares and totalStaked
            if (pastQuarter.totalStaked > 0) {
                uint256 newShares = _calculateSharesFromRewards(
                    pastQuarter.totalRewardAccrued, pastQuarter.totalShares, pastQuarter.totalStaked
                );
                quarters[i + 1].totalShares = pastQuarter.totalShares + newShares;
                quarters[i + 1].totalStaked = pastQuarter.totalStaked + pastQuarter.totalRewardAccrued;
            }

            pastQuarter.lastUpdateTimestamp = quarterEndTime;
            quarters[i + 1].lastUpdateTimestamp = quarterEndTime;
            unchecked {
                i++;
            }
        }

        // Step 2: When the previous quarters are processed and the shares and other relevant data are updaetd for the
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

    /// @dev Binary search to get the current quarter index, start timestamp and end timestamp
    function getCurrentQuarter() public view returns (bool valid, uint256 index, uint256 start, uint256 end) {
        /// @todo remove the `flag` and just use if(block.timestmap < quarterTimestamp[0]) for legal/illegal
        uint256 timestamp = block.timestamp;
        uint256 left = 0;
        uint256 right = quarterTimestamps.length - 1;

        // Binary search implementation
        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (timestamp < quarterTimestamps[mid]) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

        // Check if we're in a valid staking period
        if (timestamp >= quarterTimestamps[0] && timestamp < quarterTimestamps[quarterTimestamps.length - 1]) {
            uint256 quarterIndex = left > 0 ? left - 1 : 0;
            return (true, quarterIndex, quarterTimestamps[quarterIndex], quarterTimestamps[quarterIndex + 1]);
        }

        if (timestamp >= quarterTimestamps[quarterTimestamps.length - 1]) {
            return (
                false, quarterTimestamps.length - 2, quarterTimestamps[quarterTimestamps.length - 1], type(uint256).max
            );
        }

        return (false, 0, 0, 0);
    }

    /// @notice calculate the rewards for the given duration
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        if (start > end) return 0;
        uint256 rewards = rewardRate * (end - start);
        return rewards;
    }

    /**
     * @notice Returns the balance of the user including the rewards converted to shares
     */
    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        /**
         * Logic Explanation:
         *         1. Get the user's balance from the ERC20 contract which are the actual minted tokens. It comes from
         * the quarters that are processed,
         *             meaning the last time user did any action.
         *         2. Then run a loop from, user's last interaction to the last any interaction happened in the
         * contract. The reason is that, the quarter could be updated
         *             by any user and that would have updated all the quarters till the current quarter. So, we need to
         * calculate the rewards for the user from the last
         *         3. Then if there are still some quarters left to process, then calculate the rewards without any loop
         * because we already know the reward rate, the time elapsed
         *             and the current total shares and staked data (which from last processed quarter).
         */
        uint256 userLastProcessed = userLastProcessedQuarter[account];

        uint256 balance = userQuarterInfo[account][userLastProcessed].shares;

        (bool isValid, uint256 currentQuarter, uint256 startTimestamp,) = getCurrentQuarter();
        if (!isValid || userLastProcessed == currentQuarter) return balance;

        // Step 1: Start from lastProcessed quarter where the user did the last action
        uint256 processedQuarter = lastProcessedQuarter;
        UserInfo memory _userInfo = userQuarterInfo[account][userLastProcessed];
        Quarter memory _quarter = quarters[userLastProcessed];

        // Step 1: Process the last interacted quarter first and settle that
        uint256 accumulatedReward =
            _userInfo.rewardAccrued + Math.mulDiv(balance, _quarter.accRewardPerShare, PRECISION) - _userInfo.rewardDebt;

        uint256 newShares;

        if (accumulatedReward > 0) {
            newShares = _calculateSharesFromRewards(accumulatedReward, _quarter.totalShares, _quarter.totalStaked);
            balance += newShares;
        }

        // Step 1: Run a loop to process the user rewards from the user's last processed quarter to the last processed
        // global Quarter
        for (uint256 i = userLastProcessed + 1; i < processedQuarter; i++) {
            Quarter memory quarter = quarters[i];

            accumulatedReward = Math.mulDiv(balance, quarter.accRewardPerShare, PRECISION);

            if (accumulatedReward > 0) {
                newShares = _calculateSharesFromRewards(accumulatedReward, quarter.totalShares, quarter.totalStaked);
                balance += newShares;
            }
        }

        // Step 2: From the there on to the current quarter calculate the rewards and shares without loop
        uint256 totalRewards = calculateRewards(_quarter.lastUpdateTimestamp, startTimestamp);
        uint256 accRewardPerShares =
            _quarter.accRewardPerShare + Math.mulDiv(totalRewards, PRECISION, _quarter.totalShares);
        balance += Math.mulDiv(accRewardPerShares, balance, PRECISION) - _userInfo.rewardDebt;

        return balance;
    }

    function calculateSharesFromRewards(
        uint256 rewards,
        uint256 shares,
        uint256 staked
    )
        private
        pure
        returns (uint256)
    {
        if (staked == 0) return 0;
        return Math.mulDiv(rewards, shares, staked);
    }

    // Convert the rewards to shares
    function _processPendingRewards(address user, uint256 currentQuarter) internal {
        uint256 lastProcessed = userLastProcessedQuarter[user];
        uint256 totalShares = userQuarterInfo[user][lastProcessed].shares;
        // Update the current quarter's user data with the last updated quarter's data
        UserInfo storage currentUserInfo = userQuarterInfo[user][currentQuarter];

        // If all quarters are processed then don't do any processing
        if (lastProcessed == currentQuarter) return;

        for (uint256 i = lastProcessed; i < currentQuarter; i++) {
            UserInfo memory userInfo = userQuarterInfo[user][i];
            Quarter memory quarter = quarters[i];
            // Calculate the pending rewards: There is precision error of 1e-18
            uint256 accumulatedReward = Math.mulDiv(totalShares, quarter.accRewardPerShare, PRECISION);
            uint256 pending = userQuarterInfo[user][i].rewardAccrued + accumulatedReward - userInfo.rewardDebt;
            if (pending > 0) {
                // Convert the pending rewards to shares
                uint256 newShares = _calculateSharesFromRewards(pending, totalShares, quarter.totalStaked);
                totalShares += newShares;
            }

            // Reset user's data for thran loop processed quarter
            delete userQuarterInfo[user][i];
        }

        // Mint shares for the user
        _mint(user, totalShares);
        currentUserInfo.shares = totalShares;
        currentUserInfo.lastUpdateTimestamp = quarterTimestamps[currentQuarter];
        userLastProcessedQuarter[user] = currentQuarter;
    }

    /// @dev override totalSupply to return the total supply of the token
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        // Step 1: Initialize the `supply` variable with the last known supply from `Quarter` data
        Quarter memory lastQuarter = quarters[lastProcessedQuarter];
        uint256 supply = lastQuarter.totalShares;
        (bool isValid,, uint256 startTimestamp,) = getCurrentQuarter();
        if (!isValid) return supply;

        // Step 2: Calculate the rewards for the last quarter and convert them to shares
        uint256 rewardsAccumulated =
            lastQuarter.totalRewardAccrued + calculateRewards(lastQuarter.lastUpdateTimestamp, startTimestamp);

        if (lastQuarter.totalStaked > 0) {
            uint256 shares = Math.mulDiv(rewardsAccumulated, lastQuarter.totalShares, lastQuarter.totalStaked);
            supply += shares;
        }

        return supply;
    }

    /**
     * @notice Override the totalAssets to return the total assets staked in the contract
     */
    function totalAssets() public view virtual override returns (uint256) {
        (bool isValid,, uint256 startTimestamp,) = getCurrentQuarter();
        uint256 totalStaked = quarters[lastProcessedQuarter].totalStaked;
        if (!isValid && block.timestamp <= quarterTimestamps[0]) return totalStaked;

        uint256 rewardsAccumulated = quarters[lastProcessedQuarter].totalRewardAccrued
            + calculateRewards(quarters[lastProcessedQuarter].lastUpdateTimestamp, startTimestamp);
        totalStaked += rewardsAccumulated;
        return totalStaked;
    }

    /// @dev override _getVotingUnits to return the balance of the user
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return balanceOf(account);
    }

    function decimals() public view virtual override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return super.decimals();
    }

    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        virtual
        override(ERC20VotesUpgradeable, ERC20Upgradeable)
    {
        super._update(from, to, value);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return super._convertToShares(assets, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    )
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return super._convertToAssets(shares, rounding);
    }
}
