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
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

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
contract CreateSubscription is Script, CodeConstants {
    /**
     * @notice Reads the VRF coordinator address from HelperConfig and
     *         creates a subscription on the current network automatically.
     * @dev    This is the config-aware wrapper. It resolves the correct
     *         VRF coordinator and account for the active chain, then delegates to
     *         createSubscription(). Used by run() for standalone execution.
     *
     * @return subId          The newly created subscription ID.
     * @return vrfCoordinator The VRF coordinator address used.
     */
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        // Fetch the VRF coordinator address for the current network.
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;

        // Fetch the account that will sign and submit the subscription creation.
        address account = helperConfig.getConfig().account;

        (uint256 subId,) = createSubscription(vrfCoordinator, account);

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
    function createSubscription(address vrfCoordinator, address account) public returns (uint256, address) {
        // Log the chain ID so you can confirm you're on the intended network.
        console.log("Creating Subscription on Chain ID: ", block.chainid);

        // vm.startBroadcast() / vm.stopBroadcast() tells Foundry to sign and
        // submit everything between these calls as a real on-chain transaction.
        // Without this, the call would only simulate locally and not be recorded.
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        // Log the subscription ID — copy this value into HelperConfig.s.sol.
        console.log("The Subscription ID Created by is: ", subId);

        if (block.chainid != LOCAL_CHAIN_ID) {
            console.log("Please update the subscription ID in your HelperConfig.s.sol");
        }

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

/*
 * FundSubscription
 *
 * Handles funding an existing Chainlink VRF v2.5 subscription with LINK.
 *
 * Funding behaviour differs by network:
 *   - Anvil (local): calls fundSubscription() directly on the mock coordinator.
 *   - Live networks: uses transferAndCall() on the LINK token contract, which
 *     transfers LINK and notifies the coordinator in a single transaction.
 */
contract FundSubscription is Script, CodeConstants {
    // Amount of LINK to deposit into the subscription.
    // Uses ether units (1e18) since LINK also has 18 decimals — not an ETH amount.
    uint256 public constant FUND_AMOUNT = 0.1 ether;

    /**
     * @notice Reads VRF config from HelperConfig and funds the subscription
     *         on the current network automatically.
     * @dev    Config-aware wrapper around fundSubscription(). Resolves the
     *         correct coordinator, subscription ID, LINK token address, and
     *         account for the active chain, then delegates to fundSubscription().
     */
    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();

        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;

        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;

        // Fetch the LINK token address for the current network.
        // Used on live networks to call transferAndCall() for funding.
        address linkToken = helperConfig.getConfig().linkToken;

        // Fetch the account that will sign and submit the funding transaction.
        address account = helperConfig.getConfig().account;

        // Delegate to fundSubscription() with all resolved config values.
        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);
    }

    /**
     * @notice Funds a Chainlink VRF subscription with LINK on the given coordinator.
     * @dev    Funding method differs by network:
     *           - Local Anvil: calls fundSubscription() directly on the mock.
     *           - Live networks: uses LINK's transferAndCall(), which transfers
     *             tokens and notifies the coordinator atomically.
     *
     * @param vrfCoordinator  Address of the VRF coordinator managing the subscription.
     * @param subscriptionId  The subscription ID to fund.
     * @param linkToken       Address of the LINK token contract on the current network.
     */
    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken, address account)
        public
    {
        console.log("Funding Subscription: ", subscriptionId);
        console.log("Using VRF Coordinator: ", vrfCoordinator);
        console.log("On Chain Id: ", block.chainid);

        if (block.chainid == LOCAL_CHAIN_ID) {
            // On Anvil, fund the mock coordinator directly — no real LINK token exists.
            vm.startBroadcast();
            // Fund the VRFCoordinatorV2_5Mock subscription with 100x the previous amount
            // to prevent insufficient balance errors during testing and repeated VRF requests.
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
        } else {
            // On live networks, use transferAndCall() to transfer LINK and notify
            // the coordinator in a single atomic transaction.
            vm.startBroadcast(account);
            LinkToken(linkToken).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }

    /**
     * @notice Foundry entrypoint — called when running this script directly.
     * @dev    Delegates to fundSubscriptionUsingConfig() so the correct
     *         network config is applied automatically.
     */
    function run() public {
        fundSubscriptionUsingConfig();
    }
}

/*
 * AddConsumer
 *
 * Registers a deployed Raffle contract as an approved consumer on an
 * existing Chainlink VRF subscription. A consumer must be registered
 * before it can request random numbers — unregistered contracts will
 * have their VRF requests rejected by the coordinator.
 */
contract AddConsumer is Script {
    /**
     * @notice Reads VRF config from HelperConfig and registers the given
     *         contract as a consumer on the current network automatically.
     * @param mostRecentlyDeployed Address of the contract to register as a consumer.
     */
    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subscriptionId, account);
    }

    /**
     * @notice Registers a contract as an approved consumer on a VRF subscription.
     * @dev    Wraps the call in vm.startBroadcast() so Foundry submits it
     *         as a real on-chain transaction rather than a local simulation.
     *
     * @param contractToAddToVRF  Address of the contract to register.
     * @param vrfCoordinator      Address of the VRF coordinator managing the subscription.
     * @param subscriptionId      The subscription ID to add the consumer to.
     * @param account             The account that will sign and submit the transaction.
     */
    function addConsumer(address contractToAddToVRF, address vrfCoordinator, uint256 subscriptionId, address account)
        public
    {
        console.log("Adding Consumer Contract: ", contractToAddToVRF);
        console.log("To VRF Coordinator: ", vrfCoordinator);
        console.log("On Chain ID: ", block.chainid);

        // Broadcast as the specified account so the transaction is signed correctly
        // on both local Anvil and live networks.
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, contractToAddToVRF);
        vm.stopBroadcast();
    }

    /**
     * @notice Foundry entrypoint — called when running this script directly.
     * @dev    Automatically resolves the most recently deployed Raffle contract
     *         using DevOpsTools, then registers it as a VRF consumer.
     */
    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}
