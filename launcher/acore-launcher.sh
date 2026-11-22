#!/bin/sh
# AzerothCore Launcher: start the desktop launcher for THIS server folder. Lives at the top of the server folder, next to acore-admin.
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
L="$ROOT/launcher"
[ -x "$L/run.sh" ] || { echo "launcher/ is missing in $ROOT"; exit 1; }
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then echo "No desktop session found. Use the text admin instead:  $ROOT/acore-admin"; exit 1; fi
# a menu / desktop shortcut that stays inside this folder (rewritten each start, so moving the folder keeps it working)
cat > "$ROOT/AzerothCore Launcher.desktop" <<DESK 2>/dev/null
[Desktop Entry]
Type=Application
Name=AzerothCore Launcher
Comment=Manage this AzerothCore server and install its client addons
Exec="$ROOT/acore-launcher"
Path=$ROOT
Terminal=false
Categories=Game;
DESK
chmod +x "$ROOT/AzerothCore Launcher.desktop" 2>/dev/null
export ACORE_ROOT="$ROOT"
exec "$L/run.sh" "$@"
