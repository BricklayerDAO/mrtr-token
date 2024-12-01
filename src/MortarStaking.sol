// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { MortarStakingTreasury } from "./MortarStakingTreasury.sol";
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
    address public treasury;

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
     * @param _admin The address of the admin.
     */
    function initialize(IERC20 _asset, address _admin) external initializer {
        __ERC4626_init(_asset);
        __ERC20_init("XMortar", "xMRTR");
        __Votes_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        // Grant admin role to the admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Deploy the treasury contract
        treasury = address(new MortarStakingTreasury(_asset, _admin));

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
        // If all quarters are processed already then don't update the user data
        /// @dev We check only for `from` because, in the transfer function, the `to` would also be updated if `from` is
        /// updated till the current quarter
        if (userLastProcessedQuarter[from] == 80) return;

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
                SafeERC20.safeTransferFrom(IERC20(asset()), treasury, address(this), pastQuarter.totalRewardAccrued);
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
