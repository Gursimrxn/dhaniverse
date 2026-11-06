#!/usr/bin/env bash
# What each part of the world costs the GPU, in fixed views: every view once with everything, then once with each part left out.
# Run it with nothing else busy; other work on the machine changes the numbers.  tools/perf.sh [1920x1080] [off,lists,...]
RES="${1:-1920x1080}"
ROOT="/d/code/dhaniverse-eth"
# name:eye x,y,z,target x,y,z
VIEWS=("square:-27,3,-20,-27,1,10" "stall:-16,3.5,-33,-16,1,-24" "landing:-112,2,49,-92,1,48" "bank:-27,2.5,11,-27,1.5,22")
shots=""
run() {
  timeout 90 bash "$ROOT/tools/godot_d.sh" --path "$ROOT/game" --resolution "$RES" -- --mode=day --player=perfbot --server-url=ws://127.0.0.1:29999 \
    --snap=D:/DhaniverseData/Temp/perf.png --cam="$2" ${3:+--off=$3} 2>&1 | grep -E "^snap:" | sed -E 's/, time.*//'
}
for v in "${VIEWS[@]}"; do
  name="${v%%:*}"; cam="${v#*:}"
  echo "$name all: $(run "$name" "$cam")"
  for off in ${2:-grass trees water post shadows street}; do
    echo "$name -$off: $(run "$name" "$cam" "$off")"
  done
done
rm -f /d/DhaniverseData/Temp/perf.png
