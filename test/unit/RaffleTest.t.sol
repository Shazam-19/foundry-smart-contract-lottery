// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink-evm/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

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

    /**
     * @dev Verifies that checkUpkeep() returns false when the contract
     *      holds no ETH (i.e. no players have entered and paid a fee).
     *
     *      Time is warped past the interval to ensure the only failing
     *      condition is the missing balance — not the time check.
     */
    function testCheckUpkeepReturnsFalseIfRaffleHasNoETH() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    /**
     * @dev Verifies that checkUpkeep() returns false when the raffle is
     *      in the CALCULATING state (i.e. a VRF request is in flight).
     *
     *      performUpkeep() is called to transition the raffle from OPEN
     *      to CALCULATING before the upkeep check is made.
     */
    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Transition raffle to CALCULATING state, blocking new entries.
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    /**
     * @notice Tests that performUpkeep can only execute when upkeep conditions are met.
     *
     * @dev This test simulates a valid raffle scenario by:
     * 1. Making a player enter the raffle
     * 2. Advancing blockchain time past the required interval
     * 3. Advancing the block number
     *
     * After all conditions are satisfied, performUpkeep should execute successfully
     * without reverting.
     *
     * The test will fail if:
     * - No player entered the raffle
     * - Not enough time has passed
     * - performUpkeep incorrectly reverts
     */
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);

        // Simulate PLAYER entering the raffle
        raffle.enterRaffle{value: enteranceFee}();

        // Move blockchain time forward past the upkeep interval
        vm.warp(block.timestamp + interval + 1);

        // Mine a new block
        vm.roll(block.number + 1);

        // Act / Assert
        raffle.performUpkeep("");
    }

    /**
     * @notice Tests that performUpkeep reverts when upkeep conditions are not met.
     *
     * @dev This test intentionally avoids advancing time, so checkUpkeep()
     * should return false.
     *
     * The test verifies that performUpkeep() reverts with the exact
     * custom error and arguments expected.
     */
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange

        // Expected contract balance for the revert
        uint256 currentBalance = 0;

        // Expected number of raffle players
        uint256 numPlayers = 0;

        // Current raffle state (likely OPEN)
        Raffle.RaffleState rState = raffle.getRaffleState();

        // Pretend the next transaction is sent by PLAYER
        vm.prank(PLAYER);

        // PLAYER enters the raffle and sends ETH
        raffle.enterRaffle{value: enteranceFee}();

        // Update expected values after entering
        currentBalance += enteranceFee;
        numPlayers = 1;

        // Act / Assert

        /**
         * expectRevert() tells Foundry:
         * "The next function call MUST revert with this exact error data."
         *
         * abi.encodeWithSelector() builds the raw revert bytes.
         *
         * The selector is the first 4 bytes of:
         *
         * keccak256(
         *   "Raffle__UpkeepNotNeeded(uint256,uint256,uint256)"
         * )
         *
         * Every custom error/function in Solidity has a unique selector.
         *
         * Equivalent concept:
         *
         * bytes4 selector =
         *     bytes4(
         *         keccak256(
         *             "Raffle__UpkeepNotNeeded(uint256,uint256,uint256)"
         *         )
         *     );
         *
         * Then Solidity ABI-encodes:
         * - selector
         * - currentBalance
         * - numPlayers
         * - rState
         *
         * into one bytes payload.
         *
         * The contract is expected to revert with:
         *
         * revert Raffle__UpkeepNotNeeded(
         *     currentBalance,
         *     numPlayers,
         *     rState
         * );
         */
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );

        // This should revert because upkeep conditions are not satisfied
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);

        // Simulate PLAYER entering the raffle
        raffle.enterRaffle{value: enteranceFee}();

        // Move blockchain time forward past the upkeep interval
        vm.warp(block.timestamp + interval + 1);

        // Mine a new block
        vm.roll(block.number + 1);

        _;
    }

    /**
     * @notice Verifies that calling `performUpkeep` updates the raffle state
     *         and emits a valid VRF request ID.
     *
     * @dev The `raffleEntered` modifier performs the test setup by:
     *      1. Entering a player into the raffle.
     *      2. Advancing time beyond the upkeep interval.
     *      3. Mining a new block.
     *
     * Expected results:
     * - A randomness request is submitted to the VRF coordinator.
     * - A non-zero request ID is emitted.
     * - The raffle state changes from OPEN to CALCULATING.
     */
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        // Setup is handled by the `raffleEntered` modifier.

        // Begin recording all events emitted during the transaction.
        vm.recordLogs();

        // Execute upkeep. This should request randomness and update
        // the raffle state to CALCULATING.
        raffle.performUpkeep("");

        // Retrieve all logs emitted during the upkeep call.
        Vm.Log[] memory entries = vm.getRecordedLogs();

        /**
         * Event logs are returned as an array of `Vm.Log` structs.
         *
         *
         * During performUpkeep(), two events are emitted which corresponds to the VRF coordinator 'requestId':
         * - entries[0] → RandomWordsRequested, emitted by the VRF coordinator which is implemented and returned by the VRFCoordinatorV2_5Mock.sol.
         * - entries[1] → RequestedRaffleWinner, emitted by our performUpkeep()
         *                  function in Raffle.sol. This is the event that contains the requestId we need.
         *
         * Each `Vm.Log` contains a `topics` array used for indexed event parameters:
         * - topics[0] = event signature hash (identifies the event type)
         * - topics[1] = first indexed parameter (requestId in this case)
         *
         * Example event:
         * event RequestedRaffleWinner(uint256 indexed requestId);
         *
         * Therefore:
         * entries[1].topics[1] corresponds to the VRF requestId emitted by `performUpkeep`.
         */
        bytes32 requestId = entries[1].topics[1];

        // Read the current raffle state after upkeep execution.
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Verify that a valid VRF request ID was generated.
        assert(uint256(requestId) > 0);

        // Verify that the raffle is now waiting for the random number response.
        // State value 1 corresponds to RaffleState.CALCULATING.
        assert(uint256(raffleState) == 1);
    }

    /**
     * @dev Stateless fuzz test — verifies that fulfillRandomWords() can only
     *      be called with a valid requestId produced by performUpkeep().
     *
     *      Foundry automatically runs this test with many random values for
     *      `randomRequestId`. Any arbitrary ID that was not issued by the
     *      coordinator should be rejected with InvalidRequest.
     *
     *      The `raffleEntered` modifier sets up a player, warps time, and
     *      calls performUpkeep() — but any requestId other than the one it
     *      produced should still revert.
     */
    function testFulfillrandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered {
        // Arrange / Act / Assert

        // Tells Foundry that the next call must revert with InvalidRequest.
        // If it doesn't revert, the test fails.
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);

        // Attempts to call fulfillRandomWords() with an arbitrary requestId.
        // Since this ID was never issued by performUpkeep(), the coordinator
        // has no record of it and rejects it; triggering the expected revert.
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    /**
     * @dev Verifies the full end-to-end raffle flow:
     *      1. Multiple players enter the raffle.
     *      2. performUpkeep() triggers a VRF randomness request.
     *      3. fulfillRandomWords() selects a winner, resets state, and pays out.
     *
     *      The `raffleEntered` modifier pre-enters PLAYER before this test runs,
     *      so the total player count is additionalEntrants + 1.
     *
     *      expectedWinner is address(1) because the VRF mock returns a predictable
     *      random value, and randomWords[0] % 4 resolves to index 0 → address(1).
     */
    function testFulfillrandomWordsPicksWinnerThenResetAndSendsMoney() public raffleEntered {
        // Arrange
        uint256 startingIndex = 1;
        uint256 additionalEntrants = 3; // 3 extra players = 4 total
        address expectedWinner = address(1); // Current balance is 0 ether

        // Enter additional players into the raffle.
        // hoax() combines vm.prank() and vm.deal(); it funds and impersonates
        // the address in a single call, then reverts to the original sender after.
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            // uint256 (i) cannot be cast to address directly — it must go through uint160 first
            // because an Ethereum address is 20 bytes (160 bits) wide.
            // Path: uint256 → uint160 → address
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: enteranceFee}();
        }

        // Capture pre-draw values to compare against after the draw.
        uint256 startingTimeStamp = raffle.getLastTimeStamp();

        // expectedWinner is address(1); it was only funded with 1 ether via hoax()
        // to cover the entrance fee. After paying it, its remaining balance is
        // approximately 0 (1 ether - entranceFee).
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act

        // Begin recording all events emitted from this point forward.
        // Needed to extract the VRF requestId from the emitted logs.
        vm.recordLogs();

        // Trigger upkeep — transitions raffle to CALCULATING and emits a VRF request.
        raffle.performUpkeep("");

        // Retrieve all logs emitted during performUpkeep().
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Extract the requestId from the second log entry's second topic.
        // entries[1] is the RequestedRaffleWinner event emitted by performUpkeep() in Raffle.sol.
        // topics[1] is the 'requestId'; topics[0] is always the event signature hash retuned by VRFCoordinatorV2_5Mock.sol
        bytes32 requestId = entries[1].topics[1];

        // Simulate the Chainlink VRF callback — delivers the random result to the raffle.
        // On a real network, the VRF oracle would call this automatically.
        // The mock allows us to trigger it manually in tests.
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert

        // Fetch the winner selected by fulfillRandomWords().
        address recentWinner = raffle.getRecentWinner();

        // Fetch the raffle state — should be OPEN (0) after the draw resets it.
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Fetch the winner's balance after receiving the prize payout.
        uint256 winnerBalance = recentWinner.balance;

        // Fetch the timestamp updated at the end of fulfillRandomWords().
        // Should be greater than startingTimeStamp, confirming a new round began.
        uint256 endingTimeStamp = raffle.getLastTimeStamp();

        // Total prize = entranceFee × total number of players.
        uint256 prize = enteranceFee * (additionalEntrants + 1);

        // Verify the correct winner was selected.
        assert(recentWinner == expectedWinner);

        // Verify the raffle state was reset to OPEN (0) after the draw.
        assert(uint256(raffleState) == 0);

        // Verify the winner received the full prize pool.
        // Since winnerStartingBalance ≈ 0, this effectively asserts:
        // winnerBalance == prize (the full pool paid out to the winner).
        assert(winnerBalance == winnerStartingBalance + prize);

        // Verify the timestamp was updated, confirming a new round started.
        assert(endingTimeStamp > startingTimeStamp);
    }
}
