// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MortarStaking is ERC4626Upgradeable, ERC20VotesUpgradeable {
    uint256 private constant TOTAL_REWARDS = 450_000_000 ether;
    uint256 private constant TOTAL_QUARTERS = 80;
    uint256 rewardRate;

    struct Quarter {
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

    mapping(uint256 => Quarter) public quarters;
    mapping(address => mapping(uint256 => UserInfo)) public userQuarterInfo;
    mapping(address => uint256) public userLastProcessedQuarter;

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

    modifier isStakeValid() {
        require(
            block.timestamp >= quarterTimestamps[0] && block.timestamp <= quarterTimestamps[TOTAL_QUARTERS],
            "Staking is not allowed outside the staking period"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _asset) public initializer {
        __ERC4626_init(_asset);
        __ERC20_init("XMortar", "xMRTR");
        __ERC20Votes_init();

        // Initialize reward rate
        uint256 totalDuration = quarterTimestamps[quarterTimestamps.length - 1] - quarterTimestamps[0];
        rewardRate = TOTAL_REWARDS / totalDuration;
    }

    function _updateQuarter() internal {
        uint256 currentTime = block.timestamp;
        (uint256 currentQuarter, uint256 startTime, uint256 endTime) = getCurrentQuarter();

        if (currentTime <= quarters[currentQuarter].lastUpdateTimestamp) {
            return;
        }

        Quarter storage _quarter = quarters[currentQuarter];

        // Only calculate rewards within quarter boundaries
        uint256 calculationEndTime = Math.min(currentTime, endTime);
        uint256 calculationStartTime = Math.max(_quarter.lastUpdateTimestamp, startTime);

        if (_quarter.totalStaked > 0) {
            uint256 rewards = calculateRewards(calculationStartTime, calculationEndTime);
            _quarter.accRewardPerShare += (rewards * 1e12) / _quarter.totalStaked;
        }

        _quarter.lastUpdateTimestamp = calculationEndTime;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        (uint256 currentQuarter,,) = getCurrentQuarter();
        Quarter memory _quarter = quarters[currentQuarter];

        if (_quarter.totalStaked == 0) {
            return assets;
        }

        return (assets * _quarter.totalShares) / _quarter.totalStaked;
    }

    function stake(uint256 amount, address receiver) public isStakeValid {
        // Update the epoch state
        _updateQuarter();

        // Deposit the amount
        uint256 shares = super.deposit(amount, receiver);
        (uint256 currentQuarter,,) = getCurrentQuarter();
        // Load the user and quarter data
        UserInfo memory _userInfo = userQuarterInfo[receiver][currentQuarter];
        Quarter memory _quarter = quarters[currentQuarter];
        // Update user shares
        _userInfo.shares += shares;
        // Update user reward debt
        _userInfo.rewardDebt = (_userInfo.shares * _quarter.accRewardPerShare) / 1e12;
        // Process reward
        _userInfo.rewardAccrued += _calculatePendingRewards(receiver, currentQuarter);
        // Update the last update time
        _userInfo.lastUpdateTime = block.timestamp;

        // Update quarter totals
        _quarter.totalShares += shares;
        _quarter.totalStaked += amount;

        // Save the updated user and quarter data
        userQuarterInfo[receiver][currentQuarter] = _userInfo;
        quarters[currentQuarter] = _quarter;
    }

    function unstake(uint256 amount, address receiver) public {
        // Update the epoch state
        _updateQuarter();

        // Withdraw the amount
        uint256 stake_ = super.withdraw(amount, receiver, msg.sender);
        (uint256 currentQuarter,,) = getCurrentQuarter();
        // Load the user and quarter data
        UserInfo memory _userInfo = userQuarterInfo[msg.sender][currentQuarter];
        Quarter memory _quarter = quarters[currentQuarter];
        // Update user shares
        _userInfo.shares -= amount;
        // Process reward
        _userInfo.rewardAccrued += _calculatePendingRewards(msg.sender, currentQuarter);
        // Update last update time
        _userInfo.lastUpdateTime = block.timestamp;
        // Update user reward debt
        _userInfo.rewardDebt = (_userInfo.shares * _quarter.accRewardPerShare) / 1e12;
        // Update _quarter totals
        _quarter.totalShares -= amount;
        _quarter.totalStaked -= stake_;

        // Save the updated user and quarter data
        userQuarterInfo[msg.sender][currentQuarter] = _userInfo;
        quarters[currentQuarter] = _quarter;
    }

    /// @dev Binary search to get the current quarter index, start timestamp and end timestamp
    // Function to get the current quarter index and its start and end timestamps
    function getCurrentQuarter() public view returns (uint256, uint256, uint256) {
        uint256 currentTimestamp = block.timestamp;
        uint256 low = 0;
        uint256 high = quarterTimestamps.length - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            uint256 quarterEnd = quarterTimestamps[mid];
            uint256 quarterStart = mid == 0 ? quarterTimestamps[0] : quarterTimestamps[mid - 1];

            if (currentTimestamp >= quarterStart && currentTimestamp < quarterEnd) {
                return (mid, quarterStart, quarterEnd);
            } else if (currentTimestamp < quarterStart) {
                if (mid == 0) break;
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        // If current time is beyond the last quarter, return the last quarter's index and timestamps
        uint256 lastIndex = quarterTimestamps.length - 1;
        return (lastIndex, quarterTimestamps[lastIndex - 1], quarterTimestamps[lastIndex]);
    }

    /// @notice calculate the rewards for the given duration
    function calculateRewards(uint256 start, uint256 end) public view returns (uint256) {
        return rewardRate * (end - start);
    }

    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        uint256 balance = super.balanceOf(account);
        uint256 totalShares;
        (uint256 currentQuarter,,) = getCurrentQuarter();
        // Calculate the rewards for the user till now
        for (uint256 i = userLastProcessedQuarter[account]; i < currentQuarter; i++) {
            totalShares += _calculatePendingRewards(account, i);
        }

        return balance + totalShares;
    }

    function _calculatePendingRewards(address user_, uint256 quarter_) internal view returns (uint256) {
        (uint256 currentQuarter,,) = getCurrentQuarter();
        UserInfo memory _userInfo = userQuarterInfo[user_][quarter_];
        Quarter memory _quarter = quarters[quarter_];
        uint256 totalReward = _userInfo.rewardAccrued;
        uint256 totalAccRewardPerShare = _quarter.accRewardPerShare;
        if (quarter_ < currentQuarter && _quarter.lastUpdateTimestamp < quarterTimestamps[quarter_ + 1]) {
            totalAccRewardPerShare = _quarter.accRewardPerShare
                + (calculateRewards(_quarter.lastUpdateTimestamp, quarterTimestamps[quarter_ + 1]) / _quarter.totalShares);
        }

        // Calculated the total reward and the shares from those rewards, between the time of last user action
        // (deposit/withdraw) and quarter end timestamp
        totalReward += ((_userInfo.shares * totalAccRewardPerShare) / 1e12) - _userInfo.rewardDebt;

        // @todo - Redo the asset -> share logic
        return (totalReward * _quarter.totalShares) / _quarter.totalStaked;
    }

    function _processPendingRewards(address user) internal {
        uint256 lastProcessedQuarter = userLastProcessedQuarter[user];
        (uint256 currentQuarter,,) = getCurrentQuarter();
        uint256 shares;
        for (uint256 i = lastProcessedQuarter; i < currentQuarter; i++) {
            UserInfo storage userInfo = userQuarterInfo[user][i];
            Quarter storage quarter = quarters[i];

            // Step 1: Update Quarter Data
            // Update epoch accRewardPerShare up to the end of the epoch if not done
            if (quarter.lastUpdateTimestamp < quarterTimestamps[i + 1]) {
                uint256 rewards = calculateRewards(quarter.lastUpdateTimestamp, quarterTimestamps[i + 1]);
                quarter.accRewardPerShare += (rewards * 1e12) / quarter.totalStaked;
                quarter.lastUpdateTimestamp = quarterTimestamps[i + 1];
            }

            // Step 2: Calculate the pending rewards
            uint256 accumulatedReward = (userInfo.shares * quarter.accRewardPerShare) / 1e12;
            uint256 pending = userQuarterInfo[user][i].rewardAccrued + accumulatedReward - userInfo.rewardDebt;

            if (pending > 0) {
                // Convert the pending rewards to shares
                shares = convertToShares(pending);

                // Mint the shares to the user
                _mint(user, shares);
            }

            userQuarterInfo[user][currentQuarter].shares = shares;

            // Update user's rewardDebt = 0, because we have just only processed the previous quarter's rewards
            // Not the current deposit the user is making or not making, we don't which operation ran!
            // userInfo.rewardDebt = (userInfo.shares * quarter.accRewardPerShare) / 1e12;
        }

        userLastProcessedQuarter[user] = currentQuarter - 1;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        // Process all previous quarters before the transfer/mint/burn happens
        if (from != address(0)) {
            _processPendingRewards(from);
        }

        if (to != address(0)) {
            _processPendingRewards(to);
        }

        // Then perform the transfer/mint/burn
        super._update(from, to, amount);

        (uint256 currentQuarter,,) = getCurrentQuarter();
        Quarter storage quarter = quarters[uint256(currentQuarter)];

        // Transfer
        if (from != address(0) && to != address(0) && from != to) {
            {
                UserInfo storage fromUser = userQuarterInfo[from][uint256(currentQuarter)];
                fromUser.shares -= amount;
                fromUser.rewardDebt = (fromUser.shares * quarter.accRewardPerShare) / 1e12;
            }

            {
                UserInfo storage toUser = userQuarterInfo[to][uint256(currentQuarter)];
                toUser.shares += amount;
                toUser.rewardDebt = (toUser.shares * quarter.accRewardPerShare) / 1e12;
            }
        }

        // Update voting units for ERC20Votes
        _transferVotingUnits(from, to, amount);
    }

    /// @dev override totalSupply to return the total supply of the token
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        uint256 supply = super.totalSupply();

        // Calculate each quarter's rewards, convert them to shares and add them to the total supply
        for (uint256 i = 0; i < TOTAL_QUARTERS; i++) {
            if (quarters[i].totalStaked == 0 || (quarters[i].lastUpdateTimestamp == quarterTimestamps[i + 1])) {
                continue;
            }

            uint256 lastUpdateTimestamp = quarters[i].lastUpdateTimestamp;
            uint256 rewardsAfterLastAction = calculateRewards(lastUpdateTimestamp, quarterTimestamps[i + 1]);

            uint256 shares = (rewardsAfterLastAction * quarters[i].totalShares) / quarters[i].totalStaked;

            supply += shares;
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
}
