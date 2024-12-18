// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title FlexibleStakingPool
 * @dev Advanced staking contract with enhanced reward calculation and access control
 */
contract FlexibleStakingPool is AccessControl {
    uint256 private constant TIME_UNIT = 1 days;
    uint256 private constant PRECISION_FACTOR = 1e6;

    // Role definitions for Access
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Staking information structure
    struct StakingPosition {
        uint256 depositAmount; // Total amount deposited
        uint256 stakingPeriod; // Chosen staking period
        uint256 initiationTimestamp; // Timestamp of staking start
        uint256 lastRewardTimestamp; // Timestamp of last reward claim
    }

    mapping(address => StakingPosition) private stakingPositions;

    uint256 private maxStakingPeriod;
    uint256 private rewardBoostCoefficient;
    uint256 private rewardClaimCooldown;
    uint256 private annualYieldPercentage;

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

        // Initialize roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Setup the default admin role
        _grantRole(ADMIN_ROLE, msg.sender); // Setup custom admin role

        maxStakingPeriod = _maxPeriod;
        rewardBoostCoefficient = _boostCoeff;
        rewardClaimCooldown = _claimCooldown * TIME_UNIT;
        annualYieldPercentage = _yieldRate;
    }

    /**
     * @dev Modify maximum staking period
     */
    function getMaxStakingPeriod(
        uint256 _newMaxPeriod
    ) external onlyRole(ADMIN_ROLE) {
        maxStakingPeriod = _newMaxPeriod;
        emit ConfigurationUpdated("MaxPeriod", _newMaxPeriod);
    }

    function getMaxStakingPeriod() public view returns (uint256) {
        return maxStakingPeriod;
    }

    /**
     * @dev Modify reward boost coefficient
     */
    function adjustRewardBoost(
        uint256 _newBoostCoeff
    ) external onlyRole(ADMIN_ROLE) {
        rewardBoostCoefficient = _newBoostCoeff;
        emit ConfigurationUpdated("BoostCoeff", _newBoostCoeff);
    }

    function adjustRewardBoost() public view returns (uint256) {
        return rewardBoostCoefficient;
    }

    /**
     * @dev Modify reward claim cooldown
     */
    function modifyClaimCooldown(
        uint256 _newCooldown
    ) external onlyRole(ADMIN_ROLE) {
        rewardClaimCooldown = _newCooldown * TIME_UNIT;
        emit ConfigurationUpdated("ClaimCooldown", _newCooldown);
    }

    function modifyClaimCooldown() public view returns (uint256) {
        return rewardClaimCooldown;
    }

    /**
     * @dev Update annual yield percentage
     */
    function updateYieldRate(
        uint256 _newYieldRate
    ) external onlyRole(ADMIN_ROLE) {
        annualYieldPercentage = _newYieldRate;
        emit ConfigurationUpdated("YieldRate", _newYieldRate);
    }

    function updateYieldRate() public view returns (uint256) {
        return annualYieldPercentage;
    }

    /**
     * @dev Stake tokens with specific locking period
     */

    // Custom Errors
    error NoActiveStake();
    error TokensStillLocked();

    function initiateStake(uint256 _stakingDuration) external payable {
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
            lastRewardTimestamp: block.timestamp
        });

        emit StakeInitiated(msg.sender, msg.value, _stakingDuration);
    }

    /**
     * @dev Withdraw staked tokens and claim rewards
     */
    function concludeStake() external payable {
        StakingPosition storage position = stakingPositions[msg.sender];
        require(position.depositAmount > 0, "No Active Stake");
        require(
            block.timestamp >=
                position.initiationTimestamp +
                    (position.stakingPeriod * TIME_UNIT),
            "Staking Period Incomplete"
        );

        uint256 totalAmount = position.depositAmount +
            computeReward(msg.sender);

        delete stakingPositions[msg.sender];

        uint256 amountToTransfer = position.depositAmount;
        position.depositAmount = 0;

        (bool success, ) = payable(msg.sender).call{value: amountToTransfer}(
            ""
        );
        require(success, "TransferFailed");
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
     * @dev Calculate reward with dynamic boost
     */
    function computeReward(address _staker) public view returns (uint256) {
        StakingPosition memory position = stakingPositions[_staker];
        uint256 boostMultiplier = calculateDynamicBoost(position.stakingPeriod);

        return ((position.depositAmount *
            position.stakingPeriod *
            annualYieldPercentage *
            boostMultiplier) / (100 * PRECISION_FACTOR));
    }

    /**
     * @dev Dynamic boost calculation
     */
    function calculateDynamicBoost(
        uint256 _lockDuration
    ) public view returns (uint256) {
        uint256 dynamicMultiplier = ((_lockDuration * rewardBoostCoefficient) *
            PRECISION_FACTOR) / maxStakingPeriod;
        uint256 maxMultiplierCapped = rewardBoostCoefficient * PRECISION_FACTOR;

        return
            dynamicMultiplier > maxMultiplierCapped
                ? maxMultiplierCapped
                : dynamicMultiplier;
    }

    /**
     * @dev Retrieve current stake amount
     */
    function checkCurrentStake() external view returns (uint256) {
        return stakingPositions[msg.sender].depositAmount;
    }

    // Events
    event ConfigurationUpdated(string parameter, uint256 newValue);
    event StakeInitiated(
        address indexed staker,
        uint256 amount,
        uint256 duration
    );
    event StakeCompleted(address indexed staker, uint256 totalAmount);
    event RewardsDistributed(address indexed staker, uint256 rewardAmount);
}
