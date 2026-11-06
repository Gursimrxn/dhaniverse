# Source this before any install, build or test: `source tools/env.sh`.
# C: has almost no free space, so every temp folder, package store and cache lives on D:.
# (Cargo and rustc write their temporary files to TEMP, so this covers them too.)
export TEMP='D:\DhaniverseData\Temp'
export TMP='D:\DhaniverseData\Temp'
export npm_config_store_dir='D:\.pnpm-store'
export npm_config_cache_dir='D:\pnpm-cache'
export npm_config_state_dir='D:\pnpm-state'
export npm_config_update_notifier=false
export NEXT_TELEMETRY_DISABLED=1
# Playwright drives the installed Edge (channel: 'msedge'); it never downloads a browser here.
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
mkdir -p /d/DhaniverseData/Temp /d/.pnpm-store /d/pnpm-cache /d/pnpm-state
