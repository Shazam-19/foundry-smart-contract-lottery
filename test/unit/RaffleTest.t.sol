// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

/*
 * ─────────────────────────────────────────────────────────────
 *  RaffleTest — Unit Tests for the Raffle contract
 * ─────────────────────────────────────────────────────────────
 *
 *  Uses Foundry's Test framework (forge-std).
 *  Each test function follows the Arrange → Act → Assert pattern:
 *
 *    Arrange → set up the state and conditions for the test.
 *    Act     → call the function being tested.
 *    Assert  → verify the outcome matches expectations.
 *
 *  setUp() runs automatically before every individual test function,
 *  ensuring each test starts from a clean, consistent state.
 * ─────────────────────────────────────────────────────────────
 */
contract RaffleTest is Test {
    /* ─────────────────────────────────────────────
     * Events
     * ─────────────────────────────────────────────
     * Events must be redeclared here to use vm.expectEmit() in tests.
     * Foundry requires the test contract to emit the expected event
     * itself so it can compare it against what the contract emits.
     * These must exactly match the declarations in Raffle.sol.
     */

    // Emitted when a player successfully enters the raffle.
    event RaffleEntered(address indexed player);

    // Emitted when a winner is selected and paid at the end of a round.
    event WinnerPicked(address indexed winner);

    /* ─────────────────────────────────────────────
     * Contract Instances
     * ─────────────────────────────────────────────
     */
    Raffle public raffle;
    HelperConfig public helperConfig;

    /* ─────────────────────────────────────────────
     * Network Config Variables
     * ─────────────────────────────────────────────
     * Unpacked from HelperConfig in setUp() so individual tests
     * can reference them directly without going through the struct.
     */
    uint256 enteranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callBackGasLimi;

    /* ─────────────────────────────────────────────
     * Test Actors & Constants
     * ─────────────────────────────────────────────
     */

    // A named fake address used as a raffle participant across all tests.
    // makeAddr() creates a deterministic address from a string label.
    address public PLAYER = makeAddr("Shazam");

    // The ETH balance given to PLAYER at the start of each test via vm.deal().
    // 10 ether is enough to cover entrance fees across multiple test scenarios.
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    /* ─────────────────────────────────────────────
     * setUp()
     * ─────────────────────────────────────────────
     * Runs automatically before every test function.
     * Deploys a fresh Raffle contract using the same DeployRaffle
     * script used in production, ensuring tests reflect real deployment.
     */
    function setUp() external {
        // Deploy the raffle using the production deploy script.
        // This ensures tests run against the same setup as a real deployment.
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployRaffle();

        // Fetch the network config and unpack it into local variables
        // so individual tests can access parameters like enteranceFee directly.
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        enteranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callBackGasLimi = config.callBackGasLimit;

        // Fund PLAYER with a starting balance so they can pay entrance fees.
        // vm.deal() sets an address's ETH balance directly — no transfer needed.
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /* ─────────────────────────────────────────────
     * Tests
     * ─────────────────────────────────────────────
     */

    /**
     * @dev Verifies that the raffle starts in the OPEN state after deployment.
     *      If this fails, no player would be able to enter the raffle at all.
     */
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * @dev Verifies that enterRaffle() reverts when the caller sends
     *      less ETH than the required entrance fee.
     *
     *      vm.prank(PLAYER) makes the next call appear to come from PLAYER.
     *      vm.expectRevert() asserts that the next call reverts with the
     *      specified custom error selector.
     *      Calling raffle.enterRaffle() with no value (0 ETH) triggers the revert.
     */
    function testRaffleRevertWhenInsufficientEntranceFee() public {
        // Arrange
        vm.prank(PLAYER);

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    /**
     * @dev Verifies that a player's address is correctly stored in the
     *      s_players array after they enter the raffle.
     *
     *      getPlayer(0) retrieves the first element of the players array.
     *      If the address matches PLAYER, the storage write was successful.
     */
    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);

        // Act
        raffle.enterRaffle{value: enteranceFee}();

        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    /**
     * @dev Verifies that enterRaffle() emits the RaffleEntered event
     *      with the correct player address.
     *
     *      vm.expectEmit() parameters: (checkTopic1, checkTopic2, checkTopic3, checkData, emitter)
     *        - checkTopic1: true  → verify the first indexed param (player address).
     *        - checkTopic2: false → no second indexed param to check.
     *        - checkTopic3: false → no third indexed param to check.
     *        - checkData:   false → no non-indexed data to check.
     *        - emitter:     address(raffle) → the event must come from this contract.
     *
     *      The emit line declares what we expect the event to look like.
     *      The actual call to enterRaffle() triggers the real event,
     *      which Foundry then compares against our expectation.
     */
    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);

        // Act — declare the expected event before the call that triggers it
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        // Assert — the actual call; Foundry checks the emitted event matches
        raffle.enterRaffle{value: enteranceFee}();
    }

    /**
     * @dev Verifies that enterRaffle() reverts when the raffle is in the
     *      CALCULATING state (i.e. a VRF request is in flight).
     *
     *      To trigger the CALCULATING state, we:
     *        1. Have a player enter so the raffle has a balance and participants.
     *        2. Fast-forward time past the interval using vm.warp().
     *        3. Mine a new block using vm.roll() — some checks depend on block number.
     *        4. Call performUpkeep() which transitions the raffle to CALCULATING.
     *
     *      With the raffle in CALCULATING state, any further attempt to enter
     *      should revert with Raffle__RaffleNotOpen.
     */
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange — enter the raffle and advance time to make upkeep valid
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();

        // vm.warp() fast-forwards the block timestamp by (interval + 1) seconds.
        // The +1 ensures we are strictly past the interval, not exactly at it.
        // Example: if interval = 30s and block.timestamp = 1000,
        //          vm.warp sets block.timestamp to 1031 → time check passes.
        vm.warp(block.timestamp + interval + 1);

        // vm.roll() advances the block number by 1.
        // Some contracts and VRF checks rely on block number changing,
        // so this ensures we are on a new block after the warp.
        vm.roll(block.number + 1);

        // performUpkeep() transitions the raffle from OPEN → CALCULATING
        // and fires off the Chainlink VRF request. Passing "" means no
        // additional calldata is needed (checkUpkeep uses no input data).
        raffle.performUpkeep("");

        // ⚠️ Note: performUpkeep() may fail here on a live network if the VRF
        // subscription is not funded or if this contract is not registered as
        // a consumer. On Anvil, the mock coordinator handles this automatically.

        // Act / Assert — attempting to enter while CALCULATING should revert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }
}
