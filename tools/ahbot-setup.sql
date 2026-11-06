-- Run once after first boot, after `account create ahbot <random-pw>` (account id substituted for @AID).
-- Creates the character the AH bot module uses (guid 900001, matches config-overrides/modules/mod_ahbot.conf).
SET SESSION sql_mode='';
INSERT INTO acore_characters.characters (guid,account,name,race,class,gender,level,position_x,position_y,position_z,map,zone,online,taximask)
VALUES (900001,@AID,'Stockmarket',1,1,1,80,-8949.95,-132.493,83.5312,0,12,0,'');
