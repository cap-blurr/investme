// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "./IVault.sol";

/// @title BaseAutoLPVault
/// @notice ERC-4626 vault for automated ETH/USDC liquidity allocation on Base
contract Vault is ERC4626, Pausable, ReentrancyGuard, Ownable, IVault {
    /// @notice Emitted when funds are invested via the Allocator
    /// @param amount The amount invested
    event Invested(uint256 amount);

    /// @notice WETH address on Base mainnet
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    /// @notice USDC address on Base mainnet (TODO: confirm address)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // TODO: Allocator and strategy references

    /// @notice Constructor sets up the ERC-4626 vault with USDC as the asset
    /// @param _usdc The USDC token address (for testnet flexibility)
    constructor(address _usdc, address initialOwner)
        ERC20("Base Auto-LP Vault Share", "baLP")
        ERC4626(ERC20(_usdc))
        Ownable(initialOwner)
    {
        // Optionally, set up roles or initial state here
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        // TODO: Accept ETH (wrap to WETH) or USDC
        // For now, only USDC deposits
        shares = super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        // TODO: Sum USDC + WETH (converted to USDC) + strategy balances
        return super.totalAssets();
    }

    /// @notice Pause the vault (only owner)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the vault (only owner)
    function unpause() external onlyOwner {
        _unpause();
    }

    // TODO: Add invest/rebalance logic with Allocator
    // TODO: Add upgradeability (UUPS)
    // TODO: Add AccessControl if needed
    // TODO: Add custom error handling and events
    // TODO: Add __gap for upgradeable storage
} 