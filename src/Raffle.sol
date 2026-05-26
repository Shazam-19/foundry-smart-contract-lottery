// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ── Chainlink VRF Imports ──────────────────────────────────────────────────
// Tip: CTRL + Left Click on a contract name to navigate to its source file.

// Provides the base contract for Chainlink VRF v2.5 consumers.
// Raffle must inherit from this to receive random numbers via fulfillRandomWords().
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

// Provides the RandomWordsRequest struct and helper utilities used to
// build and encode the randomness request sent to the VRF coordinator.
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title   Raffle
 * @author  Abdelrahman Sayed
 * @notice  A decentralized raffle contract where users pay an entrance fee
 *          for a chance to be selected as the winner.
 * @dev     Implements Chainlink VRFv2.5 for provably fair randomness.
 *          This contract is currently under development — winner selection
 *          logic is not yet implemented.
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* ─────────────────────────────────────────────
     * Custom Errors
     * ─────────────────────────────────────────────
     * Prefixing errors with the contract name (Raffle__)
     * makes it easy to identify the source contract when
     * debugging multi-contract systems.
     */

    // Thrown when a user attempts to enter the raffle without
    // sending the minimum required ETH entrance fee.
    error Raffle__SendMoreToEnterRaffle();

    // Thrown when the ETH transfer to the winner fails.
    // This can happen if the winner's address is a contract
    // that does not accept ETH (i.e. has no receive() or fallback()).
    error Raffle__TransferFailed();

    // Thrown when a user attempts to enter the raffle while it is in the
    // CALCULATING state (i.e. a VRF request is in flight and the current
    // round has not yet been resolved).
    error Raffle__RaffleNotOpen();

    // Thrown when checkUpkeep() returns false and pickWinner() is called
    // prematurely. Carries diagnostic values to help identify which condition
    // was not met:
    //
    //   balance       → contract has no ETH to pay out (no one entered)
    //   playersLength → no players have entered the raffle
    //   RaffleState   → raffle is not in OPEN state (e.g. still CALCULATING)
    //
    // Example:
    //   Raffle__UpkeepNotNeeded(0, 0, 1)
    //   → balance is 0, no players, raffle is CALCULATING (1) → too early to pick
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 RaffleState);

    /* ─────────────────────────────────────────────
     * Type Declarations
     * ─────────────────────────────────────────────
     * Enums define a custom type with a fixed set of named states.
     * Under the hood, Solidity stores them as uint8 (0, 1, 2...).
     * Using an enum instead of raw numbers makes the code more
     * readable and prevents invalid state assignments.
     */
    enum RaffleState {
        OPEN, // 0 — The raffle is accepting new entrants.
        CALCULATING // 1 — A VRF request is in flight; no new entrants allowed.
    }

    /* ─────────────────────────────────────────────
     * State Variables
     * ─────────────────────────────────────────────
     * Three storage types are used here, each with its own prefix convention:
     *
     *   constant  (no prefix needed) — value fixed at compile time, cheapest to access.
     *   immutable (i_ prefix)        — set once in the constructor, baked into bytecode.
     *   storage   (s_ prefix)        — lives on the blockchain, can change over time.
     *
     * Both `constant` and `immutable` are more gas-efficient than regular
     * storage variables because they are embedded directly into the contract
     * bytecode rather than stored in a dedicated storage slot.
     */

    // ── VRF Configuration ──────────────────────────────────────────────────

    // Number of block confirmations Chainlink waits before sending the random result.
    // 3 is the recommended minimum — higher values increase security but slow response.
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    // The gas lane key hash — identifies which Chainlink VRF job to use and sets
    // the maximum gas price (in wei) you are willing to pay for the callback.
    // Different networks and gas lanes have different key hashes.
    bytes32 private immutable i_keyHash;

    // The Chainlink subscription ID that funds VRF requests for this contract.
    // Created and funded via https://vrf.chain.link before deployment.
    uint256 private immutable i_subscriptionId;

    // Maximum gas the fulfillRandomWords() callback is allowed to consume.
    // If the callback exceeds this limit, the transaction reverts.
    // Set this based on the complexity of your fulfillRandomWords() logic.
    uint32 private immutable i_callBackGasLimit;

    // Number of random values to request from Chainlink VRF per round.
    // We only need 1 — a single random number is enough to pick a winner.
    uint32 private constant NUM_WORDS = 1;

    // ── Raffle Configuration ───────────────────────────────────────────────

    // The minimum amount of ETH (in wei) a user must send to enter the raffle.
    uint256 private immutable i_enteranceFee;

    // The minimum time (in seconds) that must elapse between raffle rounds.
    // Prevents a new round from being triggered too soon after the last one.
    uint256 private immutable i_interval;

    // ── Raffle State ───────────────────────────────────────────────────────

    // Dynamic array of all current entrants' addresses.
    // Declared `payable` so ETH can be transferred directly to the winner's address.
    // Reset at the start of each new round.
    address payable[] private s_players;

    // The block timestamp of the last round's completion (or deployment for round 1).
    // Compared against block.timestamp in pickWinner() to enforce i_interval.
    uint256 private s_lastTimeStamp;

    // Stores the address of the most recently selected raffle winner.
    // Updated at the end of each round inside fulfillRandomWords().
    // Reset to address(0) at the start of each new round.
    address private s_recentWinner;

    // Tracks the current state of the raffle.
    // Initialized to OPEN (0) by default when the contract is deployed.
    // Set to CALCULATING while waiting for Chainlink VRF to respond,
    // then back to OPEN once the winner has been selected and paid.
    RaffleState private s_raffleState;

    /* ─────────────────────────────────────────────
     * Events
     * ─────────────────────────────────────────────
     * Events are signals emitted by the contract that get logged on the
     * blockchain. They are NOT stored in contract storage, making them
     * significantly cheaper than updating a state variable.
     *
     * Two key benefits:
     *   1. Easier contract migration — external systems can replay the full
     *      history of a contract by reading its event logs.
     *   2. Easier front-end indexing — tools like The Graph or ethers.js can
     *      listen for and react to events in real time without polling.
     *
     * The `indexed` keyword allows a parameter to be efficiently searched
     * and filtered in event logs (up to 3 parameters can be indexed per event).
     * Non-indexed parameters are still logged but cannot be filtered directly.
     */

    // Emitted when a player successfully enters the raffle.
    // Indexed on `player` so front-ends can filter entries by wallet address.
    event RaffleEntered(address indexed player);

    // Emitted when a winner is selected and paid at the end of a round.
    // Indexed on `winner` so front-ends can filter and display past winners.
    event WinnerPicked(address indexed winner);

    /* ─────────────────────────────────────────────
     * Constructor
     * ─────────────────────────────────────────────
     * Runs exactly once at deployment. Initializes all immutable
     * variables and starts the interval clock for the first round.
     *
     * Inherits from VRFConsumerBaseV2Plus, which requires the VRF
     * coordinator address to be passed up via its own constructor.
     *
     * @param enteranceFee    The minimum amount of ETH (in wei) required to enter.
     * @param interval        The minimum time (in seconds) between raffle rounds.
     *
     * @param vrfCoordinator  The address of the Chainlink VRF Coordinator contract
     *                        on the deployed network. This is the on-chain contract
     *                        that handles randomness requests and delivers results.
     *                        Passed directly to the VRFConsumerBaseV2Plus parent constructor.
     *
     * @param gasLane         The key hash of the VRF gas lane to use. Acts as an ID
     *                        for the off-chain VRF job that responds to requests.
     *                        Also defines the maximum gas price (in wei) you are
     *                        willing to pay for a randomness request. Different
     *                        networks offer multiple gas lanes at different price caps.
     *
     * @param subscriptionId  The Chainlink subscription ID used to fund VRF requests.
     *                        The subscription must be created and topped up with LINK
     *                        (or ETH if using nativePayment) at https://vrf.chain.link
     *                        before deployment, and this contract must be added as
     *                        an approved consumer on that subscription.
     *
     * @param callBackGasLimit The maximum gas that fulfillRandomWords() is allowed
     *                         to consume. Must be less than the coordinator's maxGasLimit.
     *                         If the callback exceeds this limit it will fail — however,
     *                         the subscription is still charged for the work done to
     *                         generate the random values. Increase this value if your
     *                         fulfillRandomWords() logic is complex or stores many values.
     */
    constructor(
        uint256 enteranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_enteranceFee = enteranceFee;
        i_interval = interval;

        // Start the clock for the first round at the moment of deployment.
        // All future interval checks measure time elapsed from this point.
        s_lastTimeStamp = block.timestamp;

        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN; // This is the same as RaffleState(0)
    }

    /**
     * @notice Enters the caller into the raffle.
     * @dev    The caller must send at least `i_enteranceFee` wei with
     *         this transaction. If they send less, the transaction reverts.
     *
     *         Three approaches to enforce this check are shown below,
     *         ordered from oldest to most gas-efficient:
     *
     *         [1] require with string message (legacy — avoid in new code):
     *               require(msg.value >= i_enteranceFee, "Not Enough ETH Sent!");
     *             Simple and readable, but storing the string wastes gas.
     *
     *         [2] require with custom error (introduced in Solidity 0.8.26):
     *               require(msg.value >= i_enteranceFee, Raffle__SendMoreToEnterRaffle());
     *             More gas-efficient than [1], but has limited compiler support
     *             and is not yet widely adopted.
     *
     *         [3] if/revert with custom error (current best practice):
     *               if (msg.value < i_enteranceFee) revert Raffle__SendMoreToEnterRaffle();
     *             Most gas-efficient option. Works reliably across 0.8.x versions.
     *             Slightly less readable than require, but preferred in production.
     */
    function enterRaffle() external payable {
        if (msg.value < i_enteranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        // Adds the caller's address to the players array.
        // `payable(msg.sender)` casts the address to a payable type
        // so ETH can be sent to it later when a winner is selected.
        s_players.push(payable(msg.sender));

        // Emits an event to log that a new player has entered.
        // Front-end applications and indexers (e.g. The Graph) can
        // listen for this event to update the UI in real time.
        emit RaffleEntered(msg.sender);
    }

    /**
     * @notice Checks whether the raffle conditions are met to trigger upkeep.
     * @dev Called by Chainlink Automation nodes to determine whether
     * `performUpkeep()` should execute.
     *
     * Requirements:
     * - The configured time interval must have elapsed.
     * - The raffle must currently be open.
     * - The contract must contain ETH.
     * - At least one player must have entered.
     *
     *
     * @return upkeepNeeded True if upkeep should be performed.
     * @return performData Encoded data to be passed to `performUpkeep()`.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        // Declaring 'checkData' as 'calldata' type is more gas efficient than 'memory'
        public
        view
        // `upkeepNeeded` is implicitly initialized through the named return variable declaration
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;

        bool isOpen = s_raffleState == RaffleState.OPEN;

        bool hasBalance = address(this).balance > 0;

        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;

        return (upkeepNeeded, "");
    }

    /**
     * @notice Initiates the process of selecting a raffle winner.
     * @dev Called by Chainlink Automation when `checkUpkeep()` returns true.
     *
     * Workflow:
     * 1. Verify that upkeep conditions are still satisfied.
     * 2. Change the raffle state to `CALCULATING` to prevent new entries.
     * 3. Request a random number from Chainlink VRF.
     * 4. Chainlink VRF later calls `fulfillRandomWords()` with the result.
     *
     * Requirements:
     * - The raffle must be open.
     * - The raffle interval must have passed.
     * - The contract must contain ETH.
     * - At least one player must have entered.
     *
     */
    function performUpkeep(
        bytes calldata /* performData */
    )
        external
    {
        // Check that upkeep conditions for safety to initialize the lottery.
        // This prevents execution if conditions changed.
        (bool upkeepNeeded,) = checkUpkeep("");

        // Revert if upkeep is not required.
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        // Lock the raffle while the winner is being determined.
        s_raffleState = RaffleState.CALCULATING;

        // Request a random number from Chainlink VRF v2.5.
        // This is Step 1 of 2 — we send the request and receive a requestId.
        // Chainlink's oracle node will later call fulfillRandomWords() with the result.
        // Note: The subscription must be funded with LINK (or ETH if nativePayment is true)
        //       or this call will revert.
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                // The gas lane key hash — determines the max gas price for the VRF callback.
                keyHash: i_keyHash,
                // The Chainlink subscription ID that funds this request.
                subId: i_subscriptionId,
                // How many block confirmations Chainlink waits before responding.
                // More confirmations = more security, but slower response.
                requestConfirmations: REQUEST_CONFIRMATIONS,
                // Max gas the callback function (fulfillRandomWords) is allowed to use.
                callbackGasLimit: i_callBackGasLimit,
                // How many random numbers to request (we only need 1 to pick a winner).
                numWords: NUM_WORDS,
                // nativePayment: false → pay the VRF fee in LINK.
                // Set to true to pay in native ETH (e.g. Sepolia ETH on testnet).
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        // Prevent unused parameter warning
        requestId;
    }

    /**
     * @notice Callback function invoked by the Chainlink VRF node with the random result.
     * @dev    This is Step 2 of 2 in the VRF process. Chainlink calls this automatically
     *         after fulfilling the request made in pickWinner().
     *
     *         Marked `internal` so only the VRF coordinator contract can trigger it,
     *         and `override` because VRFConsumerBaseV2Plus defines it as `virtual`,
     *         requiring us to provide our own implementation.
     *
     *         Executes in order:
     *           1. Derive a valid array index from the random number using modulo.
     *           2. Select and store the winner.
     *           3. Reset raffle state for the next round.
     *           4. Transfer the full contract balance to the winner.
     *           5. Revert with a custom error if the transfer fails.
     *           6. Emit an event to log the winner.
     *
     * @param requestId   The ID of the fulfilled VRF request. Not used here but
     *                    required by the parent contract's function signature.
     * @param randomWords Array of random values returned by Chainlink VRF.
     *                    Only randomWords[0] is used — one random number is enough
     *                    to derive a winner index via modulo.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        /* Checks */
        // Conditionals

        /* Effect (Internal Contract State) */

        // Use modulo to convert the large random number into a valid s_players index.
        // Example: s_players.length = 10, randomWords[0] = 54464968745561265489741236776
        //          54464968745561265489741236776 % 10 = 6 → player at index 6 wins.
        if (s_players.length == 0) {
            revert Raffle__NoPlayers();
        }
        uint256 indexOfWinner = randomWords[0] % s_players.length;

        // Retrieve the winner's address from the players array and store it.
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        // Reset the raffle state for the next round BEFORE transferring funds.
        // Resetting state first follows the Checks-Effects-Interactions (CEI) pattern,
        // which protects against reentrancy attacks; if the transfer somehow
        // triggered a reentrant call, the raffle state would already be clean.
        // Sometimes it's called Function Requirments Effects-Interactions Protocol Invariants (FREI-PI)
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        // Emit an event to log the winner's address for off-chain indexing.
        // Note: s_recentWinner is used instead of recentWinner so that the
        // emitted value reflects what is actually stored in contract state.
        emit WinnerPicked(s_recentWinner);

        /* Interactions (External Contract Interactions) */

        // Transfer the entire contract balance to the winner.
        // .call is the recommended way to send ETH — it forwards all available
        // gas and returns a success bool rather than throwing on failure.
        // The empty string ("") means we are sending ETH with no function call data.
        (bool success,) = recentWinner.call{value: address(this).balance}("");

        // If the transfer failed (e.g. winner is a contract that rejects ETH),
        // revert the entire transaction to protect the funds.
        if (!success) {
            revert Raffle__TransferFailed();
        }

        // Prevent unused parameter warning
        requestId;
    }

    /* ─────────────────────────────────────────────
     * Getter Functions
     * ─────────────────────────────────────────────
     * Read-only functions that expose private state
     * variables to the outside world. Using explicit
     * getters (rather than making variables public)
     * gives you more control over what is exposed.
     */

    /**
     * @notice Returns the entrance fee required to join the raffle.
     * @return The entrance fee in wei (1 ETH = 1e18 wei).
     */
    function getEntranceFee() external view returns (uint256) {
        return i_enteranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }
}

/**
 * Refactored this function and splitted it into checkUpkeep and pickWinner functions
 * @notice Initiates the winner selection process for the current raffle round.
 * @dev    Enforces a minimum time interval between rounds, then requests a
 *         verifiably random number from Chainlink VRF v2.5.
 *         The two-step process:
 *           1. [This function] Verify elapsed time → request randomness from Chainlink.
 *           2. [fulfillRandomWords] Receive randomness → select winner → pay out prize.
 *
 * function pickWinner() external {
 *     // Revert if not enough time has passed since the last round.
 *     // Example: if i_interval = 50s and only 30s have passed → revert.
 *     //          if i_interval = 50s and 100s have passed     → proceed.
 *     if ((block.timestamp - s_lastTimeStamp) < i_interval) {
 *         revert();
 *     }
 *
 *     s_raffleState = RaffleState.CALCULATING;
 *
 *     // Request a random number from Chainlink VRF v2.5.
 *     // This is Step 1 of 2 — we send the request and receive a requestId.
 *     // Chainlink's oracle node will later call fulfillRandomWords() with the result.
 *     // Note: The subscription must be funded with LINK (or ETH if nativePayment is true)
 *     //       or this call will revert.
 *     uint256 requestId = s_vrfCoordinator.requestRandomWords(
 *         VRFV2PlusClient.RandomWordsRequest({
 *             // The gas lane key hash — determines the max gas price for the VRF callback.
 *             keyHash: i_keyHash,
 *             // The Chainlink subscription ID that funds this request.
 *             subId: i_subscriptionId,
 *             // How many block confirmations Chainlink waits before responding.
 *             // More confirmations = more security, but slower response.
 *             requestConfirmations: REQUEST_CONFIRMATIONS,
 *             // Max gas the callback function (fulfillRandomWords) is allowed to use.
 *             callbackGasLimit: i_callBackGasLimit,
 *             // How many random numbers to request (we only need 1 to pick a winner).
 *             numWords: NUM_WORDS,
 *             // nativePayment: false → pay the VRF fee in LINK.
 *             // Set to true to pay in native ETH (e.g. Sepolia ETH on testnet).
 *             extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
 *         })
 *     );
 * }
 */