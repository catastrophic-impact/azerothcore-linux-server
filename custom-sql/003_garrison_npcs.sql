-- Garrison NPCs (gossip-only copies of stock creatures, so the stock ones stay untouched). Idempotent.
--   900003 "Breanni - Menagerie"   (copy of Breanni 28951, pet supplies vendor -> gossip NPC)
--   900004 "Sig Nicious - Jukebox" (copy of Sig Nicious 23626, the Tauren Chieftains guitarist)
USE acore_world;
DELETE FROM creature_template WHERE entry IN (900003, 900004);
DELETE FROM creature_template_model WHERE CreatureID IN (900003, 900004);
DELETE FROM creature_template_addon WHERE entry IN (900003, 900004);

CREATE TEMPORARY TABLE tmp_m SELECT * FROM creature_template WHERE entry = 28951;
UPDATE tmp_m SET entry = 900003, subname = 'Menagerie', npcflag = 1, faction = 35, gossip_menu_id = 0, ScriptName = '', AIName = '', difficulty_entry_1 = 0;
INSERT INTO creature_template SELECT * FROM tmp_m;
DROP TEMPORARY TABLE tmp_m;

CREATE TEMPORARY TABLE tmp_j SELECT * FROM creature_template WHERE entry = 23626;
UPDATE tmp_j SET entry = 900004, subname = 'Jukebox', npcflag = 1, faction = 35, gossip_menu_id = 0, ScriptName = '', AIName = '', difficulty_entry_1 = 0;
INSERT INTO creature_template SELECT * FROM tmp_j;
DROP TEMPORARY TABLE tmp_j;

INSERT INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild)
  SELECT 900003, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = 28951;
INSERT INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild)
  SELECT 900004, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = 23626;
INSERT INTO creature_template_addon (entry, path_id, mount, bytes1, bytes2, emote, visibilityDistanceType, auras)
  SELECT 900003, path_id, mount, bytes1, bytes2, emote, visibilityDistanceType, auras FROM creature_template_addon WHERE entry = 28951;
INSERT INTO creature_template_addon (entry, path_id, mount, bytes1, bytes2, emote, visibilityDistanceType, auras)
  SELECT 900004, path_id, mount, bytes1, bytes2, emote, visibilityDistanceType, auras FROM creature_template_addon WHERE entry = 23626;
