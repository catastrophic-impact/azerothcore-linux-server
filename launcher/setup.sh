#!/bin/sh
# One-time setup: install Electron INTO this folder (node_modules). Needs node + npm (the installer's build box has them, or install them on the host).
# Nothing is written outside this folder: npm's cache and config are redirected here as well.
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$HERE" || exit 1
command -v npm >/dev/null || { echo "npm not found: install Node.js 20+ (or run this inside a distrobox that has it)."; exit 1; }
mkdir -p "$HERE/data/npm-cache" "$HERE/data/xdg/config" "$HERE/data/xdg/cache"
export npm_config_cache="$HERE/data/npm-cache" npm_config_userconfig="$HERE/data/npmrc" npm_config_update_notifier=false
export XDG_CONFIG_HOME="$HERE/data/xdg/config" XDG_CACHE_HOME="$HERE/data/xdg/cache" ELECTRON_CACHE="$HERE/data/electron-download"
npm install --no-audit --no-fund || exit 1
# some npm setups skip install scripts: make sure the Electron binary itself is downloaded (into this folder, via ELECTRON_CACHE)
[ -f node_modules/electron/dist/electron ] || node node_modules/electron/install.js || exit 1
[ -f node_modules/electron/dist/electron ] && echo "done: start the launcher with ./run.sh"
