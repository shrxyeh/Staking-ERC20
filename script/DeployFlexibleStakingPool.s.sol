// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FlexibleStakingPool} from "../src/FlexibleStakingPool.sol";

contract DeployFlexibleStakingPool is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy FlexibleStakingPool
        FlexibleStakingPool stakingPool = new FlexibleStakingPool(
            365, // Maximum staking period in days
            5, // Reward boost coefficient
            7, // Reward claim cooldown in days
            100 // Annual yield percentage
        );

        vm.stopBroadcast();

        console.log("FlexibleStakingPool deployed at:", address(stakingPool));

        validateDeployment(stakingPool);
    }

    // Function to validate deployment and contract parameters
    function validateDeployment(FlexibleStakingPool contractAddress) internal {
        require(
            address(contractAddress) != address(0),
            "Deployment failed: Invalid contract address"
        );

        vm.expectRevert();
        uint256 maxPeriod = contractAddress.getMaxStakingPeriod();
        require(maxPeriod == 365, "Maximum staking period is incorrect");

        console.log("Contract deployed with correct parameters.");
    }
}
