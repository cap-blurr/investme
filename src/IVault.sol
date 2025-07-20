// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IVault
/// @notice Interface for the Auto-LP ERC-4626 Vault
interface IVault is IERC4626 {
    /// @notice Emitted when funds are invested via the Allocator
    /// @param amount The amount invested
    event Invested(uint256 amount);

    // Add any custom vault methods here if needed
} 