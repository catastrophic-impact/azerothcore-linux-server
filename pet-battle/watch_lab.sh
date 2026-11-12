#!/bin/sh
# Run the presentation lab on the live server and screenshot the whole screen about 4 times a second (parallel spectacle jobs, staggered 0.25 s).
# Usage (project root):  flatpak-spawn --host sh pet-battle/watch_lab.sh "battle 10" 60      (second argument = SECONDS to capture)
# Frames: pet-battle/.shots/lab_NNNN.png. The WoW window must be visible. The user cannot see VS Code while in game: start and end are announced IN GAME,
# and the lab pets/battle are cleaned up at the end.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/pet-battle/.shots"; mkdir -p "$OUT"; rm -f "$OUT"/lab_*.png
PIPE="$ROOT/release/config/world.in"
echo "announce [Claude] Screen test starting in 5 seconds: stay in the game, pets will appear in front of you." > "$PIPE"; sleep 5
echo "${1:-run}" > "$ROOT/release/config/pbfx.trigger"
n=0; end=$(( $(date +%s) + ${2:-30} ))
while [ "$(date +%s)" -lt "$end" ]; do n=$((n+1)); spectacle -b -n -f -o "$OUT/lab_$(printf %04d $n).png" >/dev/null 2>&1 & sleep 0.25; done
wait
echo clean > "$ROOT/release/config/pbfx.trigger"; sleep 4
echo "announce [Claude] Test finished and cleaned up: you can go back to VS Code now." > "$PIPE"
echo "frames: $n"
