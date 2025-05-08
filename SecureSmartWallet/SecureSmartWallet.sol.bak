// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // <-- TAMBAHKAN INI
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

/**
 * @title SecureSmartWalletFactory
 * @dev Factory contract for deploying SecureSmartWallet instances
 */
contract SecureSmartWalletFactory {
    IEntryPoint public immutable entryPoint;
    address public immutable walletImplementation;
    uint256 public immutable CHAIN_ID;
    
    event WalletDeployed(address indexed wallet, address[] owners, address[] guardians, uint256 threshold, string saltString);
    
    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        CHAIN_ID = block.chainid;
        walletImplementation = address(new SecureSmartWallet(_entryPoint));
    }
    
    function deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold,
        string calldata saltString // Menggunakan string sebagai identitas
    ) external returns (address wallet) {
        bytes32 salt = stringToBytes32(saltString);
        
        bytes memory initData = abi.encodeWithSelector(
            SecureSmartWallet.initialize.selector,
            owners,
            guardians,
            guardianThreshold
        );
        
        wallet = address(new ERC1967Proxy{salt: salt}(
            walletImplementation, 
            initData
        ));
        
        emit WalletDeployed(wallet, owners, guardians, guardianThreshold, saltString);
    }
    
    function computeWalletAddress(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold,
        string calldata saltString
    ) external view returns (address) {
        bytes32 salt = stringToBytes32(saltString);
        
        bytes memory initData = abi.encodeWithSelector(
            SecureSmartWallet.initialize.selector,
            owners,
            guardians,
            guardianThreshold
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(
                            walletImplementation,
                            initData
                        )
                    )
                )
            )
        );
        
        return address(uint160(uint256(hash)));
    }
    
    /**
     * @dev Mengkonversi string ke bytes32
     * @notice String yang lebih panjang dari 32 bytes akan dipotong
     */
    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        
        assembly {
            result := mload(add(source, 32))
        }
    }
}
