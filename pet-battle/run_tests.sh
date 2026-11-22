#!/bin/sh
# NOTE: engine-mechanics tests run with PB_LEGACY=1 (the original hand-picked retail kits as fixtures: Kobold Miner Rust, Cow Stampede ...); data/visual/QA tests run on the composed kits.
# Pet tests in TIERS (run from the project root: flatpak-spawn --host sh pet-battle/run_tests.sh [tier]):
#   ui      ~1 s   syntax + addon tests (journal, blips, layout, battle-addon smoke)         use after changing addons/ only
#   server  ~5 s   ui + store, wild spawns, API guard, world smoke                          use after changing pb_store / pb_wild / pb_battle / pb_cast
#   quick   ~35 s  server + the engine/data checks (abilities, auras, passives, presentation, data QA, visuals)   DEFAULT; use after pb_core / pb_data / pb_retail
#   full    ~2.5 min quick + the long simulations (600-battle fuzz, 1849-species presentation sim, QA sweep, label audit)   run before a commit, not after every edit
#   auto    picks ui / server / quick from the files that changed (deploy.sh uses it)
set -e
TIER="${1:-quick}"
if [ "$TIER" = auto ]; then
  changed=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) 2>/dev/null | sort -u)
  if echo "$changed" | grep -Eq 'scripts/pb_(core|data|retail|rules)\.lua|pet-battle/(test_abilities|test_presentation)'; then TIER=quick
  elif echo "$changed" | grep -Eq '^scripts/'; then TIER=server
  else TIER=ui; fi
  echo "[tests] tier auto -> $TIER"
fi
rank=1; case "$TIER" in ui) rank=1;; server) rank=2;; quick) rank=3;; full) rank=4;; *) echo "unknown tier $TIER"; exit 2;; esac
fail=0
for f in scripts/pb_data.lua scripts/pb_rules.lua scripts/pb_core.lua scripts/pb_retail.lua scripts/pb_vis.lua scripts/pb_store.lua scripts/acore_prime.lua scripts/acore_bus.lua scripts/pb_battle.lua scripts/pb_wild.lua scripts/pb_zone_species.lua pet-battle/lab/pb_fxlab.lua addons/wotlk_petbattle/Battle.lua addons/wotlk_pets/Pets.lua addons/wotlk_pets/WildBlips.lua; do
  luajit -bl "$f" >/dev/null || { echo "SYNTAX FAIL $f"; fail=1; }
done
[ $rank -ge 2 ] && { luajit pet-battle/test_store.lua || fail=1; }
[ $rank -ge 2 ] && { luajit pet-battle/test_rules.lua || fail=1; }
[ $rank -ge 2 ] && { luajit pet-battle/test_levels.lua || fail=1; }
[ $rank -ge 3 ] && { PB_LEGACY=1 luajit pet-battle/test_describe.lua || fail=1; }
[ $rank -ge 2 ] && { luajit pet-battle/test_levelup_wiring.lua || fail=1; }
[ $rank -ge 3 ] && { PB_LEGACY=1 luajit pet-battle/test_abilities.lua || fail=1; }
[ $rank -ge 3 ] && { PB_LEGACY=1 luajit pet-battle/test_passives.lua || fail=1; }
[ $rank -ge 3 ] && { PB_LEGACY=1 luajit pet-battle/test_auras.lua || fail=1; }
[ $rank -ge 3 ] && { PB_LEGACY=1 luajit pet-battle/test_presentation.lua || fail=1; }
[ $rank -ge 1 ] && { luajit pet-battle/test_ui_blips.lua || fail=1; }
[ $rank -ge 2 ] && { luajit pet-battle/test_api.lua || fail=1; }
[ $rank -ge 4 ] && { luajit pet-battle/sim_presentation.lua 3 || fail=1; }
[ $rank -ge 4 ] && { PB_LEGACY=1 luajit pet-battle/test_core.lua || fail=1; }
[ $rank -ge 3 ] && { luajit pet-battle/test_qa_data.lua || fail=1; }
[ $rank -ge 4 ] && { luajit pet-battle/sim_qa_sweep.lua 20 || fail=1; }
[ $rank -ge 2 ] && { luajit pet-battle/smoke_wild.lua || fail=1; }
[ $rank -ge 4 ] && { luajit pet-battle/audit_labels.lua 600 || fail=1; }
[ $rank -ge 3 ] && { luajit pet-battle/test_l1_kits.lua || fail=1; }
[ $rank -ge 3 ] && { luajit pet-battle/test_ability_vis.lua || fail=1; }
[ $rank -ge 1 ] && { luajit pet-battle/test_ui_pets.lua || fail=1; }
[ $rank -ge 1 ] && { luajit pet-battle/test_abilab.lua || fail=1; }   # the ability lab (.pblab) y/n handling
[ $rank -ge 2 ] && { luajit pet-battle/test_cast_retry.lua || fail=1; }   # pb_cast: a missed damaging spell is cast again
[ $rank -ge 1 ] && { sh pet-battle/check_ui_api.sh || fail=1; }
python3 -I pet-battle/check_fx.py >/dev/null || { echo "FX FAIL (non-instant visual spell)"; fail=1; }
for sd in 1 2 3 4 5 6 7 8; do   # real pb_store + engine + battle script, stubbed game API, played to the end incl. XP and recruit
  out=$(PB_LEGACY=1 SEED=$sd luajit pet-battle/smoke_world.lua 2>&1) || { echo "WORLD FAIL seed $sd"; echo "$out" | tail -6; fail=1; }
  echo "$out" | grep -q "^last:.*\(done|\|end|\)" || { echo "BATTLE DID NOT FINISH seed $sd"; fail=1; }
done
for sd in 1 2 3 4 5 6 7 8; do   # the same battles with a recording PB_CAST: self/target/aura/hit presentation modes run and are checked against the engine's act events
  out=$(PBCAST=1 PB_LEGACY=1 SEED=$sd luajit pet-battle/smoke_world.lua 2>&1) || { echo "PRESENTATION FAIL seed $sd"; echo "$out" | tail -6; fail=1; }
  echo "$out" | grep "presentation modes"
done
MSGS='pbt|begin|
pbt|st|P,1,10,1535,1535,Ability_Hunter_Pet_Wolf,3,299,29,Young Wolf
pbt|abil|1|Ability_Druid_Rake#Bite#A basic attack.#0
pbt|st|E,1,10,1535,1535,INV_Pick_02,2,257,54,Kobold Worker
pbt|in|P,1
pbt|tag|E|Bleed~Ability_Rogue_Rupture~3~2~1;Dodge 50%~Ability_Rogue_Feint~2~1~0
pbt|tag|P|
pbt|tag2|E|Frozen~Spell_Frost_Stun~1~1~1;
pbt|stip|Wild Magic#Adds up to 8 damage to every attack against the target.
pbt|info|E|Beast|Critter|Aquatic|Flying|Humanoid
pbt|eabil|1|Ability_Druid_Rake#Bite#100% hit chance. Bites.#0#0
pbt|eabil|2|Ability_Druid_Rake#Maul#Hits hard.#3#2
pbt|turn|go;0,2,3;1
pbt|turn|lock;0,0,0;0;Stampede: round 2 of 3
pbt|hp|E,1,1400,1535,-135
pbt|end|win
pbt|xp|Young Wolf,30,11,1
pbt|done|'
MSGS="$MSGS" luajit pet-battle/smoke_client.lua addons/wotlk_petbattle/Battle.lua | grep -q "ERROR\|NO HANDLER" && { echo "BATTLE ADDON FAIL"; fail=1; }
JMSGS='pbj|pet|721,10,0,1,1,1,Critter,Ability_Druid_Dash,1000,170,3,640,Rabbit
pbj|team|1,721,0,0
pbj|active|1
pbj|follow|721
pbj|done|'
MSGS="$JMSGS" luajit pet-battle/smoke_client.lua addons/wotlk_pets/Pets.lua | grep -q "ERROR\|NO HANDLER" && { echo "JOURNAL ADDON FAIL"; fail=1; }
SLASH=1 MSGS="" luajit pet-battle/smoke_client.lua addons/wotlk_petbattle/Battle.lua | grep -q "ERROR" && { echo "SLASH COMMAND FAIL"; fail=1; }
[ $fail = 0 ] && echo "ALL TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
