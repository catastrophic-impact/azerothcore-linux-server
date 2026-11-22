-- Removes what this component's custom-sql files created. Run with:  custom-sql/apply.sh --remove timewalking -- <mysql arguments>
-- Stop the server first and delete the component's scripts (otherwise it is installed again on the next start), take a backup, then restart.
-- Timewalking CONTENT: the Dungeon Teleporter NPC (Chromie, entry 900001) and any spawn of her. The garrison's decor catalog also lists this NPC; without it that one item is simply not placeable.
USE acore_world;
DELETE ca FROM creature_addon ca JOIN creature c ON c.guid = ca.guid WHERE c.id = 900001;
DELETE FROM creature WHERE id = 900001;
DELETE FROM creature_template_model WHERE CreatureID = 900001;
DELETE FROM creature_template WHERE entry = 900001;
