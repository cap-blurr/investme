// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IStrategy
/// @notice Interface for strategy modules used by the Auto-LP Vault Allocator
interface IStrategy {
    /// @notice Invests the specified amount of underlying asset into the strategy
    /// @param amount The amount of underlying asset to invest
    function invest(uint256 amount) external;

    /// @notice Divests the specified amount of underlying asset from the strategy
    /// @param amount The amount of underlying asset to divest
    function divest(uint256 amount) external;

    /// @notice Returns the total amount of underlying asset managed by the strategy
    /// @return totalUnderlying The total underlying asset managed
    function totalUnderlying() external view returns (uint256 totalUnderlying);

    /// @notice Harvests any rewards or fees accrued by the strategy
    function harvest() external;
} 