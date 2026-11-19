#!/bin/sh
# Spine re-roll loop (run on the HOST from the repo root): sh pet-battle/tune_loop.sh [iterations] [pairings]
# assemble kits (reads pet-battle/spine_salts.tsv) -> generate sandbox data -> skilled sweep -> rate spines, bump the salt of the outliers. Needs pet-battle/.s/ability_roles.tsv.
N="${1:-3}"; P="${2:-7000}"
for i in $(seq 1 "$N"); do
  sh pet-battle/rebuild_wild.sh > /dev/null 2>&1 || exit 1   # kits + every generated file, live data (scripts/pb_wild_kits.lua)
  luajit pet-battle/sim_skill_kits.lua "$P" 7 > pet-battle/.s/skill_it$i.txt 2>&1 || exit 1
  echo "== iteration $i" >> pet-battle/.s/tune_loop.log; grep -E "species rated|skilled win by family" pet-battle/.s/skill_it$i.txt >> pet-battle/.s/tune_loop.log
  python3 -I pet-battle/tune_spines.py 6 12 >> pet-battle/.s/tune_loop.log
done
echo "== done" >> pet-battle/.s/tune_loop.log
