#!/usr/bin/env bash
# Tallyport's local chain: starts anvil (state kept on D:), places Uniswap v4 at its Sepolia addresses with Uniswap's
# own Sepolia bytecode (script/anvil/uniswap/*.hex), deploys everything with script/Deploy.s.sol, writes
# deployments/anvil.json, and prints the environment the server needs. Then keeps anvil running (Ctrl-C stops it;
# the chain state is saved and reloaded next time).
#
#   script/dev_chain.sh            start (reuses the saved chain if there is one)
#   RESET=1 script/dev_chain.sh    throw the saved chain away and deploy fresh
#
# Keys are anvil's public development keys (mnemonic "test test ... junk"). They are for this local chain only:
# never fund them anywhere real.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME="${FOUNDRY_HOME_DIR:-/d/foundry/home}" PATH="/d/foundry:$PATH"

PORT="${ANVIL_PORT:-8545}"
RPC="http://127.0.0.1:$PORT"
STATE_DIR="${ANVIL_STATE_DIR:-$PWD/.anvil}"
STATE="$STATE_DIR/state.json"
BLOCK_TIME="${BLOCK_TIME:-2}"
MNEMONIC="test test test test test test test test test test test junk"
mkdir -p "$STATE_DIR"
if [[ "${RESET:-0}" == "1" ]]; then rm -f "$STATE" deployments/anvil.json; fi

key() { cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index "$1"; }
addr() { cast wallet address --private-key "$1"; }
DEPLOYER_KEY="$(key 0)"; KEEPER_KEY="$(key 1)"; TICKET_SIGNER_KEY="$(key 2)"; VOUCHER_SIGNER_KEY="$(key 3)"
OPS_ADDRESS="$(addr "$(key 4)")"; TEAM_ADDRESS="$(addr "$(key 5)")"; GAS_STATION_KEY="$(key 6)"; NAMES_KEY="$(key 7)"

FRESH=1
[[ -f "$STATE" && -f deployments/anvil.json ]] && FRESH=0
# Player wallets come from their own seed (never the dev keys above), made once per local chain.
PLAYER_SEED_FILE="$STATE_DIR/players.mnemonic"
if [[ "$FRESH" == "1" || ! -f "$PLAYER_SEED_FILE" ]]; then
  cast wallet new-mnemonic --words 12 | awk 'f {print; exit} /^Phrase:/ {f = 1}' > "$PLAYER_SEED_FILE"
fi

# Automine while deploying (fast); interval mining afterwards, so blocks keep coming (LuckyLedger needs them).
anvil --port "$PORT" --chain-id 31337 --mnemonic "$MNEMONIC" --state "$STATE" --state-interval 30 \
  > "$STATE_DIR/anvil.log" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 60); do cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 0.5; done
cast chain-id --rpc-url "$RPC" >/dev/null || { echo "anvil didn't start; see $STATE_DIR/anvil.log"; exit 1; }

if [[ "$FRESH" == "1" ]]; then
  echo "Placing Uniswap v4 (Sepolia bytecode) at its Sepolia addresses..."
  # (Sent as a JSON-RPC body from a file: the bytecode is too long for a Windows command line.)
  setcode() {
    local body="$STATE_DIR/setcode.json"
    printf '{"jsonrpc":"2.0","id":1,"method":"anvil_setCode","params":["%s","%s"]}'       "$1" "$(tr -d '[:space:]' < "script/anvil/uniswap/$2.hex")" > "$body"
    curl -sf -X POST -H 'content-type: application/json' --data @"$body" "$RPC" | grep -q '"result"'       || { echo "anvil_setCode failed for $2"; exit 1; }
  }
  setcode 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 PoolManager
  setcode 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4 PositionManager
  setcode 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b UniversalRouter
  setcode 0x000000000022D473030F116dDEE9F6B43aC78BA3 Permit2
  setcode 0xe1dd9c3fa50edb962e442f60dfbc432e24537e4c StateView
  setcode 0x68aFa8b853cAa7a2D40B0F6AEE5C4DbC147C8244 V4Quoter
  # PositionManager's constructor-set storage: ERC-721 name, symbol, nextTokenId = 1 (see UniswapOnAnvil.sol).
  POSM=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
  cast rpc anvil_setStorageAt $POSM 0x0 0x556e697377617020763420506f736974696f6e73204e46540000000000000030 --rpc-url "$RPC" >/dev/null
  cast rpc anvil_setStorageAt $POSM 0x1 0x554e492d56342d504f534d000000000000000000000000000000000000000016 --rpc-url "$RPC" >/dev/null
  cast rpc anvil_setStorageAt $POSM 0x8 0x0000000000000000000000000000000000000000000000000000000000000001 --rpc-url "$RPC" >/dev/null

  echo "Deploying Tallyport..."
  DEPLOYER_KEY="$DEPLOYER_KEY" KEEPER_ADDRESS="$(addr "$KEEPER_KEY")" \
  TICKET_SIGNER_ADDRESS="$(addr "$TICKET_SIGNER_KEY")" VOUCHER_SIGNER_ADDRESS="$(addr "$VOUCHER_SIGNER_KEY")" \
  OPS_ADDRESS="$OPS_ADDRESS" TEAM_ADDRESS="$TEAM_ADDRESS" NETWORK=anvil \
    forge script script/Deploy.s.sol --rpc-url "$RPC" --broadcast --slow -q
  cast rpc anvil_dumpState --rpc-url "$RPC" >/dev/null # the state file is also written every 30 s and on exit
else
  echo "Reusing the saved chain in $STATE (RESET=1 to start over)."
fi
cast rpc evm_setIntervalMining "$BLOCK_TIME" --rpc-url "$RPC" >/dev/null

cat <<ENV

# ---- Tallyport server environment (anvil; local development keys only) ----
export CHAIN_MODE=anvil
export RPC_URL=$RPC
export CHAIN_ID=31337
export DEPLOYMENTS=$PWD/deployments/anvil.json
export KEEPER_KEY=$KEEPER_KEY
export TICKET_SIGNER_KEY=$TICKET_SIGNER_KEY
export VOUCHER_SIGNER_KEY=$VOUCHER_SIGNER_KEY
export GAS_STATION_KEY=$GAS_STATION_KEY
export NAMES_KEY=$NAMES_KEY
export WALLET_SEED="$(cat "$PLAYER_SEED_FILE")"
# MockUSDC: anyone may mint on anvil, e.g.
#   cast send \$(jq -r .usdc deployments/anvil.json) "mint(address,uint256)" <player> 5000000 --private-key \$GAS_STATION_KEY --rpc-url $RPC
# ---------------------------------------------------------------------------
ENV
echo "anvil is running on $RPC (pid $ANVIL_PID, $BLOCK_TIME s blocks). Ctrl-C to stop."
wait $ANVIL_PID
