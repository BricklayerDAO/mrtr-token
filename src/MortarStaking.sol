// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
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
    error CannotRedeemZero();

    // State Variables
    uint256 public rewardRate;
    uint256 public lastProcessedQuarter;

    mapping(address => uint256) public rewardDebt;

    struct Quarter {
        uint256 accRewardPerShare; // To track the rewards per epoch - Why? In order to calculate this at the end of the
            // epoch
        uint256 lastUpdateTimestamp; // To calculate the rewards for the epoch
        uint256 totalRewardAccrued; // Total rewards accrued in the quarter
        uint256 totalShares; // Needed for accRewardPerShare for the quarter
        uint256 totalStaked; // Needed for accRewardPerShare for the quarter
    }

    struct UserInfo {
        uint128 rewardAccrued;
        uint64 lastUpdateTimestamp;
        uint128 rewardDebt;
        uint128 shares;
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

        // Initialize quarter timestamps
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

        // Calculate total duration based on first and last timestamp
        uint256 totalDuration = quarterTimestamps[quarterTimestamps.length - 1] - quarterTimestamps[0];
        rewardRate = TOTAL_REWARDS / totalDuration;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (assets == 0) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
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

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(receiver, currentQuarter);

        uint256 assets = super.mint(shares, receiver);
        _afterDepositOrMint(assets, shares, receiver, currentQuarter);

        emit Minted(receiver, shares, assets);
        return assets;
    }

    /**
     * @dev Handles post-deposit or mint actions.
     */
    function _afterDepositOrMint(uint256 assets, uint256 shares, address receiver, uint256 currentQuarter) private {
        UserInfo storage userInfo = userQuarterInfo[receiver][currentQuarter];
        Quarter storage quarter = quarters[currentQuarter];

        uint256 accruedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION) - userInfo.rewardDebt;
        userInfo.rewardAccrued += uint128(accruedReward);
        quarter.totalRewardAccrued += uint128(accruedReward);

        userInfo.shares += uint128(shares);
        userInfo.rewardDebt = uint128(Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION));
        userInfo.lastUpdateTimestamp = uint64(block.timestamp);

        quarter.totalShares += uint128(shares);
        quarter.totalStaked += uint128(assets);
    }

    /**
     * @notice Withdraws staked assets by burning shares.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        if (assets == 0) revert CannotWithdrawZero();
        if (receiver == address(0)) revert ZeroAddress();

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
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

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(owner, currentQuarter);

        uint256 assets = super.redeem(shares, receiver, owner);
        _afterWithdrawOrRedeem(assets, shares, owner, currentQuarter);

        emit Redeemed(owner, shares, assets);
        return assets;
    }

    /**
     * @dev Handles post-withdrawal or redeem actions.
     */
    function _afterWithdrawOrRedeem(uint256 assets, uint256 shares, address owner, uint256 currentQuarter) private {
        UserInfo storage userInfo = userQuarterInfo[owner][currentQuarter];
        Quarter storage quarter = quarters[currentQuarter];

        uint256 rewardsAccrued =
            Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION) - userInfo.rewardDebt;
        userInfo.shares -= uint128(shares);
        userInfo.rewardAccrued += uint128(rewardsAccrued);
        quarter.totalRewardAccrued += uint128(rewardsAccrued);

        userInfo.lastUpdateTimestamp = uint64(block.timestamp);
        userInfo.rewardDebt = uint128(Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION));

        quarter.totalShares -= uint128(shares);
        quarter.totalStaked -= uint128(assets);
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

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
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

        (bool isValid, uint256 currentQuarter,, uint256 endTime) = getCurrentQuarter();
        if (!isValid) revert InvalidStakingPeriod();

        _updateQuarter(currentQuarter, endTime);
        _processPendingRewards(from, currentQuarter);
        _processPendingRewards(to, currentQuarter);

        bool success = super.transferFrom(from, to, amount);
        _afterTransfer(from, to, amount, currentQuarter);

        emit Transfer(from, to, amount);
        return success;
    }

    /**
     * @dev Handles post-transfer actions.
     */
    function _afterTransfer(address from, address to, uint256 amount, uint256 currentQuarter) internal {
        Quarter storage quarter = quarters[currentQuarter];

        UserInfo storage senderInfo = userQuarterInfo[from][currentQuarter];
        senderInfo.shares -= uint128(amount);
        senderInfo.rewardDebt = uint128(Math.mulDiv(senderInfo.shares, quarter.accRewardPerShare, PRECISION));

        UserInfo storage recipientInfo = userQuarterInfo[to][currentQuarter];
        recipientInfo.shares += uint128(amount);
        recipientInfo.rewardDebt = uint128(Math.mulDiv(recipientInfo.shares, quarter.accRewardPerShare, PRECISION));
    }

    /**
     * @dev Updates the current quarter's reward distribution.
     */
    function _updateQuarter(uint256 currentQuarterIndex, uint256 endTime) internal {
        Quarter storage currentQuarter = quarters[currentQuarterIndex];
        if (block.timestamp <= endTime) {
            _updateAccRewardPerShare(currentQuarter, block.timestamp);
            return;
        }

        // Avoiding loop by assuming quarters are processed sequentially
        // Update until the current timestamp
        uint256 nextQuarter = currentQuarterIndex + 1;
        if (nextQuarter >= quarterTimestamps.length) return;

        Quarter storage pastQuarter = quarters[currentQuarterIndex];
        uint256 rewardsAccrued = calculateRewards(pastQuarter.lastUpdateTimestamp, endTime);
        pastQuarter.totalRewardAccrued += uint128(rewardsAccrued);

        if (pastQuarter.totalShares > 0) {
            pastQuarter.accRewardPerShare += uint128(Math.mulDiv(rewardsAccrued, PRECISION, pastQuarter.totalShares));
        }

        emit RewardDistributed(currentQuarterIndex, rewardsAccrued);

        pastQuarter.lastUpdateTimestamp = uint64(endTime);
        quarters[nextQuarter].lastUpdateTimestamp = uint64(endTime);

        lastProcessedQuarter = nextQuarter;
    }

    /**
     * @dev Updates the accumulated reward per share for a quarter.
     */
    function _updateAccRewardPerShare(Quarter storage quarter, uint256 currentTime) internal {
        uint256 rewards = calculateRewards(quarter.lastUpdateTimestamp, currentTime);
        quarter.totalRewardAccrued += uint128(rewards);

        if (quarter.totalShares > 0) {
            quarter.accRewardPerShare += uint128(Math.mulDiv(rewards, PRECISION, quarter.totalShares));
        }

        quarter.lastUpdateTimestamp = uint64(currentTime);

        emit RewardDistributed(lastProcessedQuarter, rewards);
    }

    /**
     * @dev Retrieves the current active quarter.
     */
    function getCurrentQuarter() public view returns (bool valid, uint256 index, uint256 start, uint256 end) {
        uint256 timestamp = block.timestamp;
        uint256 left = 0;
        uint256 right = quarterTimestamps.length - 1;

        // Binary search for the current quarter
        while (left < right) {
            uint256 mid = left + (right - left) / 2;
            if (timestamp < quarterTimestamps[mid]) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

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

    /**
     * @notice Calculates the rewards for a given time duration.
     */
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        return rewardRate * (end - start);
    }

    /**
     * @notice Overrides the ERC20 `balanceOf` to include pending rewards.
     */
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

            uint256 accumulatedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, 1e18);
            uint256 pending = userInfo.rewardAccrued + accumulatedReward - userInfo.rewardDebt;

            if (pending > 0) {
                uint256 newShares = calculateSharesFromRewards(pending, quarter.totalShares, quarter.totalStaked);
                balance += newShares;
            }
        }

        // Step 2: From the there on to the current quarter calculate the rewards and shares without loop
        uint256 totalRewards = calculateRewards(quarters[processedQuarter].lastUpdateTimestamp, startTimestamp);

        uint256 accRewardPerShares = quarters[processedQuarter].accRewardPerShare
            + Math.mulDiv(totalRewards, 1e18, quarters[processedQuarter].totalShares);

        balance += Math.mulDiv(accRewardPerShares, balance, 1e18);

        return balance;
    }

    /**
     * @notice Calculates the number of shares from rewards.
     */
    function calculateSharesFromRewards(
        uint256 rewards,
        uint256 shares,
        uint256 staked
    )
        public
        pure
        returns (uint256)
    {
        if (staked == 0) return 0;
        return Math.mulDiv(rewards, shares, staked);
    }

    /**
     * @dev Processes and distributes pending rewards for a user.
     */
    function _processPendingRewards(address user, uint256 currentQuarter) internal {
        uint256 lastProcessed = userLastProcessedQuarter[user];
        uint256 totalShares = userQuarterInfo[user][lastProcessed].shares;

        for (uint256 i = lastProcessed; i < currentQuarter; i++) {
            UserInfo storage userInfo = userQuarterInfo[user][i];
            Quarter storage quarter = quarters[i];

            uint256 accumulatedReward = Math.mulDiv(userInfo.shares, quarter.accRewardPerShare, PRECISION);
            uint256 pending = userInfo.rewardAccrued + accumulatedReward - userInfo.rewardDebt;

            if (pending > 0) {
                uint256 newShares = calculateSharesFromRewards(pending, totalShares, quarter.totalStaked);
                if (newShares > 0) {
                    _mint(user, newShares);
                    totalShares += newShares;
                }
            }

            delete userQuarterInfo[user][i];
        }

        userQuarterInfo[user][currentQuarter].shares = uint128(totalShares);
        userQuarterInfo[user][currentQuarter].lastUpdateTimestamp = uint64(block.timestamp);
        userLastProcessedQuarter[user] = currentQuarter;
    }

    /**
     * @notice Overrides the total supply to include pending rewards.
     */
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        uint256 supply = super.totalSupply();
        (bool isValid, uint256 currentQuarter,,) = getCurrentQuarter();
        if (!isValid) return supply;

        for (uint256 i = lastProcessedQuarter; i < currentQuarter; i++) {
            Quarter memory quarter = quarters[i];
            uint256 rewardsAfterLastAction = calculateRewards(quarter.lastUpdateTimestamp, quarterTimestamps[i + 1]);
            supply += Math.mulDiv(rewardsAfterLastAction, quarter.totalShares, quarter.totalStaked);
        }

        return supply;
    }

    /**
     * @dev Overrides the ERC20Votes `_getVotingUnits`.
     */
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Overrides the ERC20 `decimals`.
     */
    function decimals() public view virtual override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return super.decimals();
    }

    /**
     * @dev Overrides the ERC20Votes `_update`.
     */
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
     * @dev Reserved storage space to allow for layout changes in the future.
     */
    uint256[45] private __gap;
}
