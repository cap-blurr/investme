// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OptimizedFeeCollector
/// @notice Ultra gas-optimized fee collection with proper fund transfers
contract OptimizedFeeCollector {
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event ManagementFeeCollected(address indexed user, uint256 amount);
    event PerformanceFeeCollected(address indexed user, uint256 amount);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeesTransferred(address indexed recipient, uint256 amount);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAuthorized();
    error InvalidAddress();
    error TransferFailed();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public feeRecipient;
    address public owner;

    // Optimize constants for gas efficiency
    uint256 private constant MANAGEMENT_FEE_BPS = 100;     // 1%
    uint256 private constant PERFORMANCE_FEE_BPS = 2000;   // 20%
    uint256 private constant SECONDS_PER_YEAR = 31536000; // 365 days
    uint256 private constant BPS_DIVISOR = 10000;

    // Pack user fee data into single storage slot
    struct PackedUserFeeData {
        uint128 highWaterMark;    // 128 bits for value tracking
        uint128 lastAccrual;      // 128 bits for timestamp
        // Total: 256 bits (1 slot)
    }
    
    mapping(address => PackedUserFeeData) public userFeeData;
    
    // Track total fees collected for transfer
    uint256 public totalPendingFees;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAuthorized() {
        address _vault = vault;
        address _owner = owner;
        assembly {
            let _caller := caller()

            if iszero(or(eq(_caller, _vault), eq(_caller, _owner))) {
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
        if (_vault == address(0) || _feeRecipient == address(0)) revert InvalidAddress();
        
        vault = _vault;
        feeRecipient = _feeRecipient;
        owner = msg.sender;
    }

    // =====================
    // ====== ADMIN ========
    // =====================
    
    /// @notice Update fee recipient address
    function setFeeRecipient(address _feeRecipient) external {
        if (msg.sender != owner) revert NotAuthorized();
        if (_feeRecipient == address(0)) revert InvalidAddress();
        
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    // =====================
    // ====== FEE LOGIC ====
    // =====================
    
    /// @notice Calculate management fee for a user
    /// @dev Returns fee amount without collecting it
    function calculateManagementFee(address user, uint256 userBalance) public view returns (uint256 fee) {
        PackedUserFeeData memory data = userFeeData[user];
        
        uint256 nowTime = block.timestamp;
        uint256 lastAccrual = data.lastAccrual;
        
        // First time user - no fees yet
        if (lastAccrual == 0) return 0;
        
        uint256 elapsed = nowTime - lastAccrual;
        
        // Calculate annual fee prorated for elapsed time
        fee = (userBalance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * BPS_DIVISOR);
    }
    
    /// @notice Calculate performance fee for a user
    /// @dev Returns fee amount without collecting it
    function calculatePerformanceFee(address user, uint256 userBalance) public view returns (uint256 fee) {
        PackedUserFeeData memory data = userFeeData[user];
        
        if (userBalance > data.highWaterMark) {
            uint256 profit = userBalance - data.highWaterMark;
            fee = (profit * PERFORMANCE_FEE_BPS) / BPS_DIVISOR;
        }
    }
    
    /// @notice Collect management fee for a user
    function collectManagementFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        fee = calculateManagementFee(user, userBalance);
        
        if (fee > 0) {
            // Update last accrual timestamp
            PackedUserFeeData memory data = userFeeData[user];
            userFeeData[user] = PackedUserFeeData({
                highWaterMark: data.highWaterMark,
                lastAccrual: uint128(block.timestamp)
            });
            
            totalPendingFees += fee;
            emit ManagementFeeCollected(user, fee);
        }
    }
    
    /// @notice Collect performance fee for a user
    function collectPerformanceFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        PackedUserFeeData memory data = userFeeData[user];
        
        if (userBalance > data.highWaterMark) {
            uint256 profit = userBalance - data.highWaterMark;
            fee = (profit * PERFORMANCE_FEE_BPS) / BPS_DIVISOR;
            
            // Update high water mark
            userFeeData[user] = PackedUserFeeData({
                highWaterMark: uint128(userBalance),
                lastAccrual: data.lastAccrual
            });
            
            totalPendingFees += fee;
            emit PerformanceFeeCollected(user, fee);
        }
    }
    
    /// @notice Batch collect fees for multiple users
    function batchCollectFees(
        address[] calldata users, 
        uint256[] calldata balances
    ) external onlyAuthorized returns (uint256 totalManagementFees, uint256 totalPerformanceFees) {
        uint256 length = users.length;
        require(length == balances.length, "Length mismatch");
        
        uint256 nowTime = block.timestamp;
        
        for (uint256 i; i < length;) {
            address user = users[i];
            uint256 balance = balances[i];
            PackedUserFeeData memory data = userFeeData[user];
            
            // Management fee calculation
            if (data.lastAccrual > 0) {
                uint256 elapsed = nowTime - data.lastAccrual;
                uint256 mgmtFee = (balance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * BPS_DIVISOR);
                totalManagementFees += mgmtFee;
            }
            
            // Performance fee calculation  
            uint256 perfFee;
            uint128 newHighWaterMark = data.highWaterMark;
            if (balance > data.highWaterMark) {
                uint256 profit = balance - data.highWaterMark;
                perfFee = (profit * PERFORMANCE_FEE_BPS) / BPS_DIVISOR;
                totalPerformanceFees += perfFee;
                newHighWaterMark = uint128(balance);
            }
            
            // Single storage write per user
            userFeeData[user] = PackedUserFeeData({
                highWaterMark: newHighWaterMark,
                lastAccrual: uint128(nowTime)
            });
            
            unchecked { ++i; }
        }
        
        totalPendingFees += totalManagementFees + totalPerformanceFees;
    }
    
    /// @notice Transfer collected fees to recipient
    /// @dev Vault must transfer the fees to this contract first
    function transferCollectedFees(address token) external onlyAuthorized {
        uint256 amount = totalPendingFees;
        if (amount == 0) return;
        
        totalPendingFees = 0;
        
        // Transfer fees from vault to recipient
        (bool success,) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                vault,
                feeRecipient,
                amount
            )
        );
        if (!success) revert TransferFailed();
        
        emit FeesTransferred(feeRecipient, amount);
    }
    
    /// @notice Initialize fee tracking for a new user
    function initializeUser(address user) external onlyAuthorized {
        if (userFeeData[user].lastAccrual == 0) {
            userFeeData[user].lastAccrual = uint128(block.timestamp);
        }
    }

    /// @notice Transfer contract ownership
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert NotAuthorized();
        if (newOwner == address(0)) revert InvalidAddress();
        owner = newOwner;
    }
}