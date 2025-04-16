# Rebase Token Cross-Chain Vault System

This project implements a cross-chain rebase token system using Chainlink CCIP (Cross-Chain Interoperability Protocol). It allows users to deposit ETH into a vault to mint `RebaseToken` (RBT), a rebase token that accrues interest over time, and redeem RBT for ETH. The system supports cross-chain token transfers between Ethereum Sepolia and ZKsync Sepolia testnets, leveraging a custom `RebaseTokenPool` for token bridging.

## Overview

The project consists of the following core components:

- **RebaseToken.sol**: An ERC20 token with rebase functionality, where users accrue interest based on a per-second rate assigned at deposit. The global interest rate can only decrease, and each user retains their initial rate.
- **Vault.sol**: A contract that allows users to deposit ETH to mint RBT and redeem RBT for ETH. It interacts with `RebaseToken` for minting and burning.
- **RebaseTokenPool.sol**: A Chainlink CCIP-compatible token pool that facilitates cross-chain transfers by burning tokens on the source chain and minting them on the destination chain, preserving user-specific interest rates.
- **Deployment Scripts**:
  - `Deployer.s.sol`: Deploys `RebaseToken`, `RebaseTokenPool`, and `Vault` on Sepolia, setting up permissions.
  - `BridgeTokens.s.sol`: Bridges RBT from Sepolia to ZKsync Sepolia using CCIP.
  - `ConfigurePool.s.sol`: Configures the token pool for cross-chain interactions.
  - `bridgeToZksync.sh`: A bash script to automate deployment, configuration, and bridging.

## Prerequisites

- **Foundry**: For compiling, deploying, and testing smart contracts.
- **Node.js**: For managing dependencies and running scripts.
- **ZKsync CLI**: For compiling and deploying on ZKsync.
- **Environment Variables**:
  - `ZKSYNC_SEPOLIA_RPC_URL`: ZKsync Sepolia testnet RPC URL.
  - `ETH_SEPOLIA_RPC_URL`: Ethereum Sepolia testnet RPC URL.
  - `DEFAULT_ACCOUNT`: Account name for the deployer account.
- **Funds**: The deployer account must have ETH on Sepolia and ZKsync Sepolia, and LINK tokens on Sepolia for CCIP fees.
- **Chainlink CCIP Setup**: Familiarity with CCIP router, token admin registry, and network details for Sepolia and ZKsync Sepolia.

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd rebase-token-cross-chain
```

### 2. Install Dependencies

Install Foundry and ZKsync CLI if not already installed:

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install ZKsync CLI (if not already installed)
npm install -g @matterlabs/zksync-cli
```

Install project dependencies:

```bash
forge install
```

### 3. Set Up Environment Variables

Create a `.env` file in the project root with the following:

```bash
ZKSYNC_SEPOLIA_RPC_URL=<your-zksync-sepolia-rpc-url>
ETH_SEPOLIA_RPC_URL=<your-ethereum-sepolia-rpc-url>
DEFAULT_ACCOUNT=<your-account-name>
```

Source the environment variables:

```bash
source .env
```

### 4. Compile Contracts

Compile the smart contracts for both Ethereum and ZKsync:

```bash
forge build --zksync
```

### 5. Fund the Deployer Account

Ensure the `DEFAULT_ACCOUNT` has:

- ETH on Ethereum Sepolia for gas fees.
- ETH on ZKsync Sepolia for gas fees.
- LINK tokens on Sepolia (address: `0x779877A7B0D9E8603169DdbD7836e478b4624789`) for CCIP fees.

You can obtain testnet ETH and LINK from faucets like [Sepolia Faucet](https://sepolia.dev/) or Chainlink's CCIP faucet.

## Usage

### 1. Deploy and Bridge Tokens

Run the `bridgeToZksync.sh` script to:

- Deploy `RebaseToken` and `RebaseTokenPool` on ZKsync Sepolia.
- Deploy `RebaseToken`, `RebaseTokenPool`, and `Vault` on Ethereum Sepolia.
- Configure pools for cross-chain transfers.
- Deposit ETH into the vault to mint RBT.
- Bridge 100,000 RBT from Sepolia to ZKsync Sepolia.

```bash
chmod +x bridgeToZksync.sh
./bridgeToZksync.sh
```

The script outputs key addresses and balances:

- ZKsync: `ZKSYNC_REBASE_TOKEN_ADDRESS`, `ZKSYNC_POOL_ADDRESS`.
- Sepolia: `SEPOLIA_REBASE_TOKEN_ADDRESS`, `SEPOLIA_POOL_ADDRESS`, `VAULT_ADDRESS`.
- Balances before and after bridging on Sepolia.

### 2. Interact with the Vault

- **Deposit ETH**: Send ETH to the `Vault` contract on Sepolia to mint RBT:

  ```bash
  cast send <VAULT_ADDRESS> --value <amount-in-wei> --rpc-url $ETH_SEPOLIA_RPC_URL --account $DEFAULT_ACCOUNT
  ```

  Example: Deposit 0.01 ETH:

  ```bash
  cast send <VAULT_ADDRESS> --value 10000000000000000 --rpc-url $ETH_SEPOLIA_RPC_URL --account $DEFAULT_ACCOUNT
  ```

- **Redeem RBT**: Call the `redeem` function to burn RBT and withdraw ETH:
  ```bash
  cast send <VAULT_ADDRESS> "redeem(uint256)" <amount> --rpc-url $ETH_SEPOLIA_RPC_URL --account $DEFAULT_ACCOUNT
  ```
  Example: Redeem 100,000 RBT:
  ```bash
  cast send <VAULT_ADDRESS> "redeem(uint256)" 100000 --rpc-url $ETH_SEPOLIA_RPC_URL --account $DEFAULT_ACCOUNT
  ```

### 3. Check Balances and Interest

- **Check RBT Balance (with Interest)**:
  ```bash
  cast call <SEPOLIA_REBASE_TOKEN_ADDRESS> "balanceOf(address)(uint256)" <user-address> --rpc-url $ETH_SEPOLIA_RPC_URL
  ```
- **Check Principal Balance (without Interest)**:
  ```bash
  cast call <SEPOLIA_REBASE_TOKEN_ADDRESS> "principalBalanceOf(address)(uint256)" <user-address> --rpc-url $ETH_SEPOLIA_RPC_URL
  ```
- **Check User Interest Rate**:
  ```bash
  cast call <SEPOLIA_REBASE_TOKEN_ADDRESS> "getUserInterestRate(address)(uint256)" <user-address> --rpc-url $ETH_SEPOLIA_RPC_URL
  ```

### 4. Verify Cross-Chain Transfer

After bridging, check the receiver’s RBT balance on ZKsync Sepolia:

```bash
cast call <ZKSYNC_REBASE_TOKEN_ADDRESS> "balanceOf(address)(uint256)" <receiver-address> --rpc-url $ZKSYNC_SEPOLIA_RPC_URL
```

## Notes

- **Security**: The contracts are deployed on testnets. For production, conduct thorough audits and testing.
- **Gas Fees**: Ensure sufficient ETH for gas on both networks. LINK tokens are required for CCIP fees on Sepolia.
- **ZKsync Compatibility**: Contracts are compiled with `--zksync` to ensure compatibility with ZKsync’s EraVM.
- **Troubleshooting**: If the script fails, check the console output for errors (e.g., insufficient funds, invalid addresses). Verify environment variables and network connectivity.

## License

This project is licensed under the MIT License. See the SPDX-License-Identifier in each contract for details.
