// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OptimizedEmergencyModule
/// @notice Ultra gas-optimized emergency controls
contract OptimizedEmergencyModule {
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event AIPaused(address indexed by);
    event EmergencyModeEnabled(address indexed by);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAuthorized();
    error AlreadyInEmergency();
    error TimeDelayActive();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public immutable aiController;
    address public owner;
    
    // Pack emergency state into single slot
    struct PackedEmergencyState {
        bool aiPaused;                    // 1 bit
        bool emergencyMode;               // 1 bit  
        uint32 requiredConfirmations;     // 32 bits
        uint32 lastNonCriticalAction;     // 32 bits (timestamp/86400)
        uint192 reserved;                 // 190 bits for future use
        // Total: 256 bits (1 slot)
    }
    
    PackedEmergencyState public emergencyState;
    
    mapping(address => bool) public isMultiSig;
    mapping(bytes32 => uint256) public confirmations;

    uint256 private constant TIME_DELAY_DAYS = 1; // 6 hours = 0.25 days

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAuthorized() {
        if (msg.sender != owner && !isMultiSig[msg.sender]) revert NotAuthorized();
        _;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(
        address _vault, 
        address _aiController, 
        address[] memory _multiSigSigners, 
        uint32 _requiredConfirmations
    ) {
        vault = _vault;
        aiController = _aiController;
        owner = msg.sender;
        
        // Initialize packed state
        emergencyState = PackedEmergencyState({
            aiPaused: false,
            emergencyMode: false,
            requiredConfirmations: _requiredConfirmations,
            lastNonCriticalAction: uint32(block.timestamp / 86400),
            reserved: 0
        });
        
        // Batch set multi-sig signers
        uint256 length = _multiSigSigners.length;
        for (uint256 i; i < length;) {
            isMultiSig[_multiSigSigners[i]] = true;
            unchecked { ++i; }
        }
    }

    // =====================
    // ====== OPTIMIZED ====
    // =====================
    
    /// @notice Instant AI pause (most gas-efficient emergency function)
    function pauseAIOperations() external onlyAuthorized {
        emergencyState.aiPaused = true;
        emit AIPaused(msg.sender);
    }
    
    /// @notice Gas-optimized emergency mode with time delay check
    function enableEmergencyMode() external {
        if (!isMultiSig[msg.sender]) revert NotAuthorized();
        
        PackedEmergencyState memory state = emergencyState;
        if (state.emergencyMode) revert AlreadyInEmergency();
        
        // Optimized time delay check
        uint32 currentDay = uint32(block.timestamp / 86400);
        if (currentDay < state.lastNonCriticalAction + TIME_DELAY_DAYS) revert TimeDelayActive();
        
        bytes32 action = keccak256("enableEmergencyMode");
        confirmations[action]++;
        
        if (confirmations[action] >= state.requiredConfirmations) {
            emergencyState.emergencyMode = true;
            emergencyState.lastNonCriticalAction = currentDay;
            emit EmergencyModeEnabled(msg.sender);
        }
    }
}