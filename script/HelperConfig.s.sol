// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

/*
 * ─────────────────────────────────────────────────────────────
 *  HelperConfig — Network Configuration Manager
 * ─────────────────────────────────────────────────────────────
 *
 *  This script manages deployment configuration across multiple networks.
 *  Instead of hardcoding values directly in the deploy script, all
 *  network-specific parameters (VRF coordinator address, gas lane,
 *  entrance fee, etc.) are centralised here.
 *
 *  Supported networks:
 *    - Sepolia testnet  (chainId: 11155111) — uses real Chainlink VRF
 *    - Anvil local fork (chainId: 31337)    — deploys VRF mocks locally
 *
 *  Usage: the deploy script calls getConfigByChainId() which automatically
 *  returns the correct configuration for the network being deployed to.
 * ─────────────────────────────────────────────────────────────
 */

/*
 * CodeConstants — Shared chain ID constants.
 *
 * Declared as an abstract contract so multiple contracts can inherit
 * these values without duplication. Using named constants instead of
 * raw numbers prevents typos and makes the code self-documenting.
 */
abstract contract CodeConstants {
    /* VRF Mock Values */
    uint96 public MOCK_BASE_FEE = 0.25 ether;
    uint96 public MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public MOCK_WEI_PER_UINT_LINK = 4e16;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    /* ─────────────────────────────────────────────
     * Custom Errors
     * ─────────────────────────────────────────────
     */

    // Thrown when getConfigByChainId() is called with a chain ID that
    // has no configuration defined and is not the local Anvil chain.
    error HelperConfig__InvalidChainId();

    /* ─────────────────────────────────────────────
     * NetworkConfig Struct
     * ─────────────────────────────────────────────
     * Groups all deployment parameters into a single reusable type.
     * Each field maps directly to a constructor parameter in Raffle.sol.
     */
    struct NetworkConfig {
        uint256 entranceFee; // Minimum ETH (in wei) required to enter the raffle.
        uint256 interval; // Time interval (in seconds) between raffle winner selections.
        address vrfCoordinator; // Address of the Chainlink VRF Coordinator contract.
        bytes32 gasLane; // Key hash used to specify the maximum gas price for VRF requests.
        uint256 subscriptionId; // Chainlink VRF subscription ID used to fund randomness requests.
        uint32 callBackGasLimit; // Gas limit for the fulfillRandomWords() callback execution.
        address linkToken; // Address of the LINK token contract for the current network.
    }

    /* ─────────────────────────────────────────────
     * State Variables
     * ─────────────────────────────────────────────
     */

    // Stores the active configuration for the local Anvil network.
    // Populated lazily by getOrCreateAnvilEthConfig() on first call.
    NetworkConfig public localNetworkConfig;

    // Maps each chain ID to its corresponding network configuration.
    // Populated in the constructor for known networks (e.g. Sepolia).
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /* ─────────────────────────────────────────────
     * Constructor
     * ─────────────────────────────────────────────
     * Pre-populates the networkConfigs mapping with all known networks
     * at deployment time. Local Anvil config is not added here because
     * it requires deploying mock contracts, which happens lazily.
     */
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    /* ─────────────────────────────────────────────
     * Config Resolver
     * ─────────────────────────────────────────────
     */

    /**
     * @notice Returns the network configuration for the given chain ID.
     * @dev    Resolution order:
     *           1. If a config exists in the mapping → return it directly.
     *           2. If the chain is local Anvil → deploy mocks and return config.
     *           3. Otherwise → revert with HelperConfig__InvalidChainId.
     *
     * @param chainId  The EVM chain ID to look up.
     * @return         The NetworkConfig for the specified chain.
     */
    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            // A config exists for this chain — return it directly.
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            // No config yet for Anvil — deploy mocks and build one.
            return getOrCreateAnvilEthConfig();
        } else {
            // Unknown chain — no config defined.
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    /* ─────────────────────────────────────────────
     * Network Configs
     * ─────────────────────────────────────────────
     */

    /**
     * @notice Returns the deployment configuration for the Sepolia testnet.
     * @dev    Uses real Chainlink VRF infrastructure on Sepolia.
     *         VRF coordinator address and gas lane sourced from:
     *         https://docs.chain.link/vrf/v2-5/supported-networks
     *
     *         subscriptionId is set to 0 here — it must be replaced with a
     *         valid funded subscription ID before deploying to Sepolia.
     *
     * @return  A NetworkConfig struct populated with Sepolia values.
     */
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether, // 10,000,000,000,000,000 wei (1e16)
            interval: 30, // 30 seconds between rounds
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0, // ⚠️ Replace with a real funded subscription ID
            callBackGasLimit: 500000, // 500,000 gas units for the VRF callback
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789 // VRF LINK Token Contract (Sepolia Testnet)
        });
    }

    /**
     * @notice Returns the deployment configuration for the local Anvil network.
     * @dev    Uses a lazy initialisation pattern — the config is only created
     *         on the first call. Subsequent calls return the cached value.
     *
     *         Since Anvil has no real Chainlink infrastructure, this function
     *         must deploy VRF mock contracts locally before building the config.
     *
     *         TODO: Deploy VRFCoordinatorV2_5Mock and populate localNetworkConfig.
     *
     * @return  A NetworkConfig struct populated with local mock values.
     */
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // If a local config already exists, return it without redeploying mocks.
        // vrfCoordinator == address(0) means no config has been created yet.
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        // TODO: Deploy VRFCoordinatorV2_5Mock here and assign localNetworkConfig.
        vm.startBroadcast();

        VRFCoordinatorV2_5Mock vrfCoordinatorMock =
            new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE_LINK, MOCK_WEI_PER_UINT_LINK);
        
        LinkToken linkToken = new LinkToken();

        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinatorMock),
            // Doesn't matter, the mock will work no matter the gasLane is
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0,
            callBackGasLimit: 500000,
            linkToken: address(linkToken)
        });

        return localNetworkConfig;
    }
}
