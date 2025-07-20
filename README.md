# 🛠️ Base Auto-LP Vault

**One deposit → automated ETH / USDC liquidity farming on Base (Uniswap V3, Aerodrome, Aave idle buffer).**

| Metric (auto-updated Mondays 08:00 UTC) | This Week | Lifetime |
| --------------------------------------- | --------- | -------- |
| 🧑‍💻 Verified Base contracts             | — | — |
| ⛽ Txns through vault                    | — | — |
| 💰 TVL (USDC-eq)                         | — | — |
| 📈 GitHub contributions                  | — | — |

---

## Why?

Providing LP across venues is powerful but fiddly (ratio maths, fee harvests, gas).  
**Base Auto-LP** wraps everything in an ERC-4626 vault so builders earn yield while focusing on, well… building.

---

## Live Contracts (Base Mainnet – 8453)

| Module                          | Address   | Source Verified |
|---------------------------------|-----------|-----------------|
| `BaseAutoLPVault`               | `0x…`     | ✅ |
| `StrategyUniswapV3_ETH_USDC`    | `0x…`     | ✅ |

*(Add new addresses after each deploy.)*

---

## Quick Start

```bash
# Clone & install
git clone https://github.com/<you>/base-auto-lp.git
cd base-auto-lp
foundryup             # latest Foundry
forge install         # pulls lib deps listed in foundry.toml

# Run tests & static checks
forge test -vv
slither .

# Dry-run deploy to Base Sepolia
forge script script/Deploy.s.sol \
    --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify --dry-run
