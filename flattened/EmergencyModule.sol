// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/EmergencyModule.sol

/// @title EmergencyModule
/// @notice Provides emergency controls to override AI and protect user funds
contract EmergencyModule {
    // =====================
    // ====== EVENTS =======
    // =====================
    event AIPaused(address indexed by);
    event EmergencyModeEnabled(address indexed by);
    event PositionForceExited(address indexed by, uint256 positionId);
    event DrainedToVault(address indexed by);
    event MultiSigProposed(address indexed proposer, address[] newSigners);
    event MultiSigConfirmed(address indexed confirmer);

    // =====================
    // ====== ERRORS =======
    // =====================
    error NotOwner();
    error NotMultiSig();
    error AlreadyInEmergency();
    error NotInEmergency();
    error TimeDelayActive();

    // =====================
    // ====== STORAGE ======
    // =====================
    address public immutable vault;
    address public immutable aiController;
    address public owner;
    address[] public multiSigSigners;
    mapping(address => bool) public isMultiSig;
    uint256 public requiredConfirmations;
    mapping(bytes32 => uint256) public confirmations;
    mapping(bytes32 => mapping(address => bool)) public hasConfirmed;

    bool public aiPaused;
    bool public emergencyMode;
    uint256 public lastNonCriticalAction;
    uint256 public constant TIME_DELAY = 6 hours;

    // =====================
    // ====== MODIFIERS ====
    // =====================
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    modifier onlyMultiSig() {
        if (!isMultiSig[msg.sender]) revert NotMultiSig();
        _;
    }
    modifier notInEmergency() {
        if (emergencyMode) revert AlreadyInEmergency();
        _;
    }
    modifier inEmergency() {
        if (!emergencyMode) revert NotInEmergency();
        _;
    }
    modifier timeDelayPassed() {
        if (block.timestamp < lastNonCriticalAction + TIME_DELAY) revert TimeDelayActive();
        _;
    }

    // =====================
    // ====== CONSTRUCTOR ==
    // =====================
    constructor(address _vault, address _aiController, address[] memory _multiSigSigners, uint256 _requiredConfirmations) {
        vault = _vault;
        aiController = _aiController;
        owner = msg.sender;
        multiSigSigners = _multiSigSigners;
        requiredConfirmations = _requiredConfirmations;
        for (uint256 i = 0; i < _multiSigSigners.length; i++) {
            isMultiSig[_multiSigSigners[i]] = true;
        }
    }

    /// @notice Immediately pause all AI operations (owner or any multi-sig)
    function pauseAIOperations() external {
        require(msg.sender == owner || isMultiSig[msg.sender], "Not authorized");
        aiPaused = true;
        emit AIPaused(msg.sender);
    }

    /// @notice Propose and confirm enabling emergency mode (multi-sig, time delay for non-critical)
    function enableEmergencyMode() external onlyMultiSig notInEmergency timeDelayPassed {
        bytes32 action = keccak256("enableEmergencyMode");
        require(!hasConfirmed[action][msg.sender], "Already confirmed");
        hasConfirmed[action][msg.sender] = true;
        confirmations[action]++;
        if (confirmations[action] >= requiredConfirmations) {
            emergencyMode = true;
            emit EmergencyModeEnabled(msg.sender);
            lastNonCriticalAction = block.timestamp;
        }
    }

    /// @notice Force exit a DEX position (multi-sig, only in emergency)
    /// @param positionId The position to close
    function forceExitPosition(uint256 positionId) external onlyMultiSig inEmergency {
        emit PositionForceExited(msg.sender, positionId);
        // Actual position exit logic handled by adapters/controller
    }

    /// @notice Drain all funds to the vault (multi-sig, only in emergency)
    function drainToVault() external onlyMultiSig inEmergency {
        emit DrainedToVault(msg.sender);
        // Actual fund movement handled by vault/adapters
    }

    /// @notice Users can always withdraw via the vault, even in emergency
    /// @dev No function needed here; enforced by vault

    /// @notice Propose a new multi-sig signer set (owner only)
    function proposeMultiSig(address[] calldata newSigners, uint256 newRequired) external onlyOwner {
        for (uint256 i = 0; i < multiSigSigners.length; i++) {
            isMultiSig[multiSigSigners[i]] = false;
        }
        for (uint256 i = 0; i < newSigners.length; i++) {
            isMultiSig[newSigners[i]] = true;
        }
        multiSigSigners = newSigners;
        requiredConfirmations = newRequired;
        emit MultiSigProposed(msg.sender, newSigners);
    }
}

