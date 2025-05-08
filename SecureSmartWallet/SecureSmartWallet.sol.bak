// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
    string public constant NAME = "SecureSmartWallet";
    string public constant VERSION = "4.48.1";
    string public constant UPGRADE_VERSION = "1.0.0";

    event ETHReceived(address indexed sender, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IEntryPoint _entryPoint,
        address[] calldata _owners,
        address[] calldata _guardians,
        uint256 _guardianThreshold
    ) external initializer {
        __SecureSmartWalletBase_init(_entryPoint, _owners, _guardians, _guardianThreshold);
        factory = msg.sender; // Auto-set factory
    }

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

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner
    {
        require(newImplementation != address(0), "Invalid implementation");
        require(newImplementation != address(this), "Cannot upgrade to self");
        
        // Additional version validation can be added here
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    uint256[50] private __gap;
}

contract SecureSmartWalletFactory {
    IEntryPoint public immutable entryPoint;
    address public immutable walletImplementation;
    
    event WalletCreated(address indexed wallet, address[] owners);

    constructor(IEntryPoint _entryPoint) {
        require(address(_entryPoint) != address(0), "Invalid EntryPoint");
        entryPoint = _entryPoint;
        walletImplementation = address(new SecureSmartWallet());
    }
    
    function deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold
    ) external returns (address walletAddress) {
        require(owners.length > 0, "No owners provided");
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            walletImplementation,
            abi.encodeWithSelector(
                SecureSmartWallet.initialize.selector,
                entryPoint,
                owners,
                guardians,
                guardianThreshold
            )
        );
        
        walletAddress = address(proxy);
        emit WalletCreated(walletAddress, owners);
    }
}