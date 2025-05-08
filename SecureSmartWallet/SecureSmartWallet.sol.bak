// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "./SecureSmartWalletBase.sol";
import "./SecureSmartWalletEmergency.sol";
import "./SecureSmartWalletSignatures.sol";

/**
 * @title SecureSmartWallet - EIP-4337 Smart Wallet (v4.48.1 - Ultimate Edition)
 * @author DFXC Indonesian Security Web3 Project - Dev DayuWidayadi
 * @dev Main contract that combines all wallet functionality through inheritance
 */
contract SecureSmartWallet is 
    Initializable,
    UUPSUpgradeable,
    SecureSmartWalletBase,
    SecureSmartWalletEmergency, 
    SecureSmartWalletSignatures,
    IERC1271Upgradeable
{
    // ========== Contract Metadata ========== //
    string public constant NAME = "SecureSmartWallet";
    string public constant VERSION = "4.48.1";
    string public constant UPGRADE_VERSION = "1.0.0";
    string public constant DESCRIPTION = "EIP-4337 Smart Wallet with Emergency Recovery (v4.48.1)";

    event ETHReceived(address indexed sender, uint256 amount);

    constructor(IEntryPoint _entryPoint) SecureSmartWalletBase(_entryPoint) {
        _disableInitializers();
    }

    function initialize(
        address[] calldata _owners,
        address[] calldata _guardians,
        uint256 _guardianThreshold
    ) external initializer onlyFactory {
        __SecureSmartWalletBase_init(_owners, _guardians, _guardianThreshold);
    }

    // ========== ERC-1271 Compliance ========== //
    function isValidSignature(bytes32 hash, bytes memory signature) 
        external 
        view 
        override 
        returns (bytes4) 
    {
        if (_isLocked) return bytes4(0xffffffff);
        return (_validateSignature(hash, signature) || _validateGuardianSignature(hash, signature))
            ? bytes4(0x1626ba7e)
            : bytes4(0xffffffff);
    }

    // ========== UUPS Upgrade Authorization ========== //
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override(SecureSmartWalletBase, UUPSUpgradeable)
        onlyOwner 
        view
    {
        require(newImplementation != address(0), "Invalid implementation");
        require(newImplementation != address(this), "Cannot upgrade to self");
        
        string memory newVersion = UUPSUpgradeable(newImplementation).UPGRADE_INTERFACE_VERSION();
        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("5.0.0")),
            "Invalid upgrade version"
        );
    }

    receive() external payable nonReentrant {
        emit ETHReceived(msg.sender, msg.value);
    }

    // ========== Factory Integration ========== //
    function migrate(
        address[] calldata _owners,
        address[] calldata _guardians,
        uint256 _guardianThreshold
    ) external onlyFactory {
        // Migration logic if needed
    }

    uint256[50] private __gap;
}