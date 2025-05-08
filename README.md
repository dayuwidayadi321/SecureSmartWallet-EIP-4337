# SecureSmartWallet - ERC-4337 Compatible Smart Wallet (v4.48.1)

![GitHub](https://img.shields.io/badge/Solidity-^0.8.19-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Standard](https://img.shields.io/badge/ERC--4337-Compatible-brightgreen)

A secure, upgradeable smart wallet implementation featuring multi-signature transactions, emergency recovery, and ERC-4337 Account Abstraction support.

## Key Features
- 🛡️ **Multi-Owner & Guardian System**  
- ⏳ **Scheduled/Delayed Transactions**  
- 🔄 **UUPS Upgradeable**  
- 🆘 **Emergency Recovery**  
- 🔐 **ERC-1271 Signature Validation**  
- ⛽ **ERC-4337 Gas Abstraction**  

## Prerequisites
- [Node.js](https://nodejs.org/) v16+
- [MetaMask](https://metamask.io/) (for deployment)
- Testnet ETH (for deployment)

## Smart Contract Structure

SecureSmartWallet/
├── contracts/               # Main Solidity contracts
│   ├── SecureSmartWallet.sol
│   ├── SecureSmartWalletBase.sol
│   ├── SecureSmartWalletSignatures.sol
│   ├── SecureSmartWalletEmergency.sol
│   └── dependencies/        # Optional for imported contracts
├── scripts/                 # Deployment scripts
├── test/                    # Test files
├── README.md                # Project documentation
└── .gitignore              # Git ignore file


## Deployment Guide (Using Remix IDE)

### 1. Prepare Contract Files
1. Open [Remix IDE](https://remix.ethereum.org/)
2. Upload all contract files to the `contracts` folder:
   - Main contracts (listed above)
   - Dependencies (`@openzeppelin`, `@account-abstraction`)

### 2. Compile Contracts
1. Go to the `Solidity Compiler` tab
2. Select compiler version `0.8.19`
3. Enable optimization (200 runs)
4. Click `Compile SecureSmartWallet.sol`

### 3. Deploy via UUPS Proxy
1. **Connect to Web3**:
   - Select `Injected Provider - MetaMask` in "Deploy & Run Transactions"
   - Choose your network (Testnet recommended first)

2. **Deploy Implementation**:
   - Select `SecureSmartWallet` contract
   - Click `Deploy` (constructor requires EntryPoint address)
     ```solidity
     constructor(IEntryPoint _entryPoint)
     ```
     *Default EntryPoint: `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`*

3. **Deploy Proxy**:
   - Install `OpenZeppelin Upgrades` plugin via Plugin Manager
   - Use `Deploy with Proxy` option
   - Enter implementation address
   - Initialize with parameters:
     ```javascript
     ["0xOwnerAddress"],  // Owners array
     ["0xGuardianAddress"], // Guardians array
     1                    // Guardian threshold
     ```

### 4. Verify on Etherscan
1. Get your proxy contract address
2. Verify using:
   - All contract files
   - Compiler settings matching Remix
   - Constructor arguments (ABI-encoded)

## Key Functions
| Function | Description |
|----------|-------------|
| `depositWithSignature()` | Deposit ETH with off-chain signature |
| `scheduleOperation()` | Schedule time-delayed transactions |
| `executeScheduledOperation()` | Execute pending operations |
| `isValidSignature()` | ERC-1271 signature validation |

## Security Considerations
1. Always test on testnets before mainnet deployment
2. Ensure proper guardian threshold configuration
3. Keep owner keys secure
4. Monitor scheduled operations

## Support
For issues or questions, please open a [GitHub Issue](https://github.com/your-repo/issues)

## License
MIT © 2023 DFXC Indonesian Security Web3 Project
