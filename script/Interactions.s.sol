// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// See openchain.xyz to see signatures DBs and see how to interact with it using Foundry docs

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;

        (uint256 subId,) = createSubscription(vrfCoordinator);

        return (subId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator) public returns (uint256, address) {
        console.log("Creating Subscription on Chain ID: ", block.chainid);
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        console.log("The Subscription ID is: ", subId);
        console.log("Please, update the subscription ID in your HelperConfig.s.sol");

        return (subId, vrfCoordinator);
    }

    function run() {
        createSubscriptionUsingConfig();
    }
}
