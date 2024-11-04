// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC4626 } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Votes } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MortarStaking is ERC4626Upgradeable, ERC20Votes {
    uint256 constant TOTAL_REWARDS = 450_000_000 ether;
    uint256 constant TOTAL_QUARTERS = 80;

    struct Epoch {
        uint256 accRewardPerShare; // To track the rewards per epoch - Why? In order to calculate this at the end of the
            // epoch
        uint256 lastUpdateTimestamp; // To calculate the rewards for the epoch
        uint256 totalStaked; // Needed for share calculation for the quarter
        uint256 totalShares; // Needed for accRewardPerShare for the quarter
        uint256 totalRewards; // Needed for admin to know how much to transfer at the end of the quarter
    }

    struct UserInfo {
        uint256 rewardAccrued; // Total reward - Not needed actually, but can be used for "optimization"
        uint256 lastUpdateTime; // To calculate the reward from last action till the quarter end timestamp
        uint256 rewardDebt; // To know how much the user's current deposit would have made since the beginning of
            // staking
        uint256 shares; // To calculate the reward for the user in a particular epoch -- reward = accRewardPerEpoch *
            // shares
    }

    mapping(uint256 => Epoch) public epochs;
    mapping(address => mapping(uint256 => UserInfo)) public userEpochInfo;

    uint256[] public quarterTimestamps = [
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string _name, string _symbol) public initializer {
        __ERC4626_init("Mortar", "MRTR");
        __ERC20Votes_init();
    }

    function _updateEpoch() internal {
        uint256 currentTime = block.timestamp;

        if (currentTime <= lastUpdateTime) {
            return;
        }

        // Do not consider reward distribution if no one has staked
        if (totalStaked == 0) {
            lastUpdateTime = currentTime;
            return;
        }

        // Calculate rewards till now
        uint256 rewards = calculateRewards(lastUpdateTime, currentTime);
        accRewardPerShare += (rewards * 1e12) / totalStaked;
        lastUpdateTime = currentTime;
    }

    function pendingRewards(address account) public view returns (uint256) {
        uint256 userShares = balanceOf(account);
        (uint256 quarterIndex,,) = getCurrentQuarter();
        uint256 accumulatedReward = (userShares * epochs[quarterIndex].accRewardPerShare) / 1e12;
        uint256 pending = accumulatedReward - userEpochInfo[account][quarterIndex].rewardDebt;
        return pending;
    }

    function stake(uint256 amount, address receiver) public {
        _updateEpoch();
        uint256 shares = super.deposit(amount, receiver);
        (uint256 currentEpoch,,) = getCurrentQuarter();
        // 1. reward debt
        UserInfo storage user = userEpochInfo[msg.sender][currentEpoch];
        user.rewardDebt = (shares * accRewardPerShare[currentEpoch]) / 1e12;

        user.rewardAccrued += pendingRewards(msg.sender);
        // 2. total shares
        epochs[currentEpoch].totalShares += shares;
        // 3. total staked
        epochs[currentEpoch].totalStaked += amount;
    }

    function unstake(uint256 amount) public {
        _updateEpoch();
        uint256 shares = super.withdraw(msg.sender);
        (uint256 currentEpoch,,) = getCurrentQuarter();
        UserInfo storage user = userEpochInfo[currentEpoch][msg.sender];

        // reward debt
        user.rewardDebt -= (shares * accRewardPerShare) / 1e12;
        // total shares
        epochs[currentEpoch].totalShares -= shares;
        // total staked
        epochs[currentEpoch].totalStaked -= amount;
    }

    /// @dev Binary search to get the current quarter index, start timestamp and end timestamp
    // Function to get the current quarter index and its start and end timestamps
    function getCurrentQuarter() public view returns (uint256, uint256, uint256) {
        uint256 currentTimestamp = block.timestamp;
        uint256 low = 0;
        uint256 high = quarters.length - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            Quarter memory q = quarters[mid];

            if (currentTimestamp >= q.startTimestamp && currentTimestamp < q.endTimestamp) {
                return (mid, q.startTimestamp, q.endTimestamp);
            } else if (currentTimestamp < q.startTimestamp) {
                if (mid == 0) break; // Prevent underflow
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        // Base case
        return (0, 0, 0);
    }

    /// @notice The rewards are distributed linearly over the duration
    /// @dev The rewards per quarter are not constant
    /// @todo: Remove this function and move it to `initialize()` function and make the rewardRate a variable
    function rewardRate() public view returns (uint256) {
        uint256 totalTimeDuration = quarterTimestamps[80] - quarterTimestamps[0];
        return TOTAL_REWARDS / totalTimeDuration;
    }

    /// @notice calculate the rewards for the given duration
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        return rewardRate() * (end - start);
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = super.balanceOf(account);
        uint256 totalShares;
        (uint256 currentQuarter,, uint256 endTimestamp) = getCurrentQuarter();
        // Calculate the rewards for the user till now
        for (uint256 i = 0; i < currentQuarter; i++) {
            UserInfo memory userInfo = userEpochInfo[account][i];
            uint256 totalReward = userInfo.rewardAccrued;
            uint256 totalAccRewardPerShare =
                ((endTimestamp - epochs[i].lastUpdateTimestamp) * rewardRate()) / epochs[i].totalShares;
            // Calculated the total reward and the shares from those rewards, between the time of last user action
            // (deposit/withdraw) and quarter end timestamp
            totalReward += ((userInfo.shares * epochs[i].accRewardPerShare) / 1e12) - userInfo.rewardDebt;
            totalShares += (totalRewards * epochs[i].totalShares) / epochs[i].totalStaked;
        }

        return balance + totalShares;
    }

    function _calculatePendingRewards(
        address account,
        uint256 fromQuarter,
        uint256 toQuarter
    )
        internal
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[account];
        uint256 pending = 0;

        for (uint256 q = fromQuarter; q < toQuarter; q++) {
            QuarterInfo storage qInfo = quarters[q];

            uint256 accRewardPerShare = qInfo.accRewardPerShare;
            if (!qInfo.rewardsDistributed && block.timestamp >= getQuarterEndTimestamp(q)) {
                // Simulate rewards distribution
                if (qInfo.totalStaked > 0) {
                    accRewardPerShare += (rewardPerQuarter * 1e12) / qInfo.totalStaked;
                }
            }
            
            uint256 userShare = (user.amount * accRewardPerShare) / 1e12;
            uint256 reward = userShare - user.rewardDebt;

            pending += reward;

            // Update user reward debt for simulation purposes
            user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;
        }

        return pending;
    }

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    /// @dev override the internal _update function to be able to calculate the whole share balance
    function _update() internal override { }
}
