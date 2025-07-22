// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AIWalletController
/// @notice Manages permissions and DEX interactions for the AI-controlled wallet
/// @dev Only allows whitelisted, parameter-limited operations; no custody of funds
contract AIWalletController {
    // =====================
    // ====== EVENTS =======
    // =====================
    event DexWhitelisted(address indexed dex);
    event DexRemoved(address indexed dex);
    event TokenWhitelisted(address indexed token);
    event TokenRemoved(address indexed token);
    event SwapExecuted(address indexed dex, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut);
    event LiquidityAdded(address indexed dex, address token0, address token1, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper);
    event LiquidityRemoved(address indexed dex, uint256 positionId, uint256 liquidity);
    event FeesCollected(address indexed dex, uint256 positionId, uint256 amount0, uint256 amount1);
    event PositionRebalanced(address indexed dex, uint256 positionId, int24 newTickLower, int24 newTickUpper);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAIWallet();
    error NotOwner();
    error DexNotWhitelisted(address dex);
    error TokenNotApproved(address token);
    error SlippageTooHigh(uint256 requested, uint256 maxAllowed);
    error PositionSizeTooLarge(uint256 requested, uint256 maxAllowed);
    error DailyLimitExceeded();
    error ExternalWithdrawalsNotAllowed();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public aiWallet;
    address public owner;

    mapping(address => bool) public whitelistedDex;
    mapping(address => bool) public approvedToken;

    uint256 public maxSlippageBps; // e.g., 100 = 1%
    uint256 public maxPositionSize; // in asset units
    uint256 public dailyOperationLimit;
    uint256 public operationsToday;
    uint256 public lastOperationDay;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAIWallet() {
        if (msg.sender != aiWallet) revert NotAIWallet();
        _;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    modifier checkDex(address dex) {
        if (!whitelistedDex[dex]) revert DexNotWhitelisted(dex);
        _;
    }
    modifier checkToken(address token) {
        if (!approvedToken[token]) revert TokenNotApproved(token);
        _;
    }
    modifier checkSlippage(uint256 slippageBps) {
        if (slippageBps > maxSlippageBps) revert SlippageTooHigh(slippageBps, maxSlippageBps);
        _;
    }
    modifier checkPositionSize(uint256 size) {
        if (size > maxPositionSize) revert PositionSizeTooLarge(size, maxPositionSize);
        _;
    }
    modifier checkDailyLimit() {
        uint256 today = block.timestamp / 1 days;
        if (today != lastOperationDay) {
            operationsToday = 0;
            lastOperationDay = today;
        }
        if (operationsToday >= dailyOperationLimit) revert DailyLimitExceeded();
        operationsToday++;
        _;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(address _vault, address _aiWallet) {
        vault = _vault;
        aiWallet = _aiWallet;
        owner = msg.sender;
        maxSlippageBps = 100; // 1%
        maxPositionSize = 1_000_000e6; // Example: 1M USDC
        dailyOperationLimit = 100;
    }

    // =====================
    // ====== OWNER ADMIN ==
    // =====================
    function setAIWallet(address _aiWallet) external onlyOwner {
        aiWallet = _aiWallet;
    }
    function whitelistDex(address dex) external onlyOwner {
        whitelistedDex[dex] = true;
        emit DexWhitelisted(dex);
    }
    function removeDex(address dex) external onlyOwner {
        whitelistedDex[dex] = false;
        emit DexRemoved(dex);
    }
    function approveToken(address token) external onlyOwner {
        approvedToken[token] = true;
        emit TokenWhitelisted(token);
    }
    function removeToken(address token) external onlyOwner {
        approvedToken[token] = false;
        emit TokenRemoved(token);
    }
    function setLimits(uint256 _maxSlippageBps, uint256 _maxPositionSize, uint256 _dailyOperationLimit) external onlyOwner {
        maxSlippageBps = _maxSlippageBps;
        maxPositionSize = _maxPositionSize;
        dailyOperationLimit = _dailyOperationLimit;
    }

    // =====================
    // ====== AI OPS =======
    // =====================
    // All functions below can only be called by the AI wallet
    // All must interact only with whitelisted DEX adapters and approved tokens

    struct SwapParams {
        address dex;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minOut;
        uint256 slippageBps;
    }
    function executeSwap(SwapParams calldata params)
        external
        onlyAIWallet
        checkDex(params.dex)
        checkToken(params.tokenIn)
        checkToken(params.tokenOut)
        checkSlippage(params.slippageBps)
        checkPositionSize(params.amountIn)
        checkDailyLimit
    {
        // Call the DEX adapter (assume it pulls from vault)
        // (bool success, ) = params.dex.call(abi.encodeWithSignature(
        //     "swap(address,address,uint256,uint256)", params.tokenIn, params.tokenOut, params.amountIn, params.minOut));
        // require(success, "Swap failed");
        emit SwapExecuted(params.dex, params.tokenIn, params.tokenOut, params.amountIn, params.minOut);
    }

    struct LiquidityParams {
        address dex;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint256 slippageBps;
    }
    function addLiquidity(LiquidityParams calldata params)
        external
        onlyAIWallet
        checkDex(params.dex)
        checkToken(params.token0)
        checkToken(params.token1)
        checkSlippage(params.slippageBps)
        checkPositionSize(params.amount0 + params.amount1)
        checkDailyLimit
    {
        emit LiquidityAdded(params.dex, params.token0, params.token1, params.amount0, params.amount1, params.tickLower, params.tickUpper);
    }

    function removeLiquidity(address dex, uint256 positionId, uint256 liquidity)
        external
        onlyAIWallet
        checkDex(dex)
        checkPositionSize(liquidity)
        checkDailyLimit
    {
        emit LiquidityRemoved(dex, positionId, liquidity);
    }

    function collectFees(address dex, uint256 positionId)
        external
        onlyAIWallet
        checkDex(dex)
        checkDailyLimit
    {
        emit FeesCollected(dex, positionId, 0, 0);
    }

    struct RebalanceParams {
        address dex;
        uint256 positionId;
        int24 newTickLower;
        int24 newTickUpper;
    }
    function rebalancePosition(RebalanceParams calldata params)
        external
        onlyAIWallet
        checkDex(params.dex)
        checkDailyLimit
    {
        emit PositionRebalanced(params.dex, params.positionId, params.newTickLower, params.newTickUpper);
    }

    // No external withdrawals allowed
    fallback() external payable {
        revert ExternalWithdrawalsNotAllowed();
    }
    receive() external payable {
        revert ExternalWithdrawalsNotAllowed();
    }
} 