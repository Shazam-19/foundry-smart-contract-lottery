// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Reads a uint256 value from an environment (.env file) variable (e.g., a private key) securely at runtime.
// Commonly used in Foundry scripts to avoid hardcoding sensitive data like PRIVATE_KEY when broadcasting transactions.
// uint256 privateKey = vm.envUint("PRIVATE_KEY");
// I didn't use it in this project yet.

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

/*
 * DeployRaffle
 *
 * Deploys the Raffle contract with the correct configuration for the
 * active network. Automatically handles subscription setup if needed:
 *   - Creates a VRF subscription if none exists (subscriptionId == 0).
 *   - Funds the subscription with LINK.
 *   - Registers the deployed Raffle as an approved VRF consumer.
 */
contract DeployRaffle is Script {
    /**
     * @notice Foundry entrypoint — called when running this script directly.
     */
    function run() public {
        deployRaffle();
    }

    /**
     * @notice Deploys a fully configured Raffle contract for the active network.
     * @dev    Resolves network config via HelperConfig, handles VRF subscription
     *         setup if needed, deploys Raffle, then registers it as a consumer.
     * @return raffle        The deployed Raffle contract instance.
     * @return helperConfig  The HelperConfig instance used during deployment.
     */
    function deployRaffle() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // local -> deploy mocks, get local config
        // sepolia -> get sepolia config
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // A subscriptionId of 0 means none was configured (e.g. fresh Anvil run).
        // Create and fund one programmatically before deploying Raffle.
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscription.createSubscription(config.vrfCoordinator, config.account);

            // Fund the newly created subscription with LINK before deploying.
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator, config.subscriptionId, config.linkToken, config.account
            );
        }

        // Broadcast only the Raffle deployment as an on-chain transaction.
        // Subscription setup above is handled inside its own broadcast calls.
        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callBackGasLimit
        );

        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        // Runs outside of broadcast — addConsumer() manages its own vm.startBroadcast() internally.
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }
}
