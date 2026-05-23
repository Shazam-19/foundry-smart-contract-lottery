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

// Use CTRL + Left Mouse Click on the contract name to go to the contract file
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

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
     * Prefixing errors with the contract name (Raffle_)
     * makes it easy to identify the source contract when
     * debugging multi-contract systems.
     */
    error Raffle_SendMoreToEnterRaffle();

    /* ─────────────────────────────────────────────
     * State Variables
     * ─────────────────────────────────────────────
     * The `immutable` keyword means the variable is set
     * once in the constructor and can never be changed.
     * It is more gas-efficient than a regular storage variable
     * because it is embedded directly into the contract bytecode.
     *
     * The `i_` prefix is a naming convention for immutable variables.
     */
    uint256 private immutable i_enteranceFee;

    /* s_ prefix is a naming convention for storage variables,
    * variables that are permanently stored on the blockchain.
    *
    * This is a dynamic array of payable addresses, one per entrant.
    * `payable` is required because we need to be able to send ETH
    * to the winner's address when `pickWinner()` runs.
    */
    address payable[] private s_players;

    // The minimum time (in seconds) that must pass between each raffle round.
    // Set once at deployment and never changed.
    uint256 private immutable i_interval;

    // Stores the block timestamp of the last time a winner was picked
    // (or the deployment time for the very first round).
    // Used to enforce the interval between rounds.
    uint256 private s_lastTimeStamp;

    /* Events
    *
    * Events are signals emitted by the contract that get logged on the blockchain.
    * They are NOT stored in contract storage, making them gas-efficient.
    *
    * Two key benefits:
    *   1. Easier contract migration —> external systems can replay history via logs.
    *   2. Easier front-end indexing —> tools like The Graph or ethers.js can
    *      listen for and react to events in real time.
    *
    * The `indexed` keyword on `player` allows this field to be efficiently
    * searched and filtered in event logs (up to 3 parameters can be indexed).
    */
    event RaffleEntered(address indexed player);

    /* ─────────────────────────────────────────────
    * Constructor
    * ─────────────────────────────────────────────
    * Runs exactly once at deployment. Initializes all
    * immutable variables and sets the starting timestamp
    * for the first raffle round.
    *
    * @param enteranceFee  The minimum amount of ETH (in wei)
    *                      required to enter the raffle.
    * @param interval      The minimum time (in seconds) that must
    *                      elapse between raffle rounds.
    */
    constructor(uint256 enteranceFee, uint256 interval, address vrfCoordinator) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_enteranceFee = enteranceFee;
        i_interval = interval;

        // Start the clock for the first round at the moment of deployment.
        // All future interval checks will measure time elapsed from this point.
        s_lastTimeStamp = block.timestamp;

        // Inherited variable from VRFConsumerBaseV2Plus
        s_vrfCoordinator.requestRandomWords();
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
     *               require(msg.value >= i_enteranceFee, Raffle_SendMoreToEnterRaffle());
     *             More gas-efficient than [1], but has limited compiler support
     *             and is not yet widely adopted.
     *
     *         [3] if/revert with custom error (current best practice):
     *               if (msg.value < i_enteranceFee) revert Raffle_SendMoreToEnterRaffle();
     *             Most gas-efficient option. Works reliably across 0.8.x versions.
     *             Slightly less readable than require, but preferred in production.
     */
    function enterRaffle() external payable {
        if (msg.value < i_enteranceFee) {
            revert Raffle_SendMoreToEnterRaffle();
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
     * @notice Picks a winner from the current pool of entrants.
     * @dev    Enforces a minimum time interval between rounds before
     *         requesting randomness from Chainlink VRF.
     *         Steps:
     *           1. Verify enough time has elapsed since the last round.
     *           2. Request a random number from Chainlink VRF v2.5.
     *           3. Use the random number to select a winner.
     *           4. Transfer the prize and reset the raffle state.
     */
    function pickWinner() external {
        // Revert if not enough time has passed since the last round.
        // Example: if i_interval = 50s and only 30s have passed → revert.
        //          if i_interval = 50s and 100s have passed     → proceed.
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert();
        }

        // TODO: Request a verifiably random number from Chainlink VRF v2.5.
        // The random number will be used in a callback function to select
        // and pay out the winner.
        // Get a random number 2.5
        // 1. Request RNG - we send the request
        // 2. Get RNG - chanlink node give us the random number
        /*
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        */
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {}

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
}
