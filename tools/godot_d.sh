#!/usr/bin/env bash
# Run Godot on the project with everything it writes kept on D: (C: is full): saves, settings, logs, shader and driver caches.
# Its window is kept off the screen (tools/godot_hidden.ps1) and never takes focus, because someone may be working at this machine;
# it still renders, so captures and bots work. Its log comes out here as it runs. Arguments go to Godot.  tools/godot_d.sh --path game --headless --import
export DATA='D:\DhaniverseData'
export APPDATA="$DATA\\Roaming" LOCALAPPDATA="$DATA\\Local" TEMP="$DATA\\Temp" TMP="$DATA\\Temp"
mkdir -p "/d/DhaniverseData/Roaming" "/d/DhaniverseData/Local" "/d/DhaniverseData/Temp"
GODOT="/d/code/Godot/Godot_v4.7.2-stable_win64.exe"
for a in "$@"; do [ "$a" = "--headless" ] && exec "$GODOT" "$@"; done

# One game at a time (GODOT_NO_LOCK=1 for a run that needs two): each takes about 1 GB, and with several at once Windows grows its
# swap file on D: until the disk is full. A holder that died without letting go is noticed by its pid.
LOCK="/d/DhaniverseData/Temp/godot.lock"
if [ -z "$GODOT_NO_LOCK" ]; then
  until mkdir "$LOCK" 2>/dev/null; do
    holder="$(cat "$LOCK/pid" 2>/dev/null)"
    [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null && rm -rf "$LOCK"
    sleep 2
  done
  echo $$ > "$LOCK/pid"
fi
unlock() { [ -z "$GODOT_NO_LOCK" ] && rm -rf "$LOCK"; }

# The game opens fullscreen for players (project.godot), and that beats --windowed and --position. A run from here brings its own
# window settings in the project's override.cfg for as long as it runs: windowed, far off the screen, never taking focus.
OVERRIDE="$(cd "$(dirname "$0")/.." && pwd)/game/override.cfg"
cat > "$OVERRIDE" <<'CFG'
[display]
window/size/mode=0
window/size/initial_position_type=0
window/size/initial_position=Vector2i(-32000, -32000)
window/size/no_focus=true
CFG
unoverride() { [ -z "$GODOT_NO_LOCK" ] && rm -f "$OVERRIDE"; }   # side-by-side runs leave it for the last one out

RUN="/d/DhaniverseData/Temp/godot_$$"
LOG="$RUN.log"
: > "$LOG"
export GODOT_EXE="$(cygpath -w "$GODOT")" GODOT_PID_FILE="$(cygpath -w "$RUN.pid")"
GODOT_ARGS="--windowed --position -3000,-3000 --audio-driver Dummy --log-file \"$(cygpath -m "$LOG")\""   # silent too: someone is at this machine
for a in "$@"; do case "$a" in /*) a="$(cygpath -m "$a")";; esac; GODOT_ARGS="$GODOT_ARGS \"$a\""; done   # bash only converts paths for what it starts itself
export GODOT_ARGS GODOT_W=1280 GODOT_H=720
prev=""; for a in "$@"; do [ "$prev" = "--resolution" ] && { GODOT_W="${a%x*}"; GODOT_H="${a#*x}"; }; prev="$a"; done
stop() { [ -f "$RUN.pid" ] && taskkill //F //PID "$(tr -d '\r\n' < "$RUN.pid")" > /dev/null 2>&1; }
trap 'stop; rm -f "$RUN.pid" "$LOG"; unoverride; unlock; exit 143' TERM INT
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$(dirname "$0")/godot_hidden.ps1")" &   # keeps the window off the screen
PS_PID=$!
tail -n +1 -f "$LOG" --pid=$PS_PID &
wait $PS_PID
CODE=$?
sleep 0.3
rm -f "$RUN.pid" "$LOG"
unoverride
unlock
exit $CODE
