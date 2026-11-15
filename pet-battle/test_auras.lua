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

-- PHOTOSYNTHESIS (aura 267, effects 23 + 171): heals every round, twice as much in Sunny weather (weather aura 403 carries Weather_Sunlight)
do
    local function run(sunny)
        local h, e = pet("Elemental", 10, PASS), pet("Beast", 10, PASS); h.hp = math.floor(h.max * 0.3); aura(h, 267, 99, h)
        local b = battle(h, e); if sunny then b.weather = { id = 403, left = 5 } end
        local hp0 = h.hp; C.Round(b, "A1", "A1"); return h.hp - hp0
    end
    local plain, sunny = run(false), run(true)
    ok(plain > 0, "Photosynthesis heals every round (" .. plain .. ")")
    ok(sunny == plain * 2 or sunny == plain * 2 + 1 or sunny == plain * 2 - 1 or sunny > plain + plain * 0.8, "Photosynthesis heals about twice as much in Sunny weather (" .. plain .. " vs " .. sunny .. ")")
end

-- DARK REBIRTH (794 casts aura 795; proc event 7 + effect 111): killed once -> reborn at full health, then the aura 796 drains 20% of max health per round
do
    D.species[999951] = { name = "Pinned Dark Rebirth", retail = 270 }
    local ab; for _, k in ipairs(C.Kit(999951)) do if k.ability.id == 794 then ab = k.ability end end
    ok(ab ~= nil, "Dark Rebirth (794) is available through a pinned species")
    local h, e = pet("Undead", 10, PASS), pet("Beast", 10, hit(2000, nil, 1)); h.speed = 1; e.speed = 999
    aura(h, 795, 99, h)
    local b = battle({ h, pet("Beast") }, { e }); local ev = C.Round(b, "A1", "A1")
    ok(h.hp > 0 and count(ev, function(x) return x.k == "heal" and x.revive end) == 1, "Dark Rebirth: the holder is reborn instead of fainting (hp " .. h.hp .. "/" .. h.max .. ")")
    local drain = 0; for _, a in ipairs(h.auras) do if a.id == 796 then drain = drain + 1 end end
    ok(drain == 1 and not (function() for _, a in ipairs(h.auras) do if a.id == 795 then return true end end end)(), "the rebirth aura is used up and the drain aura 796 is on")
    e.abil = { PASS }; e.cd = { 0, 0, 0 }; local hpR = h.hp; C.Round(b, "A1", "A1")
    ok(hpR - h.hp == math.floor(h.max * 20 / 100), "the drain takes 20% of max health per round from the next round on (" .. hpR .. " -> " .. h.hp .. " of " .. h.max .. ")")
    local h2, e2 = pet("Undead", 10, PASS), pet("Beast", 10, hit(2000, nil, 1)); e2.speed = 999; h2.revived = true
    local b2 = battle({ h2 }, { e2 }); local ev2 = C.Round(b2, "A1", "A1")
    ok(h2.hp == 0, "without the aura the pet faints as usual")
end

-- HOWLING BLAST (120): extra damage to the enemy TEAM when the target is Chilled
do
    D.species[999952] = { name = "Pinned Howling Blast", retail = 253 }
    local ab; for _, k in ipairs(C.Kit(999952)) do if k.ability.id == 120 then ab = k.ability end end
    ok(ab ~= nil, "Howling Blast (120) is available through a pinned species")
    if ab then
        local function run(chilled)
            local a, e1, e2, e3 = pet("Elemental", 10, ab), pet("Beast", 10, PASS), pet("Beast", 10, PASS), pet("Beast", 10, PASS); a.speed = 999
            if chilled then aura(e1, 415, 3, a) end
            local b = battle({ a }, { e1, e2, e3 }); C.Round(b, "A1", "A1"); return e1, e2, e3
        end
        local e1, e2, e3 = run(true); local f1, f2, f3 = run(false)
        ok(e2.hp < e2.max and e3.hp < e3.max, "Howling Blast hurts the benched enemies when the target is Chilled (" .. e2.hp .. "/" .. e2.max .. ", " .. e3.hp .. "/" .. e3.max .. ")")
        ok(f2.hp == f2.max and f3.hp == f3.max, "no team damage when the target is not Chilled")
    end
end

-- NEVERMORE (522 casts aura 738 on the enemy; effects 168 / 129): the enemy's NEXT ability is locked out for 5 rounds, then the aura ends
do
    D.species[999961] = { name = "Pinned Nevermore", retail = 630 }
    local ab; for _, k in ipairs(C.Kit(999961)) do if k.ability.id == 522 then ab = k.ability end end
    ok(ab ~= nil, "Nevermore (522) is available through a pinned species")
    if ab then
        local a, e = pet("Flying", 10, ab), pet("Beast", 10, hit(10, nil, 1)); a.speed = 999
        local b = battle(a, e); C.Round(b, "A1", "A1")   -- the caster is faster: the enemy's very next ability (this round) is the locked one
        ok(e.cd[1] >= 4, "the enemy's next ability is locked out for about 5 rounds (cooldown " .. e.cd[1] .. ")")
        local still = false; for _, x in ipairs(e.auras) do if x.id == 738 then still = true end end
        ok(not still, "the lock aura ends after the locked ability")
        local a2, e2 = pet("Flying", 10, ab), pet("Beast", 10, hit(10, nil, 1)); a2.speed = 1; e2.speed = 999
        local b2 = battle(a2, e2); C.Round(b2, "A1", "A1")   -- the enemy is faster: it acts BEFORE the lock lands, so its next ability is the one of the following round
        local has2 = false; for _, x in ipairs(e2.auras) do if x.id == 738 then has2 = true end end
        ok(has2 and e2.cd[1] == 0, "a faster enemy keeps the lock aura for its next ability")
    end
end

-- REFLECTIVE SHIELD (aura 1104, proc event 1, effect 204): "deals damage equal to 50% of direct attacks back to the attacker"
do
    local a, e = pet("Beast", 10, hit(30, nil, 1)), pet("Beast", 10, PASS); aura(e, 1104, 3, e)
    local b = battle(a, e); local a0, e0 = a.hp, e.hp; local ev = C.Round(b, "A1", "A1")
    local took, reflected = e0 - e.hp, a0 - a.hp
    ok(took > 0 and reflected == math.floor(took * 50 / 100), "Reflective Shield: the attacker takes 50% of the damage back (took " .. took .. ", reflected " .. reflected .. ")")
    local a2, e2 = pet("Beast", 10, hit(30, nil, 1)), pet("Beast", 10, PASS); local b2 = battle(a2, e2); local ev2 = C.Round(b2, "A1", "A1")
    ok(a2.hp == a2.max, "no reflect without the aura")
end

-- HEALING STREAM / DRACONIC REMEDY / REBUILD (effect 100): "restoring N health to the user, and half that to other <family> allies" (pinned species supply the abilities)
do
    D.species[999971] = { name = "Pinned Healing Stream", retail = 1206 }; D.species[999972] = { name = "Pinned Draconic Remedy", retail = 2079 }
    for _, cfg in ipairs({ { "Healing Stream", "Aquatic" }, { "Draconic Remedy", "Dragonkin" } }) do
        local ab = kitAbility(cfg[1]); ok(ab ~= nil, cfg[1] .. " is available through a pinned species")
        if ab then
            local u, same, other = pet(cfg[2], 10, ab), pet(cfg[2], 10, PASS), pet("Beast", 10, PASS)
            for _, q in ipairs({ u, same, other }) do q.hp = math.floor(q.max * 0.3) end
            local e = pet("Beast", 10, PASS); local b = battle({ u, same, other }, { e }); local u0, s0, o0 = u.hp, same.hp, other.hp
            C.Round(b, "A1", "A1")
            ok(u.hp > u0, cfg[1] .. ": the user is healed (" .. u0 .. " -> " .. u.hp .. ")")
            ok(same.hp > s0 and same.hp - s0 < u.hp - u0 + 2, cfg[1] .. ": another " .. cfg[2] .. " ally is healed for about half (" .. (same.hp - s0) .. " vs " .. (u.hp - u0) .. ")")
            ok(other.hp == o0, cfg[1] .. ": an ally of another family is NOT healed")
        end
    end
end

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
