-- AURA-ONLY effects and passive interactions, tested DIRECTLY (the ability harness only sees abilities that are in a species kit, so aura abilities like Brittle Webbing never ran there)
-- plus regression tests for every bug the independent review found.  luajit pet-battle/test_auras.lua
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1; if not c then fails = fails + 1; print("FAIL " .. msg) end end
local function dice(v) return function(a, b) return math.max(a, math.min(b, v)) end end
local function hit(points, fam, hits) local fx = {}; for i = 1, hits or 1 do fx[i] = { prop = 24, aura = 0, p = { points, 100, 0, 0, 0, 0 } } end
    return { id = 1, name = "Hit", icon = "x", tip = "", cd = 0, family = fam or -1, procs = {}, turns = { { event = 255, fx = fx } } } end
local PASS = { id = 0, name = "Pass", icon = "x", tip = "", cd = 0, procs = {}, turns = { { event = 255, fx = {} } } }
local function pet(family, level, ability, roll)
    local p = C.NewPet(721, level or 10, { 1, 1, 1 }, dice(roll or 6), { quality = 2 }); p.family = family or "Beast"; p.abil = { ability or PASS }; p.cd = { 0, 0, 0 }; p.speed = 100; return p
end
local function battle(P, E, roll) return C.NewBattle(type(P[1]) == "table" and P or { P }, type(E[1]) == "table" and E or { E }, dice(roll or 6)) end
local function kitAbility(name) for e in pairs(D.species) do for _, k in ipairs(C.Kit(e)) do if k.ability.retailName == name then return k.ability end end end end
local function count(ev, f) local c = 0; for _, x in ipairs(ev) do if f(x) then c = c + 1 end end return c end
local function aura(p, id, left, src, extra) local a = { id = id, left = left or 3, states = R.states[id] or {}, pwr = src and src.power or 0, fam = src and src.family, src = src }; for k, v in pairs(extra or {}) do a[k] = v end; p.auras[#p.auras + 1] = a; return a end

-- BRITTLE WEBBING (aura 381, proc event 2): the holder takes damage each time it attacks; a holder killed by it stops attacking
do
    local a, e = pet("Beast", 10, PASS), pet("Beast", 10, hit(10, nil, 1)); aura(e, 381, 3, a)
    local b = battle(a, e); local hp0 = e.hp; local ev = C.Round(b, "A1", "A1")
    local recoil = count(ev, function(x) return x.reflect and x.tside == "E" end)
    ok(recoil == 1 and e.hp < hp0 - 0, "Brittle Webbing: the webbed pet takes damage each time it attacks (" .. recoil .. " recoil hit, hp " .. hp0 .. " -> " .. e.hp .. ")")
    local a2, e2 = pet("Beast", 10, PASS), pet("Beast", 10, hit(10, nil, 3)); e2.hp = 3; aura(e2, 381, 3, a2); e2.speed = 999
    local b2 = battle({ a2 }, { e2, pet("Beast") }); local ev2 = C.Round(b2, "A1", "A1"); local faintAt, after = nil, 0
    for i, x in ipairs(ev2) do if x.k == "faint" and x.side == "E" and not faintAt then faintAt = i end end
    for i, x in ipairs(ev2) do if faintAt and i > faintAt and x.k == "dmg" and x.side == "E" and x.tside == "P" then after = after + 1 end end
    ok(faintAt ~= nil and after == 0, "a pet killed by recoil does not finish its remaining hits (" .. after .. " hits after its faint)")
end
-- PLAGUED BLOOD (aura 658, proc event 1): when the holder is damaged the ATTACKER is healed
do
    local a, e = pet("Beast", 10, PASS), pet("Beast", 10, hit(20)); aura(a, 658, 3, a); e.hp = math.floor(e.max * 0.5)
    local b = battle(a, e); local ev = C.Round(b, "A1", "A1")
    local healed = 0; for _, x in ipairs(ev) do if x.k == "heal" and x.side == "E" then healed = healed + x.amt end end
    ok(healed == Rules.Heal(4, a.power), "Plagued Blood heals the attacker for 4 points x power bonus (" .. healed .. " expected " .. Rules.Heal(4, a.power) .. ")")
end
-- CYCLONE (aura 189, "your team"): the k-th damage effect hits the k-th living pet; hit chance respected
do
    local function run(roll) local holder = pet("Beast", 10, PASS, roll); local src = pet("Flying", 10, PASS, roll); aura(holder, 189, 5, src)
        local team = { holder, pet("Beast", 10, PASS, roll), pet("Beast", 10, PASS, roll) }; local b = C.NewBattle({ src }, team, dice(roll)); return C.Round(b, "A1", "A1"), team end
    local ev, team = run(1)
    ok(count(ev, function(x) return x.k == "dot" and x.side == "E" end) == 1 and count(ev, function(x) return x.bench and x.tside == "E" end) == 2, "Cyclone: the active pet takes ONE tick and each benched pet one")
    ok(team[2].hp < team[2].max and team[3].hp < team[3].max, "Cyclone hurts the benched pets")
    local ev0 = run(100); ok(count(ev0, function(x) return x.k == "dot" or x.bench end) == 0, "Cyclone ticks respect the 35% hit chance (no damage on a bad roll)")
end
-- CLEANSING RAIN: hostile damage over time lasts one round less
do
    local goo = kitAbility("Acidic Goo")
    local function left(rain) local a, e = pet("Beast", 10, goo), pet("Beast"); local b = battle(a, e); if rain then b.weather = { id = 229, left = 5 } end; C.Round(b, "A1", "A1"); local m = 0; for _, au in ipairs(e.auras) do m = math.max(m, au.left) end return m end
    ok(left(true) == left(false) - 1, "Cleansing Rain shortens a DoT by one round (" .. left(false) .. " -> " .. left(true) .. ")")
end
-- CREEPING FUNGUS (aura 742, effect 65): more damage in Moonlight (weather state 55)
do
    R.states[99998] = R.states[99998] or { Weather_Moonlight = 1 }
    local function tick(moon) local src, holder = pet("Undead", 10, PASS), pet("Beast", 10, PASS); aura(holder, 742, 3, src); local b = battle(src, holder); if moon then b.weather = { id = 99998, left = 5 } end
        for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dot" then return x.dmg end end return 0 end
    ok(tick(true) > tick(false) and tick(false) > 0, "Creeping Fungus deals more in Moonlight (" .. tick(false) .. " -> " .. tick(true) .. ")")
end

-- REVIEW REGRESSIONS ----------------------------------------------------------------------------------------------------------------------------
-- Explode is a REAL death: an Undead / Mechanical exploder does not come back
do
    local boom = { id = 2, name = "Explode", icon = "x", tip = "", cd = 0, family = -1, procs = {}, turns = { { event = 255, fx = { { prop = 68, aura = 0, p = { 100, 100, 0, 0, 0, 0 } } } } } }
    for _, fam in ipairs({ "Undead", "Mechanical", "Beast" }) do
        local a, e = pet(fam, 10, boom), pet("Beast"); local b = C.NewBattle({ a, pet("Beast") }, { e, pet("Beast") }, dice(6)); local ev = C.Round(b, "A1", "A1")
        ok(a.hp == 0 and count(ev, function(x) return x.k == "heal" and x.revive end) == 0, fam .. " exploder stays dead (hp " .. a.hp .. ")")
    end
end
-- Magic cap applies to damage over time too
do
    local src, holder = pet("Beast", 25, PASS), pet("Magic", 10, PASS); holder.max = 20; holder.baseMax = 20; holder.hp = 20; aura(holder, 368, 3, src)
    local b = battle(src, holder); C.Round(b, "A1", "A1"); ok(holder.hp >= 13, "Magic: one DoT tick takes at most 35% of max health (hp " .. holder.hp .. " of 20)")
end
-- Undead: the borrowed round ends even on the bench; a just-revived Undead cannot be killed again in the same round
do
    local a, u = pet("Beast", 10, hit(900, nil, 3)), pet("Undead", 10, PASS); local b = C.NewBattle({ a }, { u, pet("Beast") }, dice(6)); local ev = C.Round(b, "A1", "A1")
    ok(u.hp == 1 and u.revived and count(ev, function(x) return x.k == "faint" and x.side == "E" end) == 0, "a multi-hit does not kill a just-revived Undead in the same round (hp " .. u.hp .. ")")
    local a2, u2, o2 = pet("Beast", 10, PASS), pet("Undead", 10, hit(900)), pet("Beast", 10, PASS)
    local b2 = C.NewBattle({ pet("Beast", 10, hit(900)), pet("Beast") }, { u2, o2 }, dice(6)); C.Round(b2, "A1", "A1")
    ok(u2.hp == 1 and u2.undeadLeft == 1, "setup: the Undead was revived and its first end-of-round tick passed (undeadLeft " .. tostring(u2.undeadLeft) .. ")")
    b2.P[1].abil = { PASS }; C.Round(b2, "A1", "S2"); C.Round(b2, "A1", "A1")
    ok(u2.hp == 0 or b2.active.E ~= 1, "an Undead swapped out after reviving does not keep its borrowed life on the bench (hp " .. u2.hp .. ")")
end
-- no "+0" heals; a revive never shows the pet dead first
do
    local a, e = pet("Humanoid", 10, hit(20)), pet("Beast"); local b = battle(a, e); local ev = C.Round(b, "A1", "A1")
    ok(count(ev, function(x) return x.k == "heal" and x.amt <= 0 end) == 0, "a full-health Humanoid emits no +0 heal events")
    local a2, u = pet("Beast", 10, hit(900)), pet("Undead"); local b2 = C.NewBattle({ a2 }, { u, pet("Beast") }, dice(6)); local ev2 = C.Round(b2, "A1", "A1")
    local zero = count(ev2, function(x) return x.k == "dmg" and x.tside == "E" and x.hp == 0 end)
    ok(zero == 0, "the hit that triggers a revive does not carry hp = 0 (" .. zero .. " dead-looking events)")
end
-- Leech Seed never heals more than the holder really lost
do
    local src, holder = pet("Beast", 25, PASS), pet("Beast", 10, PASS); src.hp = 1; holder.hp = 2; aura(holder, 744, 3, src); local b = battle(src, holder); local ev = C.Round(b, "A1", "A1")
    local healed = 0; for _, x in ipairs(ev) do if x.k == "heal" and x.side == "P" then healed = healed + x.amt end end
    ok(healed <= 2, "Leech Seed heals at most the holder's remaining health (" .. healed .. ")")
end
-- temporary max health never leaks: Finish ends all effects and restores the real maximum
do
    local perk = kitAbility("Perk Up"); local a, e = pet("Beast", 10, perk), pet("Beast"); local b = battle(a, e); local base = a.max; a.hp = math.floor(a.max * 0.5)
    C.Round(b, "A1", "A1"); ok(a.max > base, "setup: Perk Up raised the maximum"); C.Finish(b)
    ok(a.max == base and a.hp <= a.max and #a.auras == 0, "Finish restores the real maximum health and clears effects (max " .. a.max .. " vs " .. base .. ")")
end
-- weather lookups do not leak out of a round
do
    local a, e = pet("Beast", 10, PASS), pet("Beast", 10, PASS); local b = battle(a, e); b.weather = { id = 205, left = 5 }
    C.Round(b, "A1", "A1"); ok(C.Locked(e, "Mechanic_IsChilled") == false, "Blizzard's chill is not visible outside a round")
end
-- a pet whose ONLY ability is on cooldown passes the turn (the cooldown is never ignored): Consume / Face Punch at level 1
do
    local single = hit(20); single.cd = 1
    local a, e = pet("Beast", 10, single), pet("Beast", 10, PASS); a.abil = { single }; local b = battle(a, e)
    local d1 = count(C.Round(b, "A1", "A1"), function(x) return x.k == "dmg" and x.side == "P" end)
    local ev2 = C.Round(b, "A1", "A1"); local d2 = count(ev2, function(x) return x.k == "dmg" and x.side == "P" end); local passed = count(ev2, function(x) return x.pass end)
    local d3 = count(C.Round(b, "A1", "A1"), function(x) return x.k == "dmg" and x.side == "P" end)
    ok(d1 == 1 and d2 == 0 and passed == 1 and d3 == 1, "cooldown 1 on the only ability: acts, passes, acts (" .. d1 .. "/" .. d2 .. "/" .. d3 .. ", pass events " .. passed .. ")")
end
print(string.format("auras: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
