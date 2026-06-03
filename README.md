<a id="readme-top"></a>

# Lottery Raffle
A decentralized lottery raffle smart contract built with Solidity and Foundry, using Chainlink VRF 2.5 and Automation for verifiable on-chain randomness.

---

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#how-it-works">How It Works</a></li>
    <li><a href="#built-with">Built With</a></li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
        <li><a href="#environment-variables">Environment Variables</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#deploy-locally-anvil">Deploy Locally (Anvil)</a></li>
        <li><a href="#deploy-to-sepolia">Deploy to Sepolia</a></li>
        <li><a href="#vrf-subscription-management">VRF Subscription Management</a></li>
      </ul>
    </li>
    <li><a href="#running-tests">Running Tests</a></li>
    <li><a href="#contract-overview">Contract Overview</a></li>
    <li><a href="#security-considerations">Security Considerations</a></li>
    <li><a href="#supported-networks">Supported Networks</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#author">Author</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

---

## About The Project

A decentralized raffle contract where users pay an entrance fee for a chance to be selected as the winner. The winner selection process is fully automated and provably fair; no central authority can influence or predict the outcome.

**Key highlights:**

- **Provably fair** — winner selection uses Chainlink VRF v2.5, making randomness verifiable and tamper-proof on-chain.
- **Fully automated** — Chainlink Automation triggers the draw once the configured interval elapses and conditions are met.
- **Secure prize distribution** — uses the pull (withdrawal) pattern to prevent funds from being locked if a transfer fails.
- **Multi-network** — works on Sepolia testnet with real Chainlink infrastructure, and locally on Anvil with deployed mocks.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Features

- 🎲 **Provably fair randomness** — Chainlink VRF v2.5 generates verifiable random numbers that cannot be manipulated by miners, validators, or the contract owner.
- 🤖 **Fully automated draws** — Chainlink Automation monitors the contract and triggers `performUpkeep()` once all conditions are met — no manual intervention needed.
- 🔒 **Reentrancy-safe prize distribution** — uses the pull (withdrawal) pattern with CEI ordering; winners call `claimPrize()` themselves rather than receiving ETH automatically.
- 🛡️ **Request ID validation** — `fulfillRandomWords()` validates the incoming `requestId` against `s_lastRequestId` to reject unexpected or duplicate VRF callbacks.
- ♻️ **Automatic round reset** — after each draw the contract resets `s_players`, `s_raffleState`, and `s_lastTimeStamp` so a new round begins immediately.
- 🌐 **Multi-network support** — deploys to Sepolia testnet with real Chainlink infrastructure, or locally on Anvil with auto-deployed VRF and LINK mocks.
- ⚙️ **Centralised config management** — `HelperConfig.s.sol` resolves all network-specific parameters automatically, keeping deploy scripts clean and portable.
- 🧪 **Comprehensive test suite** — unit, integration, fuzz, and fork tests using Foundry's `forge-std` framework.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## How It Works

1. **Enter** — Players call `enterRaffle()` and send at least the entrance fee in ETH.
2. **Wait** — The raffle stays open until the configured time interval elapses.
3. **Trigger** — Chainlink Automation calls `performUpkeep()` once all conditions are met (time passed, raffle open, ETH in contract, players present).
4. **Randomness** — `performUpkeep()` requests a random number from Chainlink VRF. The raffle enters the `CALCULATING` state and blocks new entries.
5. **Select Winner** — Chainlink VRF calls `fulfillRandomWords()` with the result. A winner is picked using modulo on the random value.
6. **Claim Prize** — The winner calls `claimPrize()` to withdraw the full prize pool to their wallet.
7. **Reset** — The raffle resets to `OPEN` and a new round begins.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Built With

- [Solidity](https://soliditylang.org/) `^0.8.19`
- [Foundry](https://getfoundry.sh/) — Smart contract development framework
- [Chainlink VRF](https://chain.link/vrf) v2.5 — Verifiable randomness
- [Chainlink Automation](https://chain.link/automation) — Automated upkeep execution
- [forge-std](https://github.com/foundry-rs/forge-std) — Testing utilities
- [foundry-devops](https://github.com/Cyfrin/foundry-devops) — Deployment helpers
- [OpenZeppelin Contracts](https://github.com/openzeppelin/openzeppelin-contracts) — Security-focused contract standards
- [Solady](https://github.com/vectorized/solady) — Gas-optimized contract utilities

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Project Structure

```
raffle/
├── foundry.toml                        # Foundry configuration
├── Makefile                            # Shorthand commands for common tasks
├── README.md
│
├── src/
│   └── Raffle.sol                      # Core raffle contract
│
├── script/
│   ├── DeployRaffle.s.sol              # Deployment script — deploys and wires everything
│   ├── HelperConfig.s.sol              # Network config manager (Sepolia + Anvil)
│   └── Interactions.s.sol             # VRF subscription scripts (Create, Fund, AddConsumer)
│
├── test/
│   ├── unit/
│   │   └── RaffleTest.t.sol            # Unit and fuzz tests for Raffle.sol
│   └── mocks/
│       └── LinkToken.sol               # Mock LINK token for local Anvil testing
│
└── lib/
    ├── chainlink-evm/                  # Chainlink VRF contracts and mocks
    ├── forge-std/                      # Foundry standard library
    └── foundry-devops/                 # DevOps helpers (e.g. get_most_recent_deployment)
```

> Run `tree -L 2` in your project root to verify your local structure matches.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- [Git](https://git-scm.com/)
- An RPC URL (e.g. from [Alchemy](https://alchemy.com/) or [Infura](https://infura.io/))
- A funded wallet private key (for testnet deployment)
- An [Etherscan API key](https://etherscan.io/myapikey) (for contract verification)

Verify your Foundry installation:

```sh
forge --version
```

### Installation

1. Clone the repository:

```sh
git clone https://github.com/Shazam-19/foundry-smart-contract-lottery.git
cd foundry-smart-contract-lottery
```

2. Install dependencies:

```sh
forge install
```

3. Build the project:

```sh
forge build
```

### Environment Variables

Create a `.env` file in the project root:

```env
SEPOLIA_RPC_URL="your_sepolia_rpc_url"
ETH_MAINNET_RPC_URL="your_alchemy_rpc_url"
ALCHEMY_API_KEY="your_alchemy_api_key"
ETHERSCAN_API_KEY="your_etherscan_api_key"
PRIVATE_KEY="your_wallet_private_key"
DEPLOYED_CONTRACT_ADDRESS="deployed_contract_address_on_sepolia"
```

> ⚠️ Never commit your `.env` file or expose your private key. Add `.env` to your `.gitignore`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Usage

### Deploy Locally (Anvil)

Start a local Anvil node in one terminal:

```sh
anvil
```

In another terminal, deploy the contract. VRF mocks and a subscription are created automatically:

```sh
forge script script/DeployRaffle.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

### Deploy to Sepolia

Before deploying to Sepolia, make sure you have:

1. A funded Chainlink VRF subscription at [vrf.chain.link](https://vrf.chain.link).
2. Your `subscriptionId` updated in `HelperConfig.s.sol`.
3. Your `.env` file configured.

Then deploy using the Makefile command:

```sh
make deploy-sepolia
```

### VRF Subscription Management

These scripts can be run independently if needed:

**Create a subscription:**
```sh
forge script script/Interactions.s.sol:CreateSubscription \
  --rpc-url $SEPOLIA_RPC_URL --broadcast
```

**Fund a subscription:**
```sh
forge script script/Interactions.s.sol:FundSubscription \
  --rpc-url $SEPOLIA_RPC_URL --broadcast
```

**Add a consumer:**
```sh
forge script script/Interactions.s.sol:AddConsumer \
  --rpc-url $SEPOLIA_RPC_URL --broadcast
```

> 💡 Use [openchain.xyz](https://openchain.xyz) to decode function selectors and event signatures when debugging transactions with `cast`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Running Tests

Run all tests:

```sh
forge test
```

Run a specific test by name:

```sh
forge test --mt testFulfillrandomWordsPicksWinnerThenResetAndSendsMoney -vvvv
```

Run tests with debug output:

```sh
forge test --mt <TEST_FUNCTION_NAME> --debug
```

Run tests against a forked network:

```sh
forge test --fork-url $SEPOLIA_RPC_URL
```

Generate a coverage report:

```sh
forge coverage --report debug > coverage.txt
```

### Test Types Covered

| Type | Description |
|------|-------------|
| **Unit** | Tests individual functions in isolation |
| **Integration** | Verifies interactions between contracts |
| **Fuzz (Stateless)** | Runs functions with randomized inputs to find edge cases |
| **Fork** | Tests against a live forked network state |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contract Overview

### `Raffle.sol`

The core contract. Key functions:

| Function | Visibility | Description |
|----------|-----------|-------------|
| `enterRaffle()` | `external payable` | Enter the raffle by sending at least the entrance fee |
| `checkUpkeep()` | `public view` | Called by Chainlink Automation to check if a draw should be triggered |
| `performUpkeep()` | `external` | Triggers the draw and requests randomness from Chainlink VRF |
| `fulfillRandomWords()` | `internal override` | VRF callback — selects the winner and stores their prize |
| `claimPrize()` | `external` | Allows the winner to withdraw their prize |
| `getEntranceFee()` | `external view` | Returns the entrance fee in wei |
| `getRaffleState()` | `external view` | Returns the current raffle state (`OPEN` or `CALCULATING`) |
| `getRecentWinner()` | `external view` | Returns the most recently selected winner |
| `getLastTimeStamp()` | `external view` | Returns the timestamp of the last completed round |
| `getPlayer(index)` | `external view` | Returns the player address at the given index |

### `HelperConfig.s.sol`

Manages deployment configuration across networks. Automatically resolves the correct VRF coordinator, gas lane, entrance fee, and other parameters based on the active chain ID.

### `Interactions.s.sol`

Contains three standalone scripts: `CreateSubscription`, `FundSubscription`, and `AddConsumer` — each handling a step of the Chainlink VRF subscription lifecycle.

### `DeployRaffle.s.sol`

Orchestrates the full deployment: resolves config, creates and funds a VRF subscription if needed, deploys `Raffle`, and registers it as a VRF consumer — all in one script.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Security Considerations

This contract was designed with the following Chainlink VRF security guidelines in mind:

- ✅ **`fulfillRandomWords` never reverts** — uses early returns and the pull pattern instead of reverting, preventing funds from being permanently locked.
- ✅ **`requestId` validation** — `s_lastRequestId` is stored in `performUpkeep()` and validated in `fulfillRandomWords()` to reject unexpected or duplicate callbacks.
- ✅ **No new entries during randomness request** — the `CALCULATING` state blocks `enterRaffle()` while a VRF request is in flight.
- ✅ **Pull (withdrawal) pattern** — prizes are stored in `s_pendingWithdrawals` and claimed by winners via `claimPrize()`, following CEI to prevent reentrancy.
- ✅ **Minimum block confirmations** — `REQUEST_CONFIRMATIONS = 3` meets Chainlink's recommended minimum to make rewrite attacks unprofitable.
- ✅ **Inherits `VRFConsumerBaseV2Plus`** — ensures `fulfillRandomWords` can only be called by the legitimate VRF coordinator.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Supported Networks

| Network | Chain ID | VRF | Notes |
|---------|----------|-----|-------|
| Sepolia Testnet | `11155111` | Real Chainlink VRF | Requires a funded subscription |
| Anvil (Local) | `31337` | `VRFCoordinatorV2_5Mock` | Mocks deployed automatically |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Roadmap

- [x] Core raffle contract with entrance fee and player tracking
- [x] Chainlink VRF v2.5 integration for provably fair randomness
- [x] Chainlink Automation integration via `checkUpkeep` / `performUpkeep`
- [x] Pull (withdrawal) pattern for safe prize distribution
- [x] `requestId` validation to reject unexpected VRF callbacks
- [x] Multi-network support (Sepolia + Anvil with mocks)
- [x] Centralised `HelperConfig` for network-aware deployments
- [x] Comprehensive test suite (unit, fuzz, fork)
- [ ] Front-end interface for entering the raffle and tracking results
- [ ] Support for additional testnets (e.g. Mumbai, Fuji)
- [ ] ERC-20 token entrance fee support
- [ ] Multiple concurrent raffle pools with different entry tiers
- [ ] On-chain history of past winners

See the [open issues](https://github.com/your_username/raffle/issues) for a full list of proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contributing

Contributions are what make the open source community such an amazing place to learn and grow. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would improve this project, please fork the repo and open a pull request. You can also open an issue with the tag `enhancement`.

1. Fork the repository
2. Create your feature branch:
```sh
git checkout -b feature/YourFeature
```
3. Commit your changes following the [Conventional Commits](https://www.conventionalcommits.org/) format:
```sh
git commit -m "feat: add your feature description"
```
4. Push to your branch:
```sh
git push origin feature/YourFeature
```
5. Open a Pull Request

### Commit Prefix Guide

| Prefix | Use for |
|--------|---------|
| `feat` | New feature or function |
| `fix` | Bug fix |
| `docs` | Documentation or comments only |
| `refactor` | Code restructuring without behaviour change |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks (config, dependencies) |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Author

**Abdelrahman Sayed**

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Acknowledgments

- [Foundry Book](https://book.getfoundry.sh/)
- [Patrick Collins — Foundry Course](https://github.com/Cyfrin/foundry-full-course-cu)
- [Chainlink VRF v2.5 Docs](https://docs.chain.link/vrf/v2-5/overview/subscription)
- [vrf.chain.link — Subscription Manager](https://vrf.chain.link)
- [Chainlink VRF Security Considerations](https://docs.chain.link/vrf/v2-5/security)
- [OpenChain — Selector & Event Lookup](https://openchain.xyz)

<p align="right">(<a href="#readme-top">back to top</a>)</p>