#!/bin/bash
# Deploy GLADIATOR on Monad testnet
# Usage: ./deploy_monad.sh
# Prerequisites: 
#   1. Foundry installed (curl -L https://foundry.paradigm.xyz | bash && foundryup)
#   2. Testnet MON from https://faucet.quicknode.com/monad/testnet (needs tweet)
#   3. Set PRIVATE_KEY env var with your Monad testnet wallet

set -e

export PATH="$HOME/.foundry/bin:$PATH"

MONAD_RPC="https://testnet-rpc.monad.xyz"
CHAIN_ID=10143

if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: Set PRIVATE_KEY env var"
    echo "  export PRIVATE_KEY=0x..."
    echo "  Get testnet MON from https://faucet.quicknode.com/monad/testnet"
    exit 1
fi

# Check balance
BAL=$(cast balance --rpc-url $MONAD_RPC $(cast wallet address $PRIVATE_KEY) 2>/dev/null || echo "0")
echo "Wallet balance: $BAL"
if [ "$BAL" = "0" ]; then
    echo "ERROR: No MON balance. Get testnet tokens from:"
    echo "  https://faucet.quicknode.com/monad/testnet"
    exit 1
fi

echo "Deploying GLADIATOR on Monad testnet (Chain ID $CHAIN_ID)..."
echo ""

cd /tmp/gladiator
forge build
forge script script/Deploy.s.sol \
    --rpc-url $MONAD_RPC \
    --broadcast \
    --chain-id $CHAIN_ID

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo "Update frontend/index.html with the deployed contract addresses"