#!/usr/bin/env bash
# Makes every wallet and secret Tallyport needs for Sepolia and Arkiv, and writes them to a private env file that git
# ignores. It never prints a private key: only the public addresses you have to fund.
#
#   tools/make_keys.sh            # writes .env.sepolia in the repo root (refuses to overwrite one)
#   source .env.sepolia           # in Git Bash, before deploying or starting the server
#
# Needs Foundry's `cast` (D:/foundry). World ID values are pasted into the file by hand afterwards (see the guide:
# docs/submission/keys_guide.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.env.sepolia}"
export PATH="/d/foundry:$PATH" HOME="${HOME:-/d/foundry/home}"

if [[ -e "$OUT" ]]; then
  echo "$OUT already exists. Keys aren't replaced: move it away first if you really want new ones." >&2
  exit 1
fi
command -v cast >/dev/null || { echo "cast (Foundry) not found: expected in /d/foundry" >&2; exit 1; }

umask 077
new_key() {   # prints "address private_key", nothing else: cast's readable text (with the key) goes to stderr, dropped
  cast wallet new 2>/dev/null | awk 'NF == 2 && $1 ~ /^0x/ {print $1, $2; exit}'
}
random32() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

declare -A ADDR KEY
for who in DEPLOYER KEEPER TICKET_SIGNER VOUCHER_SIGNER NAMES GAS_STATION OPS TEAM ARKIV; do
  read -r a k < <(new_key)
  [[ "$a" =~ ^0x[0-9a-fA-F]{40}$ && "$k" =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "cast gave an unexpected answer" >&2; exit 1; }
  ADDR[$who]=$a; KEY[$who]=$k
done
SEED="$(cast wallet new-mnemonic 2>/dev/null | awk 'f{print; exit} /^Phrase:/{f=1}' | xargs)"
[[ $(wc -w <<<"$SEED") -ge 12 ]] || { echo "couldn't read the mnemonic from cast" >&2; exit 1; }

cat >"$OUT" <<EOF
# Tallyport secrets for Sepolia and Arkiv. Made by tools/make_keys.sh on $(date -u +%Y-%m-%dT%H:%MZ).
# NEVER commit, share or paste this file anywhere. Load it in Git Bash with:  source .env.sepolia

# --- Ethereum Sepolia ---------------------------------------------------------------------------------------------
# A free public endpoint works; swap in an Alchemy/Infura URL if it's slow.
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
export RPC_URL=\$SEPOLIA_RPC_URL

# The deployer also owns the ENS name (tallyport.eth).
export DEPLOYER_KEY=${KEY[DEPLOYER]}
export ENS_ADMIN_KEY=${KEY[DEPLOYER]}
export ENS_ADMIN_ADDRESS=${ADDR[DEPLOYER]}

export KEEPER_KEY=${KEY[KEEPER]}
export KEEPER_ADDRESS=${ADDR[KEEPER]}
export TICKET_SIGNER_KEY=${KEY[TICKET_SIGNER]}
export TICKET_SIGNER_ADDRESS=${ADDR[TICKET_SIGNER]}
export VOUCHER_SIGNER_KEY=${KEY[VOUCHER_SIGNER]}
export VOUCHER_SIGNER_ADDRESS=${ADDR[VOUCHER_SIGNER]}
export NAMES_KEY=${KEY[NAMES]}
export GAS_STATION_KEY=${KEY[GAS_STATION]}
export OPS_ADDRESS=${ADDR[OPS]}
export OPS_KEY=${KEY[OPS]}
export TEAM_ADDRESS=${ADDR[TEAM]}
export TEAM_KEY=${KEY[TEAM]}

# Every player's wallet is derived from this phrase. Losing it loses access to all players' wallets.
export WALLET_SEED="$SEED"
# Any 32 random bytes, used once by the ENS setup (setUpCity, then registerCity).
export NAMES_SECRET=0x$(random32)

# --- World ID (paste from developer.world.org, see the guide) ------------------------------------------------------
export WORLD_APP_ID=
export WORLD_RP_ID=
export RP_SIGNING_KEY=
export WORLD_ENVIRONMENT=production

# --- Arkiv (Rabdi testnet) ------------------------------------------------------------------------------------------
export ARKIV_PRIVATE_KEY=${KEY[ARKIV]}
export ARKIV_WRITER_ADDRESS=${ADDR[ARKIV]}
export ARKIV_ACCESS_KEY=
export ARKIV_CHAIN=rabdi

# --- Swarm (optional, see the guide) --------------------------------------------------------------------------------
export BEE_URL=
export BEE_POSTAGE_BATCH=
EOF

cat <<EOF
Wrote $OUT (private keys inside; never share it).

Fund these on Sepolia (public addresses, safe to share):
  Deployer / ENS admin  ${ADDR[DEPLOYER]}   Sepolia ETH (~0.15) + test USDC (~18) + ENS fee token
  Keeper                ${ADDR[KEEPER]}   Sepolia ETH (~0.03)
  Names key             ${ADDR[NAMES]}   Sepolia ETH (~0.03)
  Gas station           ${ADDR[GAS_STATION]}   Sepolia ETH (~0.05): pays players' gas

Fund this on Arkiv Rabdi (tGLM from hub.arkiv.network/faucet):
  Arkiv writer          ${ADDR[ARKIV]}

Not funded (signers and payees only): ticket signer ${ADDR[TICKET_SIGNER]}, voucher signer ${ADDR[VOUCHER_SIGNER]},
ops ${ADDR[OPS]}, team ${ADDR[TEAM]}.
EOF
