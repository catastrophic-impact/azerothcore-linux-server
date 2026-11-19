#!/bin/sh
# names loop for the GOLDEN pipeline (HOST, repo root): visual-name check -> novis names -> regenerate kits file only (no refit needed)
for i in $(seq 1 ${1:-15}); do
  luajit pet-battle/test_ability_vis.lua > pet-battle/.s/names_fast.out 2>&1 && { echo "green after $i pass(es)"; exit 0; }
  n=$(wc -l < pet-battle/ability_novis.txt)
  python3 -I pet-battle/tests_to_blocklist.py pet-battle/.s/names_fast.out > /dev/null 2>&1
  [ "$n" = "$(wc -l < pet-battle/ability_novis.txt)" ] && { echo "nothing new learned"; cat pet-battle/.s/names_fast.out | tail -3; exit 1; }
  python3 -I pet-battle/gen_wild_kits.py scripts/pb_wild_kits.lua > /dev/null || exit 1
done
