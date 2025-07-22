// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title FeeCollector
/// @notice Collects and distributes protocol management and performance fees
contract FeeCollector {
    // =====================
    // ====== EVENTS =======
    // =====================
    event ManagementFeeCollected(address indexed user, uint256 amount);
    event PerformanceFeeCollected(address indexed user, uint256 amount);
    event FeeRecipientUpdated(address indexed newRecipient);

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

    uint256 public constant MANAGEMENT_FEE_BPS = 100; // 1% per annum (basis points)
    uint256 public constant PERFORMANCE_FEE_BPS = 2000; // 20% of profits
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct UserFeeData {
        uint256 highWaterMark;
        uint256 lastAccrual;
    }
    mapping(address => UserFeeData) public userFeeData;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAuthorized() {
        if (msg.sender != vault && msg.sender != owner) revert NotAuthorized();
        _;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
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

    /// @notice Set the fee recipient address
    /// @param newRecipient The new fee recipient
    function setFeeRecipient(address newRecipient) external onlyOwner {
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /// @notice Collects the pro-rated management fee for a user
    /// @param user The user to collect from
    /// @param userBalance The user's current vault balance (passed in for gas efficiency)
    function collectManagementFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        UserFeeData storage data = userFeeData[user];
        uint256 last = data.lastAccrual;
        uint256 nowTime = block.timestamp;
        if (last == 0) last = nowTime;
        uint256 elapsed = nowTime - last;
        fee = (userBalance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10_000);
        data.lastAccrual = nowTime;
        // Transfer fee from user to feeRecipient (handled by vault)
        emit ManagementFeeCollected(user, fee);
    }

    /// @notice Collects the performance fee for a user if above high-water mark
    /// @param user The user to collect from
    /// @param userBalance The user's current vault balance (passed in for gas efficiency)
    function collectPerformanceFee(address user, uint256 userBalance) external onlyAuthorized returns (uint256 fee) {
        UserFeeData storage data = userFeeData[user];
        uint256 hwm = data.highWaterMark;
        if (userBalance > hwm) {
            uint256 profit = userBalance - hwm;
            fee = (profit * PERFORMANCE_FEE_BPS) / 10_000;
            data.highWaterMark = userBalance;
            // Transfer fee from user to feeRecipient (handled by vault)
            emit PerformanceFeeCollected(user, fee);
        }
    }

    /// @notice Returns the pending management and performance fees for a user
    /// @param user The user to check
    /// @param userBalance The user's current vault balance
    function getFeesDue(address user, uint256 userBalance) external view returns (uint256 managementFee, uint256 performanceFee) {
        UserFeeData storage data = userFeeData[user];
        uint256 last = data.lastAccrual;
        uint256 nowTime = block.timestamp;
        if (last == 0) last = nowTime;
        uint256 elapsed = nowTime - last;
        managementFee = (userBalance * MANAGEMENT_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10_000);
        uint256 hwm = data.highWaterMark;
        if (userBalance > hwm) {
            uint256 profit = userBalance - hwm;
            performanceFee = (profit * PERFORMANCE_FEE_BPS) / 10_000;
        }
    }
} 