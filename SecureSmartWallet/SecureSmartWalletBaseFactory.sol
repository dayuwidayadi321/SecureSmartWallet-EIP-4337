// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./SecureSmartWallet.sol";
import "./SecureSmartWalletBase.sol";

contract SecureSmartWalletFactory {
    address public immutable walletImplementation;
    uint256 public immutable CHAIN_ID;
    
    // Mapping untuk mencegah duplikasi wallet dengan parameter sama
    mapping(bytes32 => address) public deployedWallets;
    
    event WalletDeployed(address indexed wallet, address[] owners, address[] guardians, uint256 threshold);
    event WalletDeploymentFailed(address[] owners, address[] guardians, uint256 threshold, string reason);
    
    constructor(address _implementation) {
        require(_implementation != address(0), "Factory: invalid implementation");
        walletImplementation = _implementation;
        CHAIN_ID = block.chainid;
    }
    
    /**
     * @dev Deploys a new SecureSmartWallet with given parameters
     */
    function deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold,
        bytes32 salt
    ) external returns (address wallet) {
        require(owners.length > 0, "Factory: no owners");
        require(guardians.length > 0, "Factory: no guardians");
        require(guardianThreshold > 0 && guardianThreshold <= guardians.length, "Factory: invalid threshold");
        
        bytes32 walletKey = _getWalletKey(owners, guardians, guardianThreshold, salt);
        require(deployedWallets[walletKey] == address(0), "Factory: wallet already deployed");
        
        try this._deployWallet(owners, guardians, guardianThreshold, salt) returns (address deployed) {
            wallet = deployed;
            deployedWallets[walletKey] = wallet;
            emit WalletDeployed(wallet, owners, guardians, guardianThreshold);
        } catch Error(string memory reason) {
            emit WalletDeploymentFailed(owners, guardians, guardianThreshold, reason);
            revert(reason);
        } catch {
            string memory reason = "Factory: deployment failed without reason";
            emit WalletDeploymentFailed(owners, guardians, guardianThreshold, reason);
            revert(reason);
        }
    }
    
    /**
     * @dev Internal function to deploy wallet using CREATE2
     */
    function _deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold,
        bytes32 salt
    ) external returns (address) {
        require(msg.sender == address(this), "Factory: internal only");
        
        bytes memory initData = abi.encodeWithSelector(
            SecureSmartWallet.initialize.selector,
            owners,
            guardians,
            guardianThreshold
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(
            walletImplementation,
            initData
        );
        
        // Set factory address on the new wallet
        SecureSmartWalletBase(address(proxy)).setFactory(address(this));
        
        return address(proxy);
    }
    
    /**
     * @dev Predicts wallet address for given parameters
     */
    function predictWalletAddress(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold,
        bytes32 salt
    ) external view returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            SecureSmartWallet.initialize.selector,
            owners,
            guardians,
            guardianThreshold
        );
        
        bytes memory creationCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(walletImplementation, initData)
        );
        
        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(creationCode)
        ));
        
        return address(uint160(uint256(hash)));
    }
    
    /**
     * @dev Generates unique key for wallet parameters
     */
    function _getWalletKey(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 threshold,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(owners)),
            keccak256(abi.encodePacked(guardians)),
            threshold,
            salt
        ));
    }
}

