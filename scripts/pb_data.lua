-- Pet battle DATA (pure tables, no game API). Everything about fighting (stats, abilities, effects, families) comes from the RETAIL data in pb_retail.lua (generated from the
-- DB2 tables by pet-battle/gen_retail.py) and the rules in pb_rules.lua. This file only holds OUR choices: which retail kit each creature uses, how its abilities are named,
-- where wild pets appear, and the progression constants.
local D = {}

D.MAX_LEVEL = 25                  -- retail pet levels 1-25 cover the whole world; level 25 = the level 80 cap
-- mob level (1-80) -> pet level (1-25). PLACEHOLDER curve until the retail zone/level data is pulled: proportional.
function D.PetLevel(mobLevel) return math.max(1, math.min(D.MAX_LEVEL, math.floor((mobLevel or 1) * D.MAX_LEVEL / 80 + 0.5))) end

-- QUALITY: 1 common (white), 2 uncommon (green), 3 rare (blue), 4 epic (purple). Retail: +10% health/power/speed per step (pb_rules.QualityMult).
D.QUALITY_NAMES = { "Common", "Uncommon", "Rare", "Epic" }
D.QUALITY_WEIGHTS = { 55, 28, 13, 4 }      -- how often a wild pet is each quality
D.CAPTURE_HP = 0.35                        -- retail: an enemy pet can be captured (trap) at or below 35% health; the capture always works, costs your turn, keeps the pet's level/quality/skin
D.REGEN_PCT, D.REGEN_SECONDS = 1, 10       -- a pet recovers 1% of its max health every 10 seconds (also while you are offline)
D.XP_STEP = 0.20                 -- XP: retail table (pb_retail R.xp: wins x XpPerWin per level, a win = XpPerWin of the ENEMY level); our rule on top: -20% per level the enemy is BELOW the pet, 0 at 5+ below

-- ANIMATION / SOUND RULE: an ability's name, animation and spell share one style. Claw/Scratch/Swipe/Rake = attack emote + pet Claw spell; Bite/Maul = attack emote + Bite spell;
-- Gore/Headbutt/Hoof/Bash = attack emote + Gore spell; weapon users = attack emote + Sinister Strike; casters = a real spell, no lunge (ranged = true). Spell defaults per RETAIL ability
-- name are in pb_core.lua (VIS); the per-species overrides below win. Fields: name (display), icon, vis (spell id), ranged.
D.rename = {
    [299] = { ["Vengeance"] = { name = "Revenge Bite" }, ["Crouch"] = { name = "Hunker Down" } },                       -- Young Wolf (retail Frostwolf Pup)
    [69]  = { ["Dazzling Dance"] = { name = "Feint" }, ["Crouch"] = { name = "Hunker Down" } },                          -- Timber Wolf (retail Worg Pup)
    [257] = { ["Thrash"] = { name = "Pick Swing", vis = 1752 }, ["Takedown"] = { name = "Tackle", vis = 49966 }, ["Mangle"] = { name = "Rusty Cut", vis = 1752 },
              ["Frost Shock"] = { name = "Dust Kick", vis = 49966 }, ["Rampage"] = { name = "Pickaxe Frenzy", vis = 1752 }, ["Deep Freeze"] = { name = "Rockfall", vis = 49966 } },   -- Kobold Worker (retail Kun-Lai Runt)
    [80]  = { ["Punch"] = { name = "Shovel Bash", vis = 49966 }, ["Flank"] = { name = "Shovel Sweep", vis = 1752 }, ["Acid Touch"] = { name = "Rusty Cut", vis = 1752 },
              ["Lucky Dance"] = { name = "Dodge Around" }, ["Clobber"] = { name = "Skull Whack", vis = 49966 }, ["Stampede"] = { name = "Wheelbarrow Rush", vis = 49966 } },       -- Kobold Laborer (retail Murky)
    [6]   = { ["Feedback"] = { name = "Fire Bolt", vis = 133, ranged = true, icon = "Spell_Fire_FlameBolt" }, ["Flurry"] = { name = "Scorch", vis = 2948, ranged = true, icon = "Spell_Fire_SoulBurn" },
              ["Drain Power"] = { name = "Sap Heat", vis = 133, ranged = true }, ["Amplify Magic"] = { name = "Candle Flare" }, ["Mana Surge"] = { name = "Meteor", vis = 133, ranged = true, icon = "Spell_Fire_Meteorstorm" },
              ["Deflection"] = { name = "Flicker" } },                                                                  -- Kobold Vermin (retail Mana Wyrmling)
    -- ---- Elwynn roster, batch 2 (retail kit in the species comment)
    [285] = { ["Punch"] = { name = "Fin Slap", vis = 49966 }, ["Flank"] = { name = "Gill Rake", vis = 16827 }, ["Acid Touch"] = { name = "Brine Spit" }, ["Lucky Dance"] = { name = "Scuttle" },
              ["Clobber"] = { name = "Skull Bash", vis = 49966 }, ["Stampede"] = { name = "Murloc Rush", vis = 49966 } },                                   -- Murloc (retail Gurky)
    [46]  = { ["Punch"] = { name = "Fin Slap", vis = 49966 }, ["Flank"] = { name = "Gill Rake", vis = 16827 }, ["Acid Touch"] = { name = "Brine Spit" }, ["Lucky Dance"] = { name = "Scuttle" },
              ["Clobber"] = { name = "Skull Bash", vis = 49966 }, ["Stampede"] = { name = "Forager Rush", vis = 49966 } },                                  -- Murloc Forager (retail Lurky)
    [735] = { ["Water Jet"] = { name = "Spray", vis = 133 }, ["Tongue Lash"] = { name = "Tail Whip", vis = 49966 }, ["Healing Wave"] = { name = "Tide Mend" }, ["Cleansing Rain"] = { name = "River Rain" },
              ["Frog Kiss"] = { name = "Slippery Strike", vis = 49966 }, ["Swarm of Flies"] = { name = "Gnat Swarm" } },                                    -- Murloc Streamrunner (retail Jubling)
    [116] = { ["Crush"] = { name = "Club Smash", vis = 49966 }, ["Whirlwind"] = { name = "Dust Whirl" }, ["Hawk Eye"] = { name = "Sharp Eye" }, ["Sandstorm"] = { name = "Sand Toss" },
              ["Reckless Strike"] = { name = "Wild Swing", vis = 1752 }, ["Blackout Kick"] = { name = "Low Blow", vis = 49966 } },                           -- Defias Bandit (retail Qiraji Guardling)
    [94]  = { ["Blitz"] = { name = "Quick Stab", vis = 1752 }, ["Triple Snap"] = { name = "Triple Slash", vis = 1752 }, ["Focus"] = { name = "Steady Aim" }, ["Deflection"] = { name = "Parry" },
              ["Kick"] = { name = "Dirty Kick", vis = 49966 }, ["Rampage"] = { name = "Frenzy", vis = 1752 } },                                            -- Defias Cutpurse (retail Flayer Youngling)
    [38]  = { ["Punch"] = { name = "Haymaker", vis = 49966 }, ["Flank"] = { name = "Back Stab", vis = 1752 }, ["Acid Touch"] = { name = "Poisoned Blade", vis = 1752 }, ["Lucky Dance"] = { name = "Sidestep" },
              ["Clobber"] = { name = "Cudgel Blow", vis = 49966 }, ["Stampede"] = { name = "Thug Rush", vis = 49966 } },                                   -- Defias Thug (retail Terky)
    [474] = { ["Feedback"] = { name = "Frost Bolt", vis = 116, ranged = true, icon = "Spell_Frost_FrostBolt02" }, ["Arcane Blast"] = { name = "Arcane Missiles", vis = 133, ranged = true },
              ["Evanescence"] = { name = "Blink" }, ["Sear Magic"] = { name = "Fire Blast", vis = 133, ranged = true }, ["Wish"] = { name = "Mana Shield" }, ["Amplify Magic"] = { name = "Arcane Power" } },   -- Defias Rogue Wizard (retail Hyjal Wisp)
    [476] = { ["Beam"] = { name = "Stone Bolt", vis = 403, ranged = true, icon = "Spell_Nature_StoneClawTotem" }, ["Light"] = { name = "Pebble Barrage", vis = 403, ranged = true },
              ["Flash"] = { name = "Earth Mend" }, ["Arcane Blast"] = { name = "Tremor", vis = 403, ranged = true }, ["Soul Ward"] = { name = "Stoneskin" }, ["Arcane Explosion"] = { name = "Earthquake", vis = 403, ranged = true } },   -- Kobold Geomancer (retail Nordrassil Wisp)
    [40]  = { ["Jab"] = { name = "Pick Jab", vis = 1752 }, ["Charge"] = { name = "Pickaxe Charge", vis = 1752 }, ["Creeping Fungus"] = { name = "Rust" }, ["Leech Seed"] = { name = "Sap Strength" },
              ["Spore Shrooms"] = { name = "Rockslide" }, ["Crouch"] = { name = "Brace" } },                                                               -- Kobold Miner (retail Sporeling Sprout)
    [478] = { ["Crush"] = { name = "Club Smash", vis = 49966 }, ["Tongue Lash"] = { name = "Gnoll Lash", vis = 49966 }, ["Sticky Goo"] = { name = "Mud Throw" }, ["Poison Lash"] = { name = "Rusty Spear", vis = 1752 },
              ["Backflip"] = { name = "Leap Away" }, ["Dreadful Breath"] = { name = "Foul Howl" } },                                                      -- Riverpaw Outrunner (retail Hopling)
    [97]  = { ["Punch"] = { name = "Club Whack", vis = 49966 }, ["Flank"] = { name = "Spear Poke", vis = 1752 }, ["Acid Touch"] = { name = "Poisoned Spear", vis = 1752 }, ["Lucky Dance"] = { name = "Gnoll Shuffle" },
              ["Clobber"] = { name = "Skull Crack", vis = 49966 }, ["Stampede"] = { name = "Runt Rush", vis = 49966 } },                                  -- Riverpaw Runt (retail Gurky)
}

-- Species by creature entry. retail = the retail BattlePetSpecies id whose kit (family, stats, 6 abilities with level unlocks) this creature uses (chosen by pet-battle/assign_kits.py + curation).
-- scale = optional size override. wild = true: a tiny pet spawns next to the real mobs (pb_wild.lua). critter = a real critter species.
D.species = {
    [299] = { name = "Young Wolf", retail = 1542, wild = true, icon = "Ability_Hunter_Pet_Wolf" },
    [69] = { name = "Timber Wolf", retail = 89, wild = true, icon = "Ability_Hunter_Pet_Wolf" },
    [257] = { name = "Kobold Worker", retail = 1166, wild = true, icon = "INV_Pick_02" },
    [7381] = { name = "Silver Tabby Cat", retail = 45, icon = "Ability_Hunter_Pet_Cat" },
    [7382] = { name = "Orange Tabby Cat", retail = 43, icon = "Ability_Hunter_Pet_Cat" },
    [7384] = { name = "Cornish Rex Cat", retail = 41, icon = "Ability_Hunter_Pet_Cat" },
    [7385] = { name = "Bombay Cat", retail = 40, icon = "Ability_Hunter_Pet_Cat" },
    [6] = { name = "Kobold Vermin", retail = 136, wild = true, icon = "Spell_Fire_FlameBolt" },
    [80] = { name = "Kobold Laborer", retail = 107, wild = true, icon = "INV_Pick_02" },
    [883] = { name = "Deer", retail = 390, wild = true, critter = true, icon = "Spell_Nature_HealingWay" },
    [721] = { name = "Rabbit", retail = 72, wild = true, critter = true, icon = "Ability_Druid_Dash" },
    -- ---- Elwynn roster, batch 2
    [525] = { name = "Mangy Wolf", retail = 529, wild = true, icon = "Ability_Hunter_Pet_Wolf" },
    [1922] = { name = "Gray Forest Wolf", retail = 1542, wild = true, icon = "Ability_Hunter_Pet_Wolf" },
    [118] = { name = "Prowler", retail = 301, wild = true, icon = "Ability_Hunter_Pet_Cat" },
    [30] = { name = "Forest Spider", retail = 412, wild = true, icon = "Ability_Hunter_Pet_Spider" },
    [43] = { name = "Mine Spider", retail = 470, wild = true, icon = "Ability_Hunter_Pet_Spider" },
    [113] = { name = "Stonetusk Boar", retail = 518, wild = true, icon = "Ability_Hunter_Pet_Boar" },
    [524] = { name = "Rockhide Boar", retail = 205, wild = true, icon = "Ability_Hunter_Pet_Boar" },
    [14869] = { name = "Pygmy Cockatrice", retail = 47, wild = true, icon = "Ability_Hunter_Pet_Bat" },
    [32820] = { name = "Wild Turkey", retail = 201, wild = true, icon = "Ability_Hunter_Pet_Bat" },   -- only exists during the Pilgrim's Bounty event
    [2442] = { name = "Cow", retail = 1543, wild = true, critter = true, icon = "Ability_Hunter_Pet_Boar" },
    [890] = { name = "Fawn", retail = 203, wild = true, critter = true, icon = "Spell_Nature_HealingWay" },
    [14864] = { name = "Khaz Modan Ram", retail = 434, wild = true, icon = "Ability_Hunter_Pet_Boar" },
    [1933] = { name = "Sheep", retail = 394, wild = true, critter = true, icon = "Ability_Hunter_Pet_Boar" },
    [6368] = { name = "Cat", retail = 42, wild = true, critter = true, icon = "Ability_Hunter_Pet_Cat" },
    [9699] = { name = "Fire Beetle", retail = 406, wild = true, critter = true, icon = "Ability_Hunter_Pet_Scorpid" },
    [5403] = { name = "Riding White Stallion", retail = 3334, wild = true, icon = "Ability_Mount_WhiteStallion" },
    [285] = { name = "Murloc", retail = 121, wild = true, icon = "INV_Misc_Fish_02" },
    [46] = { name = "Murloc Forager", retail = 111, wild = true, icon = "INV_Misc_Fish_02" },
    [732] = { name = "Murloc Lurker", retail = 2726, wild = true, icon = "INV_Misc_Fish_02" },
    [735] = { name = "Murloc Streamrunner", retail = 106, wild = true, icon = "INV_Misc_Fish_02" },
    [116] = { name = "Defias Bandit", retail = 513, wild = true, icon = "INV_Misc_Bandana_03" },
    [94] = { name = "Defias Cutpurse", retail = 514, wild = true, icon = "INV_Misc_Bandana_03" },
    [38] = { name = "Defias Thug", retail = 1073, wild = true, icon = "INV_Misc_Bandana_03" },
    [474] = { name = "Defias Rogue Wizard", retail = 1631, wild = true, icon = "Spell_Frost_FrostBolt02" },
    [476] = { name = "Kobold Geomancer", retail = 547, wild = true, icon = "Spell_Nature_StoneClawTotem" },
    [40] = { name = "Kobold Miner", retail = 515, wild = true, icon = "INV_Pick_02" },
    [478] = { name = "Riverpaw Outrunner", retail = 835, wild = true, icon = "INV_Misc_Pelt_Wolf_01" },
    [97] = { name = "Riverpaw Runt", retail = 121, wild = true, icon = "INV_Misc_Pelt_Wolf_01" },
    [36511] = { name = "Spectral Tiger Cub", retail = 242, scale = 1.0, icon = "Ability_Hunter_Pet_Cat" },   -- companion models already pet sized
}

return D
