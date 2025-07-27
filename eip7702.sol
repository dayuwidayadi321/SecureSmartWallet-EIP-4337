// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract HybridEOADelegateV6 is Initializable, UUPSUpgradeable {
    address public delegatedEOA;
    mapping(address => bool) public isGuardian;
    address[] public guardianAddresses;
    uint256 public recoveryThreshold;

    // Recovery state variables
    mapping(address => bool) private _hasVotedForRecovery;
    uint256 private _recoveryVoteCount;
    address private _proposedNewEOAOwner;

    address public approvedSponsor;
    bool private _initialized;

    // Events
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryProposed(address indexed newOwner, uint256 votes);
    event RecoverySuccessful(address indexed oldOwner, address indexed newOwner);
    event SponsorSet(address indexed sponsor);
    event Initialized(address indexed initializer);
    event DelegatedEOAUpdated(address indexed oldEOA, address indexed newEOA);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        // Mencegah implementasi kontrak diinisialisasi
        _disableInitializers();
    }

    function initialize(
        address _initialDelegatedEOA,
        uint256 _initialRecoveryThreshold,
        address _initialSponsor,
        address[] memory _initialGuardians
    ) public initializer {
        require(_initialDelegatedEOA != address(0), "Delegated EOA cannot be zero");
        __UUPSUpgradeable_init();
        
        delegatedEOA = _initialDelegatedEOA;
        setRecoveryThreshold(_initialRecoveryThreshold);
        
        if (_initialSponsor != address(0)) {
            approvedSponsor = _initialSponsor;
            emit SponsorSet(_initialSponsor);
        }

        for (uint256 i = 0; i < _initialGuardians.length; i++) {
            _addGuardian(_initialGuardians[i]);
        }

        _initialized = true;
        emit Initialized(msg.sender);
    }

    // MODIFIERS
    modifier onlyDelegatedEOA() {
        require(tx.origin == delegatedEOA, "Only delegated EOA");
        _;
    }

    modifier onlyDelegatedEOAOrSelf() {
        require(msg.sender == address(this) || tx.origin == delegatedEOA, 
            "Only delegated EOA or contract");
        _;
    }

    // ADMIN FUNCTIONS
    function setApprovedSponsor(address _sponsor) external onlyDelegatedEOAOrSelf {
        approvedSponsor = _sponsor;
        emit SponsorSet(_sponsor);
    }

    function addGuardian(address _guardian) external onlyDelegatedEOAOrSelf {
        _addGuardian(_guardian);
    }

    function _addGuardian(address _guardian) internal {
        require(_guardian != address(0), "Invalid guardian");
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

    // PAYABLE EXECUTION FUNCTIONS
    function execute(address _target, uint256 _value, bytes memory _calldata)
        external
        payable  // <-- Ditambahkan payable
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
        payable  // <-- Ditambahkan payable
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

    // RECOVERY SYSTEM
    function initiateRecovery(address _newEOAOwner) external {
        require(isGuardian[msg.sender], "Only guardians");
        require(!_hasVotedForRecovery[msg.sender], "Already voted");
        require(_newEOAOwner != address(0), "Invalid address");

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
        payable  // <-- Ditambahkan payable
        returns (bytes memory)
    {
        require(msg.sender == approvedSponsor, "Only sponsor");
        require(msg.value == _value, "Value mismatch");
        (bool success, bytes memory result) = _target.call{value: _value}(_calldata);
        require(success, "Sponsored call failed");
        return result;
    }

    // UPGRADE FUNCTIONALITY
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyDelegatedEOAOrSelf 
    {}

    // HELPER FUNCTIONS
    function getGuardianCount() external view returns (uint256) {
        return guardianAddresses.length;
    }

    function getGuardianAt(uint256 index) external view returns (address) {
        require(index < guardianAddresses.length, "Invalid index");
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

