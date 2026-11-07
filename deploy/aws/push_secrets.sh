#!/usr/bin/env bash
# Writes the town's secrets from the repo's root .env to the server, as /etc/dhaniverse/server.env and publisher.env (root
# only, mode 600). Only what the game server and the Arkiv publisher use: never DEPLOYER_KEY, ENS_ADMIN_KEY, NAMES_KEY, OPS_KEY
# or TEAM_KEY. Nothing is printed. Run from your machine after bootstrap.sh, and again whenever .env changes.
#
#   deploy/aws/push_secrets.sh <ssh key> <ssh target> <public host>
#   deploy/aws/push_secrets.sh dhaniverse.pem ec2-user@13.201.102.25 13-201-102-25.sslip.io
set -euo pipefail

KEY="${1:?ssh key}"; TARGET="${2:?ssh target}"; HOST="${3:?public host}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
set -a; source "$ROOT/.env" >/dev/null 2>&1; set +a

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
umask 077
# systemd EnvironmentFile lines: KEY="value"
put() { local v="${!1:-}"; [[ -n "$v" ]] || { echo "$1 is not set in .env" >&2; exit 1; }; printf '%s="%s"\n' "$1" "$v"; }

{
  put SEPOLIA_RPC_URL
  put KEEPER_KEY
  put TICKET_SIGNER_KEY
  put VOUCHER_SIGNER_KEY
  put GAS_STATION_KEY
  put WALLET_SEED
  put RP_SIGNING_KEY
  put WORLD_APP_ID
  put WORLD_RP_ID
  put WORLD_ENVIRONMENT
  echo "PUBLIC_URL=https://$HOST"
  echo "PUBLIC_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com"
  echo "PUBLISHER_URL=http://127.0.0.1:8787"
  # Player gas top-ups sized for today's Sepolia fees (about 0.05 gwei): 0.001 ETH covers about 20M gas.
  echo "CHAIN_GAS_FLOOR_WEI=200000000000000"
  echo "CHAIN_GAS_TOPUP_WEI=1000000000000000"
  echo "CHAIN_GAS_DAILY_CAP_WEI=5000000000000000"
} > "$tmp/server.env"

{
  put ARKIV_PRIVATE_KEY
  put ARKIV_ACCESS_KEY
  put DHANIVERSE_LOG_KEY
  put DHANIVERSE_RESTORE_TOKEN
  echo "ARKIV_CHAIN=${ARKIV_CHAIN:-rabdi}"
  echo "PUBLISHER_ENV=live"
  echo "SERVER_URL=http://127.0.0.1:7878"
  echo "SAVE_PATH=/var/lib/dhaniverse/town.jsonl"
  echo "PUBLISHER_STATE_DIR=/var/lib/dhaniverse/publisher"
  echo "PUBLISHER_HOST=127.0.0.1"
  echo "PUBLISHER_PORT=8787"
} > "$tmp/publisher.env"

scp -q -i "$KEY" "$tmp/server.env" "$tmp/publisher.env" "$TARGET:/tmp/"
ssh -i "$KEY" "$TARGET" 'set -e; for f in server.env publisher.env; do sudo install -m 600 -o root -g root /tmp/$f /etc/dhaniverse/$f; rm -f /tmp/$f; done; sudo systemctl try-restart dhaniverse-server dhaniverse-publisher'
echo "secrets written to $TARGET:/etc/dhaniverse (server.env, publisher.env)"
