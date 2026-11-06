-- GENERATED (pass 6): inert templates 940000+ for shop-front models, review shelf. Idempotent.
USE acore_world;
DELETE FROM gameobject_template WHERE entry BETWEEN 940000 AND 940099;
INSERT INTO gameobject_template (entry, type, displayId, name, IconName, castBarCaption, unk1, size, AIName, ScriptName, VerifiedBuild) VALUES
(940000, 5, 171, 'Armorershop01 Sign', '', '', '', 1, '', '', 12340),
(940001, 5, 172, 'Fletchershop01 Sign', '', '', '', 1, '', '', 12340),
(940002, 5, 173, 'Weaponsmithshop01 Sign', '', '', '', 1, '', '', 12340),
(940003, 5, 175, 'Bank01 Sign', '', '', '', 1, '', '', 12340),
(940004, 5, 176, 'Generalstore01 Sign', '', '', '', 1, '', '', 12340),
(940005, 5, 177, 'Visitorscenter01 Sign', '', '', '', 1, '', '', 12340),
(940006, 5, 180, 'Tavern01 Sign', '', '', '', 1, '', '', 12340);
