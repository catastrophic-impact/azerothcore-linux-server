#!/bin/sh
# One-command deploy of the pet system WITHOUT restarting the server:  flatpak-spawn --host sh pet-battle/deploy.sh   (from the project root)
# 1 tests (stops on failure)  2 copy scripts  3 sync client addons  4 'reload ale' through the world console pipe  5 check the log for errors
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
REL="$ROOT/release"; LOG="$REL/logs/world.out"; PIPE="$REL/config/world.in"
ADDONS="${WOW_ADDONS:-$(cat "$ROOT/local/addons_path.txt" 2>/dev/null)}"   # your client Interface/AddOns folder: env WOW_ADDONS or the one-line file local/addons_path.txt (gitignored)
[ -n "$ADDONS" ] || { echo "set WOW_ADDONS or write the client AddOns path into local/addons_path.txt"; exit 1; }
sh pet-battle/run_tests.sh auto || { echo "NOT DEPLOYED: tests failed"; exit 1; }   # tier picked from the changed files; run `run_tests.sh full` before a commit
cp scripts/pb_*.lua scripts/shop_prime.lua scripts/shop_server.lua "$REL/lua_scripts/"
rm -f "$REL/lua_scripts/pb_world_test.lua" "$REL/lua_scripts/pb_fxlab.lua"
mkdir -p "$ADDONS/wotlk_pets" "$ADDONS/wotlk_petbattle"
cp -a addons/wotlk_pets/. "$ADDONS/wotlk_pets/"; cp -a addons/wotlk_petbattle/. "$ADDONS/wotlk_petbattle/"
[ -p "$PIPE" ] || { echo "world console pipe missing: is the world server running? (scripts and addons were copied, start the server)"; exit 1; }
before=$(grep -a -c "\[pb_battle\] loaded" "$LOG"); lines=$(wc -l < "$LOG")
echo "reload ale" > "$PIPE"
i=0; while [ $i -lt 20 ]; do
  [ "$(grep -a -c '\[pb_battle\] loaded' "$LOG")" -gt "$before" ] && break
  sleep 1; i=$((i+1))
done
[ "$(grep -a -c '\[pb_battle\] loaded' "$LOG")" -gt "$before" ] || { echo "RELOAD DID NOT HAPPEN (no new load line in 20 s)"; exit 1; }
sleep 1
new=$(tail -n +$((lines+1)) "$LOG" | grep -a -i "error\|traceback\|attempt to" || true)
if [ -n "$new" ]; then echo "SCRIPT ERRORS AFTER RELOAD:"; echo "$new"; exit 1; fi
echo "DEPLOYED: scripts reloaded live (no restart), client addons synced -> /reload in the client if an addon changed"
