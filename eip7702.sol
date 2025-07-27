// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HybridEOADelegateV6 {
    address public delegatedEOA;
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
    event MetaTransactionExecuted(address indexed relayer, address indexed target, bool success);

    constructor(address _initialDelegatedEOA, uint256 _initialRecoveryThreshold) {
        require(_initialDelegatedEOA != address(0), "Delegated EOA cannot be zero.");
        delegatedEOA = _initialDelegatedEOA;
        setRecoveryThreshold(_initialRecoveryThreshold);
    }

    // MODIFIERS
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

    // INITIALIZATION
    function initialize(
        address _initialSponsor,
        address[] memory _initialGuardians
    ) external payable onlyDelegatedEOAOrSelf onlyOnce {
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

    // ADMIN FUNCTIONS
    function setApprovedSponsor(address _sponsor) external payable onlyDelegatedEOAOrSelf {
        approvedSponsor = _sponsor;
        emit SponsorSet(_sponsor);
    }

    function addGuardian(address _guardian) external payable onlyDelegatedEOAOrSelf {
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

    function removeGuardian(address _guardian) external payable onlyDelegatedEOAOrSelf {
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

    function setRecoveryThreshold(uint256 _newThreshold) public payable onlyDelegatedEOAOrSelf {
        require(_newThreshold > 0, "Threshold must be positive");
        recoveryThreshold = _newThreshold;
    }

    // PAYABLE EXECUTION FUNCTIONS
    function execute(address _target, uint256 _value, bytes memory _calldata)
        external
        payable
        onlyDelegatedEOAOrSelf
        returns (bytes memory)
    {
        require(msg.value == _value, "Value mismatch");
        (bool success, bytes memory result) = _target.call{value: _value}(_calldata);
        require(success, "Execution failed");
        return result;
    }

    function executeBatch(
        address[] memory _targets, 
        uint256[] memory _values, 
        bytes[] memory _calldatas
    )
        external
        payable
        onlyDelegatedEOAOrSelf
        returns (bool[] memory successes)
    {
        require(_targets.length == _values.length, "Length mismatch");
        require(_targets.length == _calldatas.length, "Length mismatch");
        
        uint256 totalValue;
        for (uint256 i = 0; i < _values.length; i++) {
            totalValue += _values[i];
        }
        require(msg.value == totalValue, "Total value mismatch");

        successes = new bool[](_targets.length);
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            successes[i] = success;
            require(success, string(abi.encodePacked("Call failed at: ", Strings.toString(i))));
        }
    }

    // META TRANSACTION SUPPORT
    function metaExecute(
        address _target,
        uint256 _value,
        bytes memory _calldata,
        uint256 _nonce,
        bytes memory _signature
    ) external payable returns (bool success) {
        // Implement EIP-712 style signature verification here
        bytes32 hash = keccak256(abi.encodePacked(_target, _value, _calldata, _nonce));
        address signer = recoverSigner(hash, _signature);
        require(signer == delegatedEOA, "Invalid signature");
        
        (success, ) = _target.call{value: _value}(_calldata);
        emit MetaTransactionExecuted(msg.sender, _target, success);
    }
    
    // RECOVERY SYSTEM
    function initiateRecovery(address _newEOAOwner) external payable {
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
        
        _recoveryVoteCount = 0;
        _proposedNewEOAOwner = address(0);
        
        for (uint256 i = 0; i < guardianAddresses.length; i++) {
            _hasVotedForRecovery[guardianAddresses[i]] = false;
        }
        
        emit RecoverySuccessful(oldEOA, delegatedEOA);
        emit DelegatedEOAUpdated(oldEOA, delegatedEOA);
    }

    // SPONSORED FUNCTIONS (payable)
    function sponsoredExecute(address _target, uint256 _value, bytes memory _calldata)
        external
        payable
        returns (bytes memory)
    {
        require(msg.sender == approvedSponsor, "Only sponsor");
        require(msg.value == _value, "Value mismatch");
        (bool success, bytes memory result) = _target.call{value: _value}(_calldata);
        require(success, "Sponsored call failed");
        return result;
    }

    // HELPER FUNCTIONS
    function getGuardianCount() external view returns (uint256) {
        return guardianAddresses.length;
    }

    function getGuardianAt(uint256 index) external view returns (address) {
        require(index < guardianAddresses.length, "Invalid index");
        return guardianAddresses[index];
    }
    
    // Add this function to your contract
    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }
    
    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");
    
        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
    
        // Ethereum uses 27/28, so adjust if needed
        if (v < 27) v += 27;
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


