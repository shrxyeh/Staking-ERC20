// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title FlexibleStakingPool
 * @dev staking contract with enhanced reward calculation, NFT staking, and access control
 */
contract FlexibleStakingPool is AccessControl, ReentrancyGuard {
    // Constants
    uint256 private constant TIME_UNIT = 1 days;
    uint256 private constant PRECISION_FACTOR = 1e6;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @dev Token Staking information structure
     */
    struct StakingPosition {
        uint256 depositAmount; // Total amount deposited
        uint256 stakingPeriod; // Chosen staking period
        uint256 initiationTimestamp; // Timestamp of staking start
        uint256 lastRewardTimestamp; // Timestamp of last reward claim
        uint256 pendingRewards; // Accumulated pending rewards
    }

    /**
     * @dev NFT Staking information structure
     */
    struct UserInfo {
        uint256 numberOfNftsStaked; // Number of NFTs staked by user
        uint256 lastRewardTimestamp; // Timestamp of last NFT reward claim
        uint256 pendingRewards; // Accumulated NFT pending rewards
    }

    // State variables - Token staking
    mapping(address => StakingPosition) private stakingPositions;
    uint256 private maxStakingPeriod;
    uint256 private rewardBoostCoefficient;
    uint256 private rewardClaimCooldown;
    uint256 private annualYieldPercentage;

    // State variables - NFT staking
    IERC20 public rewardToken;
    IERC721 public nftCollection;
    uint256 public nftRewardsPerDay;
    uint256 public totalNftsStaked;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => address) public tokenOwner;
    mapping(address => uint256[]) public userStakedNFTs;

    // Events
    event ConfigurationUpdated(string parameter, uint256 newValue);
    event StakeInitiated(
        address indexed staker,
        uint256 amount,
        uint256 duration
    );
    event StakeCompleted(address indexed staker, uint256 totalAmount);
    event RewardsDistributed(address indexed staker, uint256 rewardAmount);
    event NFTStaked(address indexed user, uint256 tokenId);
    event NFTUnstaked(address indexed user, uint256 tokenId);
    event NFTRewardsDistributed(address indexed user, uint256 amount);
    event NFTRewardsPerDayUpdated(uint256 oldValue, uint256 newValue);

    /**
     * @dev Contract constructor with initial configuration
     */
    constructor(
        uint256 _maxPeriod,
        uint256 _boostCoeff,
        uint256 _claimCooldown,
        uint256 _yieldRate
    ) {
        require(
            _maxPeriod > 0 &&
                _boostCoeff > 0 &&
                _claimCooldown > 0 &&
                _yieldRate > 0,
            "Invalid Initial Parameters"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        maxStakingPeriod = _maxPeriod;
        rewardBoostCoefficient = _boostCoeff;
        rewardClaimCooldown = _claimCooldown * TIME_UNIT;
        annualYieldPercentage = _yieldRate;
    }

    /**
     * @dev Stake tokens with specific locking period
     */
    function initiateStake(
        uint256 _stakingDuration
    ) external payable nonReentrant {
        require(_stakingDuration <= maxStakingPeriod, "Exceeds Max Duration");
        require(msg.value > 0, "Zero Amount Not Allowed");
        require(
            stakingPositions[msg.sender].depositAmount == 0,
            "Ongoing Stake"
        );

        stakingPositions[msg.sender] = StakingPosition({
            depositAmount: msg.value,
            stakingPeriod: _stakingDuration,
            initiationTimestamp: block.timestamp,
            lastRewardTimestamp: block.timestamp,
            pendingRewards: 0
        });

        emit StakeInitiated(msg.sender, msg.value, _stakingDuration);
    }

    /**
     * @dev Withdraw staked tokens and claim rewards
     */
    function concludeStake() external nonReentrant {
        StakingPosition storage position = stakingPositions[msg.sender];
        require(position.depositAmount > 0, "No Active Stake");
        require(
            block.timestamp >=
                position.initiationTimestamp +
                    (position.stakingPeriod * TIME_UNIT),
            "Staking Period Incomplete"
        );

        uint256 totalRewards = computeReward(msg.sender) +
            position.pendingRewards;
        uint256 totalAmount = position.depositAmount + totalRewards;

        delete stakingPositions[msg.sender];

        (bool success, ) = payable(msg.sender).call{value: totalAmount}("");
        require(success, "Transfer Failed");

        emit StakeCompleted(msg.sender, totalAmount);
    }

    /**
     * @dev Claim accumulated rewards
     */
    function collectRewards() external payable {
        StakingPosition storage position = stakingPositions[msg.sender];
        require(position.depositAmount > 0, "No Active Stake");
        require(
            block.timestamp >=
                position.lastRewardTimestamp + rewardClaimCooldown,
            "Claim Cooldown Active"
        );

        uint256 rewardAmount = computeReward(msg.sender);
        require(rewardAmount > 0, "No Rewards Available");

        position.lastRewardTimestamp = block.timestamp;
        payable(msg.sender).transfer(rewardAmount);

        emit RewardsDistributed(msg.sender, rewardAmount);
    }

    /**
     * @dev Initialize NFT staking functionality
     */
    function initializeNFTStaking(
        address _rewardToken,
        address _nftCollection,
        uint256 _nftRewardsPerDay
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _rewardToken != address(0) && _nftCollection != address(0),
            "Invalid addresses"
        );
        require(address(rewardToken) == address(0), "Already initialized");

        rewardToken = IERC20(_rewardToken);
        nftCollection = IERC721(_nftCollection);
        nftRewardsPerDay = _nftRewardsPerDay;
    }

    /**
     * @dev Stake NFT token
     */
    function stakeNFT(uint256 _tokenId) external nonReentrant {
        require(
            address(nftCollection) != address(0),
            "NFT staking not initialized"
        );
        require(
            nftCollection.ownerOf(_tokenId) == msg.sender,
            "Not token owner"
        );

        UserInfo storage user = userInfo[msg.sender];
        user.pendingRewards = calculateNFTRewards(msg.sender);
        user.lastRewardTimestamp = block.timestamp;
        user.numberOfNftsStaked += 1;

        totalNftsStaked += 1;
        tokenOwner[_tokenId] = msg.sender;
        userStakedNFTs[msg.sender].push(_tokenId);

        nftCollection.transferFrom(msg.sender, address(this), _tokenId);
        emit NFTStaked(msg.sender, _tokenId);
    }

    /**
     * @dev Unstake NFT token
     */
    function unstakeNFT(uint256 _tokenId) external nonReentrant {
        require(tokenOwner[_tokenId] == msg.sender, "Not staker of token");

        UserInfo storage user = userInfo[msg.sender];
        user.pendingRewards = calculateNFTRewards(msg.sender);
        user.lastRewardTimestamp = block.timestamp;
        user.numberOfNftsStaked -= 1;

        totalNftsStaked -= 1;
        tokenOwner[_tokenId] = address(0);

        removeStakedNFT(msg.sender, _tokenId);
        nftCollection.transferFrom(address(this), msg.sender, _tokenId);

        emit NFTUnstaked(msg.sender, _tokenId);
    }

    /**
     * @dev Modify maximum staking period
     */
    function setMaxStakingPeriod(
        uint256 _newMaxPeriod
    ) external onlyRole(ADMIN_ROLE) {
        maxStakingPeriod = _newMaxPeriod;
        emit ConfigurationUpdated("MaxPeriod", _newMaxPeriod);
    }

    /**
     * @dev Modify reward boost coefficient
     */
    function setRewardBoostCoefficient(
        uint256 _newBoostCoeff
    ) external onlyRole(ADMIN_ROLE) {
        rewardBoostCoefficient = _newBoostCoeff;
        emit ConfigurationUpdated("BoostCoeff", _newBoostCoeff);
    }

    /**
     * @dev Modify reward claim cooldown
     */
    function setClaimCooldown(
        uint256 _newCooldown
    ) external onlyRole(ADMIN_ROLE) {
        rewardClaimCooldown = _newCooldown * TIME_UNIT;
        emit ConfigurationUpdated("ClaimCooldown", _newCooldown);
    }

    /**
     * @dev Update annual yield percentage
     */
    function setYieldRate(uint256 _newYieldRate) external onlyRole(ADMIN_ROLE) {
        annualYieldPercentage = _newYieldRate;
        emit ConfigurationUpdated("YieldRate", _newYieldRate);
    }

    /**
     * @dev Emergency withdrawal of contract balance
     */
    function emergencyWithdraw() external onlyRole(ADMIN_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @dev Calculate reward with dynamic boost
     */
    function computeReward(address _staker) public view returns (uint256) {
        StakingPosition memory position = stakingPositions[_staker];
        uint256 boostMultiplier = calculateDynamicBoost(position.stakingPeriod);

        return
            (position.depositAmount *
                position.stakingPeriod *
                annualYieldPercentage *
                boostMultiplier) / (100 * PRECISION_FACTOR);
    }

    /**
     * @dev Calculate NFT rewards for a user
     */
    function calculateNFTRewards(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        if (user.numberOfNftsStaked == 0) {
            return user.pendingRewards;
        }

        uint256 daysSinceLastReward = (block.timestamp -
            user.lastRewardTimestamp) / TIME_UNIT;
        uint256 totalRewards = (daysSinceLastReward * nftRewardsPerDay);

        return
            user.pendingRewards +
            ((totalRewards * user.numberOfNftsStaked) / totalNftsStaked);
    }

    /**
     * @dev Dynamic boost calculation
     */
    function calculateDynamicBoost(
        uint256 _lockDuration
    ) public view returns (uint256) {
        uint256 dynamicMultiplier = (_lockDuration *
            rewardBoostCoefficient *
            PRECISION_FACTOR) / maxStakingPeriod;
        uint256 maxMultiplierCapped = rewardBoostCoefficient * PRECISION_FACTOR;

        return
            dynamicMultiplier > maxMultiplierCapped
                ? maxMultiplierCapped
                : dynamicMultiplier;
    }

    /**
     * @dev Getter functions for contract parameters
     */
    function getMaxStakingPeriod() public view returns (uint256) {
        return maxStakingPeriod;
    }

    function getRewardBoostCoefficient() public view returns (uint256) {
        return rewardBoostCoefficient;
    }

    function getClaimCooldown() public view returns (uint256) {
        return rewardClaimCooldown;
    }

    function getStakeAmount(address _staker) public view returns (uint256) {
        return stakingPositions[_staker].depositAmount;
    }

    function getYieldRate() public view returns (uint256) {
        return annualYieldPercentage;
    }

    function checkCurrentStake() external view returns (uint256) {
        return stakingPositions[msg.sender].depositAmount;
    }

    /**
     * @dev Remove NFT from user's staked list
     */
    function removeStakedNFT(address _user, uint256 _tokenId) internal {
        uint256[] storage userNFTs = userStakedNFTs[_user];
        for (uint256 i = 0; i < userNFTs.length; i++) {
            if (userNFTs[i] == _tokenId) {
                userNFTs[i] = userNFTs[userNFTs.length - 1];
                userNFTs.pop();
                break;
            }
        }
    }
}
