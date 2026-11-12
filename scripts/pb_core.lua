-- Pet battle CORE (retail-based): pure Lua, no game API. Interprets the retail ability data in pb_retail.lua (generated from the DB2 tables by pet-battle/gen_retail.py)
-- with the retail rules in pb_rules.lua. pb_battle plays back the event list this returns and syncs the addon.
-- Species: pb_data.species[creature entry].retail = retail BattlePetSpecies id. Abilities unlock by level exactly as retail (slot 1 at L1, slot 2 at L2, slot 3 at L4; 2nd option of a slot at L10/15/20).
-- EFFECT PROPS (BattlePetEffectProperties id -> meaning, inferred from the ability texts; params are the labelled columns Param_0..5):
--   24, 222  damage: p1 Points, p2 Accuracy       96 same, but always hits when the target has state p4 (Spectral Strike vs Blinded)       384  extra hit only if the user acted first       29  extra damage if the target has state p3 (Takedown vs stunned, Maul vs bleeding)
--   23       heal: p1 Points (one effect per ally in team order: Bleat has three)                    104 heal p1 points when this ability kills       197 damage = last hit taken
--   26       apply aura to the USER (or the enemy if its states are harmful): p2 chance, p3 duration     50/52/178  same with p2 chance, p3 duration, 50: p4 max stacks   172 stun chance p5
--   54       damage-over-time aura on the enemy (p3 duration)      63  heal-over-time aura on the user (p3 duration)
--   49       remove aura f.aura from the user (also what an aura does to itself after its event 1 = holder was hit, 2 = holder attacked)
--   158 177 85 229 116 28 170: gates/weather/transform markers, not interpreted (they are listed by pet-battle/test_core.lua as "not interpreted")
local D = require("pb_data")
local R = require("pb_retail")
local Rules = require("pb_rules")
local C = {}
PB_CORE = C
C.unknown = {}

local DAMAGE = { [24] = true, [222] = true, [96] = true }
local APPLY = { [50] = true, [52] = true, [178] = true }
local INERT = { [158] = true, [177] = true, [85] = true, [229] = true, [116] = true, [28] = true, [170] = true }
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
    Stampede = "Ability_Hunter_Pet_Boar", Bite = "Ability_Druid_Maul", Claw = "Ability_Druid_Rake", Rake = "Ability_Druid_Rake", Pounce = "Ability_Druid_Pounce", Screech = "Ability_Hunter_Pet_Bat",
    Devour = "Ability_Druid_FerociousBite", Prowl = "Ability_Druid_SupriseAttack", Maul = "Ability_Druid_Maul", Howl = "Ability_Hunter_Pet_Wolf", Crouch = "Ability_Defend", Leap = "Ability_Druid_Dash",
    Vengeance = "Ability_Warrior_Revenge", Hoof = "Ability_Druid_Maul", Headbutt = "Ability_Warrior_PunishingBlow", Bleat = "Spell_Nature_HealingWay", Tranquility = "Spell_Nature_Tranquility",
    ["Nature's Ward"] = "Spell_Nature_ResistNature", Roar = "Ability_Druid_DemoralizingRoar", Bash = "Ability_Druid_Bash", Hibernate = "Spell_Nature_Sleep", Clobber = "Ability_ThunderBolt",
    Punch = "Ability_Warrior_Sunder", Takedown = "Ability_Warrior_Charge", Mangle = "Ability_Druid_Mangle2", Rampage = "Ability_Warrior_Rampage",
}
local function Clean(text)
    text = (text or ""):gsub("%[[^%]]*%]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("Hit Chance", ""):gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function MakeAbility(speciesId, aid)
    local a = assert(R.abilities[aid], "retail ability " .. tostring(aid) .. " missing from pb_retail.lua")
    local ov = D.rename[speciesId] and D.rename[speciesId][a.name] or {}
    return { id = aid, name = ov.name or a.name, retailName = a.name, icon = ov.icon or ICON[a.name] or "Ability_Warrior_Rampage", tip = Clean(a.text), cd = a.cd, turns = a.turns,
             vis = ov.vis or VIS[a.name], ranged = ov.ranged }
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
                  max = st.health, power = st.power, speed = st.speed, auras = {}, channel = nil, lastTaken = 0 }
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
            pet.abil[slot] = k.ability
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
local function Mod(pet, state) local t = 0; for _, a in ipairs(pet.auras) do t = t + (a.states[state] or 0) end; return t end
local function HasState(pet, stateId) local n = R.stateNames[stateId]; return n and Mod(pet, n) ~= 0 end
local function Beneficial(states)
    local score = 0
    for k, v in pairs(states) do
        if k == "Stat_Dodge" or k == "untargettable" or k == "Mod_HealingDealtPercent" or k == "Mod_MaxHealthPercent" or k == "Mod_SpeedPercent" or k == "Mod_DamageDealtPercent"
            or k == "Mod_HealingTakenPercent" then score = score + (v > 0 and 1 or -1)
        elseif k == "Mod_DamageTakenPercent" or k == "Add_FlatDamageTaken" then score = score + (v < 0 and 1 or -1)
        elseif k == "Mechanic_IsStunned" or k == "Mechanic_IsPoisoned" or k == "Mechanic_IsBurning" or k == "Mechanic_IsBleeding" or k == "Mechanic_IsWebbed"
            or k == "Mechanic_IsBlind" or k == "Mechanic_IsChilled" then score = score - 1 end
    end
    return score >= 0
end
function C.Speed(p) return p.speed * (1 + Mod(p, "Mod_SpeedPercent") / 100) end

local AURA_NAME = { [340] = "Burrowed", [311] = "Dodge" }
local function AuraName(id) return AURA_NAME[id] or (R.abilities[id] and R.abilities[id].name) or ("Effect " .. id) end
local function AuraTrigger(id)   -- event after which the aura removes itself (1 = the holder was hit, 2 = the holder attacked), nil = lasts its duration
    local a = R.abilities[id]; local t = a and a.turns[1]
    if not t or t.event == 255 then return nil end
    for _, f in ipairs(t.fx) do if f.prop == 49 then return t.event end end
end

-- apply aura `id` to pet (side s, index idx). duration in rounds; skipTick = it does not lose a round at the end of the round it was applied in
local function ApplyAura(b, ev, s, idx, id, duration, skipTick, maxStacks, source)
    local pet = b[s][idx]
    local states = R.states[id] or {}
    local n = 0
    for _, a in ipairs(pet.auras) do if a.id == id then n = n + 1; a.left = duration; a.skip = skipTick and b.round or nil end end
    if n < (maxStacks and maxStacks > 0 and maxStacks or 1) then
        pet.auras[#pet.auras + 1] = { id = id, left = duration, states = states, skip = skipTick and b.round or nil, on = AuraTrigger(id),
                                       pwr = source and source.power, fam = source and source.family }
    end
    ev[#ev + 1] = { k = Beneficial(states) and "buff" or "debuff", side = s, idx = idx, what = AuraName(id):lower(), turns = duration }
end
local function RemoveAura(pet, id)
    for i = #pet.auras, 1, -1 do if pet.auras[i].id == id then table.remove(pet.auras, i) end end
end
local function ConsumeAuras(pet, event)   -- auras that end after "the holder attacked" (2) / "the holder was hit" (1)
    for i = #pet.auras, 1, -1 do if pet.auras[i].on == event then table.remove(pet.auras, i) end end
end

-- ---------------------------------------------------------------- statuses for the addon
function C.StatusList(p)
    local t, seen = {}, {}
    for _, a in ipairs(p.auras) do
        local e = seen[a.id]
        if e then e.stacks = e.stacks + 1; e.turns = math.max(e.turns, a.left)
        else
            local good = Beneficial(a.states)
            e = { label = AuraName(a.id), icon = good and "Spell_Holy_PowerWordShield" or "Spell_Shadow_CurseOfTounges", turns = a.left, stacks = 1, bad = not good }
            if a.states.untargettable then e.icon = "Ability_Stealth" elseif a.states.Stat_Dodge then e.icon = "Ability_Rogue_Feint"
            elseif a.states.Mod_SpeedPercent then e.icon = "Ability_Rogue_Sprint" elseif a.states.Mechanic_IsStunned then e.icon = "Spell_Frost_Stun"
            elseif a.states.Mechanic_IsBleeding then e.icon = "Ability_Rogue_Rupture" elseif a.states.Mechanic_IsPoisoned then e.icon = "Ability_Rogue_DualWeild"
            elseif a.states.Mod_DamageTakenPercent and a.states.Mod_DamageTakenPercent < 0 then e.icon = "Ability_Defend" end
            seen[a.id] = e; t[#t + 1] = e
        end
    end
    return t
end
function C.StatusString(p)
    local out = {}
    for _, st in ipairs(C.StatusList(p)) do out[#out + 1] = table.concat({ st.label, st.icon, st.turns, st.stacks, st.bad and 1 or 0 }, "~") end
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
local function Faint(b, ev, s, idx)
    local p = b[s][idx]; p.hp = 0; p.auras = {}; p.channel = nil
    ev[#ev + 1] = { k = "faint", side = s, idx = idx }
end
local function Heal(b, ev, s, i, amount, quick)
    local q = b[s][i]
    if not q or q.hp <= 0 then return 0 end
    local amt = math.min(amount, q.max - q.hp); q.hp = q.hp + amt
    ev[#ev + 1] = { k = "heal", side = s, idx = i, amt = amt, hp = q.hp, max = q.max, quick = quick }
    return amt
end

-- one damaging hit of `points` from pet (side s) to the enemy active pet. raw = a fixed damage number (Vengeance). Returns true when it landed.
local function Hit(b, ev, s, pet, points, accuracy, slot, more, raw)
    local o = Other(s); local oi = b.active[o]; local tgt = b[o][oi]
    if tgt.hp <= 0 then return false end
    if Mod(tgt, "untargettable") > 0 then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Burrowed!", more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    local dodge = math.min(100, Mod(tgt, "Stat_Dodge"))
    if dodge > 0 and b.rng(1, 100) <= dodge then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    if accuracy < 100 and b.rng(1, 100) > accuracy then
        ev[#ev + 1] = { k = "dodge", side = o, idx = oi, from = s, text = "Miss!", more = more, hp = tgt.hp, max = tgt.max }; return false
    end
    local dmg = raw or Rules.Damage(points, pet.power, pet.family, tgt.family, Mod(pet, "Mod_DamageDealtPercent"), Mod(tgt, "Mod_DamageTakenPercent"))
    local crit = (not raw) and b.rng(1, 100) <= 5
    if crit then dmg = dmg * 2 end
    tgt.hp = math.max(0, tgt.hp - dmg); tgt.lastTaken = dmg
    ev[#ev + 1] = { k = "dmg", side = s, idx = b.active[s], tside = o, tidx = oi, dmg = dmg, crit = crit, hp = tgt.hp, max = tgt.max, slot = slot, more = more,
                    counter = Rules.Matchup(pet.family, tgt.family) }
    ConsumeAuras(pet, 2); ConsumeAuras(tgt, 1)
    if tgt.hp <= 0 then Faint(b, ev, o, oi) end
    return true
end

local function Act(b, ev, s, cmd, used)
    local idx, o = b.active[s], Other(s)
    local pet, tgt = b[s][idx], b[o][b.active[o]]
    if pet.hp <= 0 or tgt.hp <= 0 then return end
    if Mod(pet, "Mechanic_IsStunned") > 0 then ev[#ev + 1] = { k = "stunned", side = s, idx = idx }; return end
    local ab, turnNo, slot
    if pet.channel then ab, turnNo, slot = pet.channel.ab, pet.channel.turn, pet.channel.slot
    else
        slot = tonumber((cmd or "A1"):sub(2)) or 1
        if not C.Ready(pet, slot) then slot = 1 end
        ab = pet.abil[slot]; turnNo = 1
        pet.cd[slot] = ab.cd; used[pet] = slot
    end
    local turn = ab.turns[turnNo]
    local actedFirst = b.acted[o] ~= true
    local actedSecond = not actedFirst
    b.acted[s] = true
    pet.channel = (#ab.turns > turnNo) and { ab = ab, turn = turnNo + 1, slot = slot } or nil
    local hits = 0   -- how many damage hits this turn deals (playback needs to know which one is the last)
    for _, f in ipairs(turn.fx) do if DAMAGE[f.prop] or f.prop == 197 or (f.prop == 384 and actedFirst) then hits = hits + 1 end end
    ev[#ev + 1] = { k = "act", side = s, idx = idx, slot = slot, ab = ab.id, name = ab.name, dmg = hits > 0, vis = ab.vis, ranged = ab.ranged }
    local done, healed, landed = 0, 0, false
    for _, f in ipairs(turn.fx) do
        local p = f.p
        if DAMAGE[f.prop] or (f.prop == 384 and actedFirst) then
            done = done + 1
            local acc = (f.prop == 96 and HasState(tgt, p[4])) and 100 or p[2]
            landed = Hit(b, ev, s, pet, p[1], acc, slot, done < hits) or landed
            if landed and tgt.hp <= 0 then break end
        elseif f.prop == 197 then   -- damage equal to the last hit this pet took
            done = done + 1
            if pet.lastTaken > 0 then landed = Hit(b, ev, s, pet, 0, 100, slot, done < hits, math.floor(pet.lastTaken * p[1] / 100)) or landed end
        elseif f.prop == 29 then   -- extra damage when the target has the state in p3
            if HasState(tgt, p[3]) and tgt.hp > 0 then Hit(b, ev, s, pet, p[1], p[2], slot, false) end
        elseif f.prop == 23 then   -- heal: the k-th heal effect of an ability heals the k-th living ally (a lone effect heals the user)
            healed = healed + 1
            local amount = Rules.Heal(p[1], pet.power)
            if turn.healAll == nil then local n = 0; for _, g in ipairs(turn.fx) do if g.prop == 23 then n = n + 1 end end; turn.healAll = n > 1 end
            if turn.healAll then
                local k = 0
                for i, q in ipairs(b[s]) do if q.hp > 0 then k = k + 1; if k == healed then Heal(b, ev, s, i, amount, healed > 1); break end end end
            else Heal(b, ev, s, idx, amount) end
        elseif f.prop == 104 then   -- heal when the target was killed by this ability
            if tgt.hp <= 0 then Heal(b, ev, s, idx, Rules.Heal(p[1], pet.power)) end
        elseif f.prop == 26 or f.prop == 63 or APPLY[f.prop] or f.prop == 54 or f.prop == 172 then
            local states = R.states[f.aura] or {}
            local selfAura                      -- 63 heal-over-time = user; 54 damage-over-time and 172 stun chance = enemy; the rest by the sign of the aura's states
            if f.prop == 63 then selfAura = true elseif f.prop == 54 or f.prop == 172 then selfAura = false else selfAura = Beneficial(states) end
            local chance, dur, stacks = p[2], p[3], (f.prop == 50) and p[4] or nil
            if f.prop == 172 then chance, dur = p[5], p[4] end
            local target = selfAura and s or o
            local ok = (target == s) or (tgt.hp > 0 and Mod(tgt, "untargettable") == 0)
            if ok and (chance >= 100 or b.rng(1, 100) <= chance) then
                ApplyAura(b, ev, target, b.active[target], f.aura, math.max(1, dur), actedSecond, stacks, pet)
            end
        elseif f.prop == 49 then RemoveAura(pet, f.aura)
        elseif not (INERT[f.prop] or DAMAGE[f.prop] or f.prop == 384) then C.unknown[f.prop] = (C.unknown[f.prop] or 0) + 1 end
    end
end

-- periodic effects of auras (damage over time, heal over time) at the end of every round, then durations tick down
local function Periodic(b, ev, s)
    local idx = b.active[s]; local p = b[s][idx]
    if p.hp <= 0 then return end
    local dmg, stacks, heal = 0, 0, 0
    for _, a in ipairs(p.auras) do
        local ab = R.abilities[a.id]; local t = ab and ab.turns[1]
        if t and t.event == 255 then
            for _, f in ipairs(t.fx) do
                if DAMAGE[f.prop] then dmg = dmg + Rules.Damage(f.p[1], a.pwr or p.power, a.fam or p.family, p.family, 0, Mod(p, "Mod_DamageTakenPercent")); stacks = stacks + 1
                elseif f.prop == 23 then heal = heal + Rules.Heal(f.p[1], a.pwr or p.power) end
            end
        end
    end
    if dmg > 0 then
        p.hp = math.max(0, p.hp - dmg); p.lastTaken = dmg
        ev[#ev + 1] = { k = "dot", side = s, idx = idx, dmg = dmg, stacks = stacks, hp = p.hp, max = p.max }
        if p.hp <= 0 then Faint(b, ev, s, idx); return end
    end
    if heal > 0 then Heal(b, ev, s, idx, heal) end
end
local function EndOfRound(b, ev, used)
    for _, s in ipairs({ "P", "E" }) do
        Periodic(b, ev, s)
        local p = b[s][b.active[s]]
        if p.hp > 0 then
            for i = #p.auras, 1, -1 do
                local a = p.auras[i]
                if a.skip ~= b.round then a.left = a.left - 1 end
                if a.left <= 0 then table.remove(p.auras, i) end
            end
        end
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
    local ready = {}
    for sl = 1, 3 do if C.Ready(pet, sl) then ready[#ready + 1] = sl end end
    return "A" .. (ready[b.rng(1, #ready)] or 1)
end

function C.Round(b, cmdP, cmdE)
    local ev, used = {}, {}
    b.round = b.round + 1
    b.acted = {}
    local forcedSwap = b.P[b.active.P].hp <= 0
    if cmdP:sub(1, 1) == "S" then
        local to = tonumber(cmdP:sub(2)); local from = b.active.P
        b.active.P = to
        ev[#ev + 1] = { k = "swap", side = "P", from = from, idx = to, free = forcedSwap }
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
    elseif cmdP then order = (C.Speed(pe) >= C.Speed(ee)) and { "P", "E" } or { "E", "P" }   -- equal speed: the player goes first
    else order = { "E" } end
    for _, s in ipairs(order) do local from = #ev; Act(b, ev, s, s == "P" and cmdP or cmdE, used); Snap(b, ev, from) end
    local from = #ev; EndOfRound(b, ev, used); Snap(b, ev, from)
    if b.E[b.active.E].hp <= 0 then
        local nx = NextAlive(b, "E")
        if nx then b.active.E = nx; ev[#ev + 1] = { k = "spawn", side = "E", idx = nx }
        else ev[#ev + 1] = { k = "end", result = "win" }; return ev, "win" end
    end
    if b.P[b.active.P].hp <= 0 then
        if Alive(b, "P") == 0 then ev[#ev + 1] = { k = "end", result = "loss" }; return ev, "loss" end
        return ev, "force"
    end
    return ev, "turn"
end

return C
