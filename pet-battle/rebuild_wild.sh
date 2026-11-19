#!/bin/sh
# Rebuild the composed Outland/Northrend kits and every generated file that depends on them (run on the HOST from the repo root):  sh pet-battle/rebuild_wild.sh
# Needs pet-battle/.s/{abil.json,cand2.json,ability_roles.tsv} (the retail ability filter output; see DEVNOTES) and zone_census.tsv (zone_census.py).
set -e
python3 -I pet-battle/mechanic_templates.py pet-battle/.s/abil.json pet-battle/.s/cand2.json pet-battle/.s/ability_roles.tsv > pet-battle/mechanic_templates.tsv
python3 -I pet-battle/mechanic_baseline.py > pet-battle/mechanic_baseline.tsv
python3 -I pet-battle/family_rules.py pet-battle/zone_census.tsv > pet-battle/family_assign.tsv
python3 -I pet-battle/assemble_kits.py pet-battle/.s/ability_roles.tsv > pet-battle/kits_prototype.tsv 2> pet-battle/.s/assemble.err
python3 -I pet-battle/wire_wild_kits.py > /dev/null
python3 -I pet-battle/gen_wild_kits.py scripts/pb_wild_kits.lua
python3 -I pet-battle/gen_zone_levels.py
luajit pet-battle/gen_pet_dex.lua
python3 -I pet-battle/gen_standins_sql.py
