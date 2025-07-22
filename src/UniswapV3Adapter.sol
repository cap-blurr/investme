// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IDEXAdapter.sol";

/// @title UniswapV3Adapter
/// @notice Adapter for interacting with Uniswap V3 liquidity positions
contract UniswapV3Adapter is IDEXAdapter {
    // Events for transparency
    event Swap(address indexed token0, address indexed token1, uint256 amount, uint256 minOut);
    event LiquidityAdded(address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper);
    event LiquidityRemoved(uint256 indexed positionId, uint256 liquidity);
    event FeesCollected(uint256 indexed positionId, uint256 amount0, uint256 amount1);

    /// @inheritdoc IDEXAdapter
    function swap(address, address, uint256, uint256) external pure override returns (uint256) {
        revert("UniswapV3Adapter: swap not implemented");
    }

    /// @inheritdoc IDEXAdapter
    function addLiquidity(
        address,
        address,
        uint256,
        uint256,
        int24,
        int24
    ) external pure override returns (uint256) {
        revert("UniswapV3Adapter: addLiquidity not implemented");
    }

    /// @inheritdoc IDEXAdapter
    function removeLiquidity(uint256, uint256) external pure override returns (uint256, uint256) {
        revert("UniswapV3Adapter: removeLiquidity not implemented");
    }

    /// @inheritdoc IDEXAdapter
    function collectFees(uint256) external pure override returns (uint256, uint256) {
        revert("UniswapV3Adapter: collectFees not implemented");
    }

    /// @inheritdoc IDEXAdapter
    function getPositionValue(uint256) external pure override returns (uint256) {
        revert("UniswapV3Adapter: getPositionValue not implemented");
    }
}