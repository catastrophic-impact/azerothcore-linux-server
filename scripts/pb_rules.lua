-- Retail pet battle RULES as pure functions (no game API): stats from level/quality/species, family strengths, damage and hit numbers.
-- Source of the formulas: retail behaviour (Level 25 Rare with base stats 8: health 1400, power 260, speed 260), species base values from the DB2 BattlePetSpeciesState.
-- Used by the retail-based engine (pb_core.lua, in progress); tested by pet-battle/test_rules.lua.
local Rules = {}

Rules.MAX_LEVEL = 25
Rules.FAMILIES = { "Humanoid", "Dragonkin", "Flying", "Undead", "Critter", "Magic", "Elemental", "Beast", "Aquatic", "Mechanical" }   -- BattlePetSpecies.PetTypeEnum order
-- family -> family it is STRONG against (x1.5 damage dealt). The reverse pairs are WEAK (x0.67): Humanoid>Dragonkin>Magic>Flying>Aquatic>Elemental>Mechanical>Beast>Critter>Undead>Humanoid
Rules.STRONG = { Humanoid = "Dragonkin", Dragonkin = "Magic", Magic = "Flying", Flying = "Aquatic", Aquatic = "Elemental", Elemental = "Mechanical", Mechanical = "Beast", Beast = "Critter", Critter = "Undead", Undead = "Humanoid" }
-- family -> family it is WEAK against (x0.67 damage dealt)
Rules.WEAK = { Humanoid = "Beast", Dragonkin = "Undead", Flying = "Dragonkin", Undead = "Aquatic", Critter = "Humanoid", Magic = "Mechanical", Elemental = "Critter", Beast = "Flying", Aquatic = "Magic", Mechanical = "Elemental" }
Rules.STRONG_MULT, Rules.WEAK_MULT = 1.5, 2 / 3

-- quality 1..4 (white, green, blue, purple) -> multiplier. Retail: poor 1.0, common 1.1, uncommon 1.2, rare 1.3 (+0.1 per step).
function Rules.QualityMult(q) return 1.0 + 0.1 * math.max(1, math.min(4, q or 1)) end

-- species = the retail species stats table ({ Stat_Power = -200, Stat_Speed = 200, Stat_Stamina = 0 } = hundredths added to the base 8)
local function base(species, key) return 8 + ((species and species[key]) or 0) / 100 end
function Rules.Stats(species, level, quality)
    level = math.max(1, math.min(Rules.MAX_LEVEL, level or 1)); local q = Rules.QualityMult(quality)
    local hp = math.floor(base(species, "Stat_Stamina") * level * q * 5 + 100 + 0.5)
    return { health = hp, power = base(species, "Stat_Power") * level * q, speed = base(species, "Stat_Speed") * level * q }
end

-- damage/healing of an effect with `points`: points * (1 + power/20) (retail: keeps a fight at about 5 hits per pet at every level), times the family matchup and percentage modifiers
function Rules.Matchup(attFamily, defFamily)
    if Rules.STRONG[attFamily] == defFamily then return Rules.STRONG_MULT end
    if Rules.WEAK[attFamily] == defFamily then return Rules.WEAK_MULT end
    return 1
end
function Rules.Damage(points, power, attFamily, defFamily, dealtPct, takenPct)
    local d = points * (1 + power / 20) * Rules.Matchup(attFamily, defFamily)
    d = d * (1 + (dealtPct or 0) / 100) * (1 + (takenPct or 0) / 100)
    return math.max(1, math.floor(d + 0.5))
end
function Rules.Heal(points, power) return math.max(1, math.floor(points * (1 + power / 20) + 0.5)) end
return Rules
