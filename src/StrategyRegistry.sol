// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title StrategyRegistry
/// @notice Registry for managing strategy contracts and their parameters
/// @dev Allows registration, parameter updates, emergency pause, and performance tracking
contract StrategyRegistry {
    // =====================
    // ====== EVENTS =======
    // =====================
    /// @notice Emitted when a strategy is registered
    event StrategyRegistered(address indexed strategy, string name, uint256 minAlloc, uint256 maxAlloc, uint256 riskScore);
    /// @notice Emitted when strategy parameters are updated
    event StrategyParamsUpdated(address indexed strategy, uint256 minAlloc, uint256 maxAlloc, uint256 riskScore);
    /// @notice Emitted when a strategy is paused/unpaused
    event StrategyPaused(address indexed strategy, bool paused);
    /// @notice Emitted when a strategy is emergency exited
    event StrategyEmergencyExited(address indexed strategy);

    // =====================
    // ====== ERRORS =======
    // =====================
    error StrategyAlreadyRegistered(address strategy);
    error StrategyNotRegistered(address strategy);
    error StrategyPausedError(address strategy);
    error Unauthorized(address caller);

    // =====================
    // ====== STRUCTS ======
    // =====================
    struct StrategyInfo {
        string name;
        uint256 minAlloc;
        uint256 maxAlloc;
        uint256 riskScore;
        bool paused;
        // TODO: Add performance tracking fields
    }

    // =====================
    // ====== STORAGE ======
    // =====================
    mapping(address => StrategyInfo) public strategies;
    address[] public strategyList;

    // =====================
    // ====== FUNCTIONS ====
    // =====================
    /// @notice Register a new strategy
    function registerStrategy(address strategy, string calldata name, uint256 minAlloc, uint256 maxAlloc, uint256 riskScore) external {
        // TODO: Implement registration logic
        revert("registerStrategy not implemented");
    }

    /// @notice Update parameters for a strategy
    function updateStrategyParams(address strategy, uint256 minAlloc, uint256 maxAlloc, uint256 riskScore) external {
        // TODO: Implement parameter update logic
        revert("updateStrategyParams not implemented");
    }

    /// @notice Get all active strategies
    function getActiveStrategies() external view returns (address[] memory) {
        // TODO: Implement active strategy retrieval
        revert("getActiveStrategies not implemented");
    }

    /// @notice Emergency exit a strategy
    function emergencyExitStrategy(address strategy) external {
        // TODO: Implement emergency exit logic
        revert("emergencyExitStrategy not implemented");
    }
} 