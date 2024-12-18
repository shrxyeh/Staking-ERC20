// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlexibleStakingPool
 * @dev Interface for the Flexible Staking Pool contract
 */
interface IFlexibleStakingPool {
    event StakeInitiated(address indexed staker, uint256 amount, uint256 stakingPeriod);

    event StakeCompleted(address indexed staker, uint256 totalAmount);

    event RewardsDistributed(address indexed staker, uint256 rewardAmount);

    event ConfigurationUpdated(string parameter, uint256 newValue);

    // Errors
    error StakingInProgress();
    error NoActiveStake();
    error StakingPeriodIncomplete();
    error ClaimCooldownActive();
    error NoRewardsAvailable();
    error StakingPeriodExceedsMax();
    error ZeroAmountNotAllowed();
    error InvalidParameterInput();
    error FundsTransferFailed();

    // Configuration Management Functions
    function updateMaxStakingPeriod(uint256 _newMaxPeriod) external;

    function adjustRewardBoost(uint256 _newBoostCoefficient) external;

    function modifyClaimCooldown(uint256 _newCooldown) external;

    function updateYieldRate(uint256 _newYieldRate) external;

    // Staking Lifecycle Functions
    function initiateStake(uint256 _stakingDuration) external payable;

    function concludeStake() external payable;

    function collectRewards() external payable;

    // View Functions
    function checkCurrentStake() external view returns (uint256);

    function computeReward(address _staker) external view returns (uint256);

    function calculateDynamicBoost(uint256 _lockDuration) external view returns (uint256);
}
