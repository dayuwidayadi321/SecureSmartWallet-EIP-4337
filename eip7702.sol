// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title HybridEOADelegateV3
 * @notice Smart delegation contract designed for EIP-7702,
 * with EIP-4337-inspired features for Hybrid Account Abstraction.
 * Empowers EOAs with smart account functionalities.
 */
contract HybridEOADelegateV3 {
    address public immutable delegatedEOA;

    mapping(address => bool) public isGuardian;
    address[] public guardianAddresses;
    uint256 public recoveryThreshold;

    mapping(address => bool) private _hasVotedForRecovery;
    uint256 private _recoveryVoteCount;
    address private _proposedNewEOAOwner;

    uint256 public dailyLimit;
    uint256 public lastResetDay;
    uint256 public spentToday;

    address public approvedSponsor;

    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryProposed(address indexed newOwner, uint256 votes);
    event RecoverySuccessful(address indexed oldOwner, address indexed newOwner);
    event DailyLimitSet(uint256 newLimit);
    event SponsorSet(address indexed sponsor);
    event SpendingRecorded(uint256 amountSpent);

    constructor(address _initialDelegatedEOA, uint256 _initialRecoveryThreshold) {
        require(_initialDelegatedEOA != address(0), "Delegated EOA cannot be zero.");
        require(_initialRecoveryThreshold > 0, "Recovery threshold must be greater than zero.");
        delegatedEOA = _initialDelegatedEOA;
        recoveryThreshold = _initialRecoveryThreshold;
        dailyLimit = 0;
        lastResetDay = block.timestamp / 1 days;
    }

    modifier onlyDelegatedEOA() {
        require(msg.sender == address(this) && tx.origin == delegatedEOA, "HybridEOADelegate: Only delegated EOA can trigger this.");
        _;
    }

    /**
     * @notice Sets the daily spending limit for this EOA.
     * @dev Can only be called by the delegated EOA.
     * @param _newLimit The new spending limit in wei.
     */
    function setDailyLimit(uint256 _newLimit) external onlyDelegatedEOA {
        dailyLimit = _newLimit;
        emit DailyLimitSet(_newLimit);
    }

    /**
     * @notice Sets or changes the approved sponsor address.
     * @dev Can only be called by the delegated EOA.
     * @param _sponsor The new sponsor address (address(0) to remove).
     */
    function setApprovedSponsor(address _sponsor) external onlyDelegatedEOA {
        approvedSponsor = _sponsor;
        emit SponsorSet(_sponsor);
    }

    /**
     * @notice Adds an address as a guardian for account recovery.
     * @dev Can only be called by the delegated EOA.
     * @param _guardian The address to add as a guardian.
     */
    function addGuardian(address _guardian) external onlyDelegatedEOA {
        require(_guardian != address(0), "Guardian cannot be zero.");
        require(!isGuardian[_guardian], "Guardian already exists.");
        isGuardian[_guardian] = true;
        guardianAddresses.push(_guardian);
        emit GuardianAdded(_guardian);
    }

    /**
     * @notice Removes an address from the guardian list.
     * @dev Can only be called by the delegated EOA.
     * @param _guardian The address to remove.
     */
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

    /**
     * @notice Changes the guardian recovery threshold.
     * @dev Can only be called by the delegated EOA.
     * @param _newThreshold The new threshold.
     */
    function setRecoveryThreshold(uint256 _newThreshold) external onlyDelegatedEOA {
        require(_newThreshold > 0 && _newThreshold <= guardianAddresses.length, "Invalid threshold.");
        recoveryThreshold = _newThreshold;
    }

    /**
     * @notice Executes a single transaction call with daily spending limits.
     * @dev Can only be called by the delegated EOA.
     * @param _target The target address.
     * @param _value The amount of Ether (wei) to send.
     * @param _calldata The calldata for the target.
     */
    function execute(address _target, uint256 _value, bytes memory _calldata)
        external
        onlyDelegatedEOA
        returns (bool success, bytes memory result)
    {
        _checkAndApplyDailyLimit(_value);
        (success, result) = _target.call{value: _value}(_calldata);
        require(success, "HybridEOADelegate: Execution call failed.");
        return (success, result);
    }

    /**
     * @notice Executes multiple transaction calls in a single batch with daily spending limits.
     * @dev Can only be called by the delegated EOA.
     * @param _targets Array of target addresses.
     * @param _values Array of Ether amounts (wei) for each target.
     * @param _calldatas Array of calldata for each target.
     * @return Array of boolean results for each call.
     */
    function executeBatch(address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
        external
        onlyDelegatedEOA
        returns (bool[] memory successes)
    {
        require(_targets.length == _values.length && _targets.length == _calldatas.length, "HybridEOADelegate: Input array mismatch.");

        uint256 totalValue = 0;
        for (uint256 i = 0; i < _values.length; i++) {
            totalValue += _values[i];
        }
        _checkAndApplyDailyLimit(totalValue);

        successes = new bool[](_targets.length);
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call{value: _values[i]}(_calldatas[i]);
            successes[i] = success;
            require(success, string(abi.encodePacked("HybridEOADelegate: Batch call failed at index ", Strings.toString(i))));
        }
        return successes;
    }

    /**
     * @notice Initiates or votes for the EOA account recovery process.
     * @dev Can be called by registered guardians.
     * @param _newEOAOwner The proposed new EOA owner address.
     */
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

    /**
     * @notice Allows an 'approvedSponsor' to trigger an execution on behalf of the delegated EOA.
     * @dev This simulates a Paymaster-like mechanism where the sponsor pays for the call.
     * @param _target The target address.
     * @param _value The amount of Ether (wei) to send (typically 0 if sponsored).
     * @param _calldata The calldata for the target.
     */
    function sponsoredExecute(address _target, uint256 _value, bytes memory _calldata)
        external
        returns (bool success, bytes memory result)
    {
        require(msg.sender == approvedSponsor, "HybridEOADelegate: Only approved sponsor can call.");

        (success, result) = _target.call{value: _value}(_calldata);
        require(success, "HybridEOADelegate: Sponsored call failed.");
        return (success, result);
    }

    function _checkAndApplyDailyLimit(uint256 _amount) internal {
        if (dailyLimit == 0) return;

        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastResetDay) {
            spentToday = 0;
            lastResetDay = currentDay;
        }

        require(spentToday + _amount <= dailyLimit, "HybridEOADelegate: Daily spending limit exceeded.");
        spentToday += _amount;
        emit SpendingRecorded(_amount);
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
