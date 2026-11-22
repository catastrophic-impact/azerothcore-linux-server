#!/bin/sh
# Start the launcher. PORTABLE: everything (Electron profile, cache, settings) stays inside this folder (launcher/data); the XDG variables are
# pointed here too, so nothing lands in the user's home or ~/.config. The launcher does not start the WoW client.
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$HERE" || exit 1
EL="$HERE/electron/electron"                       # installed layout: portable runtime fetched by the installer (fetch-electron.sh)
[ -x "$EL" ] || EL="$HERE/node_modules/.bin/electron"   # dev checkout: ./setup.sh
[ -x "$EL" ] || { echo "Electron is not installed yet: run ./fetch-electron.sh (no Node needed) in this folder first."; exit 1; }
mkdir -p "$HERE/data/xdg/config" "$HERE/data/xdg/cache" "$HERE/data/xdg/data" "$HERE/data/xdg/state"
export XDG_CONFIG_HOME="$HERE/data/xdg/config" XDG_CACHE_HOME="$HERE/data/xdg/cache" XDG_DATA_HOME="$HERE/data/xdg/data" XDG_STATE_HOME="$HERE/data/xdg/state"
# --no-sandbox: Linux Electron needs a setuid helper for its Chromium sandbox, which a portable folder cannot have. The window only ever loads
# the launcher's own local files (no web content), so this is acceptable here.
exec "$EL" . --no-sandbox "$@"
