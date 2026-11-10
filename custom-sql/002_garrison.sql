-- Garrison / housing (proof of concept: Northshire Abbey). Idempotent; re-applied by the admin TUI on every start.
-- 1) Portal gameobject 900002: a goober wearing the "Portal to Stormwind" model so scripts/garrison.lua can handle the click.
USE acore_world;
DELETE FROM gameobject_template WHERE entry = 900002;
INSERT INTO gameobject_template (entry, type, displayId, name, IconName, castBarCaption, unk1, size, Data4, Data11, AIName, ScriptName, VerifiedBuild)
VALUES (900002, 10, 4396, 'Garrison Portal', '', '', '', 1, 5, 1, '', '', 12340);
-- 2) Its permanent spawn at the Stormwind Mage Tower (= .tele garportal, normal phase). The garrison locations themselves are in scripts/garrison.lua.
DELETE FROM gameobject WHERE guid = 900100;
INSERT INTO gameobject (guid, id, map, spawnMask, phaseMask, position_x, position_y, position_z, orientation, rotation0, rotation1, rotation2, rotation3, spawntimesecs, animprogress, state)
VALUES (900100, 900002, 0, 1, 1, -8981.65, 855.01, 29.621, 3.03693, 0, 0, 0.998631, 0.052307, 300, 100, 1);
-- 2b) The same portal for the Horde in Orgrimmar (= .tele hportals). Either faction may use either portal; leaving a garrison returns you to your own faction's one.
DELETE FROM gameobject_template WHERE entry = 900003;
INSERT INTO gameobject_template (entry, type, displayId, name, IconName, castBarCaption, unk1, size, Data4, Data11, AIName, ScriptName, VerifiedBuild)
VALUES (900003, 10, 4395, 'Garrison Portal', '', '', '', 1, 5, 1, '', '', 12340);
DELETE FROM gameobject WHERE guid = 900101;
INSERT INTO gameobject (guid, id, map, spawnMask, phaseMask, position_x, position_y, position_z, orientation, rotation0, rotation1, rotation2, rotation3, spawntimesecs, animprogress, state)
VALUES (900101, 900003, 1, 1, 1, 1455.46, -4220.69, 43.1861, 0.0887271, 0, 0, 0.0443, 0.999, 300, 100, 1);
-- 3) Player data lives in the CHARACTERS database (so "player" backups keep layouts).
USE acore_characters;
CREATE TABLE IF NOT EXISTS dc_garrison_object (
  id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  account  INT UNSIGNED NOT NULL,
  location INT UNSIGNED NOT NULL,
  kind     VARCHAR(32)  NOT NULL,
  x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, o FLOAT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_owner_kind (account, location, kind)
) ENGINE=InnoDB;
-- Optional per-location overrides set in game with `.garrison center` / `.garrison radius N` (GM).
CREATE TABLE IF NOT EXISTS dc_garrison_location (
  id INT UNSIGNED NOT NULL, cx FLOAT NOT NULL, cy FLOAT NOT NULL, radius FLOAT NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;
-- Players who logged out while inside a garrison (next login: teleported to the portal, normal phase).
CREATE TABLE IF NOT EXISTS dc_garrison_logout (guid INT UNSIGNED NOT NULL, PRIMARY KEY (guid)) ENGINE=InnoDB;
-- Temporary spawns made by scripts/garrison.lua (so a script reload or crash can never leave orphan NPCs/pets behind).
CREATE TABLE IF NOT EXISTS dc_garrison_spawn (low INT UNSIGNED NOT NULL, t CHAR(1) NOT NULL, entry INT UNSIGNED NOT NULL, map INT UNSIGNED NOT NULL, PRIMARY KEY (low, t)) ENGINE=InnoDB;
