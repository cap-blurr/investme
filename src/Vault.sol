// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "./IVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title BaseAutoLPVault
/// @notice ERC-4626 vault for automated ETH/USDC liquidity allocation on Base
/// @dev Upgradeable (UUPS), multi-asset, multi-strategy, with share classes and detailed events
contract Vault is Initializable, ERC4626, Pausable, ReentrancyGuard, Ownable, UUPSUpgradeable, IVault {
    // =====================
    // ====== EVENTS =======
    // =====================
    /// @notice Emitted when a user deposits
    /// @param user The depositor
    /// @param asset The asset deposited (ETH/USDC)
    /// @param amount The amount deposited
    /// @param shares The shares minted
    /// @param strategy The strategy class selected
    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 shares, ShareClass strategy);
    /// @notice Emitted when a user withdraws
    /// @param user The withdrawer
    /// @param asset The asset withdrawn (ETH/USDC)
    /// @param amount The amount withdrawn
    /// @param shares The shares burned
    /// @param strategy The strategy class
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 shares, ShareClass strategy);
    /// @notice Emitted when a user switches strategy
    /// @param user The user
    /// @param fromStrategy The previous strategy
    /// @param toStrategy The new strategy
    event StrategySwitched(address indexed user, ShareClass fromStrategy, ShareClass toStrategy);
    /// @notice Emitted when funds are invested via the Allocator
    /// @param amount The amount invested
    event Invested(uint256 amount);
    // ... other events as needed

    // =====================
    // ====== ERRORS =======
    // =====================
    error VaultDepositBelowMinimum(uint256 provided, uint256 minimum);
    error VaultInvalidAsset(address asset);
    error VaultStrategyCooldown(address user, uint256 nextAllowed);
    error VaultUnauthorized(address caller);
    // ... other custom errors as needed

    // =====================
    // ====== CONSTANTS ====
    // =====================
    /// @notice WETH address on Base mainnet
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    /// @notice USDC address on Base mainnet (TODO: confirm address)
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 public constant STRATEGY_SWITCH_COOLDOWN = 1 days;
    uint8 public constant NUM_SHARE_CLASSES = 3;

    // =====================
    // ====== ENUMS ========
    // =====================
    /// @notice Share class/strategy type
    enum ShareClass { Conservative, Balanced, Aggressive }

    // =====================
    // ====== STORAGE ======
    // =====================
    /// @notice Mapping of user to share class
    mapping(address => ShareClass) public userStrategy;
    /// @notice Mapping of user to last strategy switch timestamp
    mapping(address => uint256) public lastStrategySwitch;
    /// @notice Mapping of user to deposit timestamp (for fee calculation)
    mapping(address => uint256) public userDepositTimestamp;
    /// @notice Total assets under management per strategy
    mapping(ShareClass => uint256) public totalAUMPerStrategy;
    /// @notice Strategy allocation percentages (0-100)
    mapping(ShareClass => uint256) public strategyAllocPercent;
    // TODO: Add Allocator and strategy references

    // =====================
    // ====== UUPS GAP =====
    // =====================
    uint256[50] private __gap;

    // =====================
    // ====== INIT =========
    // =====================
    /// @notice Initializer for upgradeable contract
    /// @param _usdc The USDC token address (for testnet flexibility)
    /// @param initialOwner The initial owner
    function initialize(address _usdc, address initialOwner) public initializer {
        __ERC20_init("Base Auto-LP Vault Share", "baLP");
        __ERC4626_init(ERC20(_usdc));
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        // Optionally, set up roles or initial state here
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =====================
    // ====== DEPOSIT ======
    // =====================
    /// @notice Deposit ETH (wraps to WETH and allocates)
    /// @param strategy The share class/strategy to allocate to
    /// @custom:security nonReentrant, whenNotPaused
    function depositETH(ShareClass strategy) external payable whenNotPaused nonReentrant returns (uint256 shares) {
        // TODO: Implement ETH deposit logic, wrap to WETH, allocate, update mappings, emit event
        revert("depositETH not implemented");
    }

    /// @notice Deposit USDC and allocate
    /// @param amount The amount of USDC
    /// @param strategy The share class/strategy to allocate to
    /// @custom:security nonReentrant, whenNotPaused
    function depositUSDC(uint256 amount, ShareClass strategy) external whenNotPaused nonReentrant returns (uint256 shares) {
        // TODO: Implement USDC deposit logic, allocate, update mappings, emit event
        revert("depositUSDC not implemented");
    }

    /// @notice Withdraw as ETH
    /// @param shares The shares to redeem
    /// @custom:security nonReentrant, whenNotPaused
    function withdrawToETH(uint256 shares) external whenNotPaused nonReentrant returns (uint256 assets) {
        // TODO: Implement withdraw to ETH logic
        revert("withdrawToETH not implemented");
    }

    /// @notice Withdraw as USDC
    /// @param shares The shares to redeem
    /// @custom:security nonReentrant, whenNotPaused
    function withdrawToUSDC(uint256 shares) external whenNotPaused nonReentrant returns (uint256 assets) {
        // TODO: Implement withdraw to USDC logic
        revert("withdrawToUSDC not implemented");
    }

    /// @notice Switch user's strategy (with cooldown)
    /// @param newStrategy The new share class/strategy
    /// @custom:security nonReentrant, whenNotPaused
    function switchStrategy(ShareClass newStrategy) external whenNotPaused nonReentrant {
        // TODO: Implement strategy switching with cooldown, update mappings, emit event
        revert("switchStrategy not implemented");
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        // For now, only USDC deposits via base ERC4626
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
    // TODO: Add custom error handling and events
    // TODO: Add performance fee logic
    // TODO: Add NatSpec to all functions
    // TODO: Add access control if needed
} 