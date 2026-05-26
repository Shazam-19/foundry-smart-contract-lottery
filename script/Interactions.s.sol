// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
 * ─────────────────────────────────────────────────────────────
 *  CreateSubscription — Chainlink VRF Subscription Setup Script
 * ─────────────────────────────────────────────────────────────
 *
 *  Before a contract can request random numbers from Chainlink VRF,
 *  it needs a funded subscription. This script automates creating one.
 *
 *  A Chainlink VRF subscription is an account that:
 *    - Funds VRF requests on behalf of your consumer contracts.
 *    - Tracks how much LINK (or ETH) has been spent.
 *    - Can have multiple consumer contracts attached to it.
 *
 *  After running this script:
 *    1. Copy the logged Subscription ID.
 *    2. Update subscriptionId in HelperConfig.s.sol.
 *    3. Fund the subscription at https://vrf.chain.link.
 *    4. Add your Raffle contract as an approved consumer.
 *
 *  Tip: Use https://openchain.xyz to look up function selectors
 *  and event signatures — useful when decoding raw transaction data
 *  or interacting with contracts via Foundry's cast tool.
 * ─────────────────────────────────────────────────────────────
 */

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/*
 * CreateSubscription
 *
 * Handles the creation of a Chainlink VRF v2.5 subscription.
 * Supports both real networks (via HelperConfig) and local Anvil
 * (via VRFCoordinatorV2_5Mock).
 *
 * Two entry points:
 *   - run()                        → used by Foundry (forge script)
 *   - createSubscription(address)  → used directly in other scripts
 *                                    (e.g. when deploying on Anvil)
 */
contract CreateSubscription is Script {
    /**
     * @notice Reads the VRF coordinator address from HelperConfig and
     *         creates a subscription on the current network automatically.
     * @dev    This is the config-aware wrapper. It resolves the correct
     *         VRF coordinator for the active chain, then delegates to
     *         createSubscription(). Used by run() for standalone execution.
     *
     * @return subId          The newly created subscription ID.
     * @return vrfCoordinator The VRF coordinator address used.
     */
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        // Fetch the VRF coordinator address for the current network.
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;

        (uint256 subId,) = createSubscription(vrfCoordinator);

        return (subId, vrfCoordinator);
    }

    /**
     * @notice Creates a Chainlink VRF subscription on the given coordinator.
     * @dev    Works on both real networks and local Anvil (via mock).
     *         Wraps the call in vm.startBroadcast() / vm.stopBroadcast()
     *         so Foundry signs and submits it as a real transaction.
     *
     *         After running, copy the logged Subscription ID and update
     *         subscriptionId in HelperConfig.s.sol before deploying Raffle.
     *
     * @param vrfCoordinator  Address of the VRF coordinator to create
     *                        the subscription on.
     * @return subId          The newly created subscription ID.
     * @return vrfCoordinator The same coordinator address passed in
     *                        (returned for convenience in calling scripts).
     */
    function createSubscription(address vrfCoordinator) public returns (uint256, address) {
        // Log the chain ID so you can confirm you're on the intended network.
        console.log("Creating Subscription on Chain ID: ", block.chainid);

        // vm.startBroadcast() / vm.stopBroadcast() tells Foundry to sign and
        // submit everything between these calls as a real on-chain transaction.
        // Without this, the call would only simulate locally and not be recorded.
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        // Log the subscription ID — copy this value into HelperConfig.s.sol.
        console.log("The Subscription ID is: ", subId);
        console.log("Please update the subscription ID in your HelperConfig.s.sol");

        return (subId, vrfCoordinator);
    }

    /**
     * @notice Foundry entrypoint — called when running this script directly.
     * @dev    Foundry looks for run() as the default function when executing
     *         a script with `forge script`. Delegates to createSubscriptionUsingConfig()
     *         so the correct network config is applied automatically.
     */
    function run() public {
        createSubscriptionUsingConfig();
    }
}
