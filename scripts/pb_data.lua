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
D.XP_PER_LEVEL = 100             -- flat requirement per level
D.XP_FULL = 30                   -- XP a pet earns from one win against an enemy of its level or higher (about 4 wins per level)
D.XP_STEP = 0.20                 -- -20 % per enemy level BELOW the pet: 5+ levels below = 0 (no power leveling)

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
    [36511] = { name = "Spectral Tiger Cub", retail = 242, scale = 1.0, icon = "Ability_Hunter_Pet_Cat" },   -- companion models already pet sized
}

return D
