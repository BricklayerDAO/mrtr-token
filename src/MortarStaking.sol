// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/console.sol";
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
    uint256 private constant TOTAL_QUARTERS = 80;
    uint256 private constant PRECISION = 1e18;

    // Custom Errors
    error InvalidStakingPeriod();
    error CannotStakeZero();
    error ZeroAddress();
    error CannotWithdrawZero();

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
        uint256 shares = _stake(assets, 0, receiver, true);
        emit Deposited(receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Mints shares by depositing the equivalent assets.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256) {
        uint256 assets = _stake(0, shares, receiver, false);
        emit Minted(receiver, shares, assets);
        return assets;
    }

    /**
     * @dev Internal function to handle staking logic for deposit and mint.
     * TODO: Not a big fan of this function I prefer duplicating the logic in this case
     *    1. checks
     *    2. Quarter update & pernding reward
     *    3. mint / deposit logic
     *    4. after stake
     *    5. return
     */
    function _stake(uint256 assets, uint256 shares, address receiver, bool isDeposit) internal returns (uint256) {
        // TODO: I think it looks better just to do the zero check in deposit and mint functions
        if ((isDeposit && assets == 0) || (!isDeposit && shares == 0)) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(receiver, currentQuarter);

        uint256 result;
        if (isDeposit) {
            result = super.deposit(assets, receiver);
            shares = result;
            assets = assets; // TODO; not needed
        } else {
            result = super.mint(shares, receiver);
            assets = result;
            shares = shares; // TODO; not needed
        }

        _afterStake(assets, shares, receiver, currentQuarter);
        return result;
    }

    function _afterStake(uint256 assets, uint256 shares, address receiver, uint256 currentQuarter) private {
        UserInfo storage userInfo = userQuarterInfo[receiver][currentQuarter];
        Quarter storage quarter = quarters[currentQuarter];

        uint256 accruedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION) - userInfo.rewardDebt;
        userInfo.rewardAccrued += accruedReward;
        quarter.totalRewardAccrued += accruedReward;

        userInfo.shares += shares;
        userInfo.rewardDebt = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION);
        userInfo.lastUpdateTimestamp = block.timestamp;

        quarter.totalShares += shares;
        quarter.totalStaked += assets;
    }

    /**
     * @notice Withdraws staked assets by burning shares.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        uint256 shares = _unstake(assets, 0, receiver, owner, true);
        emit Withdrawn(owner, assets, shares);
        return shares;
    }

    /**
     * @notice Redeems shares to withdraw the equivalent staked assets.
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        uint256 assets = _unstake(0, shares, receiver, owner, false);
        emit Redeemed(owner, shares, assets);
        return assets;
    }

    /**
     * @dev Internal function to handle unstaking logic for withdraw and redeem.
     */
    function _unstake(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        bool isWithdraw
    )
        internal
        returns (uint256)
    {
        if ((isWithdraw && assets == 0) || (!isWithdraw && shares == 0)) revert CannotWithdrawZero();
        if (receiver == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(owner, currentQuarter);

        uint256 result;
        if (isWithdraw) {
            result = super.withdraw(assets, receiver, owner);
            shares = result;
            assets = assets;
        } else {
            result = super.redeem(shares, receiver, owner);
            assets = result;
            shares = shares;
        }

        _afterUnstake(assets, shares, owner, currentQuarter);
        return result;
    }

    function _afterUnstake(uint256 assets, uint256 shares, address owner, uint256 currentQuarter) private {
        UserInfo storage userInfo = userQuarterInfo[owner][currentQuarter];
        Quarter storage quarter = quarters[currentQuarter];

        uint256 accruedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION) - userInfo.rewardDebt;
        userInfo.rewardAccrued += accruedReward;
        quarter.totalRewardAccrued += accruedReward;

        userInfo.shares -= shares;
        userInfo.rewardDebt = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION);
        userInfo.lastUpdateTimestamp = block.timestamp;

        quarter.totalShares -= shares;
        quarter.totalStaked -= assets;
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
        // TODO: _msgSender()
        _transferTokens(msg.sender, to, amount);
        return true; // TODO: Always?
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
        _transferTokens(from, to, amount);
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance < amount) revert ZeroAddress();
        // TODO: What is this????? it should not be needed
        _approve(from, msg.sender, currentAllowance - amount);
        return true;
    }

    /**
     * @dev Internal function to handle token transfers and reward updates.
     */
    function _transferTokens(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(from, currentQuarter);
        _processPendingRewards(to, currentQuarter);

        _afterTransfer(from, to, amount, currentQuarter); // TODO: Doesn't happen completely after the transfer
        super.transfer(to, amount); // TODO: Maybe use transferFrom instead and this remove the _approve that you have above
    }

    /**
     * @dev Handles post-transfer actions.
     */
    function _afterTransfer(address from, address to, uint256 amount, uint256 currentQuarter) internal {
        Quarter storage quarter = quarters[currentQuarter];

        // TODO: Why no rewardAccured update like in the other afterSomething functions?
        UserInfo storage senderInfo = userQuarterInfo[from][currentQuarter];
        senderInfo.shares -= amount;
        senderInfo.rewardDebt = Math.mulDiv(senderInfo.shares, quarter.accRewardPerShare, PRECISION);

        UserInfo storage recipientInfo = userQuarterInfo[to][currentQuarter];
        recipientInfo.shares += amount;
        recipientInfo.rewardDebt = Math.mulDiv(recipientInfo.shares, quarter.accRewardPerShare, PRECISION);
    }

    function _updateQuarter(uint256 currentQuarterIndex, uint256 endTime) internal {
        if (block.timestamp > endTime) return;

        Quarter storage _quarter = quarters[currentQuarterIndex];

        // Process previous quarters and calculate total shares, in order to calculate the rewards for the current
        // quarter
        for (uint256 i = lastProcessedQuarter; i < currentQuarterIndex;) {
            Quarter storage pastQuarter = quarters[i];
            uint256 quarterEndTime = quarterTimestamps[i + 1];

            // 1. Calculate rewards accrued since the last update to the end of the quarter
            uint256 rewardsAccrued = calculateRewards(pastQuarter.lastUpdateTimestamp, quarterEndTime);
            pastQuarter.totalRewardAccrued += rewardsAccrued;

            console.log("_updateQuarter %s: %s", i, rewardsAccrued); // TODO: Remember to remove at the end
            // 2. Calculate accRewardPerShare BEFORE updating totalShares to prevent dilution
            if (pastQuarter.totalShares > 0) {
                pastQuarter.accRewardPerShare =
                    Math.mulDiv(pastQuarter.totalRewardAccrued, PRECISION, pastQuarter.totalShares);
                console.log("_updateQuarter %s: %s", i, pastQuarter.accRewardPerShare); // TODO: Remember to remove at the end
            } else {
                console.log("_updateQuarter %s: %s", i, 0); // TODO: Remember to remove at the end
                pastQuarter.accRewardPerShare = 0; // TODO: Is this needed?
            }

            // 3. Convert rewards to shares based on the current totalShares and totalStaked
            if (pastQuarter.totalStaked > 0) { // TODO: Second time checking this, notice there is no change in the value, should you merge the ifs or fix something?
                uint256 newShares = calculateSharesFromRewards(
                    pastQuarter.totalRewardAccrued, pastQuarter.totalShares, pastQuarter.totalStaked
                );
                quarters[i + 1].totalShares = pastQuarter.totalShares + newShares;
                quarters[i + 1].totalStaked = pastQuarter.totalStaked + pastQuarter.totalRewardAccrued;
                console.log("Quarter %s: %s", i, newShares);
            }

            pastQuarter.lastUpdateTimestamp = quarterEndTime;
            quarters[i + 1].lastUpdateTimestamp = quarterEndTime;
            unchecked {
                i++;
            }
        }

        // Update the accRewardPerShare for the current quarter
        if (_quarter.totalShares > 0) {
            uint256 rewards = calculateRewards(_quarter.lastUpdateTimestamp, block.timestamp);
            _quarter.accRewardPerShare += Math.mulDiv(rewards, PRECISION, _quarter.totalShares);
        }

        // current quarter updates
        // TODO: you should set currentQuarterIndex directly I would say, can it be greater?
        lastProcessedQuarter = lastProcessedQuarter < currentQuarterIndex ? lastProcessedQuarter : currentQuarterIndex;
        _quarter.lastUpdateTimestamp = block.timestamp;
    }

    /// @dev Binary search to get the current quarter index, start timestamp and end timestamp
    function getCurrentQuarter() public view returns (bool valid, uint256 index, uint256 start, uint256 end) {
        uint256 timestamp = block.timestamp;
        uint256 left = 0;
        uint256 right = quarterTimestamps.length - 1;

        // Binary search implementation
        // TODO: Binary search is nice for finding a quarter given a timestamp
        // but not that efficient for getting the current one.
        // I would have a variable indicating the current one, and will increase the value iterating until finding the current one
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
                false,
                quarterTimestamps.length - 2,
                quarterTimestamps[quarterTimestamps.length - 2],
                quarterTimestamps[quarterTimestamps.length - 1]
            );
        }

        return (false, 0, 0, 0);
    }

    /// @notice calculate the rewards for the given duration
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        uint256 rewards = rewardRate * (end - start);
        return rewards;
    }

    /// No need to write a loop. You use the same `totalShares` and `totalStaked` from last action
    /// and use those over the quarters. Use a formula instead to calculate the rewards and then the shares.
    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        uint256 balance = super.balanceOf(account);
        (bool isValid, uint256 currentQuarter, uint256 startTimestamp,) = getCurrentQuarter();
        // Step 1: Start from lastProcessed quarter where the user did the last action
        uint256 userLastProcessed = userLastProcessedQuarter[account];
        if (!isValid || userLastProcessed == currentQuarter) return balance;
        uint256 processedQuarter = lastProcessedQuarter;

        // Step 1: Run a loop to process the user rewards from the user's last processed quarter to the quarter's last
        // processed quarter
        for (uint256 i = userLastProcessed; i < processedQuarter && processedQuarter != 0; i++) {
            UserInfo memory userInfo = userQuarterInfo[account][i];
            Quarter memory quarter = quarters[i];

            uint256 accumulatedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION);
            uint256 pending = userInfo.rewardAccrued + accumulatedReward - userInfo.rewardDebt;

            if (pending > 0) {
                uint256 newShares = calculateSharesFromRewards(pending, quarter.totalShares, quarter.totalStaked);
                balance += newShares;
            }
        }

        // Step 2: From the there on to the current quarter calculate the rewards and shares without loop // TODO: Fix comment
        uint256 totalRewards = calculateRewards(quarters[processedQuarter].lastUpdateTimestamp, startTimestamp);
        uint256 accRewardPerShares = quarters[processedQuarter].accRewardPerShare
            + Math.mulDiv(totalRewards, PRECISION, quarters[processedQuarter].totalShares);

        balance += Math.mulDiv(accRewardPerShares, balance, PRECISION);

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

        for (uint256 i = lastProcessed; i < currentQuarter; i++) { 
            UserInfo storage userInfo = userQuarterInfo[user][i];
            Quarter storage quarter = quarters[i];
            // Calculate the pending rewards: There is precision error of 1e-18
            uint256 accumulatedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION);

            uint256 pending = userQuarterInfo[user][i].rewardAccrued + accumulatedReward - userInfo.rewardDebt;
            if (pending > 0) {
                // Convert the pending rewards to shares
                uint256 newShares = calculateSharesFromRewards(pending, totalShares, quarter.totalStaked);
                totalShares += newShares;
                // Mint the shares to the user
                _mint(user, newShares);
            }

            // Reset user's data for thran loop processed quarter
            delete userQuarterInfo[user][i]; // TODO: nothing is needed anymore?
        }

        userQuarterInfo[user][currentQuarter].shares = totalShares;
        userQuarterInfo[user][currentQuarter].lastUpdateTimestamp = block.timestamp;

        userLastProcessedQuarter[user] = currentQuarter;
    }

    /// @dev override totalSupply to return the total supply of the token
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        // Actual Minted Supply + (Reward to Supply)
        uint256 supply = super.totalSupply();
        (bool isValid, uint256 currentQuarter,, uint256 endTimestamp) = getCurrentQuarter();
        if (!isValid) return supply;
        // Calculate each quarter's rewards, convert them to shares and add them to the total supply
        // TODO: Check lastProcessedQuarter != 0 outside of the for
        for (uint256 i = lastProcessedQuarter; i < currentQuarter && lastProcessedQuarter != 0;) {
            /// @todo Check if shares exists after the last action, then calculate the rewards // TODO: Unresolved?
            uint256 rewardsAfterLastAction = calculateRewards(quarters[i].lastUpdateTimestamp, endTimestamp);
            supply += Math.mulDiv(rewardsAfterLastAction, quarters[i].totalShares, quarters[i].totalStaked);
            unchecked {
                i++;
            }
        }

        return supply;
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
}
