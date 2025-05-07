// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISecureSmartWalletFactory {
    function deployWallet(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold
    ) external returns (address wallet);
    
    function predictWalletAddress(
        address[] calldata owners,
        address[] calldata guardians,
        uint256 guardianThreshold
    ) external view returns (address);
}