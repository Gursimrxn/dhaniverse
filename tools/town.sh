#!/usr/bin/env bash
# The live town on this machine, on Ethereum Sepolia: the game server, the Arkiv publisher (env "live") and the browser game.
# Everything it writes stays in live/ (git-ignored). Secrets come from the root .env; the publisher's from services/publisher/.env.
#
#   tools/town.sh start    start all three (the game at http://localhost:8060)
#   tools/town.sh stop     stop them
#   tools/town.sh status   what's running, and the server's health
#   tools/town.sh logs     follow the server and publisher logs
#   tools/town.sh reset    stop, archive this town in live/archive/, begin a new city (wallets are never handed out twice)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE="$ROOT/live"
SAVE="$LIVE/town.jsonl"
CHAIN_DIR="$LIVE/town.chain-sepolia"   # the server names it after the save, without the .jsonl
mkdir -p "$LIVE/logs"

running() { [[ -f "$LIVE/$1.pid" ]] && kill -0 "$(cat "$LIVE/$1.pid")" 2>/dev/null; }

node24() {
  if node --version 2>/dev/null | grep -q '^v24\.'; then command -v node; return; fi
  # shellcheck disable=SC1091
  [[ -s "$HOME/.nvm/nvm.sh" ]] && . "$HOME/.nvm/nvm.sh" >/dev/null && nvm which 24 2>/dev/null && return
  echo "the publisher needs Node 24 (nvm install 24)" >&2; exit 1
}

start_server() {
  running server && { echo "server: already running"; return; }
  local bin="$ROOT/server/target/release/tallyport"
  [[ -x "$bin" ]] || { echo "build it first: (cd server && cargo build --release -p tallyport)"; exit 1; }
  (
    cd "$ROOT/server"
    set -a; source "$ROOT/.env" >/dev/null 2>&1; set +a
    unset NAMES_KEY DEPLOYER_KEY ENS_ADMIN_KEY OPS_KEY TEAM_KEY   # ENS is off; the server never deploys or spends team money
    export CHAIN_GAS_FLOOR_WEI=200000000000000 CHAIN_GAS_TOPUP_WEI=1000000000000000 CHAIN_GAS_DAILY_CAP_WEI=5000000000000000
    export PUBLISHER_URL=http://127.0.0.1:8787
    nohup "$bin" --chain sepolia --save "$SAVE" --new-if-incompatible >> "$LIVE/logs/server.log" 2>&1 &
    echo $! > "$LIVE/server.pid"
  )
  for _ in $(seq 1 30); do curl -s -m 2 http://127.0.0.1:7878/health >/dev/null && break; sleep 1; done
  echo "server: $(curl -s -m 3 http://127.0.0.1:7878/health || echo 'not answering yet: tools/town.sh logs')"
}

start_publisher() {
  running publisher && { echo "publisher: already running"; return; }
  local node; node="$(node24)"
  (
    cd "$ROOT/services/publisher"
    nohup "$node" --env-file-if-exists=.env src/main.ts >> "$LIVE/logs/publisher.log" 2>&1 < /dev/null &
    echo $! > "$LIVE/publisher.pid"      # node's own id (backgrounding `cd && node` would record a wrapper shell instead)
  )
  echo "publisher: started (Arkiv, env live)"
}

start_game() {
  running game && { echo "game: already serving"; return; }
  [[ -f "$ROOT/build/web/index.html" ]] || { echo "game: no web build in build/web (export it from Godot)"; return; }
  nohup python3 -m http.server 8060 --bind 127.0.0.1 --directory "$ROOT/build/web" >> "$LIVE/logs/game.log" 2>&1 &
  echo $! > "$LIVE/game.pid"
  echo "game: http://localhost:8060"
}

stop_one() {
  if running "$1"; then kill "$(cat "$LIVE/$1.pid")" && echo "$1: stopped"; else echo "$1: not running"; fi
  rm -f "$LIVE/$1.pid"
}

case "${1:-status}" in
  start) start_server; start_publisher; start_game ;;
  stop) stop_one game; stop_one publisher; stop_one server ;;
  status)
    for p in server publisher game; do printf '%-10s %s\n' "$p" "$(running "$p" && echo running || echo stopped)"; done
    echo "health:    $(curl -s -m 3 http://127.0.0.1:7878/health || echo 'no answer')"
    echo "arkiv:     $(curl -s -m 5 http://127.0.0.1:8787/health | head -c 300 || echo 'no answer')" ;;
  logs) tail -n 40 -f "$LIVE/logs/server.log" "$LIVE/logs/publisher.log" ;;
  reset)
    "$0" stop
    old="$LIVE/archive/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$old"
    for f in "$SAVE" "$CHAIN_DIR" "$LIVE/publisher"; do [[ -e "$f" ]] && mv "$f" "$old/"; done
    # Player wallets come from one seed, by index: the new town carries on the old one's list, so it never hands a new player
    # an old player's wallet (and whatever is still in it).
    # Each old wallet stays reserved under an archived name, so a player who signs up again under the same name gets a new,
    # empty wallet: a fresh account, not the old one.
    if [[ -f "$old/$(basename "$CHAIN_DIR")/wallets.jsonl" ]]; then
      mkdir -p "$CHAIN_DIR"
      sed -E "s/\"player\":\"([^\"]*)\"/\"player\":\"archived-$(basename "$old")-\1\"/" \
        "$old/$(basename "$CHAIN_DIR")/wallets.jsonl" > "$CHAIN_DIR/wallets.jsonl"
    fi
    echo "the old town is archived in $old; tools/town.sh start begins a new one" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
