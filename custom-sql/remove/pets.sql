-- Removes what this component's custom-sql files created. Run with:  custom-sql/apply.sh --remove pets -- <mysql arguments>
-- Stop the server first and delete the component's scripts (otherwise it is installed again on the next start), take a backup, then restart.
-- Pet Battles CONTENT: the 3,400+ stand-in creature templates (entry 9000000 + species). Player data: see pets_playerdata.sql.
USE acore_world;
DELETE FROM creature_equip_template WHERE CreatureID BETWEEN 9000000 AND 9099999;
DELETE FROM creature_template_model WHERE CreatureID BETWEEN 9000000 AND 9099999;
DELETE FROM creature_template WHERE entry BETWEEN 9000000 AND 9099999;
