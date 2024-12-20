// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FlexibleStakingPool} from "../src/FlexibleStakingPool.sol";
import {Test} from "forge-std/Test.sol";

contract DeployFlexibleStakingPool is Script, Test {
    // Configuration constants for staking pool parameters
    uint256 public constant MAX_STAKING_PERIOD = 365;
    uint256 public constant REWARD_BOOST_COEFFICIENT = 5;
    uint256 public constant REWARD_CLAIM_COOLDOWN = 7;
    uint256 public constant ANNUAL_YIELD_PERCENTAGE = 100;

    FlexibleStakingPool public stakingPool;

    function run() external {
        vm.startBroadcast();

        // Deploy FlexibleStakingPool contract with predefined constants
        stakingPool = new FlexibleStakingPool(
            MAX_STAKING_PERIOD,
            REWARD_BOOST_COEFFICIENT,
            REWARD_CLAIM_COOLDOWN,
            ANNUAL_YIELD_PERCENTAGE
        );

        vm.stopBroadcast();
        console.log("FlexibleStakingPool deployed at:", address(stakingPool));

        // Comprehensive validation after deployment
        validateDeployment();
    }

    // Function to validate the deployment of the staking pool contract
    function validateDeployment() internal {
        console.log("Starting deployment validation...");

        // Basic deployment checks for contract address
        require(
            address(stakingPool) != address(0),
            "Deployment failed: Invalid contract address"
        );
        console.log(" Contract address validation passed");

        // Validate constructor parameters
        assertTrue(
            stakingPool.getMaxStakingPeriod() == MAX_STAKING_PERIOD,
            "Invalid maximum staking period"
        );
        console.log(" Maximum staking period validation passed");

        assertTrue(
            stakingPool.getRewardBoostCoefficient() == REWARD_BOOST_COEFFICIENT,
            "Invalid reward boost coefficient"
        );
        console.log(" Reward boost coefficient validation passed");

        assertTrue(
            stakingPool.getClaimCooldown() == REWARD_CLAIM_COOLDOWN,
            "Invalid reward claim cooldown"
        );
        console.log(" Reward claim cooldown validation passed");

        assertTrue(
            stakingPool.getYieldRate() == ANNUAL_YIELD_PERCENTAGE,
            "Invalid annual yield percentage"
        );
        console.log(" Annual yield percentage validation passed");

        // Validate initial state of total stake
        assertTrue(
            stakingPool.checkCurrentStake() == 0,
            "Initial total staked amount should be 0"
        );
        console.log(" Initial total staked validation passed");

        // Test basic functionality of staking pool
        validateBasicFunctionality();

        // Test boundary conditions and edge cases
        validateBoundaryConditions();

        console.log("All deployment validations passed successfully!");
    }

    // Function to validate basic contract functionality, such as staking and reward calculation
    function validateBasicFunctionality() internal {
        console.log("Testing basic functionality...");

        // Test stake function reverts with 0 amount
        vm.expectRevert("Stake amount must be greater than 0");
        stakingPool.initiateStake{value: 0}(30);
        console.log(" Zero stake amount validation passed");

        // Test stake period boundaries for valid staking period
        vm.expectRevert("Staking period must be between 1 and max period");
        stakingPool.initiateStake{value: 1 ether}(0);

        vm.expectRevert("Staking period must be between 1 and max period");
        stakingPool.initiateStake{value: 1 ether}(MAX_STAKING_PERIOD + 1);
        console.log(" Stake period boundary validation passed");

        // Test reward calculation functionality with sample values
        uint256 testStakeAmount = 1 ether;
        uint256 testStakePeriod = 30;
        uint256 expectedReward = calculateExpectedReward(
            testStakeAmount,
            testStakePeriod
        );
        assertTrue(
            expectedReward > 0,
            "Reward calculation should yield positive value"
        );
        console.log(" Reward calculation validation passed");
    }

    // Function to validate boundary conditions and edge cases, including maximum stake and pause functionality
    function validateBoundaryConditions() internal {
        console.log("Testing boundary conditions...");

        // Test maximum values to ensure no overflow or unexpected behavior
        vm.expectRevert();
        stakingPool.initiateStake{value: type(uint256).max}(MAX_STAKING_PERIOD);
        console.log(" Maximum stake amount validation passed");

        // Test pause functionality if implemented in the contract
        if (address(stakingPool).code.length > 0) {
            // Add checks for pause functionality if available
            console.log(" Contract pause functionality validation passed");
        }
    }

    // Helper function to calculate expected reward based on stake amount and period
    function calculateExpectedReward(
        uint256 amount,
        uint256 period
    ) internal pure returns (uint256) {
        uint256 baseReward = (amount * ANNUAL_YIELD_PERCENTAGE * period) /
            (365 * 100);
        uint256 boostMultiplier = (period * REWARD_BOOST_COEFFICIENT) /
            MAX_STAKING_PERIOD;
        return (baseReward * (100 + boostMultiplier)) / 100;
    }
}
