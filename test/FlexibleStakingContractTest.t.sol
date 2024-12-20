// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FlexibleStakingPool} from "../src/FlexibleStakingPool.sol";
import "forge-std/console.sol";

contract NoETHReceive {
    receive() external payable {
        revert("ETH not accepted");
    }
}

contract FlexibleStakingPoolTest is Test, NoETHReceive {
    FlexibleStakingPool public stakingPool;

    address public owner;
    address public UserAddress1 = address(0x123);
    address public UserAddress2 = address(0x456);
    address public UserAddress3 = address(0x789);
    address public nftCollection;
    address public rewardToken;

    uint256 constant MAX_STAKING_PERIOD = 365;
    uint256 constant REWARD_BOOST_COEFF = 5;
    uint256 constant CLAIM_COOLDOWN = 7;
    uint256 constant ANNUAL_YIELD = 100;
    uint256 TIME_UNIT = 5;

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
        vm.deal(UserAddress3, 100 ether);

        vm.warp(1 days);
    }

    // Test to check if constructor parameters are set correctly
    function testConstructorParameters() public view {
        assertEq(stakingPool.getMaxStakingPeriod(), MAX_STAKING_PERIOD);
        assertEq(stakingPool.getRewardBoostCoefficient(), REWARD_BOOST_COEFF);
        assertEq(stakingPool.getClaimCooldown(), CLAIM_COOLDOWN * 1 days);
        assertEq(stakingPool.getYieldRate(), ANNUAL_YIELD);
    }

    // Test to verify the update of staking pool parameters
    function testUpdateParameters() public {
        uint256 newMaxPeriod = 180;
        uint256 newBoostCoeff = 10;
        uint256 newCooldown = 14;
        uint256 newYieldRate = 120;

        stakingPool.setMaxStakingPeriod(newMaxPeriod);
        stakingPool.setRewardBoostCoefficient(newBoostCoeff);
        stakingPool.setClaimCooldown(newCooldown);
        stakingPool.setYieldRate(newYieldRate);

        assertEq(stakingPool.getMaxStakingPeriod(), newMaxPeriod);
        assertEq(stakingPool.getRewardBoostCoefficient(), newBoostCoeff);
        assertEq(stakingPool.getClaimCooldown(), newCooldown * 1 days);
        assertEq(stakingPool.getYieldRate(), newYieldRate);
    }

    // Test to fail NFT staking initialization with zero address
    function testFailInitializeNFTStakingZeroAddress() public {
        stakingPool.initializeNFTStaking(
            address(0),
            address(nftCollection),
            100
        );
    }

    // Test to fail staking with zero amount
    function testFailZeroStakeAmount() public {
        vm.prank(UserAddress1);
        stakingPool.initiateStake{value: 0}(30);
    }

    // Test to fail access to admin-only function by non-admin
    function testFailAdminRoleAccess() public {
        vm.prank(UserAddress1);
        stakingPool.setMaxStakingPeriod(600);
    }

    // Test to fail setting staking parameters by non-admin
    function testFailSetMaxStakingPeriodNonAdmin() public {
        vm.prank(address(0xDEF));
        stakingPool.setMaxStakingPeriod(365);
    }

    // Test to fail update of yield rate by non-owner
    function testFailUpdateYieldRateByNonOwner() public {
        vm.prank(UserAddress1);
        stakingPool.setYieldRate(200);
    }

    // Basic staking functionality test to verify stake initiation
    function testBasicStaking() public {
        vm.startPrank(UserAddress1);
        uint256 initialBalance = UserAddress1.balance;
        stakingPool.initiateStake{value: 1 ether}(30);

        assertEq(stakingPool.getStakeAmount(UserAddress1), 1 ether);
        assertEq(UserAddress1.balance, initialBalance - 1 ether);
        vm.stopPrank();
    }

    // Test multiple staking scenarios with different users
    function testMultipleStakingScenarios() public {
        // First user stake
        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: 0.1 ether}(10);
        assertEq(stakingPool.getStakeAmount(UserAddress1), 0.1 ether);
        vm.warp(block.timestamp + 11 days);
        uint256 initialBalance = UserAddress1.balance;
        stakingPool.concludeStake();
        assertTrue(UserAddress1.balance > initialBalance);
        vm.stopPrank();

        // Second user stake
        vm.startPrank(UserAddress2);
        stakingPool.initiateStake{value: 0.2 ether}(20);
        assertEq(stakingPool.getStakeAmount(UserAddress2), 0.2 ether);
        vm.warp(block.timestamp + 21 days);
        initialBalance = UserAddress2.balance;
        stakingPool.concludeStake();
        assertTrue(UserAddress2.balance > initialBalance);
        vm.stopPrank();
    }

    // Test to verify correct reward calculation based on stake and duration
    function testRewardCalculation() public {
        uint256 stakeAmount = 100 ether;
        uint256 lockDuration = 100;

        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: stakeAmount}(lockDuration);
        vm.warp(block.timestamp + lockDuration * 1 days);

        uint256 expectedMultiplier = (lockDuration * REWARD_BOOST_COEFF * 1e6) /
            MAX_STAKING_PERIOD;
        uint256 expectedReward = (stakeAmount *
            lockDuration *
            ANNUAL_YIELD *
            expectedMultiplier) / (100 * 1e6);

        uint256 actualReward = stakingPool.computeReward(UserAddress1);
        assertEq(actualReward, expectedReward, "Reward calculation mismatch");
        vm.stopPrank();
    }

    // Test dynamic boost calculation based on stake duration
    function testDynamicBoostCalculation() public {
        uint256 zeroBoost = stakingPool.calculateDynamicBoost(0);
        uint256 maxBoost = stakingPool.calculateDynamicBoost(
            MAX_STAKING_PERIOD
        );
        uint256 halfPeriodBoost = stakingPool.calculateDynamicBoost(
            MAX_STAKING_PERIOD / 2
        );

        assertEq(zeroBoost, 0, "Zero duration should give zero boost");
        assertEq(maxBoost, REWARD_BOOST_COEFF * 1e6, "Should cap at max boost");
        assertTrue(
            halfPeriodBoost < maxBoost && halfPeriodBoost > 0,
            "Half period boost should be between 0 and max"
        );
    }

    // Test to verify correct rewards for multiple users staking simultaneously
    function testSimultaneousStakers() public {
        vm.prank(UserAddress1);
        stakingPool.initiateStake{value: 1 ether}(30);

        vm.prank(UserAddress2);
        stakingPool.initiateStake{value: 2 ether}(30);

        vm.prank(UserAddress3);
        stakingPool.initiateStake{value: 3 ether}(30);

        vm.warp(block.timestamp + 31 days);

        uint256 reward1 = stakingPool.computeReward(UserAddress1);
        uint256 reward2 = stakingPool.computeReward(UserAddress2);
        uint256 reward3 = stakingPool.computeReward(UserAddress3);

        assertTrue(
            reward2 > reward1,
            "Higher stake should yield higher reward"
        );
        assertTrue(
            reward3 > reward2,
            "Higher stake should yield higher reward"
        );
    }

    // Test to verify staking renewal and stake amount update
    function testStakeRenewal() public {
        vm.startPrank(UserAddress1);
        stakingPool.initiateStake{value: 1 ether}(30);

        vm.warp(block.timestamp + 31 days);
        stakingPool.concludeStake();

        stakingPool.initiateStake{value: 2 ether}(60);
        assertEq(
            stakingPool.getStakeAmount(UserAddress1),
            2 ether,
            "New stake amount should be recorded"
        );
        vm.stopPrank();
    }

    // Test to ensure the maximum stake amount is accepted correctly
    function testMaxStakeAmount() public {
        vm.startPrank(UserAddress1);
        uint256 maxStake = 50 ether;
        stakingPool.initiateStake{value: maxStake}(MAX_STAKING_PERIOD);
        assertEq(
            stakingPool.getStakeAmount(UserAddress1),
            maxStake,
            "Should accept maximum stake"
        );
        vm.stopPrank();
    }

    // Test to fail emergency withdrawal by non-admin
    function testFailEmergencyWithdrawNonAdmin() public {
        vm.prank(UserAddress1);
        stakingPool.emergencyWithdraw();
    }
}
