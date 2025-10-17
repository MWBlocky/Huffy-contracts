# Huffy Contracts

Smart contract suite for the Huffy DAO treasury management system on Hedera. This repository contains the core contracts for managing treasury funds, executing validated trades, and implementing buyback-and-burn mechanisms.

## Table of Contents

- [Overview](#overview)
- [Core Contracts](#core-contracts)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Deployment](#deployment)
- [Documentation](#documentation)

## Overview

The Huffy Contracts system implements a secure, DAO-controlled treasury with multi-layered validation for all trading operations. The architecture separates concerns between fund custody (Treasury), trade validation (Relay), and pair management (PairWhitelist).

### Key Features

 **DAO-Controlled Treasury** - Secure fund management with role-based access control    
 **Trade Validation Layer** - Multi-parameter risk checks before execution  
 **Pair Whitelisting** - Only approved trading pairs can be executed    
 **Position Size Limits** - Configurable maximum trade size as % of balance     
 **Slippage Protection** - Enforced maximum slippage tolerance  
 **Rate Limiting** - Cooldown periods between trades    
 **Buyback & Burn** - Automated HTK token buyback and burning   
 **Comprehensive Events** - Full transparency via detailed event logs

## Core Contracts

### Treasury.sol
Main contract holding DAO funds and executing trades. Only accepts execution commands from authorized Relay contract.   
Supports:
- Token deposits and DAO-controlled withdrawals
- Buyback-and-burn operations for HTK governance token
- Generic token swaps via Saucerswap DEX
- Role-based access control (DAO_ROLE, RELAY_ROLE)

### Relay.sol
Validation gateway enforcing DAO risk parameters before forwarding trades to Treasury:
- **Pair Whitelisting**: Validates against PairWhitelist contract
- **maxTradeBps**: Limits trade size (e.g., 10% of Treasury balance)
- **maxSlippageBps**: Enforces slippage tolerance (e.g., 5%)
- **tradeCooldownSec**: Rate limiting between trades
- **Trader Authorization**: Only allowlisted traders (e.g., HuffyPuppet) can submit

### PairWhitelist.sol
DAO-managed registry of approved trading pairs. Supports:
- Individual pair whitelisting/blacklisting
- Batch operations for multiple pairs
- Query interface for validation checks

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Hedera Testnet account with test HBAR
- RPC endpoint (e.g., HashIO, Arkhia)

### Installation

```bash
# Clone the repository
git clone https://github.com/Ariane-Labs/Huffy-contracts/
cd huffy-contracts

# Install dependencies
forge install

# Build contracts
forge build
```

### Environment Setup

Create a `.env` file in the project root from env.example and fill in the required variables.

## Testing

### Run All Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test contract
forge test --match-contract TreasuryTest
forge test --match-contract RelayTest

# Run with gas reporting
forge test --gas-report
```

### Test Coverage

```bash
forge coverage
```

## Deployment

### Option 1: Testing Environment (Mocks)

Deploy complete test environment with mock tokens and router:

```bash
forge script script/DeployMocks.s.sol:DeployMocks \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vv
```

This deploys:
- Mock HTK and USDC tokens
- Mock Saucerswap Router
- Mock DAO (admin)
- Treasury (with mocks)
- Mock Relay

### Option 2: Production Deployment

Deploy production Treasury with real tokens:

```bash
forge script script/Treasury.s.sol:DeployTreasury \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vv
```

### Deploy Relay System

1. Deploy PairWhitelist:
```bash
forge create src/PairWhitelist.sol:PairWhitelist \
  --constructor-args $DAO_ADMIN_ADDRESS \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $PRIVATE_KEY
```

2. Deploy Relay:
```bash
forge create src/Relay.sol:Relay \
  --constructor-args \
    $PAIR_WHITELIST_ADDRESS \
    $TREASURY_ADDRESS \
    $DAO_ADMIN_ADDRESS \
    $INITIAL_TRADER_ADDRESS \
    $MAX_TRADE_BPS \
    $MAX_SLIPPAGE_BPS \
    $TRADE_COOLDOWN_SEC \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $PRIVATE_KEY
```

3. Update Treasury to use new Relay:
```bash
cast send $TREASURY_ADDRESS "updateRelay(address,address)" \
  $OLD_RELAY_ADDRESS $NEW_RELAY_ADDRESS \
  --rpc-url $HEDERA_RPC_URL \
  --private-key $DAO_ADMIN_PRIVATE_KEY
```

## Documentation

Detailed guides for testing and operations:

### [TREASURY_TESTING.md](./TREASURY_TESTING.md)
Complete guide for deploying and testing the Treasury contract:
- Deployment instructions (mocks and production)
- Deposit and withdrawal operations
- Buyback-and-burn execution
- Generic swap operations
- Relay management
- Troubleshooting

### [RELAY_TESTING.md](./RELAY_TESTING.md)
Complete guide for deploying and testing the Relay system:
- Relay and PairWhitelist deployment
- Pair whitelisting operations
- Trade proposal workflows (swap and buyback)
- Risk parameter configuration (maxTradeBps, maxSlippageBps, cooldown)
- Trader authorization management
- Event monitoring
- Troubleshooting

## Support & Resources

- **Hedera Docs**: https://docs.hedera.com/
- **Saucerswap Docs**: https://docs.saucerswap.finance/
- **Foundry Book**: https://book.getfoundry.sh/
- **HashScan Explorer**: https://hashscan.io/

## License

MIT License
