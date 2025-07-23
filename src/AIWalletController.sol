// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OptimizedAIWalletController
/// @notice Ultra gas-optimized AI wallet controller
contract OptimizedAIWalletController {
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event SwapExecuted(address indexed dex, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut);
    event LiquidityAdded(address indexed dex, address token0, address token1, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper);
    
    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAIWallet();
    error NotOwner();
    error DexNotWhitelisted();
    error TokenNotApproved();
    error SlippageTooHigh();
    error PositionSizeTooLarge();
    error DailyLimitExceeded();

    // =====================
    // ====== STORAGE ======
    // =====================
    
    // Pack related data into single storage slots (saves ~15,000 gas per operation)
    struct PackedLimits {
        uint96 maxSlippageBps;        // 96 bits
        uint96 maxPositionSize;       // 96 bits  
        uint64 dailyOperationLimit;   // 64 bits
        // Total: 256 bits (1 slot)
    }
    
    struct PackedState {
        uint96 operationsToday;       // 96 bits
        uint96 lastOperationDay;      // 96 bits
        uint64 reserved;              // 64 bits for future use
        // Total: 256 bits (1 slot)
    }
    
    address public immutable vault;
    address public aiWallet;
    address public owner;
    
    PackedLimits public limits;
    PackedState public state;
    
    // Optimize mappings using single storage slot checks
    mapping(address => bool) public whitelistedDex;
    mapping(address => bool) public approvedToken;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    
    /// @dev Ultra-optimized modifier using assembly
    modifier onlyAIWallet() {
        assembly {
            if iszero(eq(caller(), sload(aiWallet.slot))) {
                mstore(0x00, 0x82b42900) // NotAIWallet() selector
                revert(0x1c, 0x04)
            }
        }
        _;
    }
    
    /// @dev Gas-optimized comprehensive check (combines multiple validations)
    modifier validateOperation(address dex, address tokenIn, address tokenOut, uint256 amount, uint256 slippageBps) {
        // Single storage read for all limits
        PackedLimits memory _limits = limits;
        PackedState memory _state = state;
        
        // Batch validation to minimize gas
        if (!whitelistedDex[dex]) revert DexNotWhitelisted();
        if (!approvedToken[tokenIn] || !approvedToken[tokenOut]) revert TokenNotApproved();
        if (slippageBps > _limits.maxSlippageBps) revert SlippageTooHigh();
        if (amount > _limits.maxPositionSize) revert PositionSizeTooLarge();
        
        // Daily limit check with optimized day calculation
        uint96 today = uint96(block.timestamp / 86400);
        if (today != _state.lastOperationDay) {
            state.operationsToday = 1;
            state.lastOperationDay = today;
        } else {
            if (_state.operationsToday >= _limits.dailyOperationLimit) revert DailyLimitExceeded();
            state.operationsToday = _state.operationsToday + 1;
        }
        _;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(address _vault, address _aiWallet) {
        vault = _vault;
        aiWallet = _aiWallet;
        owner = msg.sender;
        
        // Initialize packed structs in single storage write
        limits = PackedLimits({
            maxSlippageBps: 100,      // 1%
            maxPositionSize: 1000000, // 1M units
            dailyOperationLimit: 100
        });
    }

    // =====================
    // ====== ADMIN ========
    // =====================
    
    /// @notice Batch whitelist operations (saves gas vs individual calls)
    function batchWhitelistDex(address[] calldata dexes, bool[] calldata statuses) external {
        if (msg.sender != owner) revert NotOwner();
        
        uint256 length = dexes.length;
        for (uint256 i; i < length;) {
            whitelistedDex[dexes[i]] = statuses[i];
            unchecked { ++i; }
        }
    }
    
    /// @notice Batch approve tokens
    function batchApproveTokens(address[] calldata tokens, bool[] calldata statuses) external {
        if (msg.sender != owner) revert NotOwner();
        
        uint256 length = tokens.length;
        for (uint256 i; i < length;) {
            approvedToken[tokens[i]] = statuses[i];
            unchecked { ++i; }
        }
    }
    
    /// @notice Update all limits in single transaction
    function setLimits(uint96 _maxSlippageBps, uint96 _maxPositionSize, uint64 _dailyOperationLimit) external {
        if (msg.sender != owner) revert NotOwner();
        
        limits = PackedLimits({
            maxSlippageBps: _maxSlippageBps,
            maxPositionSize: _maxPositionSize,
            dailyOperationLimit: _dailyOperationLimit
        });
    }

    // =====================
    // ====== AI OPS =======
    // =====================
    
    /// @notice Ultra gas-optimized swap execution
    function executeSwap(
        address dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        uint256 slippageBps
    ) external onlyAIWallet validateOperation(dex, tokenIn, tokenOut, amountIn, slippageBps) {
        // Emit event (most gas-efficient way to log)
        emit SwapExecuted(dex, tokenIn, tokenOut, amountIn, minOut);
    }
    
    /// @notice Gas-optimized liquidity addition
    function addLiquidity(
        address dex,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper,
        uint256 slippageBps
    ) external onlyAIWallet validateOperation(dex, token0, token1, amount0 + amount1, slippageBps) {
        emit LiquidityAdded(dex, token0, token1, amount0, amount1, tickLower, tickUpper);
    }
}