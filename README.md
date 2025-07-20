# 🛠️ Base Auto-LP Vault

**Automated ETH/USDC liquidity allocation and yield farming on Base (Uniswap V3, Aerodrome, Aave idle buffer) via a single ERC-4626 vault.**

---

## Overview

Base Auto-LP Vault is a modular, upgradeable ERC-4626 vault that accepts ETH (wrapped to WETH) and USDC on Base mainnet. It automatically allocates liquidity across:

- **Uniswap V3**: Concentrated liquidity position in the WETH/USDC pool.
- **Aerodrome Slipstream**: LP for the same pair, staked in its gauge to earn $AERO rewards.
- *(Planned)* **Aave v3**: Idle reserve for unallocated funds.

Shares represent proportional ownership of all underlying assets and accrued fees/incentives. Admin (Safe multisig) can change weights, pause, and upgrade the vault.

---

## Architecture

- **Vault (ERC-4626)**: Accepts deposits/withdrawals, manages shares, and interacts with the Allocator.
- **Allocator**: Routes funds to strategies based on target weights.
- **Strategies**: Modular contracts for Uniswap V3, Aerodrome, and (future) Aave.
- **Upgradeable**: UUPS proxy pattern via OpenZeppelin.
- **Security**: ReentrancyGuard, Pausable, Ownable/AccessControl.

---

## Features

- Single deposit for multi-venue LP farming
- Automated rebalancing and fee harvesting
- Modular, extensible strategy architecture
- Upgradeable and pausable for safety
- Thoroughly tested with Foundry (unit, fuzz, invariant)

---

## Quick Start

```bash
# Clone & install
git clone https://github.com/<your-username>/base-auto-lp.git
cd base-auto-lp
foundryup             # latest Foundry
forge install         # pulls lib deps listed in foundry.toml

# Run tests & static checks
forge test -vvv
slither .

# Dry-run deploy to Base Sepolia
forge script script/Deploy.s.sol \
    --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify --dry-run
```

---

## Live Contracts (Base Mainnet – 8453)

| Module                          | Address   | Source Verified |
|---------------------------------|-----------|-----------------|
| `BaseAutoLPVault`               | `0x…`     | ✅ |
| `StrategyUniswapV3_ETH_USDC`    | `0x…`     | ✅ |
| `StrategyAerodrome_ETH_USDC`    | `0x…`     | ✅ |

*(Add new addresses after each deploy.)*

---

## Contributing


- All code must pass `forge test` and `forge fmt --check`.
- Open issues for significant TODOs and tag with `good first issue` where appropriate.
- PRs should be atomic and well-documented.

---

## License

MIT
