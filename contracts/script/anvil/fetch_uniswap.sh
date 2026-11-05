#!/usr/bin/env bash
# Refreshes script/anvil/uniswap/*.hex: Uniswap v4's deployed runtime bytecode on Ethereum Sepolia, which
# script/dev_chain.sh places at the same addresses on anvil. Addresses: deployments/sepolia.config.json
# (source: https://docs.uniswap.org/contracts/v4/deployments). Needs SEPOLIA_RPC_URL (any public Sepolia RPC).
set -euo pipefail
cd "$(dirname "$0")/../.."
export HOME="${FOUNDRY_HOME_DIR:-/d/foundry/home}" PATH="/d/foundry:$PATH"
RPC="${SEPOLIA_RPC_URL:?set SEPOLIA_RPC_URL}"
CFG=deployments/sepolia.config.json
get() { python3 -c "import json,sys;print(json.load(open('$CFG'))['uniswap']['$1'])" 2>/dev/null || python -c "import json,sys;print(json.load(open('$CFG'))['uniswap']['$1'])"; }
for pair in PoolManager:poolManager PositionManager:positionManager UniversalRouter:universalRouter Permit2:permit2 StateView:stateView V4Quoter:quoter; do
  name="${pair%%:*}"; key="${pair##*:}"; addr="$(get "$key")"
  cast code "$addr" --rpc-url "$RPC" > "script/anvil/uniswap/$name.hex"
  echo "$name $addr $(wc -c < "script/anvil/uniswap/$name.hex") hex chars"
done
echo "PositionManager nextTokenId slot (expect 8): $(cast storage "$(get positionManager)" 8 --rpc-url "$RPC")"
