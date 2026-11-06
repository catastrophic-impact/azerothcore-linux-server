-- Generic "Chromie" gossip NPC (entry 900001): looks and is named like Chromie (10667), but has NO quests, no script, no
-- gossip menu of its own. Used as the dungeon teleporter (scripts/dungeon_teleporter.lua, acore_settings.lua).
-- Idempotent: re-applied by the admin TUI on every server start (survives DB restores / core updates).
USE acore_world;
DELETE FROM creature_template WHERE entry = 900001;
DELETE FROM creature_template_model WHERE CreatureID = 900001;
CREATE TEMPORARY TABLE tmp_chromie SELECT * FROM creature_template WHERE entry = 10667;
UPDATE tmp_chromie SET entry = 900001, npcflag = 1, gossip_menu_id = 0, ScriptName = '', AIName = '', difficulty_entry_1 = 0;
INSERT INTO creature_template SELECT * FROM tmp_chromie;
DROP TEMPORARY TABLE tmp_chromie;
INSERT INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild)
  SELECT 900001, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = 10667;
