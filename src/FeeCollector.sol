// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OptimizedFeeCollector
/// @notice Ultra gas-optimized fee collection
contract OptimizedFeeCollector {
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event ManagementFeeCollected(address indexed user, uint256 amount);
    event PerformanceFeeCollected(address indexed user, uint256 amount);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAuthorized();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public feeRecipient;
    address public owner;

    // Optimize constants for gas efficiency
    uint256 private constant MANAGEMENT_FEE_BPS = 100;
    uint256 private constant PERFORMANCE_FEE_BPS = 2000;
    uint256 private constant SECONDS_PER_YEAR = 31536000; // Hardcoded for gas savings

    // Pack user fee data into single storage slot
    struct PackedUserFeeData {
        uint128 highWaterMark;    // 128 bits
        uint128 lastAccrual;      // 128 bits
        // Total: 256 bits (1 slot)
    }
    
    mapping(address => PackedUserFeeData) public userFeeData;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAuthorized() {
        assembly {
            let _vault := sload(vault.slot)
            let _owner := sload(owner.slot)
            let caller := caller()
            
            if iszero(or(eq(caller, _vault), eq(caller, _owner))) {
                mstore(0x00, 0x82b42900) // NotAuthorized() selector
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(address _vault, address _feeRecipient) {
        vault = _vault;
        feeRecipient = _feeRecipient;
        owner = msg.sender;
    }

    // =====================
    // ====== OPTIMIZED ====
    // =====================
    
    /// @notice Ultra gas-optimized management fee collection
    function collectManagementFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        PackedUserFeeData memory data = userFeeData[user];
        
        uint256 nowTime = block.timestamp;
        uint256 last = data.lastAccrual;
        
        // Handle first-time user with assembly optimization
        assembly {
            if iszero(last) { last := nowTime }
        }
        
        uint256 elapsed = nowTime - last;
        
        // Optimized fee calculation using bit shifting where possible
        fee = (userBalance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10000);
        
        // Single storage write for updated data
        userFeeData[user] = PackedUserFeeData({
            highWaterMark: data.highWaterMark,
            lastAccrual: uint128(nowTime)
        });
        
        emit ManagementFeeCollected(user, fee);
    }
    
    /// @notice Gas-optimized performance fee collection
    function collectPerformanceFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        PackedUserFeeData memory data = userFeeData[user];
        
        if (userBalance > data.highWaterMark) {
            uint256 profit = userBalance - data.highWaterMark;
            fee = (profit * PERFORMANCE_FEE_BPS) / 10000;
            
            // Update high water mark in single storage write
            userFeeData[user].highWaterMark = uint128(userBalance);
            
            emit PerformanceFeeCollected(user, fee);
        }
    }
    
    /// @notice Batch fee collection for multiple users (major gas savings)
    function batchCollectFees(
        address[] calldata users, 
        uint256[] calldata balances
    ) external onlyAuthorized returns (uint256 totalManagementFees, uint256 totalPerformanceFees) {
        uint256 length = users.length;
        uint256 nowTime = block.timestamp;
        
        for (uint256 i; i < length;) {
            address user = users[i];
            uint256 balance = balances[i];
            PackedUserFeeData memory data = userFeeData[user];
            
            // Management fee calculation
            uint256 last = data.lastAccrual;
            if (last == 0) last = nowTime;
            uint256 elapsed = nowTime - last;
            uint256 mgmtFee = (balance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10000);
            totalManagementFees += mgmtFee;
            
            // Performance fee calculation  
            uint256 perfFee;
            if (balance > data.highWaterMark) {
                uint256 profit = balance - data.highWaterMark;
                perfFee = (profit * PERFORMANCE_FEE_BPS) / 10000;
                totalPerformanceFees += perfFee;
                data.highWaterMark = uint128(balance);
            }
            
            // Single storage write per user
            userFeeData[user] = PackedUserFeeData({
                highWaterMark: data.highWaterMark,
                lastAccrual: uint128(nowTime)
            });
            
            unchecked { ++i; }
        }
    }
}