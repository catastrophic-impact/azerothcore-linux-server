-- Shop catalog candidates: companion pets (class15/sub2) + mounts (class15/sub5) with how they can be obtained ON THIS SERVER.
-- Output columns: kind, item, name, quality, teachSpell, sources, vendorFactions, allowableRace, flags2
USE acore_world;
CREATE TEMPORARY TABLE src (item INT PRIMARY KEY, why VARCHAR(20));
INSERT IGNORE INTO src SELECT Item,'drop' FROM creature_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM gameobject_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM fishing_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM item_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM pickpocketing_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM skinning_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT Item,'drop' FROM reference_loot_template;
INSERT IGNORE INTO src SELECT Item,'drop' FROM mail_loot_template WHERE Reference=0;
INSERT IGNORE INTO src SELECT RewardItem1,'quest' FROM quest_template WHERE RewardItem1>0;
INSERT IGNORE INTO src SELECT RewardItem2,'quest' FROM quest_template WHERE RewardItem2>0;
INSERT IGNORE INTO src SELECT RewardItem3,'quest' FROM quest_template WHERE RewardItem3>0;
INSERT IGNORE INTO src SELECT RewardItem4,'quest' FROM quest_template WHERE RewardItem4>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID1,'quest' FROM quest_template WHERE RewardChoiceItemID1>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID2,'quest' FROM quest_template WHERE RewardChoiceItemID2>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID3,'quest' FROM quest_template WHERE RewardChoiceItemID3>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID4,'quest' FROM quest_template WHERE RewardChoiceItemID4>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID5,'quest' FROM quest_template WHERE RewardChoiceItemID5>0;
INSERT IGNORE INTO src SELECT RewardChoiceItemID6,'quest' FROM quest_template WHERE RewardChoiceItemID6>0;
INSERT IGNORE INTO src SELECT ItemID,'achieve' FROM achievement_reward WHERE ItemID>0;
CREATE TEMPORARY TABLE vend (item INT PRIMARY KEY, bits INT, neutral INT, n INT);
INSERT INTO vend SELECT v.item, BIT_OR(IFNULL(f.FactionGroup,0) & 6), SUM((IFNULL(f.FactionGroup,0) & 6)=0), COUNT(*)
  FROM npc_vendor v JOIN creature_template c ON c.entry=v.entry LEFT JOIN factiontemplate_dbc f ON f.ID=c.faction GROUP BY v.item;
SELECT IF(i.subclass=2,'pet','mount') kind, i.entry, i.name, i.Quality,
  CASE WHEN i.spellid_1 NOT IN (0,55884) THEN i.spellid_1 WHEN i.spellid_2 NOT IN (0,55884) THEN i.spellid_2 ELSE i.spellid_3 END teachSpell,
  CONCAT_WS(',', IF(s.item IS NOT NULL, s.why, NULL), IF(v.item IS NOT NULL, 'vendor', NULL)) sources,
  CASE WHEN v.item IS NULL THEN '' WHEN v.neutral>0 THEN 'any' WHEN v.bits=2 THEN 'ALLIANCE-only' WHEN v.bits=4 THEN 'HORDE-only' ELSE 'both' END vendorFactions,
  i.AllowableRace, i.FlagsExtra
FROM item_template i LEFT JOIN src s ON s.item=i.entry LEFT JOIN vend v ON v.item=i.entry
WHERE i.class=15 AND i.subclass IN (2,5)
  AND i.name NOT REGEXP '(^\\[|test|Test|TEST|deprecated|Deprecated|DEPRECATED|PH\\]|\\(old\\)|OLD|NYI|unused|Unused|DNT|zzz)'
ORDER BY kind, i.name;
