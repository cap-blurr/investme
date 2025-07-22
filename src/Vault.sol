// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IVault} from "./IVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title AutoYieldVault
/// @notice Minimal ERC-4626 vault for user deposits and withdrawals
/// @dev Upgradeable (UUPS), no strategy logic, only accounting and emergency withdrawal
contract Vault is Initializable, ERC4626Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable, IVault {
    // =====================
    // ====== EVENTS =======
    // =====================
    /// @notice Emitted when a user performs an emergency withdrawal
    event EmergencyWithdrawal(address indexed user, uint256 shares, uint256 assets);

    // =====================
    // ====== ERRORS =======
    // =====================
    error VaultDepositBelowMinimum(uint256 provided, uint256 minimum);
    error VaultInvalidAsset(address asset);
    error VaultUnauthorized(address caller);

    // =====================
    // ====== STORAGE ======
    // =====================
    // Add any additional storage needed for multi-token support here in the future
    uint256[50] private __gap;

    // =====================
    // ====== INIT =========
    // =====================
    /// @notice Initializer for upgradeable contract
    /// @param _asset The ERC20 token address (e.g., USDC)
    /// @param initialOwner The initial owner
    function initialize(address _asset, address initialOwner) public initializer {
        __ERC20_init("AutoYield Vault Share", "ayVLT");
        __ERC4626_init(ERC20Upgradeable(_asset));
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =====================
    // ====== PAUSE ========
    // =====================
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =====================
    // ====== EMERGENCY ====
    // =====================
    /// @notice Emergency withdrawal for users (bypasses AI, always available)
    /// @param shares The shares to redeem
    function emergencyWithdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 assets) {
        // Emergency withdrawal: redeem shares for underlying asset
        assets = previewRedeem(shares);
        _burn(msg.sender, shares);
        ERC20Upgradeable(asset()).transfer(msg.sender, assets);
        emit EmergencyWithdrawal(msg.sender, shares, assets);
    }

    // =====================
    // ====== ERC-4626 =====
    // =====================
    // All standard ERC-4626 functions are inherited
    // No strategy logic, no custom deposit/withdraw, no fee logic
} 