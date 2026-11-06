USE acore_world;
SELECT i.entry, i.name, i.class, i.subclass, i.Quality, i.spellid_1,
 (SELECT COUNT(*) FROM creature_loot_template l WHERE l.Item=i.entry) cl,
 (SELECT COUNT(*) FROM gameobject_loot_template l WHERE l.Item=i.entry) gl,
 (SELECT COUNT(*) FROM npc_vendor v WHERE v.item=i.entry) vend,
 (SELECT COUNT(*) FROM game_event_npc_vendor v WHERE v.item=i.entry) evend,
 (SELECT COUNT(*) FROM quest_template q WHERE i.entry IN (q.RewardItem1,q.RewardItem2,q.RewardItem3,q.RewardItem4,q.RewardChoiceItemID1,q.RewardChoiceItemID2,q.RewardChoiceItemID3,q.RewardChoiceItemID4,q.RewardChoiceItemID5,q.RewardChoiceItemID6)) qr,
 (SELECT COUNT(*) FROM item_loot_template l WHERE l.Item=i.entry) cont
FROM item_template i WHERE i.name IN
('Tabard of Frost','Tabard of Flame','Tabard of Brilliance','Tabard of Nature','Tabard of Fury','Tabard of the Void','Tabard of the Arcane','Epic Purple Shirt','Paper Flying Machine Kit','Goblin Gumbo Kettle','Fishing Chair','The Flag of Ownership','Foam Sword Rack','D.I.S.C.O.','Goblin Weather Machine - Prototype 01-B','Path of Illidan','Papa Hummel''s Old-Fashioned Pet Biscuit','Sandbox Tiger','Carved Ogre Idol','Heavy Ball','Golden Medallion','Gold Medallion')
ORDER BY i.name;
