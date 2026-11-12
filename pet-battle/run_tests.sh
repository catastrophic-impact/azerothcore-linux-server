#!/bin/sh
# Run BEFORE every deploy of the pet scripts/addons:  flatpak-spawn --host sh pet-battle/run_tests.sh   (from the project root)
set -e
fail=0
for f in scripts/pb_data.lua scripts/pb_rules.lua scripts/pb_core.lua scripts/pb_retail.lua scripts/pb_store.lua scripts/shop_prime.lua scripts/pb_battle.lua scripts/pb_wild.lua tools/pbtest/wotlk_pbtest/PBTest.lua addons/wotlk_pets/Pets.lua; do
  luajit -bl "$f" >/dev/null || { echo "SYNTAX FAIL $f"; fail=1; }
done
luajit pet-battle/test_store.lua || fail=1
luajit pet-battle/test_rules.lua || fail=1
luajit pet-battle/test_core.lua || fail=1
luajit pet-battle/smoke_wild.lua || fail=1
python3 -I pet-battle/check_fx.py >/dev/null || { echo "FX FAIL (non-instant visual spell)"; fail=1; }
for sd in 1 2 3 4 5 6 7 8; do   # real pb_store + engine + battle script, stubbed game API, played to the end incl. XP and recruit
  out=$(SEED=$sd luajit pet-battle/smoke_world.lua 2>&1) || { echo "WORLD FAIL seed $sd"; echo "$out" | tail -6; fail=1; }
  echo "$out" | grep -q "^last:.*\(done|\|end|\)" || { echo "BATTLE DID NOT FINISH seed $sd"; fail=1; }
done
MSGS='pbt|begin|
pbt|st|P,1,10,1535,1535,Ability_Hunter_Pet_Wolf,3,299,29,Young Wolf
pbt|abil|1|Ability_Druid_Rake#Bite#A basic attack.#0
pbt|st|E,1,10,1535,1535,INV_Pick_02,2,257,54,Kobold Worker
pbt|in|P,1
pbt|tag|E|Bleed~Ability_Rogue_Rupture~3~2~1;Dodge 50%~Ability_Rogue_Feint~2~1~0
pbt|tag|P|
pbt|turn|go;0,2,3;1
pbt|hp|E,1,1400,1535,-135
pbt|end|win
pbt|xp|Young Wolf,30,11,1
pbt|done|'
MSGS="$MSGS" luajit pet-battle/smoke_client.lua tools/pbtest/wotlk_pbtest/PBTest.lua | grep -q "ERROR\|NO HANDLER" && { echo "BATTLE ADDON FAIL"; fail=1; }
JMSGS='pbj|pet|721,10,0,1,1,1,Support,Ability_Druid_Dash,1000,170,3,640,Rabbit
pbj|team|1,721,0,0
pbj|active|1
pbj|follow|721
pbj|done|'
MSGS="$JMSGS" luajit pet-battle/smoke_client.lua addons/wotlk_pets/Pets.lua | grep -q "ERROR\|NO HANDLER" && { echo "JOURNAL ADDON FAIL"; fail=1; }
SLASH=1 MSGS="" luajit pet-battle/smoke_client.lua tools/pbtest/wotlk_pbtest/PBTest.lua | grep -q "ERROR" && { echo "SLASH COMMAND FAIL"; fail=1; }
[ $fail = 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
