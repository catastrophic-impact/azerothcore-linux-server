-- Garrison PLAYER DATA: every player's garrison, placed decor, settings and the curation edits. NOT UNDOABLE: take a backup first.
-- Run with:  custom-sql/apply.sh --remove-data garrison --yes -- <mysql arguments>      (stop the server and delete the scripts first)
USE acore_characters;
-- anyone who logged out inside a garrison would otherwise wake up at the garrison's coordinates in the normal world: send them to their hearthstone location
UPDATE characters c JOIN dc_garrison_logout l ON l.guid = c.guid JOIN character_homebind h ON h.guid = c.guid
   SET c.map = h.mapId, c.zone = h.zoneId, c.position_x = h.posX, c.position_y = h.posY, c.position_z = h.posZ WHERE c.online = 0;
DROP TABLE IF EXISTS dc_garrison_object;
DROP TABLE IF EXISTS dc_garrison_location;
DROP TABLE IF EXISTS dc_garrison_logout;
DROP TABLE IF EXISTS dc_garrison_spawn;
DROP TABLE IF EXISTS dc_garrison_setting;
DROP TABLE IF EXISTS dc_garrison_decor;
DROP TABLE IF EXISTS dc_garrison_owner;
DROP TABLE IF EXISTS dc_garrison_meta;
DROP TABLE IF EXISTS dc_garrison_cur_cat;
DROP TABLE IF EXISTS dc_garrison_cur_fit;
DROP TABLE IF EXISTS dc_garrison_cur_item;
DROP TABLE IF EXISTS dc_garrison_cur_meta;
