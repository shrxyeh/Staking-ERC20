// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FlexibleStakingPool} from "../src/FlexibleStakingPool.sol";
import "forge-std/console.sol";

contract FlexibleStakingPoolTest is Test {
    FlexibleStakingPool public stakingPool;

    // Test addresses
    address public owner;
    address public UserAddress1 = address(0x123);
    address public UserAddress2 = address(0x456);

    // Initial contract parameters
    uint256 constant MAX_STAKING_PERIOD = 365;
    uint256 constant REWARD_BOOST_COEFF = 5;
    uint256 constant CLAIM_COOLDOWN = 7;
    uint256 constant ANNUAL_YIELD = 100;

    function setUp() public {
        owner = address(this);
        stakingPool = new FlexibleStakingPool(
            MAX_STAKING_PERIOD,
            REWARD_BOOST_COEFF,
            CLAIM_COOLDOWN,
            ANNUAL_YIELD
        );
        stakingPool.grantRole(stakingPool.ADMIN_ROLE(), owner);

        vm.deal(address(stakingPool), 100 ether);
        vm.deal(UserAddress1, 100 ether);
        vm.deal(UserAddress2, 100 ether);

        // Simulate initial time passage
        vm.warp(1 days);
    }

    //Test for Admin Role Acess
    function testFailAdminRoleAccess() public {
        // Expect the function to fail with the correct error message if UserAddress1 (without admin role) tries to call an admin function
        vm.prank(UserAddress1);
        stakingPool.getMaxStakingPeriod(600);
    }

    // Test constructor and initial configuration
    function testConstructorParameters() public view {
        assertEq(stakingPool.getMaxStakingPeriod(), MAX_STAKING_PERIOD);
        assertEq(stakingPool.adjustRewardBoost(), REWARD_BOOST_COEFF);
        assertEq(stakingPool.modifyClaimCooldown(), CLAIM_COOLDOWN * 1 days);
        assertEq(stakingPool.updateYieldRate(), ANNUAL_YIELD);
    }

    // Test staking functionality
    function testStaking() public {
        vm.startPrank(UserAddress1);
        uint256 initialBalance = UserAddress1.balance;

        // Stake 1 ether for 30 days
        stakingPool.initiateStake{value: 1 ether}(30);

        assertEq(stakingPool.checkCurrentStake(), 1 ether);
        uint256 finalBalance = UserAddress1.balance;
        assertEq(finalBalance, initialBalance - 1 ether);

        vm.stopPrank();
    }

    // Test reward calculation and boost mechanism
    function testRewardCalculation() public {
        uint256 STAKE_AMOUNT = 100 ether;
        uint256 LOCK_DURATION = 100;

        vm.startPrank(UserAddress1);

        stakingPool.initiateStake{value: STAKE_AMOUNT}(LOCK_DURATION);

        vm.warp(LOCK_DURATION);

        uint256 expectedMultiplier = (LOCK_DURATION *
            REWARD_BOOST_COEFF *
            1e6) / MAX_STAKING_PERIOD;

        uint256 expectedReward = (STAKE_AMOUNT *
            LOCK_DURATION *
            ANNUAL_YIELD *
            expectedMultiplier) / (100 * 1e6);

        uint256 actualMultiplier = stakingPool.calculateDynamicBoost(
            LOCK_DURATION
        );
        uint256 actualReward = stakingPool.computeReward(UserAddress1);

        vm.stopPrank();

        console.log("Expected Multiplier", expectedMultiplier / 1e6);
        console.log("Actual Multiplier", actualMultiplier / 1e6);
        console.log("Expected Reward", expectedReward);
        console.log("Actual Reward", actualReward);

        assertTrue(
            actualMultiplier == expectedMultiplier,
            "Dynamic boost should match expected value"
        );

        assertTrue(
            actualReward == expectedReward,
            "Reward should match expected calculation"
        );
    }

    // Test multiple staking scenarios
    function testMultipleStakingScenarios() public {
        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: 1 ether}(30);
        vm.warp(31 days);
        assertEq(stakingPool.checkCurrentStake(), 1 ether);
        stakingPool.concludeStake();
        vm.stopPrank();

        vm.startPrank(UserAddress2);
        stakingPool.initiateStake{value: 2 ether}(90);
        vm.warp(121 days);
        assertEq(stakingPool.checkCurrentStake(), 2 ether);
        stakingPool.concludeStake();
        vm.stopPrank();
    }

    // Test updating contract parameters
    function testUpdateParameters() public {
        uint256 newMaxPeriod = 180;
        uint256 newBoostCoeff = 10;
        uint256 newCooldown = 14;
        uint256 newYieldRate = 120;

        assertEq(stakingPool.getMaxStakingPeriod(), MAX_STAKING_PERIOD);
        assertEq(stakingPool.adjustRewardBoost(), REWARD_BOOST_COEFF);
        assertEq(stakingPool.modifyClaimCooldown(), CLAIM_COOLDOWN * 1 days);
        assertEq(stakingPool.updateYieldRate(), ANNUAL_YIELD);

        stakingPool.getMaxStakingPeriod(newMaxPeriod);
        stakingPool.adjustRewardBoost(newBoostCoeff);
        stakingPool.modifyClaimCooldown(newCooldown);
        stakingPool.updateYieldRate(newYieldRate);

        assertEq(stakingPool.getMaxStakingPeriod(), newMaxPeriod);
        assertEq(stakingPool.adjustRewardBoost(), newBoostCoeff);
        assertEq(stakingPool.modifyClaimCooldown(), newCooldown * 1 days);
        assertEq(stakingPool.updateYieldRate(), newYieldRate);
    }

    // Test reward claiming mechanism
    function testRewardClaiming() public {
        vm.startPrank(UserAddress1);

        stakingPool.initiateStake{value: 1 ether}(10);
        vm.warp(11 days);

        uint256 initialBalance = UserAddress1.balance;
        stakingPool.collectRewards();
        uint256 finalBalance = UserAddress1.balance;

        assertTrue(
            finalBalance > initialBalance,
            "Balance should increase after claiming rewards"
        );

        vm.stopPrank();
    }

    // Test claiming rewards before cooldown
    function testClaimRewardsBeforeCooldown() public {
        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: 1 ether}(30);

        vm.expectRevert();
        stakingPool.collectRewards();

        vm.stopPrank();
    }

    //Test updating yield rate by non-owner
    function testFailUpdateYieldRateByNonOwner() public {
        uint256 newYieldRate = 200;

        vm.prank(UserAddress1);
        stakingPool.updateYieldRate(newYieldRate);
    }

    // Test unstaking before lock period
    function testUnstakeBeforeLockPeriod() public {
        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: 1 ether}(30);
        vm.expectRevert();
        stakingPool.concludeStake();

        vm.stopPrank();
    }
}
