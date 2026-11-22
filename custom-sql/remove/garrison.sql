-- Removes what this component's custom-sql files created. Run with:  custom-sql/apply.sh --remove garrison -- <mysql arguments>
-- Stop the server first and delete the component's scripts (otherwise it is installed again on the next start), take a backup, then restart.
-- Garrison CONTENT (templates, spawns, locations). Player data is NOT touched here: see garrison_playerdata.sql.
-- The Dungeon Teleporter NPC 900001 is shared with Timewalking and is left alone (remove it with: --remove timewalking).
USE acore_world;
-- placed spawns of our NPCs / objects (GM-placed with .npc add / .gobject add)
DELETE ca FROM creature_addon ca JOIN creature c ON c.guid = ca.guid WHERE c.id IN (900003, 900004, 900010) OR c.id BETWEEN 940001 AND 949999;
DELETE FROM creature WHERE id IN (900003, 900004, 900010) OR id BETWEEN 940001 AND 949999;
DELETE FROM gameobject WHERE guid IN (900100, 900101) OR id IN (900002, 900003) OR id BETWEEN 910000 AND 912595 OR id BETWEEN 920000 AND 920143 OR id BETWEEN 930000 AND 930099 OR id BETWEEN 940000 AND 940099 OR id BETWEEN 950001 AND 950118 OR id BETWEEN 960001 AND 969999 OR id = 970001;
-- templates
DELETE FROM creature_template_addon WHERE entry IN (900003, 900004);
DELETE FROM creature_template_movement WHERE CreatureId = 900010;
DELETE FROM creature_template_model WHERE CreatureID IN (900003, 900004, 900010) OR CreatureID BETWEEN 940001 AND 949999;
DELETE FROM creature_template WHERE entry IN (900003, 900004, 900010) OR entry BETWEEN 940001 AND 949999;
DELETE FROM gameobject_template WHERE entry IN (900002, 900003) OR entry BETWEEN 910000 AND 912595 OR entry BETWEEN 920000 AND 920143 OR entry BETWEEN 930000 AND 930099 OR entry BETWEEN 940000 AND 940099 OR entry BETWEEN 950001 AND 950118 OR entry BETWEEN 960001 AND 969999 OR entry = 970001;
-- 014_decor_types.sql changed the type of 113 existing stock gameobject templates; put them back (original values taken from the core's own base SQL)
UPDATE gameobject_template SET type = 5 WHERE entry IN (20811,20812,20816,20817,20818,20819,20820,20821,20822,20827);
UPDATE gameobject_template SET type = 14 WHERE entry IN (19009,19010,19029,19034,19039,19040,19041,19042,19043,19044,19045,19046,19048,19050,19060,19063,19064,19067,19086,19087,19088,19089,19095,19123,19135,19163,19165,19166,19167,19168,19169,19170,19171,19172,19173,19174,19176,19187,19199,19200,19201,19202,19207,19211,19212,19213,19214,19218,19221,19222,19225,19226,19227,19231,19235,19236,19237,19241,19242,19246,19250,19251,19252,19253,19257,19258,19259,19261,19262,19278,19279,19280,19281,19282,19285,19286,19287,19292,19296,19299,19309,19315,19316,19317,19318,19319,19320,19333,19337,19338,19339,19350,19351,19352,19359,19360,19361,19363,19366,19371,19372,19377,19388);
-- our own tables in the world database
DROP TABLE IF EXISTS dc_companion;
DROP TABLE IF EXISTS garrison_location_point;
DROP TABLE IF EXISTS garrison_location;
