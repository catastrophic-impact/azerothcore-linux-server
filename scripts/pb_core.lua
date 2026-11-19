-- Pet battle CORE (retail-based): pure Lua, no game API. Interprets the retail ability data in pb_retail.lua (generated from the DB2 tables by pet-battle/gen_retail.py)
-- with the retail rules in pb_rules.lua. pb_battle plays back the event list this returns and syncs the addon.
-- Species: pb_data.species[creature entry].retail = retail BattlePetSpecies id. Abilities unlock by level exactly as retail (slot 1 at L1, slot 2 at L2, slot 3 at L4; 2nd option of a slot at L10/15/20).
-- EFFECT PROPS (BattlePetEffectProperties id -> meaning, inferred from the ability texts; params are the labelled columns Param_0..5):
--   24, 222  damage: p1 Points, p2 Accuracy       96 same, but always hits when the target has state p4 (Spectral Strike vs Blinded)       384  extra hit only if the user acted first       29  extra damage if the target has state p3 (Takedown vs stunned, Maul vs bleeding)
--   149 Weakening Blow: damage that leaves the target at 1 health at least     107 forced swap (Nether Gate, inert: only its damage works)
--   68 Explode: p1 % of own max health as damage, user faints     135/137 gates/state markers (inert)
--   66 Impale: damage that grows by p3 % below 25% target health     44 heal p1 % of the last hit taken (Cauterize)     194 stun-on-miss marker (inert)
--   23       heal: p1 Points (one effect per ally in team order: Bleat has three)                    104 heal p1 points when this ability kills       197 damage = last hit taken
--   26       apply aura to the USER (or the enemy if its states are harmful): p2 chance, p3 duration     50/52/178  same with p2 chance, p3 duration, 50: p4 max stacks   172 stun chance p5
--   54       damage-over-time aura on the enemy (p3 duration)      63  heal-over-time aura on the user (p3 duration)
--   49       remove aura f.aura from the user (also what an aura does to itself after its event 1 = holder was hit, 2 = holder attacked)
--   62 Trample damage    59 Comeback: extra damage if the user was hit      27 damage that grows per use (p3 per use, max p4)      32 heal the user for p1 % of the damage this ability dealt
--   79 "always goes first" (Charge)      141 damage split evenly over the whole enemy team      131 stun when the user acts first (p2 chance, aura = stun)
--   158 177 85 229 116 28 170 31 157 156 136 159 80: gates/weather/transform/state markers, not interpreted (they are listed by pet-battle/test_core.lua as "not interpreted")
local D = require("pb_data")
local R = require("pb_retail")
local Rules = require("pb_rules")
local PV = require("pb_vis")   -- GENERATED presentation of every retail ability (pet-battle/gen_vis.py): visual spell + mode, from the lab answers / same-name spells / rules
local C = {}
PB_CORE = C
C.unknown = {}

local DAMAGE = { [24] = true, [222] = true, [96] = true, [62] = true }
local APPLY = { [50] = true, [52] = true, [178] = true }
local INERT = { [158] = true, [177] = true, [85] = true, [229] = true, [116] = true, [28] = true, [170] = true, [31] = true, [157] = true, [156] = true, [136] = true, [159] = true, [79] = true, [194] = true, [135] = true, [137] = true, [107] = true }   -- 31/157/156/136 = internal state markers, 159 = delayed meteor, 80 = weather (the damage/heal parts of those abilities still work)
C.INERT = INERT
local function Other(s) return s == "P" and "E" or "P" end
local function Alive(b, s) local n = 0; for _, p in ipairs(b[s]) do if p.hp > 0 then n = n + 1 end end; return n end
local function NextAlive(b, s) for i, p in ipairs(b[s]) do if p.hp > 0 then return i end end end

-- ---------------------------------------------------------------- abilities
-- hit spell (visual + sound) by RETAIL ability name; D.rename[species][name] overrides name/icon/vis/ranged
local VIS = {
    Bite = 17253, ["Diseased Bite"] = 17253, ["Obsidian Bite"] = 17253, Maul = 17253, Rampage = 17253, Devour = 17253,
    Scratch = 16827, Claw = 16827, Rake = 16827, Pounce = 16827, Flurry = 16827, Thrash = 16827, Mangle = 16827, Flank = 16827, ["Spirit Claws"] = 16827, ["Jade Claw"] = 16827,
    Headbutt = 35290, Hoof = 35290, Bash = 35290, Stampede = 35290, Gore = 35290, Charge = 35290, Smash = 35290,
    Punch = 49966, Clobber = 49966, Takedown = 49966, Crush = 49966, Jab = 49966, Slam = 49966,
}
local ICON = {
    Scratch = "Ability_Druid_Rake", Flurry = "Ability_Druid_Disembowel", ["Adrenaline Rush"] = "Spell_Nature_Bloodlust", Dodge = "Ability_Rogue_Feint", Burrow = "Ability_Stealth",
    Stampede = "Ability_Hunter_Pet_Boar", Bite = "Ability_Druid_Maul", Claw = "Ability_Druid_Rake", Rake = "Ability_Druid_Rake", Pounce = "Ability_Druid_SupriseAttack", Screech = "Ability_Hunter_Pet_Bat",
    Devour = "Ability_Druid_FerociousBite", Prowl = "Ability_Druid_SupriseAttack", Maul = "Ability_Druid_Maul", Howl = "Ability_Hunter_Pet_Wolf", Crouch = "Ability_Defend", Leap = "Ability_Druid_Dash",
    Vengeance = "Ability_Warrior_Revenge", Hoof = "Ability_Druid_Maul", Headbutt = "Ability_Warrior_PunishingBlow", Bleat = "Spell_Nature_HealingWay", Tranquility = "Spell_Nature_Tranquility",
    ["Nature's Ward"] = "Spell_Nature_ResistNature", Roar = "Ability_Druid_DemoralizingRoar", Bash = "Ability_Druid_Bash", Hibernate = "Spell_Nature_Sleep", Clobber = "Ability_ThunderBolt",
    Punch = "Ability_Warrior_Sunder", Takedown = "Ability_Warrior_Charge", Mangle = "Ability_Druid_Mangle2", Rampage = "Ability_Warrior_Rampage",
}
local function Clean(text)
    text = (text or ""):gsub("%[[^%]]*%]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("Hit Chance", ""):gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
-- Every id: a school-damage spell (effect 2) WITH a missile model and travel speed > 0 (checked by pet-battle/check_fx.py), so the projectile is visible and lands on the target.
-- Visual spell by the THEME of the ability's NAME (first row that matches wins; a pattern is a word PREFIX, a trailing $ means the whole word). All ids are plain bolt/instant
-- spells without a lingering aura or duration (checked against Spell.dbc by pet-battle/check_fx.py). Rows are ordered so that "Frost Shock" is frost and "Shadow Shock" is shadow.
local THEME_VIS = {
    { "frost|ice$|icy|icicle|snow|freez|chill|blizzard|winter|glacial|hail", 116 },
    { "fire|flame|burn|scorch|ember|lava|magma|immolat|inferno|meteor|candle|sear$|searing|cinder|blaz", 9053 },
    { "shadow|dark|death|curse|void|drain|nether|nightmare|spectral|soul|ghost|dread|siphon", 686 },
    { "web|ooze|poison|toxic|acid|plague|rot$|rotting|infect|venom|spore|leech|corros|creeping|rust|sap$", 9591 },
    { "leaf|thorn|vine|branch|seed|wrath|bloom|ironbark|woodchip|photosyn|bark|root|entangl|ensnar", 5176 },
    { "lightning|thunder|shock|storm|static|zap|spark", 403 },
    { "holy|light$|lights|smite|radian|sunlight|sunfire|sunbeam|sun$|solar|beacon", 31759 },
    { "arcane|mana|surge|nova$|beam|power|counterspell|chaos|focused", 7269 },
    { "water|wave|spray|tide|tidal|geyser|jet$|brine|mud|rain$|bubble", 31012 },
    { "rock$|rocky|rockfall|stone|boulder|quake|crystal|sand|dust|pebble|earth|avalanche|rockslide", 9483 },
    { "wind|gust|tornado|cyclone|whirl|screech|shriek|slicing|squall", 3044 },
}
local function ThemeVis(name)
    local padded = " " .. name:lower():gsub("[%p]", " ") .. " "
    for _, row in ipairs(THEME_VIS) do
        for pat in row[1]:gmatch("[^|]+") do
            local whole = pat:sub(-1) == "$"
            if padded:find(" " .. (whole and (pat:sub(1, -2) .. " ") or pat), 1, true) then return row[2], true end
        end
    end
end
C.ThemeVis = ThemeVis
-- Icon by the same name themes (an ability nobody styled by hand used to show the generic Rampage icon: 7 of 10 abilities). Index = THEME_VIS row; then utility / physical rows.
local THEME_ICON = { "Spell_Frost_FrostBolt02", "Spell_Fire_FlameBolt", "Spell_Shadow_ShadowBolt", "Ability_Rogue_DualWeild", "Spell_Nature_ResistNature", "Spell_Lightning_LightningBolt01",
                     "Spell_Holy_HolyBolt", "Spell_Arcane_StarFire", "Spell_Frost_FrostNova", "Spell_Nature_StoneClawTotem", "Spell_Nature_Cyclone" }
local UTIL_ICON = {
    { "heal|mend|regener|restor|wish|cure|soothe|rejuven|lifeblood", "Spell_Nature_HealingWay" },
    { "shield|ward|block|barrier|plating|armor|protect|fortif|carapace|stone form|hunker|crouch", "Ability_Defend" },
    { "dodge|dance|feint|evade|burrow|hide|stealth|prowl|vanish|nocturnal|blink", "Ability_Rogue_Feint" },
    { "sleep|slumber|hibernat|nap$|lullaby", "Spell_Nature_Sleep" },
    { "stun|dizz|daze|confus|haymaker|fist", "Spell_Frost_Stun" },
    { "speed|sprint|dash|charge|lift|leap|stampede|rush|flyby|swoop|dive", "Ability_Rogue_Sprint" },
    { "howl|roar|call$|cry|bellow|bleat|chirp|trumpet", "Ability_Druid_DemoralizingRoar" },
    { "bite|chomp|fang|maul|devour|gnaw", "Ability_Druid_Maul" },
    { "claw|rake|scratch|swipe|peck|talon|pounce|flank|flurry|rip$|tear", "Ability_Druid_Rake" },
    { "strike|kick|punch|slam|smash|crush|hammer|clobber|bash|thrash|headbutt|gore|hoof|tackle|jab|weakening|punish|demolish|lash|backflip", "Ability_Warrior_Sunder" },
    { "explod|explosion|barrage|rocket|grenade|bomb|cannon|shot", "Spell_Fire_Meteorstorm" },
    { "parry|deflect|riposte", "Ability_Parry" },
    { "aim|eye|sight|marksm", "Ability_Hunter_SniperShot" },
    { "stab|swing|slash|cut|whack|cudgel|blow|frenzy|sunder|strike$", "Ability_MeleeDamage" },
    { "sting|swarm|bleed|rend|rupture|wound", "Ability_Rogue_Rupture" },
}
local function ThemeIcon(name)
    local padded = " " .. name:lower():gsub("[%p]", " ") .. " "
    local function hit(list)
        for _, pat in ipairs(list) do
            local whole = pat:sub(-1) == "$"
            if padded:find(" " .. (whole and (pat:sub(1, -2) .. " ") or pat), 1, true) then return true end
        end
    end
    for i, row in ipairs(THEME_VIS) do local l = {}; for pat in row[1]:gmatch("[^|]+") do l[#l + 1] = pat end; if hit(l) then return THEME_ICON[i] end end
    for _, row in ipairs(UTIL_ICON) do local l = {}; for pat in row[1]:gmatch("[^|]+") do l[#l + 1] = pat end; if hit(l) then return row[2] end end
end
C.ThemeIcon = ThemeIcon
-- A FLAVORED ability (D.rename: Light -> Pebble Barrage) keeps the retail MECHANICS but not the retail story: the clause before ", dealing" ("Covers the enemy in brilliant light")
-- becomes neutral and the retail name inside the text becomes the new one. Keeps "1-2 times" because the hit-count claims need it, and keeps ", dealing" for the same reason.
local function Flavor(text, old, new)
    if not text or not new or new == old then return text end
    local hit
    for _, verb in ipairs{ "dealing", "causing" } do
        if not hit then
            text = text:gsub("(Hit Chance|r%s+)([^%.%[%]]-), " .. verb, function(pre, clause)
                hit = true
                local n = clause:match("(%d%-%d) times")
                return pre .. (n and ("Hits the enemy " .. n .. " times") or "Hits the target") .. ", " .. verb
            end, 1)
        end
    end
    text = text:gsub("%f[%a]" .. old:gsub("%p", "%%%0") .. "%f[%A]", new)
    return text
end
C.Flavor = Flavor
local function MakeAbility(speciesId, aid)
    local a = assert(R.abilities[aid], "retail ability " .. tostring(aid) .. " missing from pb_retail.lua")
    local ov = D.RenameOf(speciesId, a.name, C.Family(speciesId)) or {}
    local pv = PV[aid]
    local vis, ranged, vmode, vpre, vhop, vdmg
    if ov.vis then vis, ranged, vmode = ov.vis, ov.ranged or ((ov.vm == "target" or ov.vm == "ranged") and true) or nil, ov.vm or (ov.ranged and "ranged" or "melee")   -- a per-species flavored ability keeps its own spell
    elseif ov.name and pv and (pv.m == "melee" or pv.m == "ranged") and ThemeVis(ov.name) then   -- a FLAVORED name with an element (Fire Strike) is that element's spell, not the retail ability's look
        vis, vmode, ranged = ThemeVis(ov.name), "ranged", true
    elseif pv then vis, vmode, vpre, vhop, vdmg = pv.s, pv.m, pv.pre, pv.hop, pv.dmg; ranged = (pv.m == "ranged" or pv.m == "target") or nil end
    if not vis and not pv then   -- FALLBACK for abilities nobody styled yet: every damaging ability still gets a visible hit (spell animation + sound) instead of nothing
        local dmg = false
        for _, t in ipairs(a.turns) do for _, f in ipairs(t.fx) do if DAMAGE[f.prop] or f.prop == 66 or f.prop == 226 or f.prop == 68 or f.prop == 197 or f.prop == 27 or f.prop == 29 or f.prop == 59 or f.prop == 384 or f.prop == 385 or f.prop == 141 then dmg = true end end end
        if dmg then
            vis, ranged = ThemeVis(ov.name or a.name)   -- the spell must FIT THE NAME (Snowball is not a fireball)
            if not vis then if (a.family == 5 or a.family == 6) and not ov.name then vis, ranged = 9053, true else vis = 49966 end end   -- unthemed Magic / Elemental: plain fire bolt (cast, no lunge); everything else: a melee punch
        end
    end
    -- retail turns: event 255 = the ordinary turns of the ability (one per round); the others are PROCS (1 = holder hit, 2 = holder dealt damage, 6/7 = before/after the round markers)
    local main, procs = {}, {}
    for _, t in ipairs(a.turns) do if t.event == 255 then main[#main + 1] = t else procs[#procs + 1] = t end end
    if #main == 0 then main, procs = a.turns, {} end
    local priority = (a.text or ""):find("always goes first") ~= nil
    for _, t in ipairs(procs) do for _, f in ipairs(t.fx) do if f.prop == 79 or f.prop == 145 or f.prop == 107 then priority = true end end end
    return { id = aid, name = ov.name or a.name, retailName = a.name, icon = ov.icon or (ov.name and ThemeIcon(ov.name)) or ICON[a.name] or ThemeIcon(ov.name or a.name) or "Ability_Warrior_Rampage", tip = Clean(ov.text or Flavor(a.text, a.name, ov.name)), text = ov.text or Flavor(a.text, a.name, ov.name), family = a.family, cd = a.cd, turns = main, procs = procs, priority = priority,
             vis = vis, ranged = ranged, vmode = vmode, vpre = vpre, vhop = vhop, vdmg = vdmg }
end

-- ---------------------------------------------------------------- descriptions (retail ability text with its formulas resolved to numbers)
-- The retail text holds tokens like [StandardDamage(1,1)] or [abs(abilityStateMod(71,591))*AttackBonus()]. They are resolved against the ability's effects and the pet's
-- power, so the tooltip shows the numbers this pet really deals. C.unresolved collects tokens nobody handled (test_core fails on any).
C.unresolved = {}
local function Fx(ab, t, e, aura)
    if aura and ab then   -- (an aura text naming ITSELF, Geyser/Volcano, uses its own turns) the aura named in the text must be one this ability applies; retail texts sometimes name another ability
        local function reach(x, d)   -- the named aura may sit one or two levels down the chain of auras this ability applies (Spore Shrooms -> carrier 747 -> damage aura 748)
            if d > 3 or not x then return false end
            for _, tn in ipairs(x.turns or {}) do for _, f in ipairs(tn.fx) do if f.aura == aura or (f.aura and f.aura ~= 0 and reach(R.abilities[f.aura], d + 1)) then return true end end end
            return false
        end
        local applies = (ab.id == aura) or reach(ab, 1); for _, tn in ipairs(ab.turns or {}) do for _, f in ipairs(tn.fx) do if f.aura == aura then applies = true end end end
        if not applies then for _, tn in ipairs(ab.turns or {}) do for _, f in ipairs(tn.fx) do if not applies and f.aura and f.aura ~= 0 and R.abilities[f.aura] then aura = f.aura; applies = true end end end end
    end
    local src = aura and R.abilities[aura] or ab
    local main = {}
    for _, tn in ipairs(src and src.turns or {}) do if tn.event == 255 then main[#main + 1] = tn end end
    if #main == 0 then main = src and src.turns or {} end
    local turn = main[t]
    local fx = turn and turn.fx[e]
    if fx and fx.p then return fx end
    for _, tn in ipairs(main) do for _, f in ipairs(tn.fx) do if f.p and f.p[1] and f.p[1] ~= 0 then return f end end end
    return { p = { 0, 100, 0, 0, 0, 0 } }
end
local function Arith(x)   -- "4+4+4" / "-5*1.5" -> number (digits and operators only)
    x = tostring(x or "")
    if x:match("^[%d%.%+%-%*/%(%) ]+$") then local f = (loadstring or load)("return " .. x); local ok, v = pcall(f or function() end); if ok and type(v) == "number" then return v end end
    return tonumber(x)
end
local function Num(x) return Arith(x) or 0 end
local function Round(x) return math.floor(x + 0.5) end
local function Bonus(power) return 1 + (power or 0) / 20 end
local function CallFn(name, args, ab, power)
    local a = {}
    for x in (args .. ","):gmatch("([^,]*),") do a[#a + 1] = (x:gsub("^%s+", ""):gsub("%s+$", "")) end
    local lname = name:lower()
    if lname == "abs" then return tostring(math.abs(Num(a[1])))
    elseif lname == "attackbonus" then return tostring(Bonus(power))
    elseif lname == "abilitystatemod" then
        local sid = a[1]; local key = tonumber(sid) and R.stateNames[tonumber(sid)] or (sid or ""):gsub("^STATE_", "")
        local st = R.states[tonumber(a[2]) or 0] or {}
        local v = st[key]
        if v == nil then   -- wrong / missing ability id in the retail text: look at the auras THIS ability applies
            for _, tn in ipairs(ab and ab.turns or {}) do for _, f in ipairs(tn.fx) do local fs = f.aura and R.states[f.aura]; if v == nil and fs and fs[key] then v = fs[key] end end end
        end
        if v == nil and ab and ab.id then v = (R.states[ab.id] or {})[key] end   -- an aura text pointing at a wrong id (Blinding Poison): its own states
        if v == nil then for _, x in pairs(st) do v = x; break end end
        return tostring(v or 0)
    elseif lname == "standarddamage" or lname == "simpledamage" then return tostring(Round(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[1] * Bonus(power)))
    elseif lname == "standardhealing" then return tostring(Rules.Heal(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[1], power or 0))
    elseif lname == "formatdamage" then return tostring(Round(Num(a[1])))
    elseif lname == "standardaccuracy" or lname == "accuracy" then local fx = Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])); return ((fx.prop == 172) and fx.p[6] or fx.p[2]) .. "%"
    elseif lname == "duration" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[3])
    elseif lname == "statechange" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[1])
    elseif lname == "points" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[1])
    elseif lname == "percentage" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[1])
    elseif lname == "pointsmax" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[4])
    elseif lname == "pointsincreaseperuse" then return tostring(Fx(ab, Num(a[1]), Num(a[2]), tonumber(a[3])).p[3])
    elseif lname == "numturns" then local t = a[1] and R.abilities[tonumber(a[1])] or ab; return tostring(t and #t.turns or 1)
    elseif lname == "school" or lname == "pettypename" then local f = ab and ab.family or -1; return Rules.FAMILIES[f + 1] or "Magic"
    elseif lname == "abilitypettype" then return tostring(ab and ab.family or -1)
    elseif lname == "getprocindex" then return "1"
    end
    return nil
end
function C.Describe(ab, power)
    local text = ab and ab.text
    if not text or text == "" then return "" end
    text = text:gsub("%s*%(Current: %[[^%]]*%]%)", "")
    text = text:gsub("%[([^%]]*)%]", function(expr)
        local e, guard = expr, 0
        repeat   -- innermost call first
            local changed = false
            e = e:gsub("([%a_][%w_]*)%s*%(([^()]*)%)", function(name, args)
                local v = CallFn(name, args, ab, power)
                if v == nil then C.unresolved[#C.unresolved + 1] = name; v = "?" end
                changed = true; return v
            end, 1)
            guard = guard + 1
        until not changed or guard > 20
        local v = Arith(e)
        if v then return tostring(Round(v)) end
        if e:find("[%(%)%?]") or e == "" then C.unresolved[#C.unresolved + 1] = expr; return "?" end
        return e   -- a resolved word ("Beast") or "100%"
    end)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("(%w+) |4(%a+):(%a+);?", function(n, one, many) return n .. " " .. ((tonumber(n) == 1 or n:lower() == "one") and one or many) end)
    text = text:gsub("%%%%", "%%"):gsub("(%d+%%) Hit Chance%s*", "%1 hit chance. "):gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
local STATE_TEXT = {
    untargettable = "Cannot be hit.", Stat_Dodge = "Chance to dodge attacks.", Mechanic_IsStunned = "Stunned: cannot act.", Mod_SpeedPercent = "Speed changed.",
    Mod_DamageTakenPercent = "Changes the damage taken.", Mod_DamageDealtPercent = "Changes the damage dealt.", Mod_HealingTakenPercent = "Changes the healing received.",
    Mod_HealingDealtPercent = "Changes the healing done.", Mechanic_IsBleeding = "Bleeding: takes damage every round.", Mechanic_IsBurning = "Burning: takes damage every round.",
    Mechanic_IsPoisoned = "Poisoned: takes damage every round.", Add_FlatDamageTaken = "Changes the damage of every attack against it.", Stat_Accuracy = "Changes hit chance.",
}
-- the description of an aura (status icon): the retail text of the ability that owns it, else a line built from its states
function C.AuraTip(id, power)
    local a = R.abilities[id]
    local t = a and C.Describe(setmetatable({ id = id }, { __index = a }), power) or ""   -- id lets the text resolve references to the aura itself
    if t == "" then
        local parts = {}
        for k in pairs(R.states[id] or {}) do if STATE_TEXT[k] then parts[#parts + 1] = STATE_TEXT[k] end end
        table.sort(parts); t = table.concat(parts, " ")
    end
    return t
end
-- family matchup for the tooltips: what this family hits hard / weakly, what hits it hard / weakly
function C.FamilyInfo(fam)   -- fam = family NAME ("Beast")
    local strong, weak, hurtBy, resists = {}, {}, {}, {}
    for _, f in ipairs(Rules.FAMILIES) do
        local m = Rules.Matchup(fam, f); if m > 1 then strong[#strong + 1] = f elseif m < 1 then weak[#weak + 1] = f end
        local h = Rules.Matchup(f, fam); if h > 1 then hurtBy[#hurtBy + 1] = f elseif h < 1 then resists[#resists + 1] = f end
    end
    return { name = fam, strong = table.concat(strong, "/"), weak = table.concat(weak, "/"), hurtBy = table.concat(hurtBy, "/"), resists = table.concat(resists, "/") }
end

-- the 6 abilities of a species as the journal shows them: { {slot=1, opt=1, unlock=1, ability=...}, ... }
function C.Kit(speciesId)
    local sp = assert(D.species[speciesId], "unknown species " .. tostring(speciesId))
    local rs = assert(R.species[sp.retail], "species " .. tostring(speciesId) .. " has no retail kit")
    local slots = { {}, {}, {} }
    for _, x in ipairs(rs.abil) do local list = slots[x[1] + 1]; list[#list + 1] = { lvl = x[2], id = x[3] } end
    local out = {}
    for slot = 1, 3 do
        table.sort(slots[slot], function(a, b) return a.lvl < b.lvl end)
        for opt, o in ipairs(slots[slot]) do out[#out + 1] = { slot = slot, opt = opt, unlock = o.lvl, ability = MakeAbility(speciesId, o.id) } end
    end
    return out
end
-- XP (retail BattlePetXP): a level needs WinsPerLevel wins of XpPerWin each; a win is worth XpPerWin of the ENEMY's level
function C.XPNeeded(level) local x = R.xp[math.max(1, math.min(D.MAX_LEVEL, level))]; return x[1] * x[2] end
function C.XPPerWin(level) return R.xp[math.max(1, math.min(D.MAX_LEVEL, level))][2] end
function C.Family(speciesId) return R.species[D.species[speciesId].retail].family end
function C.Stats(speciesId, level, quality) return Rules.Stats(R.species[D.species[speciesId].retail].stats, level, quality) end
function C.MaxHp(speciesId, level, quality) return C.Stats(speciesId, level, quality).health end

-- ---------------------------------------------------------------- pets
-- picks = { 1|2, 1|2, 1|2 } which option of each slot (nil = random); an option that is not unlocked yet falls back to the first one. opts = { quality = 1..4, hp = current health }
function C.NewPet(speciesId, level, picks, rng, opts)
    rng = rng or math.random
    local sp = assert(D.species[speciesId], "unknown species " .. tostring(speciesId))
    level = math.max(1, math.min(D.MAX_LEVEL, level))
    local quality = (opts and opts.quality) or 1
    local st = C.Stats(speciesId, level, quality)
    local pet = { species = speciesId, name = sp.name, icon = sp.icon, family = C.Family(speciesId), level = level, quality = quality, abil = {}, cd = { 0, 0, 0 },
                  max = st.health, baseMax = st.health, power = st.power, speed = st.speed, auras = {}, channel = nil, lastTaken = 0 }
    pet.hp = math.max(1, math.min(pet.max, (opts and opts.hp) or pet.max))
    local kit = C.Kit(speciesId)
    for slot = 1, 3 do
        local first, want = nil, (picks and picks[slot]) or rng(1, 2)
        local chosen
        for _, k in ipairs(kit) do
            if k.slot == slot then
                if k.opt == 1 then first = k end
                if k.opt == want then chosen = k end
            end
        end
        if first and level >= first.unlock then
            local k = (chosen and level >= chosen.unlock) and chosen or first
            local ab = {}; for key, v in pairs(k.ability) do ab[key] = v end
            ab.tip = C.Describe({ text = ab.text, turns = ab.turns, family = ab.family }, pet.power)   -- numbers for THIS pet's power
            pet.abil[slot] = ab
        end
    end
    return pet
end
function C.RollQuality(rng)
    rng = rng or math.random
    local total = 0; for _, w in ipairs(D.QUALITY_WEIGHTS) do total = total + w end
    local r = rng(1, total)
    for q, w in ipairs(D.QUALITY_WEIGHTS) do if r <= w then return q end; r = r - w end
    return 1
end
function C.NewBattle(P, Ei, rng) return { P = P, E = Ei, active = { P = 1, E = 1 }, round = 0, rng = rng or math.random } end
function C.Ready(pet, slot) return pet.abil[slot] ~= nil and pet.cd[slot] == 0 end

-- ---------------------------------------------------------------- auras / states
local CUR   -- the battle being resolved (set at the start of C.Round): weather lookups
local function WS() return CUR and CUR.weather and R.states[CUR.weather.id] or nil end   -- the states of the weather now active
local function Mod(pet, state)
    local t = 0; for _, a in ipairs(pet.auras) do t = t + (a.states[state] or 0) end
    local w = WS(); if w and w[state] and state:find("^Mechanic_Is") and pet.family ~= "Elemental" then t = t + w[state] end   -- Blizzard chills EVERY pet (Elemental passive: ignores weather)
    return t
end
local function EffFam(p)   -- Nature's Ward: while the aura lasts the pet's TYPE is another one (Special_TypeOverride, 1-based family id)
    for _, a in ipairs(p.auras) do local t = a.states.Special_TypeOverride; if t then return Rules.FAMILIES[t] or p.family end end
    return p.family
end
local function SyncMax(p)   -- Perk Up: maxHealthBonus (hundredths per level) while the aura lasts
    local bonus = 0
    for _, a in ipairs(p.auras) do local m = a.states.maxHealthBonus; if m then bonus = bonus + math.floor(m / 100 * p.level) end end
    p.baseMax = p.baseMax or p.max
    p.max = p.baseMax + bonus
    if p.hp > p.max then p.hp = p.max end
end
local function HasState(pet, stateId) local n = R.stateNames[stateId]; return n and Mod(pet, n) ~= 0 end
local function Beneficial(states)
    local score = 0
    for k, v in pairs(states) do
        if k == "Stat_Dodge" or k == "untargettable" or k == "Mod_HealingDealtPercent" or k == "Mod_MaxHealthPercent" or k == "Mod_SpeedPercent" or k == "Mod_DamageDealtPercent"
            or k == "Mod_HealingTakenPercent" or k == "Stat_Accuracy" then score = score + (v > 0 and 1 or -1)
        elseif k == "Mod_DamageTakenPercent" or k == "Add_FlatDamageTaken" then score = score + (v < 0 and 1 or -1)
        elseif k == "Mechanic_IsStunned" or k == "Mechanic_IsPoisoned" or k == "Mechanic_IsBurning" or k == "Mechanic_IsBleeding" or k == "Mechanic_IsWebbed"
            or k == "Mechanic_IsBlind" or k == "Mechanic_IsChilled" then score = score - 1 end
    end
    return score >= 0
end
function C.CantAct(pet) return pet.hp > 0 and (Mod(pet, "Mechanic_IsStunned") > 0 or Mod(pet, "turnLock") > 0) end   -- crowd controlled: the turn passes by itself
function C.Locked(pet, state) return Mod(pet, state) > 0 end   -- e.g. "swapOutLock" while hibernating
function C.Speed(p)
    local sp = p.speed * (1 + Mod(p, "Mod_SpeedPercent") / 100)
    if p.family == "Flying" and p.hp > p.max * 0.5 then sp = sp * 1.5 end   -- Flying passive
    return sp
end

local AURA_NAME = { [340] = "Burrowed", [311] = "Dodge" }
local function AuraName(id) return AURA_NAME[id] or (R.abilities[id] and R.abilities[id].name) or ("Effect " .. id) end
local function AuraTrigger(id)   -- event after which the aura removes itself (1 = the holder was hit, 2 = the holder attacked), nil = lasts its duration
    local a = R.abilities[id]; local t = a and a.turns[1]
    if not t or t.event == 255 then return nil end
    for _, f in ipairs(t.fx) do if f.prop == 49 then return t.event end end
end

-- DISPLAY ONLY (never changes engine rules): a damaging aura an ENEMY put on this pet is a debuff even when it has no state data (Rust/Creeping Fungus, Leech Seed, Acid Touch...);
-- Toxic Skin is a damaging BUFF (thorns). The status/log also uses the caster's flavored ability name (Rust) instead of the retail aura name (Creeping Fungus).
local DISPLAY_DMG = { [24] = true, [222] = true, [96] = true, [62] = true, [65] = true, [54] = true, [52] = true, [172] = true, [178] = true }
local NOT_HOSTILE = { [1086] = true }
local function DisplayHostile(id)
    local ab = R.abilities[id]
    if not ab or NOT_HOSTILE[id] then return false end
    for _, t in ipairs(ab.turns or {}) do for _, f in ipairs(t.fx) do if DISPLAY_DMG[f.prop] then return true end end end
    return false
end
local function AuraGood(id, states, holder, src)
    -- DISPLAY ONLY: an enemy's lock (sleep/polymorph/root/web/sticky) or hit-chance cut is a debuff although Beneficial() scores it 0; the user's OWN block (Silk Cocoon) is a buff
    if src and src ~= holder and (states.turnLock or states.swapOutLock or (states.Stat_Accuracy and states.Stat_Accuracy < 0)) then return false end
    if src == holder and states.Special_BlockedAttackCount then return true end
    return Beneficial(states) and not (src and src ~= holder and DisplayHostile(id))
end
local function AuraNameFor(id, src)
    if src and src.abil then for _, ab in ipairs(src.abil) do
        local ra = ab.id and R.abilities[ab.id]
        if ra and ab.name and ab.name ~= ra.name then
            for _, t in ipairs(ra.turns or {}) do for _, f in ipairs(t.fx) do if f.aura == id then return ab.name end end end
        end
    end end
    return AuraName(id)
end

-- apply aura `id` to pet (side s, index idx). duration in rounds; skipTick = it does not lose a round at the end of the round it was applied in
local HOSTILE_FX = { [24] = true, [222] = true, [54] = true, [52] = true, [172] = true, [178] = true }
local function MainTurns(ab)
    if not ab then return {} end
    if not ab._main then ab._main = {}; for _, t in ipairs(ab.turns) do if t.event == 255 then ab._main[#ab._main + 1] = t end end end
    return ab._main
end
local function AuraHostile(id)   -- an aura without state data (Ice Tomb, Soothe, Spore Shrooms) is hostile when its own turns deal damage / stun
    local ab = R.abilities[id]
    if not ab then return false end
    for _, t in ipairs(MainTurns(ab)) do for _, f in ipairs(t.fx) do if HOSTILE_FX[f.prop] then return true end end end
    return false
end
local function ApplyAura(b, ev, s, idx, id, duration, skipTick, maxStacks, source)
    local pet = b[s][idx]
    local ab0 = R.abilities[id]; if ab0 and #MainTurns(ab0) > 1 then duration = math.max(duration, #MainTurns(ab0)) end   -- shown / lasting as many rounds as it has turns
    local states = R.states[id] or {}
    if pet.family == "Critter" and source and source ~= pet and (states.Mechanic_IsStunned or states.swapOutLock) then return end   -- Critter passive: immune to stun / root / sleep from enemies
    if pet.family == "Aquatic" and duration > 1 and (AuraHostile(id) or states.Mechanic_IsBleeding or states.Mechanic_IsBurning or states.Mechanic_IsPoisoned) then duration = duration - 1 end   -- Aquatic passive: damage over time lasts a round less
    do local w = WS(); if w and w.Weather_Rain and duration > 1 and (AuraHostile(id) or states.Mechanic_IsBleeding or states.Mechanic_IsBurning or states.Mechanic_IsPoisoned) then duration = duration - 1 end end   -- Cleansing Rain: hostile damage over time lasts one round less
    if states.Mechanic_IsBomb then   -- Minefield / Booby-Trapped Presents: an object on the victim's TEAM; the next pet to ENTER the battlefield takes its damage (Detonate)
        b.bomb = b.bomb or {}; b.bomb[s] = { id = id, left = math.max(duration, 1), src = source, pwr = source and source.power }
        local what = AuraNameFor(id, source):lower()
        ev[#ev + 1] = { k = "debuff", side = s, idx = idx, what = what, turns = duration }
        return
    end
    local n = 0
    for _, a in ipairs(pet.auras) do if a.id == id then n = n + 1; a.left = duration; a.perm = duration >= 90; a.skip = skipTick and b.round or nil end end
    if n < (maxStacks and maxStacks > 0 and maxStacks or 1) then
        pet.auras[#pet.auras + 1] = { id = id, left = duration, perm = duration >= 90, states = states, skip = skipTick and b.round or nil, on = AuraTrigger(id),
                                       pwr = source and source.power, fam = (ab0 and ab0.family and ab0.family >= 0 and Rules.FAMILIES[ab0.family + 1]) or (source and (source.useFam or source.family)), src = source, charges = states.Special_BlockedAttackCount }
    end
    SyncMax(pet)
    local k, what = AuraGood(id, states, pet, source) and "buff" or "debuff", AuraNameFor(id, source):lower()
    for _, e in ipairs(ev) do if e.k == k and e.side == s and e.idx == idx and e.what == what then return end end   -- one ability with several effects of the same aura (Stench x3) announces it once
    ev[#ev + 1] = { k = k, side = s, idx = idx, what = what, turns = duration }
end
local function RemoveAura(pet, id)
    for i = #pet.auras, 1, -1 do if pet.auras[i].id == id then table.remove(pet.auras, i) end end
end
local function ConsumeAuras(pet, event)   -- auras that end after "the holder attacked" (2) / "the holder was hit" (1)
    for i = #pet.auras, 1, -1 do if pet.auras[i].on == event then table.remove(pet.auras, i) end end
end

-- ---------------------------------------------------------------- statuses for the addon
local function AuraTipFor(id, src, power)   -- a FLAVORED aura (Spore Shrooms shown as Rockslide) explains itself with the caster ability's own (flavor-scrubbed) text, not the retail story
    local name = AuraNameFor(id, src)
    if name ~= AuraName(id) and src and src.abil then
        for _, ab in ipairs(src.abil) do if ab.name == name and ab.text then return C.Describe({ text = ab.text, turns = ab.turns, family = ab.family }, power) end end
    end
    return C.AuraTip(id, power)
end
function C.StatusList(p)
    local t, seen = {}, {}
    for _, a in ipairs(p.auras) do
        local e = seen[a.id]
        if AuraName(a.id):find("Server Only") then   -- internal bookkeeping aura (speed priority): works in the engine, never shown to the player
        elseif e then e.stacks = e.stacks + 1; if not a.perm and a.left < 90 then e.turns = math.max(e.turns, a.left) end
        else
            local good = AuraGood(a.id, a.states, p, a.src)
            e = { aid = a.id, label = AuraNameFor(a.id, a.src), tip = AuraTipFor(a.id, a.src, a.pwr or p.power), icon = good and "Spell_Holy_PowerWordShield" or "Spell_Shadow_CurseOfTounges", turns = (a.perm or a.left >= 90) and 0 or a.left, stacks = 1, bad = not good }
            if a.states.untargettable then e.icon = "Ability_Stealth" elseif a.states.Stat_Dodge then e.icon = "Ability_Rogue_Feint"
            elseif a.states.Mod_SpeedPercent then e.icon = "Ability_Rogue_Sprint" elseif a.states.Mechanic_IsStunned then e.icon = "Spell_Frost_Stun"
            elseif a.states.Mechanic_IsBleeding then e.icon = "Ability_Rogue_Rupture" elseif a.states.Mechanic_IsPoisoned then e.icon = "Ability_Rogue_DualWeild"
            elseif a.states.Mod_DamageTakenPercent and a.states.Mod_DamageTakenPercent < 0 then e.icon = "Ability_Defend" end
            seen[a.id] = e; t[#t + 1] = e
        end
    end
    return t
end
C.tips = {}   -- label -> description of the last status built with that label (the battle sends each one to the addon once)
function C.StatusString(p)
    local out = {}
    for _, st in ipairs(C.StatusList(p)) do C.tips[st.label] = st.tip; out[#out + 1] = table.concat({ st.label, st.icon, st.turns, st.stacks, st.bad and 1 or 0 }, "~") end
    return table.concat(out, ";")
end
function C.TagText(p)
    local t = {}
    for _, st in ipairs(C.StatusList(p)) do t[#t + 1] = st.label .. (st.stacks > 1 and (" x" .. st.stacks) or "") end
    return table.concat(t, "  ")
end
local function Snap(b, ev, from)
    local tags = { P = C.TagText(b.P[b.active.P]), E = C.TagText(b.E[b.active.E]) }
    local stat = { P = C.StatusString(b.P[b.active.P]), E = C.StatusString(b.E[b.active.E]) }
    for i = from + 1, #ev do ev[i].tags = tags; ev[i].stat = stat end
end

-- ---------------------------------------------------------------- acting
local function MagicCap(p, d)   -- Magic passive: no single attack / tick / splash can take more than 35% of max health
    if p.family == "Magic" and d > math.floor(p.max * 0.35) then return math.floor(p.max * 0.35) end
    return d
end
local Detonate   -- (defined before RoundImpl)
local function Faint(b, ev, s, idx, final)   -- final = true: a real death (Explode, the meteor): the Undead / Mechanical revive does not apply
    local p = b[s][idx]; p.hp = 0
    if not final then   -- DARK REBIRTH (aura with a proc on event 7 + effect 111): "if killed, reborn with p1 % health" then the aura's own effects apply (a self drain per round)
        for ai = #p.auras, 1, -1 do
            local au = p.auras[ai]; local aab = R.abilities[au.id]
            for _, pt in ipairs(aab and aab.turns or {}) do
                if pt.event == 7 then for _, rf in ipairs(pt.fx) do if rf.prop == 111 and p.hp == 0 then
                    table.remove(p.auras, ai)
                    p.hp = math.max(1, math.floor(p.max * (rf.p[1] or 100) / 100)); p.channel = nil
                    local last = ev[#ev]
                    if last and ((last.k == "dmg" and last.tside == s and last.tidx == idx) or (last.k == "dot" and last.side == s and last.idx == idx)) then last.hp = p.hp end
                    ev[#ev + 1] = { k = "heal", side = s, idx = idx, amt = p.hp, hp = p.hp, max = p.max, quick = true, revive = true }
                    for _, rf2 in ipairs(pt.fx) do if rf2.prop == 26 and rf2.aura and rf2.aura ~= 0 then ApplyAura(b, ev, s, idx, rf2.aura, 99, true, nil, nil) end end
                end end end
            end
            if p.hp > 0 then return end
        end
    end
    if not final and not p.revived and (p.family == "Undead" or p.family == "Mechanical") then   -- family passives: Undead returns to life for ONE round, Mechanical returns to life at 20% health (once per pet per battle)
        p.revived = true
        if p.family == "Undead" then p.hp = 1; p.undeadLeft = 2 else p.hp = math.max(1, math.floor(p.max * 0.2)) end
        p.auras = {}; p.channel = nil
        local last = ev[#ev]   -- the hit that 'killed' it must not show a dead pet before the revive: it carries the revived health
        if last and ((last.k == "dmg" and last.tside == s and last.tidx == idx) or (last.k == "dot" and last.side == s and last.idx == idx)) then last.hp = p.hp end
        ev[#ev + 1] = { k = "heal", side = s, idx = idx, amt = p.hp, hp = p.hp, max = p.max, quick = true, revive = true }
        return
    end
    p.auras = {}; p.channel = nil; p.undeadLeft = nil
    ev[#ev + 1] = { k = "faint", side = s, idx = idx }
end
local function Heal(b, ev, s, i, amount, quick)
    local q = b[s][i]
    if not q or q.hp <= 0 then return 0 end
    local amt = math.min(amount, q.max - q.hp)
    if amt <= 0 then return 0 end   -- nothing healed: no event (no '+0' floating text / wait)
    q.hp = q.hp + amt
    ev[#ev + 1] = { k = "heal", side = s, idx = i, amt = amt, hp = q.hp, max = q.max, quick = quick }
    return amt
end

-- one damaging hit of `points` from pet (side s) to the enemy active pet. raw = a fixed damage number (Vengeance). Returns true when it landed.
-- Add_FlatDamageTaken auras (Wild Magic +5, Deflection / Crouch style -5 ...): every attack against the holder changes by value * the source's AttackBonus
local function Flat(tgt) local t = 0; for _, a in ipairs(tgt.auras) do local v = a.states.Add_FlatDamageTaken; if v then t = t + v * (1 + (a.pwr or 0) / 20) end end; local w = WS(); if w and w.Add_FlatDamageTaken and tgt.family ~= "Elemental" then t = t + w.Add_FlatDamageTaken end; return Round(t) end
local function WeatherBoost(fam, pet)   -- Lightning Storm / Blizzard / Cleansing Rain: +25% damage for abilities of one family
    local w = WS(); if pet and pet.family == "Elemental" then return 0 end
    if w and w.Mod_PetTypeDamageDealtPercent and Rules.FAMILIES[w.Mod_PetType_ID or 0] == fam then return w.Mod_PetTypeDamageDealtPercent end
    return 0
end
local function WeatherBonus(pet, tgt)   -- Lightning Storm: "all pets deal 3 bonus Mechanical damage each time they attack" (effect 169 in the weather aura's event-2 proc turn)
    if not (CUR and CUR.weather) or pet.family == "Elemental" then return 0 end
    local wab = R.abilities[CUR.weather.id]
    for _, pt in ipairs(wab and wab.turns or {}) do
        if pt.event == 2 then for _, f in ipairs(pt.fx) do if f.prop == 169 then return Rules.Damage(f.p[1], pet.power, Rules.FAMILIES[wab.family + 1] or "Mechanical", EffFam(tgt), 0, 0) end end end
    end
    return 0
end
local function Dmg(pet, tgt, points)
    local fam = pet.useFam or pet.family
    return math.max(1, Rules.Damage(points, pet.power, fam, EffFam(tgt), Mod(pet, "Mod_DamageDealtPercent") + WeatherBoost(fam, pet) + ((pet.family == "Beast" and pet.hp < pet.max * 0.5) and 25 or 0) + ((pet.family == "Dragonkin" and pet.dragonRound == (CUR and CUR.round)) and 50 or 0), Mod(tgt, "Mod_DamageTakenPercent")) + Flat(tgt) + WeatherBonus(pet, tgt))
end
local function Hit(b, ev, s, pet, points, accuracy, slot, more, raw)
    local o = Other(s); local oi = b.active[o]; local tgt = b[o][oi]
    if pet.hp <= 0 or tgt.hp <= 0 then return false end   -- a pet that died mid-ability (reflect / recoil) does not finish its remaining hits
    if tgt.undeadLeft == 2 then return false end   -- an Undead that just returned to life cannot be hit again in that same round
    if Mod(tgt, "untargettable") > 0 then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Burrowed!", more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    for i, a in ipairs(tgt.auras) do   -- Bubble / Soul Ward: blocks the next N attacks completely
        if a.charges and a.charges > 0 then
            a.charges = a.charges - 1; if a.charges <= 0 then table.remove(tgt.auras, i) end
            ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Blocked!", more = more, hp = tgt.hp, max = tgt.max }; return false
        end
    end
    if b.wall and b.wall.charges > 0 then   -- a wall in the field eats the attack (either side's)
        b.wall.charges = b.wall.charges - 1; if b.wall.charges <= 0 then b.wall = nil end
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Blocked!", more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    local dodge = math.min(100, Mod(tgt, "Stat_Dodge"))
    if dodge > 0 and b.rng(1, 100) <= dodge then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    local ws = WS(); if ws and ws.Stat_Accuracy and accuracy <= 100 and pet.family ~= "Elemental" then accuracy = accuracy + ws.Stat_Accuracy end   -- Sandstorm: every hit chance -10%
    local auraAcc = Mod(pet, "Stat_Accuracy"); if auraAcc ~= 0 and accuracy <= 100 then accuracy = math.max(0, accuracy + auraAcc) end   -- Lucky Dance / Focus / Stench / Blinding Poison / Uncertainty / Flash: hit chance of the ATTACKER's auras
    if accuracy < 100 and b.rng(1, 100) > accuracy then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Miss!", more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    local dmg = raw or Dmg(pet, tgt, points)
    local crit = (not raw) and b.rng(1, 100) <= 5 + Mod(pet, "Stat_CritChance")   -- Hawk Eye / Wombo Combo raise it
    if crit then dmg = dmg * 2 end
    dmg = MagicCap(tgt, dmg)
    if Mod(tgt, "unkillable") > 0 and tgt.hp - dmg < 1 then dmg = math.max(0, tgt.hp - 1) end   -- Survival: cannot drop below 1 health
    local hpBefore = tgt.hp
    tgt.hp = math.max(0, tgt.hp - dmg); tgt.lastTaken = dmg
    if pet.family == "Dragonkin" and hpBefore >= tgt.max * 0.5 and tgt.hp < tgt.max * 0.5 and tgt.hp > 0 then pet.dragonRound = b.round + 1 end   -- Dragonkin passive: +50% damage next round
    ev[#ev + 1] = { k = "dmg", side = s, idx = b.active[s], tside = o, tidx = oi, dmg = dmg, crit = crit, hp = tgt.hp, max = tgt.max, slot = slot, more = more,
                    counter = Rules.Matchup(pet.useFam or pet.family, EffFam(tgt)) }
    if pet.family == "Humanoid" and dmg > 0 and pet.hp > 0 then Heal(b, ev, s, b.active[s], math.floor(pet.max * 0.04), true) end   -- Humanoid passive: heals 4% of max health after dealing damage
    for _, a in ipairs(tgt.auras) do   -- reflect: "deals N damage each time you take direct damage" (aura ability with a proc turn on event 1 holding effect 179)
        local aab = R.abilities[a.id]
        for _, pt in ipairs(aab and aab.turns or {}) do
            if pt.event == 1 then for _, rf in ipairs(pt.fx) do
                if rf.prop == 204 and pet.hp > 0 and dmg > 0 then   -- Reflective Shield: p1 % of the direct damage taken goes back to the attacker
                    local rd = math.floor(dmg * rf.p[1] / 100)
                    if rd > 0 then
                        pet.hp = math.max(0, pet.hp - rd)
                        ev[#ev + 1] = { k = "dmg", side = o, idx = oi, tside = s, tidx = b.active[s], dmg = rd, hp = pet.hp, max = pet.max, reflect = true, more = false, counter = 1 }
                        if pet.hp <= 0 then Faint(b, ev, s, b.active[s]) end
                    end
                end
                if rf.prop == 179 and pet.hp > 0 then
                    local rd = MagicCap(pet, Rules.Damage(rf.p[1], a.pwr or tgt.power, a.fam or tgt.family, pet.family, 0, Mod(pet, "Mod_DamageTakenPercent")))
                    pet.hp = math.max(0, pet.hp - rd)
                    ev[#ev + 1] = { k = "dmg", side = o, idx = oi, tside = s, tidx = b.active[s], dmg = rd, hp = pet.hp, max = pet.max, reflect = true, more = false, counter = 1 }
                    if pet.hp <= 0 then Faint(b, ev, s, b.active[s]) end
                end
            end end
        end
    end
    for _, a in ipairs(pet.auras) do   -- Brittle Webbing: the holder takes damage each time it attacks
        local aab = R.abilities[a.id]
        for _, pt in ipairs(aab and aab.turns or {}) do
            if pt.event == 2 then for _, rf in ipairs(pt.fx) do
                if rf.prop == 24 and pet.hp > 0 then
                    local rd = MagicCap(pet, Rules.Damage(rf.p[1], a.pwr or pet.power, a.fam or pet.family, EffFam(pet), 0, Mod(pet, "Mod_DamageTakenPercent")))
                    pet.hp = math.max(0, pet.hp - rd)
                    ev[#ev + 1] = { k = "dmg", side = o, idx = oi, tside = s, tidx = b.active[s], dmg = rd, hp = pet.hp, max = pet.max, reflect = true, more = false, counter = 1 }
                    if pet.hp <= 0 then Faint(b, ev, s, b.active[s]) end
                end
            end end
        end
    end
    for _, a in ipairs(tgt.auras) do   -- Plagued Blood: when the holder is damaged the ATTACKER is healed
        local aab = R.abilities[a.id]
        for _, pt in ipairs(aab and aab.turns or {}) do
            if pt.event == 1 then for _, rf in ipairs(pt.fx) do if rf.prop == 23 and pet.hp > 0 then Heal(b, ev, s, b.active[s], Rules.Heal(rf.p[1], a.pwr or tgt.power)) end end end
        end
    end
    ConsumeAuras(pet, 2); ConsumeAuras(tgt, 1)
    if tgt.hp <= 0 then Faint(b, ev, o, oi) end
    return true
end

function C.LockLabel(pet) for _, au in ipairs(pet.auras) do if au.states and (au.states.Mechanic_IsStunned or au.states.turnLock) then return AuraNameFor(au.id, au.src) end end end
-- what the battle message says when a pet cannot act (the SAME words as the status that causes it)
local LOCK_TEXT = { Asleep = " is asleep and loses its turn!", Polymorphed = " has been turned into a frog and cannot act!", Stunned = " is stunned and loses its turn!",
                    Hibernation = " is hibernating and cannot act!", Napping = " is napping and cannot act!", ["Emerald Dream"] = " is dreaming and cannot act!", Repairing = " is repairing and cannot act!" }
function C.LockText(e)
    if e.pass then return " has nothing ready and passes the turn!" end
    return LOCK_TEXT[e.label or ""] or (e.label and (" is " .. e.label:lower() .. " and cannot act!")) or (e.self and " cannot act!" or " is stunned and loses its turn!")
end
-- ---------------------------------------------------------------- ability effects (one handler per retail effect, tried in this ORDER; the order is the old elseif chain)
-- X = the state of the ability being played (see Act): b ev s idx o pet tgt ab turn turnNo slot actedFirst actedSecond missStun hits hp0 + the counters done healed landed h29 h100 runK cstate weatherSeen.
-- A handler returns "stop" to end the rest of the effect list (the target died / nothing to consume).
-- 384 = extra hit when the user acted FIRST, 385 = when the user acted LAST (Tail Sweep, Arcane Slash, Scrabble, Steady Snap)
local function FX00(X, f)
    local p = f.p
    local b, ev, s, idx, pet, tgt, slot = X.b, X.ev, X.s, X.idx, X.pet, X.tgt, X.slot
            if p[2] >= 200 and DAMAGE[f.prop] and X.done > 0 then   -- Body Slam: a damage effect with accuracy 200 AFTER the ability already hit = damage to the USER itself (a lone 200 = Package Drop: just never misses)
                local selfDmg = math.max(1, Rules.Damage(p[1], pet.power, pet.family, pet.family, 0, 0))   -- retail SimpleDamage: recoil ignores the family matchup (an Elemental ability on a Critter user hit itself x0.67)
                pet.hp = math.max(1, pet.hp - selfDmg)   -- recoil can hurt but never faint the user
                ev[#ev + 1] = { k = "dmg", side = s, idx = idx, tside = s, tidx = idx, dmg = selfDmg, hp = pet.hp, max = pet.max, slot = slot, more = false, recoil = true, counter = 1 }
                do return end
            end
            X.done = X.done + 1
            local acc = (f.prop == 96 and HasState(tgt, p[4])) and 100 or p[2]
            X.landed = Hit(b, ev, s, pet, p[1], acc, slot, X.done < X.hits) or X.landed
            if X.landed and tgt.hp <= 0 then return "stop" end
end

-- damage that grows every time the ability is used
local function FX01(X, f)
    local p = f.p
    local b, ev, s, pet, ab, turnNo, slot = X.b, X.ev, X.s, X.pet, X.ab, X.turnNo, X.slot
            X.done = X.done + 1
            local uses = pet.ramp[ab.id] or 0; local pts = math.min(p[4], p[1] + p[3] * uses)
            if turnNo == 1 and #ab.turns >= 1 then pet.ramp[ab.id] = uses + 1 end
            X.landed = Hit(b, ev, s, pet, pts, p[2], slot, X.done < X.hits) or X.landed
end

-- Comeback: extra damage only if the user was hit before
local function FX02(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            if pet.lastTaken > 0 and tgt.hp > 0 then Hit(b, ev, s, pet, p[1], p[2], slot, false) end
end

-- one damage total, split evenly over every living enemy pet
local function FX03(X, f)
    local p = f.p
    local b, ev, s, idx, pet, tgt, slot = X.b, X.ev, X.s, X.idx, X.pet, X.tgt, X.slot
            X.done = X.done + 1
            local o2 = Other(s); local alive = {}
            for i, q in ipairs(b[o2]) do if q.hp > 0 then alive[#alive + 1] = i end end
            local total = Dmg(pet, tgt, p[1])
            if (p[3] or 0) > 0 and (p[4] or 0) > 0 then local w = WS(); if w and w.Weather_Rain then total = math.floor(total * (1 + p[3] / 100) + 0.5) end end   -- Dreadful Breath: extra damage in Cleansing Rain
            local share = math.max(1, math.floor(total / #alive + 0.5))
            for k, i in ipairs(alive) do
                local q = b[o2][i]
                if i == b.active[o2] then X.landed = Hit(b, ev, s, pet, 0, 100, slot, X.done < X.hits or k < #alive, share) or X.landed
                else
                    share = MagicCap(q, share); q.hp = math.max(0, q.hp - share)
                    ev[#ev + 1] = { k = "dmg", side = s, idx = idx, tside = o2, tidx = i, dmg = share, hp = q.hp, max = q.max, slot = slot, bench = true, more = true }
                    if q.hp <= 0 then Faint(b, ev, o2, i); ev[#ev].bench = true end
                end
            end
end

-- lifesteal: heal the user for p1 % of the damage this ability dealt so far
local function FX04(X, f)
    local p = f.p
    local b, ev, s, idx, tgt = X.b, X.ev, X.s, X.idx, X.tgt
            local got = X.hp0 - tgt.hp
            if got > 0 then Heal(b, ev, s, idx, math.floor(got * p[1] / 100)) end
end

-- stun when the user acts first
local function FX05(X, f)
    local p = f.p
    local b, ev, o, pet, tgt, actedFirst = X.b, X.ev, X.o, X.pet, X.tgt, X.actedFirst
            if actedFirst and tgt.hp > 0 and Mod(tgt, "untargettable") == 0 and (p[2] >= 100 or b.rng(1, 100) <= p[2]) then
                ApplyAura(b, ev, o, b.active[o], f.aura, math.max(1, p[3] or 1), false, nil, pet)
            end
end

-- damage p1, plus p3 more when the target has the state in p4 (Sludge Claw: Poisoned; Deep Burn / Personal Inferno: Burning; Sneak Attack: Blinded)
local function FX06(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            X.done = X.done + 1
            local pts = p[1]; if HasState(tgt, p[4]) then pts = pts + (p[3] or 0) end
            X.landed = Hit(b, ev, s, pet, pts, p[2], slot, X.done < X.hits) or X.landed
            if X.landed and tgt.hp <= 0 then return "stop" end
end

-- Impale: damage p1/p2, boosted by p3 % when the target is below 25% health
local function FX07(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            X.done = X.done + 1
            local pts = p[1]; if tgt.hp < tgt.max * 0.25 then pts = pts * (100 + (p[3] or 100)) / 100 end
            X.landed = Hit(b, ev, s, pet, pts, p[2], slot, X.done < X.hits) or X.landed
            if X.landed and tgt.hp <= 0 then return "stop" end
end

-- Explode: p1 % of the user's max health as damage to the enemy, then the user faints
local function FX08(X, f)
    local p = f.p
    local b, ev, s, idx, pet, slot = X.b, X.ev, X.s, X.idx, X.pet, X.slot
            X.done = X.done + 1
            X.landed = Hit(b, ev, s, pet, 0, p[2], slot, false, math.floor(pet.max * p[1] / 100)) or X.landed
            if pet.hp > 0 then pet.hp = 0; Faint(b, ev, s, idx, true) end   -- a suicide move is a REAL death: no Undead / Mechanical revive (later effects, e.g. Corpse Explosion's infection, still apply)
end

-- Weakening Blow: ordinary damage that can never take the target below 1 health
local function FX09(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            X.done = X.done + 1
            local dmg = Dmg(pet, tgt, p[1])
            X.landed = Hit(b, ev, s, pet, 0, p[2], slot, X.done < X.hits, math.max(0, math.min(dmg, tgt.hp - 1))) or X.landed
end

-- weather (Blizzard / Lightning Storm / Sandstorm / Rain): visual only for now, the addon draws a screen effect while it lasts
local function FX10(X, f)
    local p = f.p
    local b, ev = X.b, X.ev
            X.weatherSeen = true
            b.weather = { id = f.aura, left = math.max(1, p[3] or 1) }
            ev[#ev + 1] = { k = "weather", id = f.aura, turns = b.weather.left, name = AuraName(f.aura) }
end

-- Life Exchange: both active pets end on the same health (the average); nobody can go above their own maximum, nobody faints
local function FX11(X, f)
    local p = f.p
    local b, ev, s, idx, o, pet, tgt, slot = X.b, X.ev, X.s, X.idx, X.o, X.pet, X.tgt, X.slot
            if tgt.hp > 0 and pet.hp > 0 and Mod(tgt, "untargettable") == 0 then
                local avg = math.floor((pet.hp + tgt.hp) / 2)
                if tgt.hp > avg then
                    Heal(b, ev, s, idx, avg - pet.hp)
                    Hit(b, ev, s, pet, 0, 100, slot, false, math.min(tgt.hp - avg, tgt.hp - 1))
                elseif pet.hp > avg then
                    local loss = math.min(pet.hp - avg, pet.hp - 1); pet.hp = pet.hp - loss
                    ev[#ev + 1] = { k = "dmg", side = s, idx = idx, tside = s, tidx = idx, dmg = loss, hp = pet.hp, max = pet.max, slot = slot, more = false, recoil = true, counter = 1 }
                    Heal(b, ev, o, b.active[o], avg - tgt.hp)
                end
            end
end

-- TWO-USE blast: the first use sets an aura (77 Lock-On: on the TARGET; 75 Launch Rocket: on the USER), the second use deals p1 damage and removes it
local function FX12(X, f)
    local p = f.p
    local b, ev, s, idx, o, pet, tgt, slot = X.b, X.ev, X.s, X.idx, X.o, X.pet, X.tgt, X.slot
            local holder = (f.prop == 77) and tgt or pet; local hs = (f.prop == 77) and o or s; local hi = (f.prop == 77) and b.active[o] or idx
            local have; for _, a in ipairs(holder.auras) do if a.id == f.aura then have = a end end
            if have then
                RemoveAura(holder, f.aura)
                X.done = X.done + 1
                X.landed = Hit(b, ev, s, pet, p[1], p[2] or 100, slot, false) or X.landed
            elseif f.prop == 75 or (tgt.hp > 0 and Mod(tgt, "untargettable") == 0) then
                ApplyAura(b, ev, hs, hi, f.aura, (f.prop == 75) and 99 or 2, true, nil, pet)
            end
end

-- Nevermore: the enemy's next ability is locked out (aura with effect 129, see Act)
local function FX13(X, f)
    local p = f.p
    local b, ev, o, pet, tgt = X.b, X.ev, X.o, X.pet, X.tgt
            if tgt.hp > 0 and Mod(tgt, "untargettable") == 0 and (p[2] >= 100 or b.rng(1, 100) <= p[2]) then ApplyAura(b, ev, o, b.active[o], f.aura, math.max(1, p[3] or 2), true, nil, pet) end
end

-- Buried Treasure: heals the user for p1 % of its MAXIMUM health (the same effect inside an aura = Wish, handled in the aura tick)
local function FX14(X, f)
    local p = f.p
    local b, ev, s, idx, pet = X.b, X.ev, X.s, X.idx, X.pet
            Heal(b, ev, s, idx, math.floor(pet.max * p[1] / 100))
end

-- Healing Stream / Draconic Remedy / Rebuild: heals other living allies of the family in p4 (1-based family id) for p1 points; the k-th effect takes the k-th such ally
local function FX15(X, f)
    local p = f.p
    local b, ev, s, idx, pet = X.b, X.ev, X.s, X.idx, X.pet
            X.h100 = X.h100 + 1
            local want = Rules.FAMILIES[p[4] or 0]; local k = 0
            for i, q in ipairs(b[s]) do
                if i ~= idx and q.hp > 0 and (not want or q.family == want) then
                    k = k + 1
                    if k == X.h100 then Heal(b, ev, s, i, Rules.Heal(p[1], pet.power), true); break end
                end
            end
end

-- WALL (Prismatic Barrier, Ice Barrier, Beaver Dam, Weald Wall, Illusionary Barrier, Onyx Wall): a field object that blocks the next N attacks of EITHER side (Special_BlockedAttackCount, "allied and enemy attacks both count")
local function FX16(X, f)
    local p = f.p
    local b, ev, s, idx = X.b, X.ev, X.s, X.idx
            local st = R.states[f.aura] or {}
            b.wall = { id = f.aura, charges = st.Special_BlockedAttackCount or 2, owner = s }
            ev[#ev + 1] = { k = "buff", side = s, idx = idx, what = AuraName(f.aura):lower(), turns = b.wall.charges }
end

-- Cauterize: heal p1 % of the last hit this pet took
local function FX17(X, f)
    local p = f.p
    local b, ev, s, idx, pet = X.b, X.ev, X.s, X.idx, X.pet
            if pet.lastTaken > 0 then Heal(b, ev, s, idx, math.floor(pet.lastTaken * p[1] / 100), true) end
end

-- damage equal to the last hit this pet took
local function FX18(X, f)
    local p = f.p
    local b, ev, s, pet, slot = X.b, X.ev, X.s, X.pet, X.slot
            X.done = X.done + 1
            if pet.lastTaken > 0 then X.landed = Hit(b, ev, s, pet, 0, 100, slot, X.done < X.hits, math.floor(pet.lastTaken * p[1] / 100)) or X.landed end
end

-- f.prop == 138
local function FX19(X, f)
    local p = f.p
    local tgt = X.tgt
            if (p[5] or 0) == 0 or HasState(tgt, p[5]) then X.cstate[p[1]] = true end
end

-- caster-state form: extra damage to the enemy TEAM (every other living enemy), k-th effect = k-th enemy
local function FX20(X, f)
    local p = f.p
    local b, ev, s, idx, pet, slot = X.b, X.ev, X.s, X.idx, X.pet, X.slot
            if X.cstate[p[3]] then
                X.h29 = X.h29 + 1; local o2 = Other(s); local k = 0
                for i, q in ipairs(b[o2]) do
                    if q.hp > 0 and i ~= b.active[o2] then
                        k = k + 1
                        if k == X.h29 then
                            local d = MagicCap(q, Dmg(pet, q, p[1])); q.hp = math.max(0, q.hp - d)
                            ev[#ev + 1] = { k = "dmg", side = s, idx = idx, tside = o2, tidx = i, dmg = d, hp = q.hp, max = q.max, slot = slot, bench = true, more = true }
                            if q.hp <= 0 then Faint(b, ev, o2, i); ev[#ev].bench = true end
                        end
                    end
                end
            end
end

-- extra damage when the target has the state in p4
local function FX21(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            if HasState(tgt, p[4]) and tgt.hp > 0 then Hit(b, ev, s, pet, p[1], p[2], slot, false) end
end

-- heal: the k-th heal effect of an ability heals the k-th living ally (a lone effect heals the user)
local function FX22(X, f)
    local p = f.p
    local b, ev, s, idx, pet, turn = X.b, X.ev, X.s, X.idx, X.pet, X.turn
            X.healed = X.healed + 1
            local amount = (p[1] or 0) > 0 and Rules.Heal(p[1], pet.power) or 0
            if turn.healAll == nil then local n = 0; for _, g in ipairs(turn.fx) do if g.prop == 23 then n = n + 1 end end; turn.healAll = n > 1 end
            if turn.healAll then
                local k = 0
                for i, q in ipairs(b[s]) do if q.hp > 0 then k = k + 1; if k == X.healed then if amount > 0 then Heal(b, ev, s, i, amount, X.healed > 1) end; break end end end
            elseif amount > 0 then Heal(b, ev, s, idx, amount) end
end

-- heal when the target was killed by this ability; with a state in p4 (Leech Life) the heal is EXTRA while the target has that state
local function FX23(X, f)
    local p = f.p
    local b, ev, s, idx, pet, tgt = X.b, X.ev, X.s, X.idx, X.pet, X.tgt
            if p[4] and p[4] ~= 0 then if HasState(tgt, p[4]) then Heal(b, ev, s, idx, Rules.Heal(p[1], pet.power)) end
            elseif tgt.hp <= 0 then Heal(b, ev, s, idx, Rules.Heal(p[1], pet.power)) end
end

-- Haymaker: stuns the USER when the swing misses, nothing otherwise
local function FX24(X, f)
    local p = f.p
    local b, ev, s, idx, pet = X.b, X.ev, X.s, X.idx, X.pet
            if not X.landed then ApplyAura(b, ev, s, idx, f.aura, math.max(1, p[3] or 1), true, nil, pet) end   -- skipTick: the stun costs the NEXT action
end

-- Who gets an aura effect: true = the user, false = the enemy (shared by FX25 and the presentation rules, pet-battle/gen_vis.py)
local function AuraIsSelf(prop, aura)
    local states = R.states[aura] or {}
    if prop == 63 or prop == 26 then return true end
    if prop == 54 or prop == 172 or prop == 52 or prop == 178 then return false end
    return Beneficial(states) and not states.Mechanic_IsBomb and not (prop == 50 and AuraHostile(aura))
end
C.AuraIsSelf = AuraIsSelf
-- f.prop == 26 or f.prop == 63 or APPLY[f.prop] or f.prop == 54 or f.prop == 172
local function FX25(X, f)
    local p = f.p
    local b, ev, s, o, pet, tgt, actedSecond = X.b, X.ev, X.s, X.o, X.pet, X.tgt, X.actedSecond
            local states = R.states[f.aura] or {}
            local selfAura = AuraIsSelf(f.prop, f.aura)   -- 63 heal-over-time = user; 54 damage-over-time and 172 stun chance = enemy; the rest by the sign of the aura's states (a mine is laid behind the OPPONENT; 26 = the user's OWN aura even when harmful; 50 without state data = the ENEMY when the aura's own turns deal damage / stun)
            local chance, dur, stacks = p[2], p[3], (f.prop == 50) and p[4] or nil
            if f.prop == 172 then chance, dur = (p[4] ~= 0 and HasState(tgt, p[4])) and 100 or p[6], math.max(1, p[3]) end   -- Deep Freeze: p6 % chance, certain when the target has the state in p4
            local target = selfAura and s or o
            local ok = (target == s) or (tgt.hp > 0 and Mod(tgt, "untargettable") == 0)
            if ok and (chance >= 100 or b.rng(1, 100) <= chance) then
                ApplyAura(b, ev, target, b.active[target], f.aura, (dur < 0) and 99 or math.max(1, dur), actedSecond or states.Mod_SpeedPercent ~= nil or AuraTrigger(f.aura) == 2 or (target == s and (states.Mod_DamageDealtPercent or 0) > 0), stacks, pet)   -- a speed change only matters at the START of a round: it counts from the next one
            end
end

-- Consume Corpse (condition): without an unused allied corpse the whole ability fizzles
local function FX26(X, f)
    local p = f.p
    local b, s, pet = X.b, X.s, X.pet
            local has; for _, q in ipairs(b[s]) do if q ~= pet and q.hp <= 0 and not q.corpseUsed then has = true end end
            if not has then return "stop" end
end

-- Consume Corpse: eats the first unused allied corpse and restores p1 % of the user's max health
local function FX27(X, f)
    local p = f.p
    local b, ev, s, idx, pet = X.b, X.ev, X.s, X.idx, X.pet
            for _, q in ipairs(b[s]) do if q ~= pet and q.hp <= 0 and not q.corpseUsed then q.corpseUsed = true; Heal(b, ev, s, idx, math.floor(pet.max * p[1] / 100)); break end end
end

-- placeholder turn (wind-up round of a channel): nothing happens
local function FX28(X, f)
    local p = f.p
    -- nothing happens
end

-- Refuge: every OTHER living friendly Critter (benched too) gets the aura (a block); the k-th effect = the k-th ally
local function FX29(X, f)
    local p = f.p
    local b, ev, s, pet = X.b, X.ev, X.s, X.pet
            X.runK = (X.runK or 0) + 1
            local k2 = 0
            for i2, q in ipairs(b[s]) do
                if q ~= pet and q.hp > 0 then k2 = k2 + 1; if k2 == X.runK then if q.family == "Critter" then ApplyAura(b, ev, s, i2, f.aura, (p[3] or 1) > 0 and p[3] or 1, false, nil, pet) end; break end end
            end
end

-- Plant: ACTIVATE = rooted (cannot swap) and healed p1 points every round; USING IT AGAIN deactivates
local function FX30(X, f)
    local p = f.p
    local ev, s, idx, pet = X.ev, X.s, X.idx, X.pet
            local has; for i2, a2 in ipairs(pet.auras) do if a2.id == f.aura then has = i2 end end
            if has then table.remove(pet.auras, has)
            else
                pet.auras[#pet.auras + 1] = { id = f.aura, left = 99, perm = true, states = R.states[f.aura] or { swapOutLock = 1 }, pwr = pet.power, src = pet, hot = p[1] }
                ev[#ev + 1] = { k = "buff", side = s, idx = idx, what = AuraName(f.aura):lower(), turns = 99 }
            end
end

-- Pump: FIRST use = +10% damage dealt (aura f.aura), SECOND use = the release: p1 damage, the aura ends
local function FX31(X, f)
    local p = f.p
    local b, ev, s, idx, pet, slot = X.b, X.ev, X.s, X.idx, X.pet, X.slot
            local has; for i2, a2 in ipairs(pet.auras) do if a2.id == f.aura then has = i2 end end
            if not has then
                pet.auras[#pet.auras + 1] = { id = f.aura, left = 99, perm = true, states = R.states[f.aura] or { Mod_DamageDealtPercent = 10 }, pwr = pet.power, fam = pet.useFam or pet.family, src = pet }
                ev[#ev + 1] = { k = "buff", side = s, idx = idx, what = AuraName(f.aura):lower(), turns = 99 }
            else
                table.remove(pet.auras, has); X.done = X.done + 1
                X.landed = Hit(b, ev, s, pet, p[1], p[2], slot, false) or X.landed
            end
end

-- Powerball: every use raises the user's speed by p1 % (stacks, capped)
local function FX32(X, f)
    local p = f.p
    local ev, s, idx, pet = X.ev, X.s, X.idx, X.pet
            local n = 0; for _, a2 in ipairs(pet.auras) do if a2.id == 831 then n = n + 1 end end
            if n < 8 then pet.auras[#pet.auras + 1] = { id = 831, left = 99, perm = true, states = { Mod_SpeedPercent = p[1] }, pwr = pet.power, src = pet }; ev[#ev + 1] = { k = "buff", side = s, idx = idx, what = "speed boost", turns = 99 } end
end

-- Apocalypse
local function FX33(X, f)
    local p = f.p
    local b, s = X.b, X.s
        b.meteor = { left = 15, by = s }
end

-- Mana Surge: extra damage while the weather state in p4 is active (Arcane Winds)
local function FX34(X, f)
    local p = f.p
    local b, ev, s, pet, tgt, slot = X.b, X.ev, X.s, X.pet, X.tgt, X.slot
            local wn = R.stateNames[p[4]]; local w = WS()
            if wn and w and w[wn] and tgt.hp > 0 then Hit(b, ev, s, pet, p[1], p[2], slot, false) end
end

-- Spiny Carapace: used again while its aura is still active = the stronger aura too (tripled)
local function FX35(X, f)
    local p = f.p
    local b, ev, s, idx, pet, turn = X.b, X.ev, X.s, X.idx, X.pet, X.turn
            local mainAura; for _, g in ipairs(turn.fx) do if g.prop == 26 and g.aura ~= 0 then mainAura = g.aura end end
            local active = false; for _, a in ipairs(pet.auras) do if a.id == mainAura then active = true end end
            if active then ApplyAura(b, ev, s, idx, f.aura, math.max(1, p[3] or 1), true, nil, pet) end
end

-- Sniff Out: removes every object (mushrooms, cyclones) from the battlefield
local function FX36(X, f)
    local p = f.p
    local b = X.b
            for _, sd in ipairs({ "P", "E" }) do for _, q in ipairs(b[sd]) do for i = #q.auras, 1, -1 do if q.auras[i].states.Mechanic_IsObject then table.remove(q.auras, i) end end end end
end

-- f.prop == 49
local function FX37(X, f)
    local p = f.p
    local pet = X.pet
        RemoveAura(pet, f.aura)
end

-- Consume Magic / Sear Magic: "removes all buffs and debuffs from the user"
local function FX38(X, f)
    local p = f.p
    local pet = X.pet
        pet.auras = {}; SyncMax(pet)
end

-- Nether Gate (107): forces an opponent's pet to swap into battle (a random living one); Death Grip (139): the LOWEST health living pet
local function FX39(X, f)
    local p = f.p
    local b, ev, s, idx, tgt = X.b, X.ev, X.s, X.idx, X.tgt
            local o2 = Other(s); local cand = {}
            for i2, q in ipairs(b[o2]) do if q.hp > 0 and i2 ~= b.active[o2] then cand[#cand + 1] = i2 end end
            if f.prop == 139 and #cand > 0 then table.sort(cand, function(x, y) return b[o2][x].hp < b[o2][y].hp end); cand = { cand[1] } end
            if X.landed and tgt.hp > 0 and #cand > 0 and Mod(tgt, "swapOutLock") == 0 then
                local from = b.active[o2]; b[o2][from].channel = nil;   -- a pet that leaves mid-channel forgets it (else the pet that comes in would run that slot)
                b.active[o2] = cand[(f.prop == 139) and 1 or b.rng(1, #cand)]
                ev[#ev + 1] = { k = "swap", side = o2, from = from, idx = b.active[o2], free = true, forced = true }
                Detonate(b, ev, o2)
            end
end

-- not (INERT[f.prop] or DAMAGE[f.prop] or f.prop == 384 or f.prop == 385)
local function FX40(X, f)
    local p = f.p
        C.unknown[f.prop] = (C.unknown[f.prop] or 0) + 1
end

local EFFECTS = {
    { function(f, X) local p = f.p; local actedFirst, actedSecond = X.actedFirst, X.actedSecond; return DAMAGE[f.prop] or (f.prop == 384 and actedFirst) or (f.prop == 385 and actedSecond) end,
      FX00 },
    { function(f, X) local p = f.p; return f.prop == 27 end,
      FX01 },
    { function(f, X) local p = f.p; return f.prop == 59 end,
      FX02 },
    { function(f, X) local p = f.p; return f.prop == 141 end,
      FX03 },
    { function(f, X) local p = f.p; return f.prop == 32 end,
      FX04 },
    { function(f, X) local p = f.p; return f.prop == 131 end,
      FX05 },
    { function(f, X) local p = f.p; return f.prop == 226 end,
      FX06 },
    { function(f, X) local p = f.p; return f.prop == 66 end,
      FX07 },
    { function(f, X) local p = f.p; return f.prop == 68 end,
      FX08 },
    { function(f, X) local p = f.p; return f.prop == 149 end,
      FX09 },
    { function(f, X) local p = f.p; return f.prop == 80 end,
      FX10 },
    { function(f, X) local p = f.p; return f.prop == 67 end,
      FX11 },
    { function(f, X) local p = f.p; return f.prop == 77 or f.prop == 75 end,
      FX12 },
    { function(f, X) local p = f.p; return f.prop == 168 end,
      FX13 },
    { function(f, X) local p = f.p; return f.prop == 53 end,
      FX14 },
    { function(f, X) local p = f.p; return f.prop == 100 end,
      FX15 },
    { function(f, X) local p = f.p; return f.prop == 150 end,
      FX16 },
    { function(f, X) local p = f.p; return f.prop == 44 end,
      FX17 },
    { function(f, X) local p = f.p; return f.prop == 197 end,
      FX18 },
    { function(f, X) local p = f.p; return f.prop == 138 end,
      FX19 },
    { function(f, X) local p = f.p; return f.prop == 29 and (p[3] or 0) > 0 end,
      FX20 },
    { function(f, X) local p = f.p; return f.prop == 29 end,
      FX21 },
    { function(f, X) local p = f.p; return f.prop == 23 end,
      FX22 },
    { function(f, X) local p = f.p; return f.prop == 104 end,
      FX23 },
    { function(f, X) local p = f.p; local missStun = X.missStun; return f.prop == 52 and missStun end,
      FX24 },
    { function(f, X) local p = f.p; return f.prop == 26 or f.prop == 63 or APPLY[f.prop] or f.prop == 54 or f.prop == 172 end,
      FX25 },
    { function(f, X) local p = f.p; return f.prop == 144 end,
      FX26 },
    { function(f, X) local p = f.p; return f.prop == 61 end,
      FX27 },
    { function(f, X) local p = f.p; return f.prop == 22 end,
      FX28 },
    { function(f, X) local p = f.p; return f.prop == 223 end,
      FX29 },
    { function(f, X) local p = f.p; return f.prop == 78 end,
      FX30 },
    { function(f, X) local p = f.p; return f.prop == 76 end,
      FX31 },
    { function(f, X) local p = f.p; local ab = X.ab; return f.prop == 79 and not ab.priority end,
      FX32 },
    { function(f, X) local p = f.p; return f.prop == 159 end,
      FX33 },
    { function(f, X) local p = f.p; return f.prop == 170 end,
      FX34 },
    { function(f, X) local p = f.p; return f.prop == 137 end,
      FX35 },
    { function(f, X) local p = f.p; return f.prop == 85 and p[1] == 69 end,
      FX36 },
    { function(f, X) local p = f.p; return f.prop == 49 end,
      FX37 },
    { function(f, X) local p = f.p; return f.prop == 31 and p[1] == 141 and p[2] == 1 end,
      FX38 },
    { function(f, X) local p = f.p; return f.prop == 107 or f.prop == 139 end,
      FX39 },
    { function(f, X) local p = f.p; return not (INERT[f.prop] or DAMAGE[f.prop] or f.prop == 384 or f.prop == 385) end,
      FX40 },
}
local function RunEffects(X, fxlist)
    for _, f in ipairs(fxlist) do
        for _, e in ipairs(EFFECTS) do
            if e[1](f, X) then
                if e[2](X, f) == "stop" then return end
                break
            end
        end
    end
end


local function Act(b, ev, s, cmd, used)
    local idx, o = b.active[s], Other(s)
    local pet, tgt = b[s][idx], b[o][b.active[o]]
    if pet.hp <= 0 or tgt.hp <= 0 then return end
    local function lockLabel() return C.LockLabel(pet) end
    if Mod(pet, "Mechanic_IsStunned") > 0 then ev[#ev + 1] = { k = "stunned", side = s, idx = idx, label = lockLabel() }; return end
    if Mod(pet, "turnLock") > 0 then ev[#ev + 1] = { k = "stunned", side = s, idx = idx, self = true, label = lockLabel() }; return end   -- Hibernating: cannot act (the heals still tick)
    local ab, turnNo, slot
    if pet.channel then ab, turnNo, slot = pet.channel.ab, pet.channel.turn, pet.channel.slot
    else
        slot = tonumber((cmd or "A1"):sub(2)) or 1
        if not C.Ready(pet, slot) then slot = 1 end
        if not C.Ready(pet, slot) then   -- nothing usable (every ability is on cooldown): retail passes the turn; the cooldown must never be ignored
            ev[#ev + 1] = { k = "stunned", side = s, idx = idx, self = true, pass = true }; return
        end
        ab = pet.abil[slot]; turnNo = 1
        pet.cd[slot] = ab.cd; used[pet] = slot
        for i = #pet.auras, 1, -1 do   -- Nevermore (aura with a proc on event 9 + effect 129): the NEXT ability this pet uses is locked out for p1 rounds (cooldown) and the aura ends
            local a = pet.auras[i]; local ab9 = a.on == 9 and R.abilities[a.id]
            if ab9 then for _, t9 in ipairs(ab9.turns) do for _, f9 in ipairs(t9.fx) do if f9.prop == 129 then pet.cd[slot] = math.max(pet.cd[slot] or 0, f9.p[1]); table.remove(pet.auras, i) end end end end
        end
    end
    pet.useFam = (ab.family and ab.family >= 0) and Rules.FAMILIES[ab.family + 1] or nil   -- retail: damage uses the ABILITY's family (Bite = Beast damage whoever bites)
    local turn = ab.turns[turnNo]
    local actedFirst = b.acted[o] ~= true
    local actedSecond = not actedFirst
    b.acted[s] = true
    pet.channel = (#ab.turns > turnNo) and { ab = ab, turn = turnNo + 1, slot = slot } or nil
    local missStun = false; for _, f in ipairs(turn.fx) do if f.prop == 194 then missStun = true end end
    local hits = 0   -- how many damage hits this turn deals (playback needs to know which one is the last)
    for _, f in ipairs(turn.fx) do if DAMAGE[f.prop] or f.prop == 197 or f.prop == 66 or f.prop == 226 or f.prop == 68 or f.prop == 149 or (f.prop == 384 and actedFirst) or (f.prop == 385 and actedSecond) then hits = hits + 1 end end
    ev[#ev + 1] = { k = "act", side = s, idx = idx, slot = slot, ab = ab.id, name = ab.name, dmg = hits > 0, vis = ab.vis, ranged = ab.ranged, vm = ab.vmode, vpre = ab.vpre, vhop = ab.vhop, vdmg = ab.vdmg }
    local X = { b = b, ev = ev, s = s, idx = idx, o = o, pet = pet, tgt = tgt, ab = ab, turn = turn, turnNo = turnNo, slot = slot, actedFirst = actedFirst, actedSecond = actedSecond, missStun = missStun, hits = hits,
                hp0 = tgt.hp, done = 0, healed = 0, landed = false, runK = nil, cstate = {}, h29 = 0, h100 = 0, weatherSeen = false }   -- cstate/h29: Howling Blast caster states; h100: k-th ally heal
    pet.ramp = pet.ramp or {}
    local function runFx(fxlist) return RunEffects(X, fxlist) end
    runFx(turn.fx)
    for _, pt in ipairs(ab.procs or {}) do for _, f in ipairs(pt.fx) do if (f.prop == 145 or f.prop == 107) and turnNo == 1 then   -- Portal (145): avoids this round's attacks, then swaps with the healthiest living ally; Fade (107 in a proc turn): swaps with a RANDOM living ally
        pet.auras[#pet.auras + 1] = { id = 1124, left = 1, skip = nil, states = { untargettable = 1 }, pwr = pet.power, src = pet }; pet.portalSwap = (f.prop == 145) and true or "random"
    end end end
    if X.landed then for _, pt in ipairs(ab.procs or {}) do if pt.event == 2 then runFx(pt.fx) end end end   -- procs: effects that follow damage the user dealt (Leech Life's healing)
    if not X.weatherSeen then   -- the hit killed the target and ended the loop early: the weather still arrives
        for _, f in ipairs(turn.fx) do
            if f.prop == 80 then
                b.weather = { id = f.aura, left = math.max(1, f.p[3] or 1) }
                ev[#ev + 1] = { k = "weather", id = f.aura, turns = b.weather.left, name = AuraName(f.aura) }
            end
        end
    end
    pet.useFam = nil
end

-- periodic effects of auras (damage over time, heal over time) at the end of every round, then durations tick down
local function Periodic(b, ev, s)
    local idx = b.active[s]; local p = b[s][idx]
    if p.hp <= 0 then return end
    local dmg, stacks, heal = 0, 0, 0
    for _, a in ipairs(p.auras) do
        local ab = R.abilities[a.id]
        a.ticks = (a.ticks or 0) + 1
        if a.hot then heal = heal + Rules.Heal(a.hot, a.pwr or p.power) end   -- Planted: heals every round while it lasts
        local mt = MainTurns(ab)
        local t = ab and mt[math.min(a.ticks, #mt)]   -- an aura with several turns (Hibernation: 10 / 20 / 40 healing) plays one per round
        if ab and #mt > 1 and a.ticks >= #mt then a.left = 0 end   -- ...and ends after its last one
        if t and not (a.ticks > #mt and #mt > 1) then
            local drains = false; for _, f in ipairs(t.fx) do if DAMAGE[f.prop] or f.prop == 65 then drains = true end end
            local auraDmg, leechPct, teamK = 0, nil, nil
            for _, f in ipairs(t.fx) do
                if DAMAGE[f.prop] and a.src == p then   -- Chew: the delayed bonus attack of the holder itself hits its ENEMY
                    local before = #ev; p.useFam = a.fam; Hit(b, ev, s, p, f.p[1], f.p[2], 1, false); p.useFam = nil
                    for k = before + 1, #ev do ev[k].auraHit = true end   -- a bonus attack driven by an aura (Chew, Sons of the Root)
                elseif f.prop == 32 then leechPct = f.p[1]   -- Leech Seed
                elseif DAMAGE[f.prop] or f.prop == 65 then
                    local pts, acc = f.p[1], (f.prop == 65) and 100 or f.p[2]
                    local pctOfMax = f.prop == 62 and ab and ab.text and (ab.text:find("%% of the target's health") or ab.text:find("%% health each round"))   -- (Corpse Explosion infection; Dark Rebirth drain)
                    if f.prop == 65 then local w, wn = WS(), R.stateNames[f.p[4]]; if w and wn and w[wn] then pts = pts + (f.p[3] or 0) end end   -- Creeping Fungus: more damage in Moonlight
                    if acc >= 100 or b.rng(1, 100) <= acc then   -- Cyclone: each tick lands only with its hit chance
                        local d = Rules.Damage(pts, a.pwr or p.power, a.fam or p.family, EffFam(p), 0, Mod(p, "Mod_DamageTakenPercent"))
                        if pctOfMax then d = math.max(1, math.floor(p.max * f.p[1] / 100)) end   -- Corpse Explosion's infection: 5% of max health per round
                        local teamAura = ab and ab.text and (ab.text:find("your team") or ab.text:find("enemy team"))
                        if teamAura then   -- "damage to your team each round": the k-th damage effect hits the k-th living pet of the holder's team (the active one takes only the first)
                            teamK = (teamK or 0) + 1
                            local n, target = 0, nil
                            for i2, q in ipairs(b[s]) do if q.hp > 0 then n = n + 1; if n == teamK then target = i2 end end end
                            if target and target ~= idx then
                                local q = b[s][target]; d = MagicCap(q, d); q.hp = math.max(0, q.hp - d)
                                ev[#ev + 1] = { k = "dmg", side = (s == "P") and "E" or "P", idx = b.active[(s == "P") and "E" or "P"], tside = s, tidx = target, dmg = d, hp = q.hp, max = q.max, bench = true, more = true }
                                if q.hp <= 0 then Faint(b, ev, s, target); ev[#ev].bench = true end
                            elseif target == idx then dmg = dmg + d; auraDmg = auraDmg + d; stacks = stacks + 1 end
                        else dmg = dmg + d; auraDmg = auraDmg + d; stacks = stacks + 1 end
                    end
                elseif f.prop == 23 then
                    if drains and a.src and a.src ~= p then   -- Siphon Life: the damage hurts the holder, the healing goes to the CASTER
                        for _, sd in ipairs({ "P", "E" }) do for i2, q in ipairs(b[sd]) do if q == a.src then Heal(b, ev, sd, i2, Rules.Heal(f.p[1], a.pwr or q.power)) end end end
                    else heal = heal + Rules.Heal(f.p[1], a.pwr or p.power) end
                elseif f.prop == 171 then   -- Photosynthesis: the same heal AGAIN while the weather state in p3 is up (Sunny)
                    local w, sn = WS(), R.stateNames[f.p[3] or 0]
                    if w and sn and w[sn] then heal = heal + Rules.Heal(f.p[1], a.pwr or p.power) end
                elseif f.prop == 53 then heal = heal + math.floor(p.max * f.p[1] / 100)   -- Wish: a % of the holder's maximum health
                elseif (f.prop == 54 or f.prop == 178 or f.prop == 52) and f.aura and f.aura ~= 0 then ApplyAura(b, ev, s, idx, f.aura, math.max(1, f.p[3] or 1), false, nil, a.src)   -- Spore Shrooms / Drowsy / Ice Tomb: the finished aura releases its effect
                end
            end
            if leechPct and auraDmg > 0 and a.src and a.src ~= p then   -- Leech Seed: the caster is healed for p1 % of the damage this aura dealt
                for _, sd in ipairs({ "P", "E" }) do for i2, q in ipairs(b[sd]) do if q == a.src then Heal(b, ev, sd, i2, math.floor(math.min(auraDmg, p.hp) * leechPct / 100)) end end end
            end
        end
    end
    if dmg > 0 then
        dmg = MagicCap(p, dmg)
        if Mod(p, "unkillable") > 0 and p.hp - dmg < 1 then dmg = math.max(0, p.hp - 1) end
        p.hp = math.max(0, p.hp - dmg); p.lastTaken = dmg
        ev[#ev + 1] = { k = "dot", side = s, idx = idx, dmg = dmg, stacks = stacks, hp = p.hp, max = p.max }
        if p.hp <= 0 then Faint(b, ev, s, idx); return end
    end
    if heal > 0 then Heal(b, ev, s, idx, heal) end
end
local function EndOfRound(b, ev, used)
    for _, sd in ipairs({ "P", "E" }) do local bm = b.bomb and b.bomb[sd]; if bm then bm.left = bm.left - 1; if bm.left <= 0 then b.bomb[sd] = nil end end end   -- a mine that nobody stepped on wears off
    for _, sd in ipairs({ "P", "E" }) do   -- Portal / Fade: the user swaps with the living ally that has the MOST health (Portal) or a RANDOM one (Fade)
        local cur = b[sd][b.active[sd]]
        if cur.portalSwap then
            local mode = cur.portalSwap; cur.portalSwap = nil
            local best, bi, cand = nil, nil, {}
            for i2, q in ipairs(b[sd]) do
                if i2 ~= b.active[sd] and q.hp > 0 then cand[#cand + 1] = i2; if not best or q.hp > best.hp then best, bi = q, i2 end end
            end
            if mode == "random" and #cand > 0 then bi = cand[b.rng(1, #cand)] end
            if bi and cur.hp > 0 then
                for i2 = #cur.auras, 1, -1 do if cur.auras[i2].id == 1124 then table.remove(cur.auras, i2) end end
                local from = b.active[sd]; cur.channel = nil; b.active[sd] = bi
                ev[#ev + 1] = { k = "swap", side = sd, from = from, idx = bi, free = true, forced = true }
                Detonate(b, ev, sd)
            end
        end
    end
    if b.meteor then
        b.meteor.left = b.meteor.left - 1
        if b.meteor.left <= 0 then
            b.meteor = nil
            for _, sd in ipairs({ "P", "E" }) do
                local q = b[sd][b.active[sd]]
                local roach = q.name and (q.name:find("Cockroach") or q.name:find("Beetle"))
                if q.hp > 0 and Mod(q, "unkillable") == 0 and not roach then q.hp = 0; Faint(b, ev, sd, b.active[sd], true) end
            end
        end
    end
    if b.weather then
        b.weather.left = b.weather.left - 1
        if b.weather.left <= 0 then b.weather = nil; ev[#ev + 1] = { k = "weather", id = 0, turns = 0, name = "" } end
    end
    for _, s in ipairs({ "P", "E" }) do
        Periodic(b, ev, s)
        local p = b[s][b.active[s]]
        for qi, q in ipairs(b[s]) do   -- the Undead's extra round is over (also for one that was swapped out: it dies on the bench)
            if q.undeadLeft and q.hp > 0 then q.undeadLeft = q.undeadLeft - 1; if q.undeadLeft <= 0 then q.undeadLeft = nil; q.hp = 0; Faint(b, ev, s, qi, true); if qi ~= b.active[s] then ev[#ev].bench = true end end end
        end
        p = b[s][b.active[s]]
        if p.hp > 0 then
            for i = #p.auras, 1, -1 do
                local a = p.auras[i]
                if a.skip ~= b.round and not a.perm then a.left = a.left - 1 end   -- a permanent aura (99 turns) never counts down
                if a.left <= 0 then table.remove(p.auras, i) end
            end
            SyncMax(p)
        end
        for _, q in ipairs(b[s]) do SyncMax(q) end   -- benched pets too (a temporary max health bonus never lingers)
        for _, q in ipairs(b[s]) do
            for sl = 1, 3 do if q.cd[sl] > 0 and used[q] ~= sl then q.cd[sl] = q.cd[sl] - 1 end end
        end
    end
end

-- CAPTURE (retail trap): possible when the enemy's ACTIVE pet is at or below D.CAPTURE_HP of its health. Uses the player's turn; the enemy pet is simply gone (b.captured lists its index).
function C.CanTrap(b) local e = b.E[b.active.E]; return e.hp > 0 and e.hp <= e.max * D.CAPTURE_HP and not e.noTrap end

-- random usable ability for the enemy (retail's AI picks from what is ready)
function C.AI(b)
    local pet = b.E[b.active.E]
    if pet.channel then return "A" .. pet.channel.slot end
    local hurt = false; for _, q in ipairs(b.E) do if q.hp > 0 and q.hp < q.max then hurt = true end end
    local ready = {}
    for sl = 1, 3 do
        if C.Ready(pet, sl) then
            local turn = pet.abil[sl].turns[1]; local healOnly, buffActive = true, false
            for _, f in ipairs(turn.fx) do
                if DAMAGE[f.prop] or f.prop == 384 or f.prop == 385 or f.prop == 29 or f.prop == 197 or f.prop == 66 or f.prop == 226 or f.prop == 68 or f.prop == 149 or f.prop == 44 or f.prop == 141 or f.prop == 27 or f.prop == 59 or f.prop == 131 or APPLY[f.prop] or f.prop == 54 or f.prop == 172 then healOnly = false end
                if (f.prop == 26 or f.prop == 63) and f.aura ~= 0 then for _, a in ipairs(pet.auras) do if a.id == f.aura then buffActive = true end end end
            end
            local useless = (healOnly and not hurt and #turn.fx > 0 and not (turn.fx[1].prop == 49)) or buffActive   -- the brain does not waste a heal at full health or re-apply a running buff
            if not useless then ready[#ready + 1] = sl end
        end
    end
    if #ready == 0 then return "A1" end
    return "A" .. ready[b.rng(1, #ready)]
end

Detonate = function(b, ev, s)   -- the pet that just entered side s takes the team's bomb (Minefield): the aura's own damage turn, with the caster's power and family
    local bomb = b.bomb and b.bomb[s]; if not bomb then return end
    b.bomb[s] = nil
    local q, ab = b[s][b.active[s]], R.abilities[bomb.id]
    if not q or q.hp <= 0 or not ab then return end
    local base; for _, t in ipairs(ab.turns or {}) do for _, f in ipairs(t.fx) do if not base and f.prop == 24 then base = f.p[1] end end end
    if not base then return end
    local fam = (ab.family and ab.family >= 0 and Rules.FAMILIES[ab.family + 1]) or (bomb.src and bomb.src.family)
    local d = math.max(1, math.floor(Round(base * Bonus(bomb.pwr)) * (fam and Rules.Matchup(fam, q.family) or 1)))
    d = MagicCap(q, d); q.hp = math.max(0, q.hp - d); q.lastTaken = d
    local o = (s == "P") and "E" or "P"
    ev[#ev + 1] = { k = "dmg", side = o, idx = b.active[o], tside = s, tidx = b.active[s], dmg = d, hp = q.hp, max = q.max, reflect = true }   -- shown like a reflect hit: wound emote + health, no lunge
    if q.hp <= 0 then Faint(b, ev, s, b.active[s]) end
end

local function Priority(pet, cmd)   -- abilities that "always go first" (data: effect 79 / the text)
    if not cmd or cmd:sub(1, 1) ~= "A" then return false end
    local ab = pet.channel and pet.channel.ab or pet.abil[tonumber(cmd:sub(2)) or 1]
    return ab ~= nil and ab.priority == true and not pet.channel
end

local function RoundImpl(b, cmdP, cmdE)
    CUR = b
    local ev, used = {}, {}
    b.round = b.round + 1
    b.acted = {}
    local forcedSwap = b.P[b.active.P].hp <= 0
    if cmdP:sub(1, 1) == "S" then
        local to = tonumber(cmdP:sub(2)); local from = b.active.P
        b.P[from].channel = nil
        b.active.P = to
        ev[#ev + 1] = { k = "swap", side = "P", from = from, idx = to, free = forcedSwap }
        Detonate(b, ev, "P")
        if b.P[b.active.P].hp <= 0 then   -- the mine killed the pet that came in
            if Alive(b, "P") == 0 then ev[#ev + 1] = { k = "end", result = "loss" }; return ev, "loss" end
            return ev, "force"
        end
        if forcedSwap then ev[#ev + 1] = { k = "turn" }; return ev, "turn" end
        cmdP = nil
    end
    local order
    if cmdP == "T" then
        if C.CanTrap(b) then
            local e = b.E[b.active.E]
            ev[#ev + 1] = { k = "trap", side = "E", idx = b.active.E }
            e.hp = 0; e.captured = true; e.auras = {}; e.channel = nil
            b.captured = b.captured or {}; b.captured[#b.captured + 1] = b.active.E
            cmdP = nil; order = {}
        else cmdP = "A1" end
    end
    local pe, ee = b.P[b.active.P], b.E[b.active.E]
    if order then
    elseif cmdP then
        local pp, ep = Priority(pe, cmdP), Priority(ee, cmdE)
        local playerFirst = (pp and not ep) or ((pp == ep) and C.Speed(pe) >= C.Speed(ee))   -- equal speed: the player goes first
        order = playerFirst and { "P", "E" } or { "E", "P" }
    else order = { "E" } end
    for _, s in ipairs(order) do local from = #ev; Act(b, ev, s, s == "P" and cmdP or cmdE, used); Snap(b, ev, from) end
    local from = #ev; EndOfRound(b, ev, used); Snap(b, ev, from)
    if b.E[b.active.E].hp <= 0 then
        local nx = NextAlive(b, "E")
        if nx then
            b.active.E = nx; ev[#ev + 1] = { k = "spawn", side = "E", idx = nx }; Detonate(b, ev, "E")
            while b.E[b.active.E].hp <= 0 do   -- the mine killed it: the next one comes in
                local n2 = NextAlive(b, "E"); if not n2 then break end
                b.active.E = n2; ev[#ev + 1] = { k = "spawn", side = "E", idx = n2 }
            end
            if b.E[b.active.E].hp <= 0 then ev[#ev + 1] = { k = "end", result = "win" }; return ev, "win" end
        else ev[#ev + 1] = { k = "end", result = "win" }; return ev, "win" end
    end
    if b.P[b.active.P].hp <= 0 then
        if Alive(b, "P") == 0 then ev[#ev + 1] = { k = "end", result = "loss" }; return ev, "loss" end
        return ev, "force"
    end
    return ev, "turn"
end
function C.Round(b, cmdP, cmdE)   -- CUR (weather lookups) only exists while a round is resolved: it never leaks into later calls
    local ev, st = RoundImpl(b, cmdP, cmdE); CUR = nil; return ev, st
end
-- end of a battle: every temporary effect goes away before health is saved (Perk Up's max health bonus must not inflate the saved health)
function C.Finish(b)
    for _, sd in ipairs({ "P", "E" }) do for _, q in ipairs(b[sd]) do q.auras = {}; q.channel = nil; q.undeadLeft = nil; SyncMax(q) end end
end

return C
