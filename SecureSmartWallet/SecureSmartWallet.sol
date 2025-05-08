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
 * @dev Factory untuk membuat instance SecureSmartWallet tanpa memerlukan salt manual
 */
contract SecureSmartWalletFactory {
    IEntryPoint public immutable entryPoint;
    address public immutable walletImplementation;
    mapping(address => uint256) public userNonce;

    event WalletDeployed(
        address indexed wallet,
        address indexed creator,
        address[] owners,
        address[] guardians,
        uint256 threshold,
        uint256 nonce
    );

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        walletImplementation = address(new SecureSmartWallet(_entryPoint));
    }

    /**
     * @notice Deploy wallet baru dengan nonce otomatis
     * @param owners Daftar alamat owner
     * @param guardians Daftar alamat guardian
     * @param threshold Jumlah minimal guardian untuk recovery
     */
    function deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 threshold
    ) external returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, userNonce[msg.sender]));

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            walletImplementation,
            abi.encodeWithSelector(
                SecureSmartWallet.initialize.selector,
                owners,
                guardians,
                threshold
            )
        );

        address wallet = address(proxy);
        userNonce[msg.sender]++;

        emit WalletDeployed(
            wallet,
            msg.sender,
            owners,
            guardians,
            threshold,
            userNonce[msg.sender] - 1
        );

        return wallet;
    }

    /**
     * @notice Prediksi alamat wallet sebelum di-deploy
     * @param user Alamat pembuat wallet
     * @param nonce Nonce dari user
     * @param owners Daftar alamat owner
     * @param guardians Daftar alamat guardian
     * @param threshold Jumlah minimal guardian untuk recovery
     */
    function computeWalletAddress(
        address user,
        uint256 nonce,
        address[] calldata owners,
        address[] calldata guardians,
        uint256 threshold
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(user, nonce));

        bytes memory initData = abi.encodeWithSelector(
            SecureSmartWallet.initialize.selector,
            owners,
            guardians,
            threshold
        );

        bytes memory creationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(walletImplementation, initData)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(creationCode)
            )
        );

        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Dapatkan nonce berikutnya untuk user
     * @param user Alamat yang ingin dicek
     */
    function getNextNonce(address user) external view returns (uint256) {
        return userNonce[user];
    }
}