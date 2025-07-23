// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title OptimizedAIWalletController
/// @notice Ultra gas-optimized AI wallet controller with safety checks
contract OptimizedAIWalletController {
    using SafeERC20 for IERC20;
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event SwapExecuted(address indexed dex, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut);
    event LiquidityAdded(address indexed dex, address token0, address token1, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper);
    event LiquidityRemoved(address indexed dex, uint256 positionId);
    event FeesCollected(address indexed dex, uint256 positionId);
    event DexWhitelisted(address indexed dex, bool status);
    event TokenApproved(address indexed token, bool status);
    event LimitsUpdated(uint96 maxSlippageBps, uint96 maxPositionSize, uint64 dailyOperationLimit);
    
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
    error InvalidInput();

    // =====================
    // ====== STORAGE ======
    // =====================
    
    // Pack related data into single storage slots
    struct PackedLimits {
        uint96 maxSlippageBps;        // 96 bits (max ~79 billion)
        uint96 maxPositionSize;       // 96 bits  
        uint64 dailyOperationLimit;   // 64 bits (max ~18 quintillion)
        // Total: 256 bits (1 slot)
    }
    
    struct PackedState {
        uint96 operationsToday;       // 96 bits
        uint96 lastOperationDay;      // 96 bits (days since epoch)
        uint64 reserved;              // 64 bits for future use
        // Total: 256 bits (1 slot)
    }
    
    address public immutable vault;
    address public aiWallet;
    address public owner;
    
    PackedLimits public limits;
    PackedState public state;
    
    // Optimize mappings
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
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Transfer contract ownership
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidInput();
        owner = newOwner;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(address _vault, address _aiWallet) {
        if (_vault == address(0) || _aiWallet == address(0)) revert InvalidInput();
        
        vault = _vault;
        aiWallet = _aiWallet;
        owner = msg.sender;
        
        // Initialize packed structs with reasonable defaults
        limits = PackedLimits({
            maxSlippageBps: 300,         // 3% default
            maxPositionSize: 10_000_000e6, // 10M USDC default
            dailyOperationLimit: 100
        });
        
        state = PackedState({
            operationsToday: 0,
            lastOperationDay: uint96(block.timestamp / 1 days),
            reserved: 0
        });
    }

    // =====================
    // ====== ADMIN ========
    // =====================
    
    /// @notice Update AI wallet address
    function setAIWallet(address _aiWallet) external onlyOwner {
        if (_aiWallet == address(0)) revert InvalidInput();
        aiWallet = _aiWallet;
    }
    
    /// @notice Batch whitelist operations (saves gas vs individual calls)
    function batchWhitelistDex(address[] calldata dexes, bool[] calldata statuses) external onlyOwner {
        uint256 length = dexes.length;
        if (length != statuses.length) revert InvalidInput();
        
        for (uint256 i; i < length;) {
            whitelistedDex[dexes[i]] = statuses[i];
            emit DexWhitelisted(dexes[i], statuses[i]);
            unchecked { ++i; }
        }
    }
    
    /// @notice Batch approve tokens
    function batchApproveTokens(address[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        uint256 length = tokens.length;
        if (length != statuses.length) revert InvalidInput();
        
        for (uint256 i; i < length;) {
            approvedToken[tokens[i]] = statuses[i];
            emit TokenApproved(tokens[i], statuses[i]);
            unchecked { ++i; }
        }
    }
    
    /// @notice Update all limits in single transaction
    function setLimits(uint96 _maxSlippageBps, uint96 _maxPositionSize, uint64 _dailyOperationLimit) external onlyOwner {
        limits = PackedLimits({
            maxSlippageBps: _maxSlippageBps,
            maxPositionSize: _maxPositionSize,
            dailyOperationLimit: _dailyOperationLimit
        });
        emit LimitsUpdated(_maxSlippageBps, _maxPositionSize, _dailyOperationLimit);
    }

    // =====================
    // ====== AI OPS =======
    // =====================
    
    /// @notice Validate and update daily operation count
    function _validateAndUpdateDailyLimit() private {
        PackedState memory _state = state;
        uint96 today = uint96(block.timestamp / 1 days);
        
        if (today != _state.lastOperationDay) {
            // New day, reset counter
            state.operationsToday = 1;
            state.lastOperationDay = today;
        } else {
            // Same day, check limit
            if (_state.operationsToday >= limits.dailyOperationLimit) revert DailyLimitExceeded();
            state.operationsToday = _state.operationsToday + 1;
        }
    }
    
    /// @notice Execute a token swap
    function executeSwap(
        address dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut
    ) external onlyAIWallet returns (bytes memory result) {
        // Validate inputs
        if (!whitelistedDex[dex]) revert DexNotWhitelisted();
        if (!approvedToken[tokenIn] || !approvedToken[tokenOut]) revert TokenNotApproved();
        if (amountIn > limits.maxPositionSize) revert PositionSizeTooLarge();
        
        // Calculate and validate slippage
        // Note: This is simplified - in production you'd get expected output from oracle
        uint256 slippageBps = 10000; // Placeholder - should calculate actual slippage
        if (slippageBps > limits.maxSlippageBps) revert SlippageTooHigh();
        
        _validateAndUpdateDailyLimit();
        
        // Approve tokens if needed
        IERC20(tokenIn).safeIncreaseAllowance(dex, amountIn);
        
        // Execute swap on DEX
        // Note: In production, this would encode the proper swap call for each DEX
        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "swap(address,address,uint256,uint256)",
                tokenIn,
                tokenOut,
                amountIn,
                minOut
            )
        );
        require(success, "Swap failed");
        
        emit SwapExecuted(dex, tokenIn, tokenOut, amountIn, minOut);
        return data;
    }
    
    /// @notice Add liquidity to a position
    function addLiquidity(
        address dex,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external onlyAIWallet returns (uint256 positionId) {
        // Validate inputs
        if (!whitelistedDex[dex]) revert DexNotWhitelisted();
        if (!approvedToken[token0] || !approvedToken[token1]) revert TokenNotApproved();
        
        uint256 totalAmount = amount0 + amount1;
        if (totalAmount > limits.maxPositionSize) revert PositionSizeTooLarge();
        
        _validateAndUpdateDailyLimit();
        
        // Approve tokens
        IERC20(token0).safeIncreaseAllowance(dex, amount0);
        IERC20(token1).safeIncreaseAllowance(dex, amount1);
        
        // Add liquidity on DEX
        // Note: In production, this would encode the proper call for each DEX
        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,int24,int24)",
                token0,
                token1,
                amount0,
                amount1,
                tickLower,
                tickUpper
            )
        );
        require(success, "Add liquidity failed");
        
        // Decode position ID from return data
        positionId = abi.decode(data, (uint256));
        
        emit LiquidityAdded(dex, token0, token1, amount0, amount1, tickLower, tickUpper);
    }
    
    /// @notice Remove liquidity from a position
    function removeLiquidity(address dex, uint256 positionId, uint256 liquidity) 
        external 
        onlyAIWallet 
        returns (uint256 amount0, uint256 amount1) 
    {
        if (!whitelistedDex[dex]) revert DexNotWhitelisted();
        
        _validateAndUpdateDailyLimit();
        
        // Remove liquidity from DEX
        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature(
                "removeLiquidity(uint256,uint256)",
                positionId,
                liquidity
            )
        );
        require(success, "Remove liquidity failed");
        
        (amount0, amount1) = abi.decode(data, (uint256, uint256));
        
        emit LiquidityRemoved(dex, positionId);
    }
    
    /// @notice Collect fees from a position
    function collectFees(address dex, uint256 positionId) 
        external 
        onlyAIWallet 
        returns (uint256 amount0, uint256 amount1) 
    {
        if (!whitelistedDex[dex]) revert DexNotWhitelisted();
        
        _validateAndUpdateDailyLimit();
        
        // Collect fees from DEX
        (bool success, bytes memory data) = dex.call(
            abi.encodeWithSignature("collectFees(uint256)", positionId)
        );
        require(success, "Collect fees failed");
        
        (amount0, amount1) = abi.decode(data, (uint256, uint256));
        
        emit FeesCollected(dex, positionId);
    }
}