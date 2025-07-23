// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IDEXAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Uniswap V3 interfaces
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    
    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    
    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );
    
    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );
    
    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
}

/// @title UniswapV3Adapter
/// @notice Adapter for interacting with Uniswap V3 liquidity positions
contract UniswapV3Adapter is IDEXAdapter {
    using SafeERC20 for IERC20;
    
    // =====================
    // ====== CONSTANTS ====
    // =====================
    ISwapRouter public constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public constant POSITION_MANAGER = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    
    uint24 public constant DEFAULT_FEE = 3000; // 0.3%
    uint256 private constant DEADLINE_BUFFER = 300; // 5 minutes
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(uint256 indexed tokenId, uint256 amount0, uint256 amount1, uint128 liquidity);
    event LiquidityRemoved(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    // =====================
    // ====== ERRORS =======
    // =====================
    error InvalidInput();
    error SwapFailed();
    error InsufficientOutput();
    error DeadlinePassed();

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier validDeadline() {
        if (block.timestamp > type(uint256).max - DEADLINE_BUFFER) revert DeadlinePassed();
        _;
    }

    // =====================
    // ====== FUNCTIONS ====
    // =====================

    /// @inheritdoc IDEXAdapter
    function swap(
        address token0, 
        address token1, 
        uint256 amount, 
        uint256 minOut
    ) external override validDeadline returns (uint256 outAmount) {
        if (token0 == address(0) || token1 == address(0)) revert InvalidInput();
        if (amount == 0) revert InvalidInput();
        
        // Transfer tokens from caller
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve router
        IERC20(token0).forceApprove(address(SWAP_ROUTER), amount);
        
        // Set up swap params
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: DEFAULT_FEE,
            recipient: msg.sender,
            deadline: block.timestamp + DEADLINE_BUFFER,
            amountIn: amount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
        
        // Execute swap
        try SWAP_ROUTER.exactInputSingle(params) returns (uint256 amountOut) {
            if (amountOut < minOut) revert InsufficientOutput();
            
            emit SwapExecuted(token0, token1, amount, amountOut);
            return amountOut;
        } catch {
            revert SwapFailed();
        }
    }

    /// @inheritdoc IDEXAdapter
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external override validDeadline returns (uint256 tokenId) {
        if (token0 == address(0) || token1 == address(0)) revert InvalidInput();
        if (amount0 == 0 || amount1 == 0) revert InvalidInput();
        if (tickLower >= tickUpper) revert InvalidInput();
        
        // Transfer tokens from caller
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        
        // Approve position manager
        IERC20(token0).forceApprove(address(POSITION_MANAGER), amount0);
        IERC20(token1).forceApprove(address(POSITION_MANAGER), amount1);
        
        // Order tokens (token0 must be < token1 in Uniswap V3)
        (address orderedToken0, address orderedToken1, uint256 orderedAmount0, uint256 orderedAmount1) = 
            token0 < token1 ? (token0, token1, amount0, amount1) : (token1, token0, amount1, amount0);
        
        // Set up mint params
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: orderedToken0,
            token1: orderedToken1,
            fee: DEFAULT_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: orderedAmount0,
            amount1Desired: orderedAmount1,
            amount0Min: (orderedAmount0 * 95) / 100, // 5% slippage
            amount1Min: (orderedAmount1 * 95) / 100, // 5% slippage
            recipient: msg.sender,
            deadline: block.timestamp + DEADLINE_BUFFER
        });
        
        // Mint position
        (uint256 _tokenId, uint128 liquidity, uint256 actualAmount0, uint256 actualAmount1) = 
            POSITION_MANAGER.mint(params);
        
        // Refund excess tokens
        if (orderedAmount0 > actualAmount0) {
            IERC20(orderedToken0).safeTransfer(msg.sender, orderedAmount0 - actualAmount0);
        }
        if (orderedAmount1 > actualAmount1) {
            IERC20(orderedToken1).safeTransfer(msg.sender, orderedAmount1 - actualAmount1);
        }
        
        emit LiquidityAdded(_tokenId, actualAmount0, actualAmount1, liquidity);
        return _tokenId;
    }

    /// @inheritdoc IDEXAdapter
    function removeLiquidity(
        uint256 positionId, 
        uint256 liquidity
    ) external override validDeadline returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) revert InvalidInput();
        
        // Set up decrease params
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = 
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionId,
                liquidity: uint128(liquidity),
                amount0Min: 0, // Accept any amount
                amount1Min: 0, // Accept any amount
                deadline: block.timestamp + DEADLINE_BUFFER
            });
        
        // Decrease liquidity
        (amount0, amount1) = POSITION_MANAGER.decreaseLiquidity(params);
        
        // Collect the tokens
        INonfungiblePositionManager.CollectParams memory collectParams = 
            INonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        POSITION_MANAGER.collect(collectParams);
        
        emit LiquidityRemoved(positionId, amount0, amount1);
    }

    /// @inheritdoc IDEXAdapter
    function collectFees(uint256 positionId) external override returns (uint256 amount0, uint256 amount1) {
        // Collect accumulated fees
        INonfungiblePositionManager.CollectParams memory params = 
            INonfungiblePositionManager.CollectParams({
                tokenId: positionId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        (amount0, amount1) = POSITION_MANAGER.collect(params);
        
        emit FeesCollected(positionId, amount0, amount1);
    }

    /// @inheritdoc IDEXAdapter
    function getPositionValue(uint256 positionId) external view override returns (uint256 value) {
        // Get position details (ignore token pair and ticks for now)
        (,,,,,,, uint128 liquidity,, , uint128 tokensOwed0, uint128 tokensOwed1) =
            POSITION_MANAGER.positions(positionId);
        
        // This is a simplified value calculation
        // In production, you'd need to:
        // 1. Get current tick from pool
        // 2. Calculate amounts based on liquidity and tick
        // 3. Convert to common denomination (e.g., USD)
        // 4. Add owed tokens
        
        // For now, return liquidity + owed tokens as a proxy for value
        value = uint256(liquidity) + uint256(tokensOwed0) + uint256(tokensOwed1);
    }
}