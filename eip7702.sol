// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HybridEOADelegateV4 {
    address public immutable delegatedEOA;

    mapping(address => bool) public isGuardian;
    address[] public guardianAddresses;
    uint256 public recoveryThreshold;

    mapping(address => bool) private _hasVotedForRecovery;
    uint256 private _recoveryVoteCount;
    address private _proposedNewEOAOwner;

    address public approvedSponsor;
    bool public initialized;

    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryProposed(address indexed newOwner, uint256 votes);
    event RecoverySuccessful(address indexed oldOwner, address indexed newOwner);
    event SponsorSet(address indexed sponsor);
    event Initialized(address indexed initializer);

    constructor(address _initialDelegatedEOA, uint256 _initialRecoveryThreshold) {
        require(_initialDelegatedEOA != address(0), "Delegated EOA cannot be zero.");
        require(_initialRecoveryThreshold > 0, "Recovery threshold must be greater than zero.");
        delegatedEOA = _initialDelegatedEOA;
        recoveryThreshold = _initialRecoveryThreshold;
        initialized = false;
    }

    modifier onlyDelegatedEOA() {
        require(msg.sender == address(this) && tx.origin == delegatedEOA, "HybridEOADelegate: Only delegated EOA can trigger this.");
        _;
    }

    modifier onlyOnce() {
        require(!initialized, "HybridEOADelegate: Already initialized.");
        _;
    }

    function initialize(
        address _initialSponsor,
        address[] memory _initialGuardians
    ) external onlyDelegatedEOA onlyOnce {
        if (_initialSponsor != address(0)) {
            approvedSponsor = _initialSponsor;
            emit SponsorSet(_initialSponsor);
        }

        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            address guardian = _initialGuardians[i];
            require(guardian != address(0), "Guardian cannot be zero.");
            require(!isGuardian[guardian], "Guardian already exists.");
            isGuardian[guardian] = true;
            guardianAddresses.push(guardian);
            emit GuardianAdded(guardian);
        }

        initialized = true;
        emit Initialized(msg.sender);
    }

    function setApprovedSponsor(address _sponsor) external onlyDelegatedEOA {
        approvedSponsor = _sponsor;
        emit SponsorSet(_sponsor);
    }

    function addGuardian(address _guardian) external onlyDelegatedEOA {
        require(_guardian != address(0), "Guardian cannot be zero.");
        require(!isGuardian[_guardian], "Guardian already exists.");
        isGuardian[_guardian] = true;
        guardianAddresses.push(_guardian);
        emit GuardianAdded(_guardian);
    }

    function removeGuardian(address _guardian) external onlyDelegatedEOA {
        require(isGuardian[_guardian], "Guardian not found.");
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

    function setRecoveryThreshold(uint256 _newThreshold) external onlyDelegatedEOA {
        require(_newThreshold > 0 && _newThreshold <= guardianAddresses.length, "Invalid threshold.");
        recoveryThreshold = _newThreshold;
    }

    function execute(address _target, uint256 _value, bytes memory _calldata)
        external
        onlyDelegatedEOA
        returns (bool success, bytes memory result)
    {
        (success, result) = _target.call{value: _value}(_calldata);
        require(success, "HybridEOADelegate: Execution call failed.");
        return (success, result);
    }

    function executeBatch(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
        external
        onlyDelegatedEOA
        returns (bool[] memory successes)
    {
        require(_targets.length == _values.length && _targets.length == _calldatas.length, "HybridEOADelegate: Input array mismatch.");

        successes = new bool[](_targets.length);
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            successes[i] = success;
            require(success, string(abi.encodePacked("HybridEOADelegate: Batch call failed at index ", Strings.toString(i))));
        }
        return successes;
    }

    function initiateRecovery(address _newEOAOwner) external {
        require(isGuardian[msg.sender], "HybridEOADelegate: Only guardians can trigger recovery.");
        require(!_hasVotedForRecovery[msg.sender], "HybridEOADelegate: You have already voted.");
        require(_newEOAOwner != address(0), "HybridEOADelegate: New owner address cannot be zero.");

        if (_recoveryVoteCount == 0) {
            _proposedNewEOAOwner = _newEOAOwner;
        } else {
            require(_proposedNewEOAOwner == _newEOAOwner, "HybridEOADelegate: Proposed new owner does not match existing proposal.");
        }

        _hasVotedForRecovery[msg.sender] = true;
        _recoveryVoteCount++;

        emit RecoveryProposed(_newEOAOwner, _recoveryVoteCount);

        if (_recoveryVoteCount >= recoveryThreshold) {
            emit RecoverySuccessful(delegatedEOA, _proposedNewEOAOwner);
            _recoveryVoteCount = 0;
            _proposedNewEOAOwner = address(0);
            for (uint256 i = 0; i < guardianAddresses.length; i++) {
                _hasVotedForRecovery[guardianAddresses[i]] = false;
            }
        }
    }

    function sponsoredExecute(address _target, uint256 _value, bytes memory _calldata)
        external
        returns (bool success, bytes memory result)
    {
        require(msg.sender == approvedSponsor, "HybridEOADelegate: Only approved sponsor can call.");

        (success, result) = _target.call{value: _value}(_calldata);
        require(success, "HybridEOADelegate: Sponsored call failed.");
        return (success, result);
    }

    receive() external payable {}
    fallback() external payable {}
}

library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(_HEX_SYMBOLS[value % 10]);
            value /= 10;
        }
        return string(buffer);
    }
}
