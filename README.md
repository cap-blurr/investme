# 🚀 AutoYield AI - Minimal DeFi Yield Platform

> **Secure, modular, and gas-efficient DeFi yield infrastructure with AI-driven off-chain management**

AutoYield AI is a next-generation DeFi platform that enables users to deposit crypto and have their funds managed by an autonomous AI agent. The smart contracts are designed as minimal, secure primitives for custody, accounting, and DEX interaction, while all strategy and trading logic is handled off-chain by the AI.

## 🎯 What Makes AutoYield Different?

- **Minimal On-Chain Logic**: Contracts are "dumb pipes" for fund movement and DEX access—no on-chain strategies or AI.
- **AI-Driven Management**: All trading, rebalancing, and yield optimization is performed by an off-chain AI agent.
- **Security First**: Vault contract holds all user funds; AI wallet can only perform whitelisted, limited operations.
- **Emergency Controls**: Multi-sig and time-locked emergency module for rapid response and user protection.

## 🏗️ Core Smart Contracts

### 1. Vault (ERC-4626)
- Accepts user deposits and processes withdrawals
- Tracks user share balances and total assets
- ERC-4626 compliant for composability
- Supports emergency withdrawal at all times

### 2. AIWalletController
- Manages permissions for the AI-controlled wallet
- Only allows whitelisted DEX operations (swap, add/remove liquidity, collect fees, rebalance)
- Enforces slippage, position size, and daily operation limits
- Cannot withdraw to external addresses

### 3. DEX Adapters
- Protocol-specific adapters (e.g., UniswapV3Adapter)
- Standardized interface for swaps, liquidity, and fee collection
- No strategy logic—only protocol interaction

### 4. FeeCollector
- Collects and distributes protocol fees (1% management, 20% performance)
- Tracks high-water mark per user
- Allows batch collection for gas efficiency

### 5. EmergencyModule
- Allows pausing of AI operations and enabling emergency withdrawals
- Multi-sig and time delay for critical actions
- Never blocks user withdrawals

## 🔄 System Flow

1. **User deposits crypto (e.g., USDC) into the Vault**
2. **Vault mints shares to the user**
3. **AI agent (off-chain) analyzes market and determines optimal DEX actions**
4. **AI calls AIWalletController to execute swaps, add/remove liquidity, or collect fees via DEX Adapters**
5. **FeeCollector accrues and distributes protocol fees**
6. **EmergencyModule can pause AI or enable emergency withdrawals if needed**
7. **User can withdraw at any time, even in emergencies**

## 🛡️ Security Model

- **Vault holds all user funds**; AI wallet cannot withdraw externally
- **Whitelisted DEXes and tokens only**
- **Slippage and position size limits enforced on all AI operations**
- **EmergencyModule can pause AI and enable direct withdrawals**
- **Multi-sig required for critical emergency actions**

## 💰 Fee Structure

- **Management Fee**: 1% per annum (pro-rated, accrued daily)
- **Performance Fee**: 20% of profits (high-water mark)
- **No deposit or withdrawal fees**

## 🔧 Technical Architecture

- **Vault.sol**: ERC-4626-compliant vault for deposits, withdrawals, and share accounting
- **AIWalletController.sol**: Permissioned controller for AI wallet, enforcing all limits and whitelists
- **IDEXAdapter.sol & UniswapV3Adapter.sol**: Standardized DEX adapter interface and Uniswap V3 implementation stub
- **FeeCollector.sol**: Management and performance fee logic, high-water mark tracking
- **EmergencyModule.sol**: Emergency pause, enable emergency mode, force exit, and drain-to-vault functions

## 🧪 Testing & Deployment

- All contracts are designed for modular, isolated testing
- Vault and adapters can be tested independently
- Emergency procedures and fee logic are unit tested

## 🚀 Getting Started (Developers)

```bash
# Clone the repo
# (Assume you are in the lp_balancer directory)
forge install

# Run tests
forge test

# Deploy locally (example)
forge script script/Deploy.s.sol --fork-url <RPC_URL> --broadcast
```

---

**Note:**
- All strategy, trading, and yield optimization logic is handled off-chain by the AI agent.
- Smart contracts are intentionally minimal for security, gas efficiency, and upgradability.
- For more details, see the contract source files in `src/`.
## Deployment Outputs
Deployment scripts store deployed contract addresses in `deployments/<chainId>.json`. Ensure this directory exists so scripts can write the files.
