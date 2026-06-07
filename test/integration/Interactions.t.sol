// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

/*
 * ─────────────────────────────────────────────────────────────
 *  InteractionsTest — Integration Tests for Interactions.s.sol
 * ─────────────────────────────────────────────────────────────
 *
 *  Unlike unit tests which test functions in isolation, these
 *  integration tests verify that the three VRF subscription
 *  scripts work correctly together and produce a valid,
 *  fully-wired deployment.
 *
 *  Test flow mirrors the real deployment pipeline:
 *    1. CreateSubscription  → creates a VRF subscription.
 *    2. FundSubscription    → funds it with LINK.
 *    3. AddConsumer         → registers Raffle as a consumer.
 *    4. Full pipeline       → verifies end-to-end via DeployRaffle.
 *
 *  All tests run against local Anvil using VRF and LINK mocks,
 *  so no real LINK or testnet access is required.
 * ─────────────────────────────────────────────────────────────
 */
contract InteractionsTest is Test {
    /* ─────────────────────────────────────────────
     * Contract Instances
     * ─────────────────────────────────────────────
     */
    Raffle public raffle;
    HelperConfig public helperConfig;

    /* ─────────────────────────────────────────────
     * Network Config Variables
     * ─────────────────────────────────────────────
     * Unpacked from HelperConfig in setUp() so individual
     * tests can reference them directly without going
     * through the struct on every call.
     */
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callBackGasLimit;
    address linkToken;
    address account;

    /* ─────────────────────────────────────────────
     * setUp()
     * ─────────────────────────────────────────────
     * Runs automatically before every test function.
     * Deploys a fresh Raffle using the production deploy
     * script so the integration environment reflects a
     * real deployment as closely as possible.
     */
    function setUp() external {
        // Deploy the full stack using the production deploy script.
        // This internally creates and funds the VRF subscription
        // and registers Raffle as an approved consumer.
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffle();

        // Unpack all config values for use in individual tests.
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callBackGasLimit = config.callBackGasLimit;
        linkToken = config.linkToken;
        account = config.account;

        // subscriptionId is intentionally NOT read from HelperConfig here.
        //
        // Why: deployRaffle() creates the subscription and assigns it to a
        // local memory copy of NetworkConfig — this update is never written
        // back to HelperConfig's storage. As a result, helperConfig.getConfig()
        // always returns subscriptionId = 0 after deployment, making it
        // unreliable for tests.
        //
        // Solution: read subscriptionId directly from the deployed Raffle
        // contract via getSubscriptionId(). Since Raffle stores it as an
        // immutable set during construction, it always reflects the real
        // subscription ID that was used — regardless of HelperConfig's state.
        subscriptionId = raffle.getSubscriptionId();
    }

    /* ─────────────────────────────────────────────
     * CreateSubscription Tests
     * ─────────────────────────────────────────────
     */

    /**
     * @dev Verifies that createSubscriptionUsingConfig() produces a non-zero
     *      subscription ID when resolving config automatically.
     *
     *      Flow:
     *        1. Instantiate CreateSubscription.
     *        2. Call createSubscriptionUsingConfig(); this internally creates
     *           a new HelperConfig and a new VRFCoordinatorV2_5Mock.
     *        3. Assert the returned subscription ID is non-zero.
     *
     *      Note: the returned coordinator address is discarded because
     *      createSubscriptionUsingConfig() deploys its own HelperConfig
     *      which produces a fresh VRFCoordinatorV2_5Mock at a different
     *      address than the one in setUp(). Comparing them would always fail.
     */
    function testCreateSubscriptionUsingConfig() public {
        // Arrange / Act
        CreateSubscription createSubscription = new CreateSubscription();
        (uint256 subId,) = createSubscription.createSubscriptionUsingConfig();

        // Assert; a valid subscription ID is non-zero.
        assert(subId > 0);
    }

    /**
     * @dev Verifies that createSubscription() works when called directly
     *      with explicit parameters rather than going through HelperConfig.
     *
     *      Flow:
     *        1. Instantiate CreateSubscription.
     *        2. Call createSubscription() with the vrfCoordinator and account
     *           from setUp() — the same coordinator the raffle is wired to.
     *        3. Assert the subscription ID is non-zero.
     *        4. Assert the returned coordinator matches the one passed in.
     *
     *      Unlike testCreateSubscriptionUsingConfig(), this test passes the
     *      coordinator explicitly so the address comparison is valid.
     */
    function testCreateSubscriptionDirectly() public {
        // Arrange / Act
        CreateSubscription createSubscription = new CreateSubscription();
        (uint256 subId, address coordinator) = createSubscription.createSubscription(vrfCoordinator, account);

        // Assert; a valid subscription ID is non-zero and coordinator must match config.
        assert(subId > 0);
        assertEq(coordinator, vrfCoordinator);
    }
}
