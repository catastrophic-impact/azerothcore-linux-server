# Pet battle audit (2026-11-12, 82 retail kits, 109 species)

## A. Species templates (creature_template of every species)
Checked: npcflag, unit_flags/2, type_flags, flags_extra, ScriptName, vehicle, immunities, hover, models, SmartAI rows.

Clean: no species has an npcflag, a C++ ScriptName, a vehicle or a hover height. All client models/skins exist (142 displays checked against the client MPQs).

Fixed already: unit_flags 768 (cats, Khaz Modan Ram, Pygmy Cockatrice: immune to NPC spells) cleared at spawn; tabby cat SmartAI "no aura -> Evade" (stand-in spawn = Cat 6368).

**Open risk: SmartAI scripts run on our battle pets.** 88 of the 109 species keep their SmartAI. Only combat-time events matter in theory, but a pet IS briefly "in combat" during every hostile-faction swap (pb_cast), and some scripts also run out of combat:
| Event -> action | Species | Effect on a battle pet |
|---|---|---|
| UPDATE_OOC -> cast | 1124 Frostmane Shadowcaster, 3198 BB Apprentice, 3199 BB Cultist, 474 Defias Rogue Wizard, 476 Kobold Geomancer | periodic self-buff casts (armor/shield visuals) while idle |
| RESPAWN -> cast | 1117 Rockjaw Bonesnapper, 30 Forest Spider, 43 Mine Spider, 3124 Scorpid Worker, 3125 Clattering Scorpid | cast on spawn |
| UPDATE_OOC -> ACT4 | 1922 Gray Forest Wolf | unknown, to inspect |
| AGGRO -> talk / cast (21 + 6 rows) | most humanoids, boars, quilboar | yells / charges when the pet enters combat |
| HEALTH_PCT -> flee (27 rows) | most humanoids, Makrura | a pet hit below the threshold runs away (pb_cast already stops it every 150 ms, but only during the hit window) |
| UPDATE_IC -> cast (28 rows) | many | in-combat casts during a hit window |
Recommendation: spawn every battle pet from an AI-less stand-in entry (like the cats) and set its display/scale, or at least the species above.

## B. Abilities the engine only partly interprets (damage/heal part works, listed part is ignored)
No ability in any used kit has an effect type the engine does not know at all.
- 80 weather (5): Call Blizzard, Call Lightning, Call of Winter, Cleansing Rain, Sandstorm
- 158 conditional gate (~22): Blitz, Body Slam, Conflagrate, Consume, Feed, Flank, Flurry, Maul, Mana Surge, Nether Gate, Pounce, Quills, Reckless Strike, Rend, Slicing Wind, Thrash, Tongue Lash, Triple Snap ... (their bonus condition is not applied)
- 177 (8): Backflip, Deep Freeze, Frog Kiss, Headbutt, Kick, Rupture, Tornado Punch, Udder Destruction
- 79 / 116 priority + gates: Charge, Quick Attack, Deflection, Surge, Perk Up
- 31 / 136 / 157 state markers: Consume Magic, Counterstrike, Leech Life, Sear Magic, Snail Mail
- others: Apocalypse (159 meteor), Crouch + Sniff Out (85), Nature's Ward (85, 229), Haymaker (194 stun on miss), Horn Attack (156), Nether Gate (107 forced swap), Spiny Carapace (137 tripled bonus)

## C. Not covered by any test
Presentation (facing, models, spell visuals/sound), the addons, music. Found only by playing so far.
