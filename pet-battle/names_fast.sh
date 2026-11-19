#!/bin/sh
# FAST names loop (HOST, repo root): only the ability-visuals check (4 s) + rebuild (5 s) per pass; run the quick tier ONCE afterwards.  sh pet-battle/names_fast.sh [max passes]
N="${1:-40}"; O=pet-battle/.s/names_fast.out
for i in $(seq 1 "$N"); do
  luajit pet-battle/test_ability_vis.lua > "$O" 2>&1 && { echo "visual check green after $i pass(es)"; exit 0; }
  n=$(wc -l < pet-battle/ability_novis.txt); b=$(wc -l < pet-battle/ability_blocklist.txt)
  python3 -I pet-battle/tests_to_blocklist.py "$O" > /dev/null 2>&1
  [ "$n $b" = "$(wc -l < pet-battle/ability_novis.txt) $(wc -l < pet-battle/ability_blocklist.txt)" ] && { echo "nothing new learned at pass $i"; cat "$O"; exit 1; }
  sh pet-battle/rebuild_wild.sh > /dev/null 2>&1 || { echo "rebuild failed"; exit 1; }
done
echo "not green after $N passes"; exit 1
