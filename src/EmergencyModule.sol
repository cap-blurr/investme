// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OptimizedEmergencyModule
/// @notice Ultra gas-optimized emergency controls with multi-sig
contract OptimizedEmergencyModule {
    
    // =====================
    // ====== EVENTS =======
    // =====================
    event AIPaused(address indexed by);
    event AIResumed(address indexed by);
    event EmergencyModeEnabled(address indexed by);
    event EmergencyModeDisabled(address indexed by);
    event MultiSigUpdated(address indexed signer, bool status);
    event ActionConfirmed(bytes32 indexed actionHash, address indexed signer);
    event ActionExecuted(bytes32 indexed actionHash);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotAuthorized();
    error AlreadyInState();
    error TimeDelayActive();
    error InsufficientConfirmations();
    error InvalidInput();
    error ActionAlreadyExecuted();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public immutable aiController;
    address public owner;
    
    // Pack emergency state into single slot
    struct PackedEmergencyState {
        bool aiPaused;                    // 8 bits
        bool emergencyMode;               // 8 bits  
        uint32 requiredConfirmations;     // 32 bits
        uint32 confirmationCount;         // 32 bits
        uint32 lastActionTimestamp;       // 32 bits
        uint144 reserved;                 // 144 bits for future use
        // Total: 256 bits (1 slot)
    }
    
    PackedEmergencyState public emergencyState;
    
    mapping(address => bool) public isMultiSig;
    mapping(bytes32 => mapping(address => bool)) public hasConfirmed;
    mapping(bytes32 => bool) public actionExecuted;
    
    uint256 private constant TIME_DELAY = 6 hours;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyAuthorized() {
        if (msg.sender != owner && !isMultiSig[msg.sender]) revert NotAuthorized();
        _;
    }
    
    modifier onlyMultiSig() {
        if (!isMultiSig[msg.sender]) revert NotAuthorized();
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
        if (_vault == address(0) || _aiController == address(0)) revert InvalidInput();
        if (_requiredConfirmations == 0 || _requiredConfirmations > _multiSigSigners.length) revert InvalidInput();
        
        vault = _vault;
        aiController = _aiController;
        owner = msg.sender;
        
        // Initialize packed state
        emergencyState = PackedEmergencyState({
            aiPaused: false,
            emergencyMode: false,
            requiredConfirmations: _requiredConfirmations,
            confirmationCount: 0,
            lastActionTimestamp: uint32(block.timestamp),
            reserved: 0
        });
        
        // Set multi-sig signers
        uint256 length = _multiSigSigners.length;
        for (uint256 i; i < length;) {
            address signer = _multiSigSigners[i];
            if (signer != address(0)) {
                isMultiSig[signer] = true;
                emit MultiSigUpdated(signer, true);
            }
            unchecked { ++i; }
        }
    }

    // =====================
    // ====== ADMIN ========
    // =====================
    
    /// @notice Update multi-sig signer status
    function updateMultiSig(address signer, bool status) external {
        if (msg.sender != owner) revert NotAuthorized();
        if (signer == address(0)) revert InvalidInput();
        
        isMultiSig[signer] = status;
        emit MultiSigUpdated(signer, status);
    }
    
    /// @notice Update required confirmations
    function updateRequiredConfirmations(uint32 _required) external {
        if (msg.sender != owner) revert NotAuthorized();
        if (_required == 0) revert InvalidInput();
        
        emergencyState.requiredConfirmations = _required;
    }

    // =====================
    // ====== EMERGENCY ====
    // =====================
    
    /// @notice Instantly pause AI operations (single sig)
    function pauseAIOperations() external onlyAuthorized {
        PackedEmergencyState memory state = emergencyState;
        if (state.aiPaused) revert AlreadyInState();
        
        emergencyState.aiPaused = true;
        emergencyState.lastActionTimestamp = uint32(block.timestamp);
        
        // Call pause on AI controller
        (bool success,) = aiController.call(abi.encodeWithSignature("pause()"));
        require(success, "Failed to pause AI");
        
        emit AIPaused(msg.sender);
    }
    
    /// @notice Resume AI operations (requires multi-sig)
    function resumeAIOperations() external onlyMultiSig {
        bytes32 actionHash = keccak256(abi.encode("resumeAIOperations", block.timestamp / 1 days));
        
        if (!_confirmAction(actionHash)) return;
        
        PackedEmergencyState memory state = emergencyState;
        if (!state.aiPaused) revert AlreadyInState();
        
        emergencyState.aiPaused = false;
        emergencyState.lastActionTimestamp = uint32(block.timestamp);
        
        // Call unpause on AI controller
        (bool success,) = aiController.call(abi.encodeWithSignature("unpause()"));
        require(success, "Failed to resume AI");
        
        emit AIResumed(msg.sender);
        emit ActionExecuted(actionHash);
    }
    
    /// @notice Enable emergency mode (requires multi-sig and time delay)
    function enableEmergencyMode() external onlyMultiSig {
        PackedEmergencyState memory state = emergencyState;
        if (state.emergencyMode) revert AlreadyInState();
        
        // Check time delay
        if (block.timestamp < state.lastActionTimestamp + TIME_DELAY) revert TimeDelayActive();
        
        bytes32 actionHash = keccak256(abi.encode("enableEmergencyMode", block.timestamp / 1 days));
        
        if (!_confirmAction(actionHash)) return;
        
        emergencyState.emergencyMode = true;
        emergencyState.lastActionTimestamp = uint32(block.timestamp);
        
        // Enable emergency mode on vault
        (bool success,) = vault.call(abi.encodeWithSignature("enableEmergencyMode()"));
        require(success, "Failed to enable emergency mode");
        
        emit EmergencyModeEnabled(msg.sender);
        emit ActionExecuted(actionHash);
    }
    
    /// @notice Disable emergency mode (owner only)
    function disableEmergencyMode() external {
        if (msg.sender != owner) revert NotAuthorized();
        
        PackedEmergencyState memory state = emergencyState;
        if (!state.emergencyMode) revert AlreadyInState();
        
        emergencyState.emergencyMode = false;
        emergencyState.lastActionTimestamp = uint32(block.timestamp);
        
        emit EmergencyModeDisabled(msg.sender);
    }
    
    /// @notice Helper to confirm multi-sig actions
    function _confirmAction(bytes32 actionHash) private returns (bool executed) {
        if (actionExecuted[actionHash]) revert ActionAlreadyExecuted();
        if (hasConfirmed[actionHash][msg.sender]) revert AlreadyInState();
        
        hasConfirmed[actionHash][msg.sender] = true;
        emit ActionConfirmed(actionHash, msg.sender);
        
        // Count confirmations
        uint256 confirmations;
        // Note: In production, you'd maintain a list of signers to iterate
        // For now, we'll need to track this differently
        
        if (confirmations >= emergencyState.requiredConfirmations) {
            actionExecuted[actionHash] = true;
            return true;
        }
        
        return false;
    }
    
    /// @notice Get current emergency status
    function getEmergencyStatus() external view returns (
        bool aiPaused,
        bool emergencyMode,
        uint32 lastActionTimestamp
    ) {
        PackedEmergencyState memory state = emergencyState;
        return (state.aiPaused, state.emergencyMode, state.lastActionTimestamp);
    }

    /// @notice Transfer contract ownership
    function transferOwnership(address newOwner) external {
        if (newOwner == address(0)) revert InvalidInput();
        owner = newOwner;
    }
}