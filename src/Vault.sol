// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ===== Vault.sol =====

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IVault} from "./IVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title OptimizedVault
/// @notice Ultra gas-optimized ERC-4626 vault with emergency withdrawal support
contract OptimizedVault is 
    Initializable, 
    ERC4626Upgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable, 
    IVault 
{
    using SafeERC20 for IERC20;
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event EmergencyWithdrawal(address indexed user, uint256 shares, uint256 assets);
    event AIControllerSet(address indexed controller);
    event FeeCollectorSet(address indexed feeCollector);

    // =====================
    // ====== ERRORS =======
    // =====================
    error VaultDepositBelowMinimum(uint256 provided, uint256 minimum);
    error VaultInvalidAsset(address asset);
    error VaultUnauthorized(address caller);
    error VaultInsufficientShares(uint256 requested, uint256 balance);
    error VaultTransferFailed();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public aiController;
    address public feeCollector;
    uint256 public constant MIN_DEPOSIT = 1e6; // 1 USDC minimum
    
    uint256[48] private __gap; // Reserve storage slots for upgrades

    // =====================
    // ====== INIT =========
    // =====================
    function initialize(address _asset, address initialOwner) public initializer {
        if (_asset == address(0)) revert VaultInvalidAsset(_asset);
        
        __ERC20_init("AutoYield Vault Share", "ayVLT");
        __ERC4626_init(IERC20(_asset));
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =====================
    // ====== ADMIN ========
    // =====================
    
    /// @notice Set the AI controller address
    function setAIController(address _controller) external onlyOwner {
        aiController = _controller;
        emit AIControllerSet(_controller);
    }
    
    /// @notice Set the fee collector address
    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorSet(_feeCollector);
    }

    // =====================
    // ====== OVERRIDES ====
    // =====================
    
    /// @notice Override deposit to enforce minimum and pause
    function deposit(uint256 assets, address receiver) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        if (assets < MIN_DEPOSIT) revert VaultDepositBelowMinimum(assets, MIN_DEPOSIT);
        return super.deposit(assets, receiver);
    }
    
    /// @notice Override withdraw to respect pause (except emergency)
    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        return super.withdraw(assets, receiver, owner);
    }
    
    /// @notice Override redeem to respect pause (except emergency)
    function redeem(uint256 shares, address receiver, address owner) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256) 
    {
        return super.redeem(shares, receiver, owner);
    }

    // =====================
    // ====== EMERGENCY ====
    // =====================
    
    /// @notice Emergency withdrawal bypasses pause state
    /// @dev Optimized for gas efficiency while maintaining security
    function emergencyWithdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        // Emergency withdrawals work even when paused
        address sender = msg.sender;
        
        // Check balance efficiently
        uint256 balance = balanceOf(sender);
        if (balance < shares) revert VaultInsufficientShares(shares, balance);
        
        // Calculate assets before burning to prevent reentrancy
        assets = previewRedeem(shares);
        
        // Burn shares first (CEI pattern)
        _burn(sender, shares);
        
        // Transfer assets using SafeERC20
        IERC20(asset()).safeTransfer(sender, assets);
        
        emit EmergencyWithdrawal(sender, shares, assets);
    }

    // =====================
    // ====== ADMIN OPS ====
    // =====================
    
    /// @notice Pause vault operations (except emergency withdrawals)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause vault operations
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /// @notice Check if caller is authorized (vault owner, AI controller, or fee collector)
    function isAuthorized(address caller) external view returns (bool) {
        return caller == owner() || caller == aiController || caller == feeCollector;
    }
}