-- Pet stand-in templates are INVISIBLE (display 11686, invisible stalker): the pet scripts swap the pet's real display on at spawn (SetDisplayId). The client applies a display's scale k predictably
-- only on a swapped display (k_eff = max(k, 0.63)); a display a creature is born with is not predictable. Idempotent. (Replaces the old per-display DisplayScale table; pb_store.lua computes the scale.)
USE acore_world;
UPDATE creature_template_model SET CreatureDisplayID = 11686, DisplayScale = 1 WHERE CreatureID BETWEEN 9000000 AND 9099999;
-- Family 0: the client otherwise raises a creature's size to its creature-family scale (CreatureFamily.dbc: spider 0.6, crab 1.4, ...), overriding the display scale k.
UPDATE creature_template SET family = 0 WHERE entry BETWEEN 9000000 AND 9099999;
-- Companion pets are real creatures and must look exactly as in the game: they keep their real family (only Coyote Spirit has one, wolf family).
UPDATE creature_template s JOIN creature_template r ON r.entry = s.entry - 9000000 SET s.family = r.family WHERE s.entry = 9028267;
