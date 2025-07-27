// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HybridEOADelegateV5 {
    address public delegatedEOA;  // Changed from immutable to allow recovery
    mapping(address => bool) public isGuardian;
    address[] public guardianAddresses;
    uint256 public recoveryThreshold;

    // Recovery state variables
    mapping(address => bool) private _hasVotedForRecovery;
    uint256 private _recoveryVoteCount;
    address private _proposedNewEOAOwner;

    address public approvedSponsor;
    bool public initialized;

    // Events
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryProposed(address indexed newOwner, uint256 votes);
    event RecoverySuccessful(address indexed oldOwner, address indexed newOwner);
    event SponsorSet(address indexed sponsor);
    event Initialized(address indexed initializer);
    event DelegatedEOAUpdated(address indexed oldEOA, address indexed newEOA);

    constructor(address _initialDelegatedEOA, uint256 _initialRecoveryThreshold) {
        require(_initialDelegatedEOA != address(0), "Delegated EOA cannot be zero.");
        delegatedEOA = _initialDelegatedEOA;
        setRecoveryThreshold(_initialRecoveryThreshold);
    }

    // MODIFIERS - Simplified and more flexible
    modifier onlyDelegatedEOA() {
        require(tx.origin == delegatedEOA, "Only delegated EOA can trigger this");
        _;
    }

    modifier onlyDelegatedEOAOrSelf() {
        require(msg.sender == address(this) || tx.origin == delegatedEOA, 
            "Only delegated EOA or contract itself");
        _;
    }

    modifier onlyOnce() {
        require(!initialized, "Already initialized");
        _;
    }

    // INITIALIZATION - More flexible
    function initialize(
        address _initialSponsor,
        address[] memory _initialGuardians
    ) external onlyDelegatedEOAOrSelf onlyOnce {
        if (_initialSponsor != address(0)) {
            approvedSponsor = _initialSponsor;
            emit SponsorSet(_initialSponsor);
        }

        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            _addGuardian(_initialGuardians[i]);
        }

        initialized = true;
        emit Initialized(msg.sender);
    }

    // ADMIN FUNCTIONS - More flexible access
    function setApprovedSponsor(address _sponsor) external onlyDelegatedEOAOrSelf {
        approvedSponsor = _sponsor;
        emit SponsorSet(_sponsor);
    }

    function addGuardian(address _guardian) external onlyDelegatedEOAOrSelf {
        _addGuardian(_guardian);
    }

    function _addGuardian(address _guardian) internal {
        require(_guardian != address(0), "Invalid guardian address");
        if (!isGuardian[_guardian]) {
            isGuardian[_guardian] = true;
            guardianAddresses.push(_guardian);
            emit GuardianAdded(_guardian);
        }
    }

    function removeGuardian(address _guardian) external onlyDelegatedEOAOrSelf {
        require(isGuardian[_guardian], "Guardian not found");
        isGuardian[_guardian] = false;
        
        for (uint256 i = 0; i < guardianAddresses.length; i++) {
            if (guardianAddresses[i] == _guardian) {
                guardianAddresses[i] = guardianAddresses[guardianAddresses.length - 1];
                guardianAddresses.pop();
                break;
            }
        }
        emit GuardianRemoved(_guardian);
    }

    function setRecoveryThreshold(uint256 _newThreshold) public onlyDelegatedEOAOrSelf {
        require(_newThreshold > 0, "Threshold must be positive");
        recoveryThreshold = _newThreshold;
    }

    // EXECUTION FUNCTIONS - More flexible
    function execute(address _target, uint256 _value, bytes memory _calldata)
        external
        onlyDelegatedEOAOrSelf
        returns (bool success, bytes memory result)
    {
        (success, result) = _target.call{value: _value}(_calldata);
        if (!success) {
            revert("Execution call failed");
        }
    }

    function executeBatch(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
        external
        onlyDelegatedEOAOrSelf
        returns (bool[] memory successes)
    {
        require(_targets.length == _values.length, "Input array length mismatch");
        require(_targets.length == _calldatas.length, "Input array length mismatch");

        successes = new bool[](_targets.length);
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            successes[i] = success;
            if (!success) {
                revert(string(abi.encodePacked("Batch call failed at index ", Strings.toString(i))));
            }
        }
    }

    // RECOVERY SYSTEM - More flexible
    function initiateRecovery(address _newEOAOwner) external {
        require(isGuardian[msg.sender], "Only guardians can trigger recovery");
        require(!_hasVotedForRecovery[msg.sender], "Already voted");
        require(_newEOAOwner != address(0), "Invalid new owner address");

        if (_recoveryVoteCount == 0) {
            _proposedNewEOAOwner = _newEOAOwner;
        } else {
            require(_proposedNewEOAOwner == _newEOAOwner, "Proposal mismatch");
        }

        _hasVotedForRecovery[msg.sender] = true;
        _recoveryVoteCount++;

        emit RecoveryProposed(_newEOAOwner, _recoveryVoteCount);

        if (_recoveryVoteCount >= recoveryThreshold) {
            _completeRecovery();
        }
    }

    function _completeRecovery() internal {
        address oldEOA = delegatedEOA;
        delegatedEOA = _proposedNewEOAOwner;
        
        // Reset recovery state
        _recoveryVoteCount = 0;
        _proposedNewEOAOwner = address(0);
        
        for (uint256 i = 0; i < guardianAddresses.length; i++) {
            _hasVotedForRecovery[guardianAddresses[i]] = false;
        }
        
        emit RecoverySuccessful(oldEOA, delegatedEOA);
        emit DelegatedEOAUpdated(oldEOA, delegatedEOA);
    }

    // SPONSORED FUNCTIONS
    function sponsoredExecute(address _target, uint256 _value, bytes memory _calldata)
        external
        returns (bool success, bytes memory result)
    {
        require(msg.sender == approvedSponsor, "Only approved sponsor");
        (success, result) = _target.call{value: _value}(_calldata);
        if (!success) {
            revert("Sponsored call failed");
        }
    }

    // HELPER FUNCTIONS
    function getGuardianCount() external view returns (uint256) {
        return guardianAddresses.length;
    }

    function getGuardianAt(uint256 index) external view returns (address) {
        require(index < guardianAddresses.length, "Index out of bounds");
        return guardianAddresses[index];
    }

    // Fallback functions
    receive() external payable {}
    fallback() external payable {}
}

library Strings {
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}