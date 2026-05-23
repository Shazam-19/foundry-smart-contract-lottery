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

/**
 * @title   Raffle
 * @author  Abdelrahman Sayed
 * @notice  A decentralized raffle contract where users pay an entrance fee
 *          for a chance to be selected as the winner.
 * @dev     Implements Chainlink VRFv2.5 for provably fair randomness.
 *          This contract is currently under development — winner selection
 *          logic is not yet implemented.
 */
contract Raffle {
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

    address payable[] private s_player;

    /** Events */
    event RaffleEnterd(address indexed player);

    /* ─────────────────────────────────────────────
     * Constructor
     * ─────────────────────────────────────────────
     * Runs once at deployment. Sets the entrance fee
     * that all participants must pay to enter the raffle.
     *
     * @param enteranceFee  The minimum amount of ETH (in wei)
     *                      required to enter the raffle.
     */
    constructor(uint256 enteranceFee) {
        i_enteranceFee = enteranceFee;
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
    function enterRaffle() public payable {
        if (msg.value < i_enteranceFee) {
            revert Raffle_SendMoreToEnterRaffle();
        }

        s_player.push(payable(msg.sender));

        // Events benifits
        // 1. Makes migration easier
        // 2. Makes front end "indexing" easier
        emit RaffleEnterd(msg.sender);
    }

    /**
     * @notice Selects a winner from the pool of raffle entrants.
     * @dev    TODO: Implement Chainlink VRF v2.5 to request a verifiably
     *         random number, then use it to select and pay out the winner.
     */
    function pickWinner() public {}

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
