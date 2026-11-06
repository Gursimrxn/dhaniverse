#!/usr/bin/env bash
# Exports build/Dhaniverse.exe and puts the server and its rules beside it (the game starts the server itself).
# Run the client tests first (game/tests/run_tests.gd): the founder may be playing this build at any moment. Refuses while the game is open.
ROOT="/d/code/dhaniverse-eth-new"
if tasklist 2>/dev/null | grep -qi "^Dhaniverse.exe"; then echo "the game is running: not touching build/"; exit 1; fi
timeout 400 bash "$ROOT/tools/godot_d.sh" --path "$ROOT/game" --headless --export-release "Windows Desktop" ../build/Dhaniverse.exe 2>&1 | grep -E "ERROR|No export" | cut -c1-140
# A save a new server can't replay is the server's to move aside: the game starts it with --new-if-incompatible.
cp /d/pbuild/release/server.exe "$ROOT/build/dhaniverse-server.exe"
cp "$ROOT/server/rules.toml" "$ROOT/build/rules.toml"
ls -la --time-style=+%H:%M "$ROOT"/build/Dhaniverse.exe "$ROOT"/build/dhaniverse-server.exe "$ROOT"/build/rules.toml | cut -c24-
# Play.cmd keeps saves, logs and shader caches on D: (C: is full), then starts the game; the game starts the server.
printf '@echo off\r\nset "APPDATA=D:\DhaniverseData\Roaming"\r\nset "LOCALAPPDATA=D:\DhaniverseData\Local"\r\nset "TEMP=D:\DhaniverseData\Temp"\r\nset "TMP=D:\DhaniverseData\Temp"\r\nstart "" "%%~dp0Dhaniverse.exe"\r\n' > "$ROOT/build/Play.cmd"
