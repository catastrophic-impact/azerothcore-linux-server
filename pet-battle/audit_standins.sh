#!/bin/sh
# Audit of the stand-in templates (9000000 + species) in the live world DB:  flatpak-spawn --host sh pet-battle/audit_standins.sh  (server DB must be up)
# Prints every stand-in that still has AI / script / flags / SmartAI rows / missing model rows / a non-35 faction / a type that blocks spells, and the species that lost equipment.
cd "$(dirname "$0")/../release" || exit 1
q() { ./acore-admin sql "$1" 2>&1 | grep -v '^$'; }
echo "== total stand-ins"; q "SELECT COUNT(*) FROM acore_world.creature_template WHERE entry BETWEEN 9000000 AND 9099999"
echo "== stand-ins with AI/script/flags/faction/type problems (expect none)"
q "SELECT entry,name,AIName,ScriptName,npcflag,unit_flags,unit_flags2,faction,type,flags_extra,VehicleId FROM acore_world.creature_template WHERE entry BETWEEN 9000000 AND 9099999 AND (AIName<>'' OR ScriptName<>'' OR npcflag<>0 OR unit_flags<>0 OR faction<>35 OR type IN (0,12) OR flags_extra<>0 OR VehicleId<>0)"
echo "== SmartAI rows on stand-ins (expect none)"
q "SELECT entryorguid,COUNT(*) FROM acore_world.smart_scripts WHERE source_type=0 AND entryorguid BETWEEN 9000000 AND 9099999 GROUP BY entryorguid"
echo "== stand-ins without model rows (expect none)"
q "SELECT t.entry,t.name FROM acore_world.creature_template t LEFT JOIN acore_world.creature_template_model m ON m.CreatureID=t.entry WHERE t.entry BETWEEN 9000000 AND 9099999 AND m.CreatureID IS NULL"
echo "== stand-ins whose model rows differ from the original (expect none)"
q "SELECT t.entry FROM acore_world.creature_template t WHERE t.entry BETWEEN 9000000 AND 9099999 AND (SELECT COUNT(*) FROM acore_world.creature_template_model WHERE CreatureID=t.entry) <> (SELECT COUNT(*) FROM acore_world.creature_template_model WHERE CreatureID=t.entry-9000000)"
echo "== originals that carry equipment (stand-ins have none: weapons/shields are not drawn)"
q "SELECT CreatureID,COUNT(*) n FROM acore_world.creature_equip_template WHERE CreatureID IN (SELECT entry-9000000 FROM acore_world.creature_template WHERE entry BETWEEN 9000000 AND 9099999) GROUP BY CreatureID"
