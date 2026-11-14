-- NOT WIRED INTO run_tests.sh: it still reports KNOWN FAILURES (see DEVNOTES 6.12c: Life Exchange edge cases, Frostbite growth, Dark Rebirth, one-round self buffs). Wire it in once they are fixed.
-- QA engine attacks (reviewer, new file): luajit pet-battle/test_qa_engine.lua
-- 1 recoil (Body Slam 532 / Stone Rush 621) ignores the family matchup for EVERY user family, 2 Life Exchange (277) edge cases + event stream validity,
-- 3 ability claims for abilities test_abilities cannot see (Blistering Cold growth, Dark Rebirth revive).
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local fails, passes = {}, 0
local function check(ok, msg) if ok then passes = passes + 1 else fails[#fails + 1] = msg end end
local function dice(v) return function(a, b) return math.max(a, math.min(b, v)) end end
local PASS = { id = 0, name = "Pass", icon = "x", tip = "", cd = 0, turns = { { fx = {} } } }
local function copy(ab) local c = {}; for k, v in pairs(ab) do c[k] = v end; return c end
local function kitAb(retailName)   -- the ability as built by C.Kit from any species (pinned test species 1156 included)
    D.species[999999] = D.species[999999] or { name = "Pinned", retail = 1156 }
    for id in pairs(D.species) do for _, k in ipairs(C.Kit(id)) do if k.ability.retailName == retailName then return copy(k.ability) end end end
end
local function duel(ab, o)
    o = o or {}
    local rng = dice(o.roll or 6)
    local a = C.NewPet(721, o.level or 10, { 1, 1, 1 }, rng, { quality = o.q or 3 }); local e = C.NewPet(721, o.elevel or o.level or 10, { 1, 1, 1 }, rng, { quality = o.eq or o.q or 3 })
    a.family = o.family or "Critter"; e.family = o.efamily or "Critter"
    a.abil = { ab }; a.cd = { 0, 0, 0 }; e.abil = { o.eab or PASS }; e.cd = { 0, 0, 0 }
    a.speed = o.slower and 1 or 100000; e.speed = o.slower and 100000 or 1
    local b = C.NewBattle({ a }, o.bench and { e, (function() local x = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 }); x.abil = { PASS }; x.cd = { 0, 0, 0 }; return x end)() } or { e }, rng)
    if o.prep then o.prep(a, e, b) end
    return b, a, e
end
local function round(b) return C.Round(b, "A1", "A1") end

-- 1. recoil: user takes exactly the neutral damage whatever its family
for _, nm in ipairs({ "Body Slam", "Stone Rush" }) do
    local ab = kitAb(nm)
    check(ab ~= nil, nm .. " not in any kit")
    if ab then
        for _, fam in ipairs(Rules.FAMILIES) do
            local b, a, e = duel(ab, { family = fam, efamily = "Critter" })
            local evs = round(b)
            local rec; for _, x in ipairs(evs) do if x.recoil and x.tside == "P" then rec = x end end
            local want = math.max(1, Rules.Damage((function() for _, f in ipairs(ab.turns[1].fx) do if f.p[2] >= 200 then return f.p[1] end end return 0 end)(), a.power, fam, fam, 0, 0))
            check(rec ~= nil and rec.dmg == want, nm .. " as " .. fam .. ": recoil " .. tostring(rec and rec.dmg) .. " want " .. want)
        end
    end
end

-- 2. Life Exchange
local LE = kitAb("Life Exchange"); check(LE ~= nil, "Life Exchange not found (pinned species?)")
local function stream(evs, tag)   -- event stream validity for pb_battle playback
    for i, x in ipairs(evs) do
        if x.k == "heal" then check(type(x.amt) == "number" and x.amt > 0 and x.hp and x.max and x.hp <= x.max, tag .. ": bad heal event " .. i) end
        if x.k == "dmg" then check(type(x.dmg) == "number" and x.dmg >= 0 and x.hp and x.hp >= 0 and x.tside and x.tidx, tag .. ": bad dmg event " .. i) end
    end
end
if LE then
    local function le(tag, o, expect)
        local b, a, e = duel(LE, o)
        local evs = round(b); stream(evs, tag)
        expect(a, e, evs, b)
    end
    le("equal 40%", { prep = function(a, e) a.hp = math.floor(a.max * 0.4) end }, function(a, e) check(math.abs(a.hp - e.hp) <= 1, "LE 40%: " .. a.hp .. " vs " .. e.hp) end)
    le("both 1hp", { prep = function(a, e) a.hp = 1; e.hp = 1 end }, function(a, e, evs) check(a.hp == 1 and e.hp == 1, "LE both 1 hp: " .. a.hp .. " " .. e.hp) end)
    le("untargettable", { prep = function(a, e) e.auras[1] = { id = 0, left = 5, states = { untargettable = 1 } }; a.hp = 5 end },
       function(a, e) check(a.hp == 5 and e.hp == e.max, "LE vs untargettable enemy must do nothing: user " .. a.hp .. " enemy " .. e.hp .. "/" .. e.max) end)
    le("unkillable enemy", { prep = function(a, e) e.auras[1] = { id = 0, left = 5, states = { unkillable = 1 } }; a.hp = 1 end },
       function(a, e) check(e.hp >= 1 and math.abs(a.hp - e.hp) <= 1, "LE vs unkillable: " .. a.hp .. " " .. e.hp) end)
    le("enemy dodge 100", { prep = function(a, e) e.auras[1] = { id = 0, left = 5, states = { Stat_Dodge = 100 } }; a.hp = 1 end },
       function(a, e) check(math.abs(a.hp - e.hp) <= 1 or a.hp == 1, "LE vs Dodge 100: user healed " .. a.hp .. " but enemy still " .. e.hp .. "/" .. e.max .. " (half exchange)") end)
    le("enemy bubble", { prep = function(a, e) e.auras[1] = { id = 0, left = 5, charges = 1, states = {} }; a.hp = 1 end },
       function(a, e) check(math.abs(a.hp - e.hp) <= 1 or a.hp == 1, "LE vs Bubble: user healed " .. a.hp .. " but enemy still " .. e.hp .. "/" .. e.max .. " (half exchange)") end)
    le("magic enemy cap", { efamily = "Magic", prep = function(a, e) a.hp = 1 end },
       function(a, e) check(math.abs(a.hp - e.hp) <= 1, "LE vs Magic enemy: the 35% cap cuts the drain (user " .. a.hp .. " enemy " .. e.hp .. "/" .. e.max .. ")") end)
    le("humanoid user passive", { family = "Humanoid", prep = function(a, e) a.hp = 1 end },
       function(a, e, evs) local n = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.quick then n = n + 1 end end; check(n == 0, "LE drain counted as 'dealt damage': Humanoid passive healed " .. n .. "x") end)
    le("undead enemy at 1", { efamily = "Undead", prep = function(a, e) e.hp = 1 end }, function(a, e) check(e.hp >= 1 and a.hp >= 1, "LE undead enemy 1hp") end)
    -- different maxes: user tiny, enemy huge
    le("user max small", { level = 3, elevel = 20, prep = function(a, e) end }, function(a, e) check(a.hp <= a.max and e.hp >= 1, "LE small user: " .. a.hp .. "/" .. a.max .. " enemy " .. e.hp .. "/" .. e.max) end)
    le("enemy max small", { level = 20, elevel = 3, prep = function(a, e) e.hp = 1 end }, function(a, e) check(e.hp <= e.max and a.hp >= 1, "LE small enemy: " .. a.hp .. "/" .. a.max .. " enemy " .. e.hp .. "/" .. e.max) end)
    -- sweeps: random hp pairs, invariants
    local rr = math.random; math.randomseed(7)
    for i = 1, 300 do
        local b, a, e = duel(LE, { level = rr(1, 25), elevel = rr(1, 25), q = rr(1, 4), eq = rr(1, 4) })
        a.hp = rr(1, a.max); e.hp = rr(1, e.max)
        local a0, e0 = a.hp, e.hp
        local evs = round(b); stream(evs, "fuzz")
        check(a.hp >= 1 and e.hp >= 1 and a.hp <= a.max and e.hp <= e.max, "LE fuzz bounds " .. a0 .. "/" .. a.max .. " " .. e0 .. "/" .. e.max .. " -> " .. a.hp .. " " .. e.hp)
        -- exact replay from events: the last hp stamped on each side matches
        local lastA, lastE
        for _, x in ipairs(evs) do
            if x.k == "heal" then if x.side == "P" then lastA = x.hp else lastE = x.hp end
            elseif x.k == "dmg" then if x.tside == "P" then lastA = x.hp else lastE = x.hp end end
        end
        check(lastA == nil or lastA == a.hp, "LE fuzz event hp (user) " .. tostring(lastA) .. " vs " .. a.hp)
        check(lastE == nil or lastE == e.hp, "LE fuzz event hp (enemy) " .. tostring(lastE) .. " vs " .. e.hp)
    end
    -- benched pets untouched
    local b, a, e = duel(LE, { bench = true, prep = function(a, e) a.hp = 1 end }); local bench = b.E[2]; local bh = bench.hp; round(b)
    check(bench.hp == bh, "LE changed a benched pet")
end

-- 3. Frostbite growth ("damage grows until the pet is swapped"): Blistering Cold
local BC = kitAb("Blistering Cold")
if BC then
    local b = duel(BC, { efamily = "Critter" })
    local e = b.E[1]; e.max = e.max * 10; e.hp = e.max
    local dots = {}
    for r = 1, 5 do for _, x in ipairs(round(b)) do if x.k == "dot" then dots[#dots + 1] = x.dmg end end end
    check(#dots >= 3 and dots[#dots] > dots[1], "Blistering Cold: Frostbite does not grow (" .. table.concat(dots, ",") .. ") although its text says it does")
end
-- Dark Rebirth: "If killed, will be reborn with full health"
local DR = kitAb("Dark Rebirth")
if DR then
    local BIG = { id = 1, name = "Big", icon = "x", tip = "", cd = 0, text = "", turns = { { event = 255, fx = { { prop = 24, aura = 0, p = { 9999, 100, 0, 0, 0, 0 } } } } } }
    local b, a = duel(DR, { eab = BIG, family = "Humanoid" })
    local evs = round(b)
    check(a.hp > 0, "Dark Rebirth: the user that cast it was killed and not reborn (hp " .. a.hp .. ")")
end

-- 4. abilities listed UNCHECKED by test_abilities verbose: Inner Vision, Uncertainty, Blinding Poison, Spirit Spikes (claims taken from their own texts)
local ATK = function(pts, acc) return { id = 2, name = "Atk", icon = "x", tip = "", cd = 0, text = "", turns = { { event = 255, fx = { { prop = 24, aura = 0, p = { pts, acc or 100, 0, 0, 0, 0 } } } } } } end
local function dmgTo(evs, side) local t = 0; for _, x in ipairs(evs) do if x.k == "dmg" and x.tside == side and not x.reflect and not x.recoil then t = t + x.dmg end end; return t end
local function twoRound(ab, o)   -- player casts ab in round 1 (slot 1) and attacks in round 2 (slot 2); returns events of both rounds
    o = o or {}
    local b, a, e = duel(ab, o); a.abil[2] = ATK(20, o.acc); a.cd = { 0, 0, 0 }
    local ev1 = C.Round(b, "A1", o.ecmd or "A1")
    local ev2 = C.Round(b, "A2", o.ecmd or "A1")
    return ev1, ev2, a, e, b
end
local IV, UN, BP, SS = kitAb("Inner Vision"), kitAb("Uncertainty"), kitAb("Blinding Poison"), kitAb("Spirit Spikes")
if IV then
    local _, with = twoRound(IV); local _, without = twoRound(PASS, {})
    local d1, d0 = dmgTo(with, "E"), dmgTo(without, "E")
    check(d0 > 0 and d1 >= d0 * 1.9 and d1 <= d0 * 2.1, "Inner Vision: +100% damage expected 2x, got " .. d1 .. " vs " .. d0)
end
if UN then
    local _, ev2 = twoRound(UN, { roll = 80 }); check(dmgTo(ev2, "E") == 0, "Uncertainty: accuracy -25% - a 100% attack must miss on a roll of 80")
    local _, ev2c = twoRound(UN, { roll = 6, acc = 100 }); local crit = false; for _, x in ipairs(ev2c) do if x.k == "dmg" and x.crit and x.tside == "E" then crit = true end end
    check(crit, "Uncertainty: crit chance +100% - an attack on roll 6 must crit")
end
if BP then
    local atk = ATK(20, 100)
    local b, a, e = duel(BP, { eab = atk }); local ev = round(b)
    check(dmgTo(ev, "P") == 0, "Blinding Poison: the poisoned enemy's 100% attack must miss in the same round (did " .. dmgTo(ev, "P") .. ")")
end
if SS then
    local atk = ATK(20, 100)
    local b0, a0, e0 = duel(PASS, { eab = atk }); local base = dmgTo(round(b0), "P")
    local b, a, e = duel(SS, { eab = atk }); local ev = round(b); local took = dmgTo(ev, "P")
    check(base > 0 and took < base, "Spirit Spikes: damage taken reduced (" .. took .. " vs " .. base .. ")")
    local refl = 0; for _, x in ipairs(ev) do if x.reflect and x.tside == "E" then refl = refl + x.dmg end end
    check(refl > 0, "Spirit Spikes: no reflect damage to the attacker")
end

print(string.format("qa engine: %d passed, %d failed", passes, #fails))
local seen = {}
for _, f in ipairs(fails) do local k = f:sub(1, 40); if not seen[k] or seen[k] < 3 then print("FAIL " .. f) end; seen[k] = (seen[k] or 0) + 1 end
os.exit(#fails == 0 and 0 or 1)
