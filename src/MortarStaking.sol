// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { MortarStakingTreasury } from "./MortarStakingTreasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { VotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
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

    /// @custom:storage-location erc7201:bricklayerDAO.storage.MortarStaking
    struct StakingStorage {
        uint256 rewardRate;
        uint256 lastProcessedQuarter;
        address treasury;
        // Mappings
        mapping(uint256 => Quarter) quarters;
        mapping(address => mapping(uint256 => UserInfo)) userQuarterInfo;
        mapping(address => uint256) userLastProcessedQuarter;
        // Array of quarter end timestamps
        uint256[] quarterTimestamps;
        // Quary data
        uint256 lastQuaryRewards;
        uint256 distributionTimestamp;
        uint256 claimedQuarryRewards;
        mapping(address => uint256) lastQuarryClaimedTimestamp;
    }

    // Constants
    uint256 private constant TOTAL_REWARDS = 450_000_000 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant CLAIM_PERIOD = 30 days;
    bytes32 public constant QUARRY_ROLE = keccak256("QUARRY_ROLE");
    // keccak256(abi.encode(uint256(keccak256("bricklayerDAO.storage.MortarStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MortarStakingStorageLocation =
        0xeb60ae2f593341966fbcbc1f5990151523f8acd89874031aa83b032b2e04cc00;

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

    modifier onlyStakingPeriod() {
        _onlyStakingPeriod();
        _;
    }

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

        StakingStorage storage $ = _getStakingStorage();

        $.treasury = address(new MortarStakingTreasury(_asset, _admin));
        // Quarter is open set of the time period
        // E.g., (1_735_084_800 + 1) to (1_742_860_800 - 1) is first quarter
        $.quarterTimestamps = [
            1_735_084_800, // Quarter 1 start
            1_742_860_800, // Quarter 1 end
            1_750_723_200, // Quarter 2 end
            1_759_104_000, // Quarter 3 end
            1_766_620_800, // Quarter 4 end
            1_774_396_800, // Quarter 5 end
            1_782_259_200, // Quarter 6 end
            1_790_640_000, // Quarter 7 end
            1_798_156_800, // Quarter 8 end
            1_805_932_800, // Quarter 9 end
            1_813_795_200, // Quarter 10 end
            1_822_176_000, // Quarter 11 end
            1_829_692_800, // Quarter 12 end
            1_837_555_200, // Quarter 13 end
            1_845_417_600, // Quarter 14 end
            1_853_798_400, // Quarter 15 end
            1_861_315_200, // Quarter 16 end
            1_869_091_200, // Quarter 17 end
            1_876_953_600, // Quarter 18 end
            1_885_334_400, // Quarter 19 end
            1_892_851_200, // Quarter 20 end
            1_900_627_200, // Quarter 21 end
            1_908_489_600, // Quarter 22 end
            1_916_870_400, // Quarter 23 end
            1_924_387_200, // Quarter 24 end
            1_932_163_200, // Quarter 25 end
            1_940_025_600, // Quarter 26 end
            1_948_406_400, // Quarter 27 end
            1_955_923_200, // Quarter 28 end
            1_963_785_600, // Quarter 29 end
            1_971_648_000, // Quarter 30 end
            1_980_028_800, // Quarter 31 end
            1_987_545_600, // Quarter 32 end
            1_995_321_600, // Quarter 33 end
            2_003_184_000, // Quarter 34 end
            2_011_564_800, // Quarter 35 end
            2_019_081_600, // Quarter 36 end
            2_026_857_600, // Quarter 37 end
            2_034_720_000, // Quarter 38 end
            2_043_100_800, // Quarter 39 end
            2_050_617_600, // Quarter 40 end
            2_058_393_600, // Quarter 41 end
            2_066_256_000, // Quarter 42 end
            2_074_636_800, // Quarter 43 end
            2_082_153_600, // Quarter 44 end
            2_090_016_000, // Quarter 45 end
            2_097_878_400, // Quarter 46 end
            2_106_259_200, // Quarter 47 end
            2_113_776_000, // Quarter 48 end
            2_121_552_000, // Quarter 49 end
            2_129_414_400, // Quarter 50 end
            2_137_795_200, // Quarter 51 end
            2_145_312_000, // Quarter 52 end
            2_153_088_000, // Quarter 53 end
            2_160_950_400, // Quarter 54 end
            2_169_331_200, // Quarter 55 end
            2_176_848_000, // Quarter 56 end
            2_184_624_000, // Quarter 57 end
            2_192_486_400, // Quarter 58 end
            2_200_867_200, // Quarter 59 end
            2_208_384_000, // Quarter 60 end
            2_216_246_400, // Quarter 61 end
            2_224_108_800, // Quarter 62 end
            2_232_489_600, // Quarter 63 end
            2_240_006_400, // Quarter 64 end
            2_247_782_400, // Quarter 65 end
            2_255_644_800, // Quarter 66 end
            2_264_025_600, // Quarter 67 end
            2_271_542_400, // Quarter 68 end
            2_279_318_400, // Quarter 69 end
            2_287_180_800, // Quarter 70 end
            2_295_561_600, // Quarter 71 end
            2_303_078_400, // Quarter 72 end
            2_310_854_400, // Quarter 73 end
            2_318_716_800, // Quarter 74 end
            2_327_097_600, // Quarter 75 end
            2_334_614_400, // Quarter 76 end
            2_342_476_800, // Quarter 77 end
            2_350_339_200, // Quarter 78 end
            2_358_720_000, // Quarter 79 end
            2_366_236_800 // Quarter 80 end
        ];
        // Initialize reward rate
        uint256 totalDuration = $.quarterTimestamps[$.quarterTimestamps.length - 1] - $.quarterTimestamps[0];
        $.rewardRate = TOTAL_REWARDS / totalDuration;
    }

    /**
     * @notice Deposits assets and stakes them, receiving shares in return.
     * @param assets The amount of assets to deposit.
     * @param receiver The address that will receive the shares.
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override
        nonReentrant
        onlyStakingPeriod
        returns (uint256)
    {
        if (assets == 0) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        StakingStorage storage $ = _getStakingStorage();

        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, receiver, currentQuarter);
        uint256 shares = super.deposit(assets, receiver);
        _afterDepositOrMint($, assets, shares, receiver, currentQuarter);
        emit Deposited(receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Mints shares by depositing the equivalent assets.
     * @param shares The amount of shares to mint.
     * @param receiver The address that will receive the assets.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant onlyStakingPeriod returns (uint256) {
        if (shares == 0) revert CannotStakeZero();
        if (receiver == address(0)) revert ZeroAddress();

        StakingStorage storage $ = _getStakingStorage();
        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, receiver, currentQuarter);

        uint256 assets = super.mint(shares, receiver);
        _afterDepositOrMint($, assets, shares, receiver, currentQuarter);

        emit Minted(receiver, shares, assets);
        return assets;
    }

    /**
     * @notice Withdraws staked assets by burning shares.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address that will receive the assets.
     * @param owner The address that owns the shares.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant returns (uint256) {
        if (assets == 0) revert CannotWithdrawZero();
        if (receiver == address(0)) revert ZeroAddress();

        StakingStorage storage $ = _getStakingStorage();
        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, owner, currentQuarter);

        uint256 shares = super.withdraw(assets, receiver, owner);
        _afterWithdrawOrRedeem($, assets, shares, owner, currentQuarter);

        emit Withdrawn(owner, assets, shares);
        return shares;
    }

    /**
     * @notice Redeems shares to withdraw the equivalent staked assets.
     * @param shares The amount of shares to redeem.
     * @param receiver The address that will receive the assets.
     * @param owner The address that owns the shares.
     */
    function redeem(uint256 shares, address receiver, address owner) public override nonReentrant returns (uint256) {
        if (shares == 0) revert CannotRedeemZero();
        if (receiver == address(0)) revert ZeroAddress();

        StakingStorage storage $ = _getStakingStorage();
        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, owner, currentQuarter);

        uint256 assets = super.redeem(shares, receiver, owner);
        _afterWithdrawOrRedeem($, assets, shares, owner, currentQuarter);

        emit Redeemed(owner, shares, assets);
        return assets;
    }

    /**
     * @notice Transfers tokens and updates rewards for sender and receiver.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
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
        StakingStorage storage $ = _getStakingStorage();
        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, msg.sender, currentQuarter);
        _processPendingRewards($, to, currentQuarter);
        _afterTransfer($, msg.sender, to, amount, currentQuarter);

        bool success = super.transfer(to, amount);
        return success;
    }

    /**
     * @notice Transfers tokens on behalf of another address and updates rewards.
     * @param from The address to transfer the tokens from.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
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
        StakingStorage storage $ = _getStakingStorage();
        (uint256 currentQuarter,,) = _getCurrentQuarter($);

        _updateQuarter($, currentQuarter);
        _processPendingRewards($, from, currentQuarter);
        _processPendingRewards($, to, currentQuarter);

        bool success = super.transferFrom(from, to, amount);
        _afterTransfer($, from, to, amount, currentQuarter);

        return success;
    }

    /**
     * @notice Handles post-deposit or mint actions.
     * @param assets The amount of assets deposited or minted.
     * @param shares The amount of shares received.
     * @param receiver The address that received the assets or shares.
     * @param currentQuarter The index of the current quarter.
     */
    function _afterDepositOrMint(
        StakingStorage storage $,
        uint256 assets,
        uint256 shares,
        address receiver,
        uint256 currentQuarter
    )
        private
    {
        UserInfo storage _userInfo = $.userQuarterInfo[receiver][currentQuarter];
        Quarter storage _quarter = $.quarters[currentQuarter];

        _userInfo.shares += shares;
        _userInfo.rewardDebt = Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION);
        _userInfo.lastUpdateTimestamp = block.timestamp;

        _quarter.totalShares += shares;
        _quarter.totalStaked += assets;
    }

    /**
     * @notice Handles post-withdraw or redeem actions.
     * @param assets The amount of assets withdrawn or redeemed.
     * @param shares The amount of shares burned.
     * @param owner The address that owns the shares.
     * @param currentQuarter The index of the current quarter.
     */
    function _afterWithdrawOrRedeem(
        StakingStorage storage $,
        uint256 assets,
        uint256 shares,
        address owner,
        uint256 currentQuarter
    )
        private
    {
        UserInfo storage _userInfo = $.userQuarterInfo[owner][currentQuarter];
        Quarter storage _quarter = $.quarters[currentQuarter];

        _userInfo.shares -= shares;
        _userInfo.rewardDebt = Math.mulDiv(_userInfo.shares, _quarter.accRewardPerShare, PRECISION);
        _userInfo.lastUpdateTimestamp = block.timestamp;

        _quarter.totalShares -= shares;
        _quarter.totalStaked -= assets;
    }

    /**
     * @dev Handles post-transfer actions.
     * @param from The address from which the assets are transferred.
     * @param to The address to which the assets are transferred.
     * @param amount The amount of assets transferred.
     * @param currentQuarter The index of the current quarter.
     */
    function _afterTransfer(
        StakingStorage storage $,
        address from,
        address to,
        uint256 amount,
        uint256 currentQuarter
    )
        internal
    {
        // If all quarters are processed already then don't update the user data
        /// @dev We check only for `from` because, in the transfer function, the `to` would also be updated if `from` is
        /// updated till the current quarter
        if ($.userLastProcessedQuarter[from] == 80) return;

        Quarter storage _quarter = $.quarters[currentQuarter];

        UserInfo storage senderInfo = $.userQuarterInfo[from][currentQuarter];
        senderInfo.shares -= amount;
        senderInfo.rewardDebt = Math.mulDiv(senderInfo.shares, _quarter.accRewardPerShare, PRECISION);
        senderInfo.lastUpdateTimestamp = block.timestamp;

        UserInfo storage recipientInfo = $.userQuarterInfo[to][currentQuarter];
        recipientInfo.shares += amount;
        recipientInfo.rewardDebt = Math.mulDiv(recipientInfo.shares, _quarter.accRewardPerShare, PRECISION);
        recipientInfo.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @dev Updates the quarter data.
     * @param currentQuarterIndex The index of the current quarter.
     */
    function _updateQuarter(StakingStorage storage $, uint256 currentQuarterIndex) internal {
        // If all quarters are already processed, return
        if ($.lastProcessedQuarter == 80) return;
        Quarter storage _quarter = $.quarters[currentQuarterIndex];

        // Step 1: Process previous quarters if any that are unprocessed and update the current quarter with the
        // updated data
        for (uint256 i = $.lastProcessedQuarter; i < currentQuarterIndex;) {
            Quarter storage pastQuarter = $.quarters[i];
            uint256 quarterEndTime = $.quarterTimestamps[i + 1];

            if (pastQuarter.totalShares > 0) {
                // 1. Calculate rewards accrued since the last update to the end of the quarter
                uint256 rewardsAccrued = _calculateRewards($, pastQuarter.lastUpdateTimestamp, quarterEndTime);

                pastQuarter.totalRewardAccrued += rewardsAccrued;

                // 2. Calculate accRewardPerShare BEFORE updating totalShares to prevent dilution

                pastQuarter.accRewardPerShare += Math.mulDiv(rewardsAccrued, PRECISION, pastQuarter.totalShares);

                // 3. Convert rewards to shares and mint them
                uint256 newShares = convertToShares(pastQuarter.totalRewardAccrued);
                pastQuarter.sharesGenerated = newShares;
                // Mint the shares and pull reward tokens from the treasury
                _mint(address(this), newShares);
                SafeERC20.safeTransferFrom(IERC20(asset()), $.treasury, address(this), pastQuarter.totalRewardAccrued);
                // Update the next quarter's totalShares and totalStaked
                $.quarters[i + 1].totalShares = pastQuarter.totalShares + newShares;
                $.quarters[i + 1].totalStaked = pastQuarter.totalStaked + pastQuarter.totalRewardAccrued;
            }

            pastQuarter.lastUpdateTimestamp = quarterEndTime;
            $.quarters[i + 1].lastUpdateTimestamp = quarterEndTime;
            unchecked {
                i++;
            }
        }

        // Step 2: When the previous quarters are processed and the shares and other relevant data are updated for the
        // current quarter
        // Then calculate the accRewardPerShare
        if (_quarter.totalShares > 0) {
            uint256 rewards = _calculateRewards($, _quarter.lastUpdateTimestamp, block.timestamp);
            _quarter.totalRewardAccrued += rewards;
            _quarter.accRewardPerShare += Math.mulDiv(rewards, PRECISION, _quarter.totalShares);
        }

        // current quarter updates
        $.lastProcessedQuarter = currentQuarterIndex;
        _quarter.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Gives quarter index data for the current timestamp
     */
    function getCurrentQuarter() external view returns (uint256 index, uint256 start, uint256 end) {
        StakingStorage storage $ = _getStakingStorage();
        return _getCurrentQuarter($);
    }

    /**
     * @dev Gets the current quarter index, start timestamp and end timestamp.
     */
    function _getCurrentQuarter(StakingStorage storage $)
        internal
        view
        returns (uint256 index, uint256 start, uint256 end)
    {
        return _getQuarter($, block.timestamp);
    }

    /**
     * @dev Gets the quarter index, start timestamp and end timestamp for a given timestamp.
     * @param timestamp The timestamp for which to get the quarter data.
     */
    function getQuarter(uint256 timestamp) external view returns (uint256 index, uint256 start, uint256 end) {
        StakingStorage storage $ = _getStakingStorage();
        return _getQuarter($, timestamp);
    }

    /**
     * @dev Gets the quarter index, start timestamp and end timestamp for a given timestamp.
     * @param $ The storage slot of the StakingStorage.
     * @param timestamp The timestamp for which to get the quarter data.
     */
    function _getQuarter(
        StakingStorage storage $,
        uint256 timestamp
    )
        internal
        view
        returns (uint256 index, uint256 start, uint256 end)
    {
        uint256 left = 0;
        uint256[] memory arr = $.quarterTimestamps;
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

    /**
     * @dev Calculates the rewards for the given duration.
     * @param start The start timestamp.
     * @param end The end timestamp.
     */
    function calculateRewards(uint256 start, uint256 end) external view returns (uint256) {
        StakingStorage storage $ = _getStakingStorage();
        return _calculateRewards($, start, end);
    }

    /**
     * @dev Calculates the rewards for the given duration.
     * @param start The start timestamp.
     * @param end The end timestamp.
     */
    function _calculateRewards(StakingStorage storage $, uint256 start, uint256 end) internal view returns (uint256) {
        if (start > end) return 0;
        uint256 rewards = $.rewardRate * (end - start);
        return rewards;
    }

    /**
     * @dev Processes the pending rewards for a user.
     * @param user The address of the user.
     * @param currentQuarter The index of the current quarter.
     */
    function _processPendingRewards(StakingStorage storage $, address user, uint256 currentQuarter) internal {
        uint256 lastProcessed = $.userLastProcessedQuarter[user];
        if (lastProcessed == 80) return;

        uint256 userShares = $.userQuarterInfo[user][lastProcessed].shares;
        uint256 initialShares = userShares;

        for (uint256 i = lastProcessed; i < currentQuarter; i++) {
            UserInfo storage userInfo = $.userQuarterInfo[user][i];
            Quarter memory quarter = $.quarters[i];
            if (userShares > 0) {
                // Calculate the pending rewards: There is precision error of 1e-18
                uint256 accumulatedReward = Math.mulDiv(userShares, quarter.accRewardPerShare, PRECISION);
                userInfo.rewardAccrued += accumulatedReward - userInfo.rewardDebt;
                userInfo.rewardDebt = accumulatedReward;
                if (userInfo.rewardAccrued > 0) {
                    // Convert the rewards to shares
                    uint256 newShares =
                        Math.mulDiv(userInfo.rewardAccrued, quarter.sharesGenerated, quarter.totalRewardAccrued);
                    $.userQuarterInfo[user][i + 1].shares = userInfo.shares + newShares;
                    userShares += newShares;
                }
            }
            uint256 endTimestamp = $.quarterTimestamps[i + 1];
            userInfo.lastUpdateTimestamp = endTimestamp;
        }

        // Transfer shares to the user
        _transfer(address(this), user, userShares - initialShares);

        // Update the current quarter's user data with the last updated quarter's data
        UserInfo storage currentUserInfo = $.userQuarterInfo[user][currentQuarter];

        // @dev userShares = currentUserInfo.shares
        if (userShares > 0) {
            uint256 accReward = Math.mulDiv(userShares, $.quarters[currentQuarter].accRewardPerShare, PRECISION);
            currentUserInfo.rewardAccrued += accReward - currentUserInfo.rewardDebt;
            currentUserInfo.rewardDebt = accReward;
        }

        currentUserInfo.lastUpdateTimestamp = block.timestamp;
        $.userLastProcessedQuarter[user] = currentQuarter;
    }

    /**
     * @notice Override the totalAssets to return the total assets staked in the contract.
     * @return The total assets staked in the contract.
     */
    function totalAssets() public view virtual override returns (uint256) {
        StakingStorage storage $ = _getStakingStorage();
        return super.totalAssets() - ($.lastQuaryRewards - $.claimedQuarryRewards);
    }

    /**
     * @dev Override the _getVotingUnits to return the balance of the user.
     * @param account The address of the user.
     * @return The balance of the user.
     */
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Claims the staking rewards for a user.
     * @param account The address of the user.
     */
    function claim(address account) external {
        StakingStorage storage $ = _getStakingStorage();
        (uint256 index,,) = _getCurrentQuarter($);
        _updateQuarter($, index);
        _processPendingRewards($, account, index);
    }

    /**
     * @dev Adds quarry rewards to the contract.
     * @param amount The amount of rewards to add.
     */
    function addQuarryRewards(uint256 amount) external onlyRole(QUARRY_ROLE) {
        StakingStorage storage $ = _getStakingStorage();
        if ($.claimedQuarryRewards != $.lastQuaryRewards) {
            revert UnclaimedQuarryRewardsAssetsLeft();
        }
        $.lastQuaryRewards = amount;
        $.claimedQuarryRewards = 0;
        $.distributionTimestamp = block.timestamp;

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        emit QuarryRewardsAdded(amount, $.distributionTimestamp);
    }

    /**
     * @dev Claims the quarry rewards for a user.
     * @param user The address of the user.
     */
    function claimQuarryRewards(address user) external {
        StakingStorage storage $ = _getStakingStorage();
        if (block.timestamp > $.distributionTimestamp + CLAIM_PERIOD) {
            revert ClaimPeriodOver();
        }
        if ($.lastQuarryClaimedTimestamp[user] >= $.distributionTimestamp) {
            revert QuarryRewardsAlreadyClaimed();
        }

        uint256 userShares = getPastVotes(msg.sender, $.distributionTimestamp);
        uint256 totalShares = getPastTotalSupply($.distributionTimestamp);
        uint256 rewards = Math.mulDiv(userShares, $.lastQuaryRewards, totalShares);

        if (rewards > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), msg.sender, rewards);
            $.claimedQuarryRewards += rewards;
        }
        $.lastQuarryClaimedTimestamp[user] = $.distributionTimestamp;
        emit QuarryRewardsClaimedQuarryRewards(user, rewards);
    }

    /**
     * @dev Retrieves the unclaimed quarry rewards.
     */
    function retrieveUnclaimedQuarryRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        StakingStorage storage $ = _getStakingStorage();
        if (block.timestamp <= $.distributionTimestamp + CLAIM_PERIOD) {
            revert ClaimPeriodNotOver();
        }
        uint256 unclaimedQuarryRewards = $.lastQuaryRewards - $.claimedQuarryRewards;
        $.claimedQuarryRewards = $.lastQuaryRewards;
        SafeERC20.safeTransfer(IERC20(asset()), msg.sender, unclaimedQuarryRewards);
        emit UnclaimedQuarryRewardsQuarryRewardsRetrieved(unclaimedQuarryRewards);
    }

    /**
     * @dev Checks if the current timestamp is within the staking period.
     */
    function _onlyStakingPeriod() internal view {
        StakingStorage storage $ = _getStakingStorage();
        if (
            block.timestamp < $.quarterTimestamps[0]
                || block.timestamp >= $.quarterTimestamps[$.quarterTimestamps.length - 1]
        ) revert InvalidStakingPeriod();
    }

    /**
     * @dev Override the clock function to return the block timestamp.
     * @return The block timestamp.
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @dev Override the clock mode to return the timestamp.
     * @return The clock mode.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.timestamp()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=timestamp";
    }

    /**
     * @dev Gets the storage slot of the StakingStorage.
     * @return $ The storage slot of the StakingStorage.
     */
    function _getStakingStorage() internal pure returns (StakingStorage storage $) {
        assembly {
            $.slot := MortarStakingStorageLocation
        }
    }

    /**
     * @dev Gets the treasury address.
     * @return The treasury address.
     */
    function treasury() public view returns (address) {
        StakingStorage storage $ = _getStakingStorage();
        return $.treasury;
    }

    /**
     * @dev Gets the quarter timestamp at a given index.
     * @param index The index of the quarter.
     * @return The quarter timestamp.
     */
    function quarterTimestamps(uint256 index) public view returns (uint256) {
        StakingStorage storage $ = _getStakingStorage();
        return $.quarterTimestamps[index];
    }

    /**
     * @dev Gets the reward rate.
     * @return The reward rate.
     */
    function rewardRate() public view returns (uint256) {
        StakingStorage storage $ = _getStakingStorage();
        return $.rewardRate;
    }

    /**
     * @dev Gets the user's quarter info.
     * @param user The address of the user.
     * @param quarter The index of the quarter.
     * @return The user's quarter info.
     */
    function userQuarterInfo(address user, uint256 quarter) public view returns (UserInfo memory) {
        StakingStorage storage $ = _getStakingStorage();
        return $.userQuarterInfo[user][quarter];
    }

    /**
     * @dev Gets the quarter data at a given index.
     * @param index The index of the quarter.
     * @return The quarter data.
     */
    function quarters(uint256 index) public view returns (Quarter memory) {
        StakingStorage storage $ = _getStakingStorage();
        return $.quarters[index];
    }
}
