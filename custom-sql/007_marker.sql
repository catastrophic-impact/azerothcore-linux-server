-- "Garrison Marker" (entry 900010): a Wisp copy (3681) used by scripts/garrison.lua to float a Hunter's-Mark arrow above the selected decor item.
-- Friendly, not attackable / not selectable, flying and rooted (it hovers where it is spawned). Idempotent (re-applied on every server start).
USE acore_world;
DELETE FROM creature_template WHERE entry = 900010;
DELETE FROM creature_template_model WHERE CreatureID = 900010;
DELETE FROM creature_template_movement WHERE CreatureId = 900010;
CREATE TEMPORARY TABLE tmp_marker SELECT * FROM creature_template WHERE entry = 3681;
UPDATE tmp_marker SET entry = 900010, name = 'Garrison Marker', subname = '', npcflag = 0, gossip_menu_id = 0, ScriptName = '', AIName = '',
  difficulty_entry_1 = 0, difficulty_entry_2 = 0, difficulty_entry_3 = 0, faction = 35, unit_flags = 33554434, flags_extra = 0, MovementType = 0, lootid = 0, mingold = 0, maxgold = 0;
INSERT INTO creature_template SELECT * FROM tmp_marker;
DROP TEMPORARY TABLE tmp_marker;
INSERT INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild)
  SELECT 900010, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = 3681;
INSERT INTO creature_template_movement (CreatureId, Ground, Swim, Flight, Rooted) VALUES (900010, 0, 0, 1, 1);
