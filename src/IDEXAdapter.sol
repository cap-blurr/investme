// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDEXAdapter
/// @notice Standard interface for DEX adapter contracts
interface IDEXAdapter {
    function swap(address token0, address token1, uint256 amount, uint256 minOut) external returns (uint256 outAmount);
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 positionId);
    function removeLiquidity(uint256 positionId, uint256 liquidity) external returns (uint256 amount0, uint256 amount1);
    function collectFees(uint256 positionId) external returns (uint256 amount0, uint256 amount1);
    function getPositionValue(uint256 positionId) external view returns (uint256 value);
} 