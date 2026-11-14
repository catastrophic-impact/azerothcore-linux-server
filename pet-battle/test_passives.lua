-- FAMILY PASSIVES (retail): each of the 10 families has one passive. Controlled 1v1 situations on the real engine.  luajit pet-battle/test_passives.lua
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1; if not c then fails = fails + 1; print("FAIL " .. msg) end end
local function dice(v) return function(a, b) return math.max(a, math.min(b, v)) end end
local function hit(points, fam) return { id = 1, name = "Hit", icon = "x", tip = "", cd = 0, family = fam or -1, procs = {}, turns = { { event = 255, fx = { { prop = 24, aura = 0, p = { points, 100, 0, 0, 0, 0 } } } } } } end
local PASS = { id = 0, name = "Pass", icon = "x", tip = "", cd = 0, procs = {}, turns = { { event = 255, fx = {} } } }
local function pet(family, level, ability)
    local p = C.NewPet(721, level or 10, { 1, 1, 1 }, dice(6), { quality = 2 }); p.family = family; p.abil = { ability or PASS }; p.cd = { 0, 0, 0 }; p.speed = 100; return p
end
local function battle(a, e, roll) return C.NewBattle({ a }, { e }, dice(roll or 6)) end
local function dmgOf(evs, side) local t = 0; for _, x in ipairs(evs) do if x.k == "dmg" and x.side == side and not x.recoil then t = t + x.dmg end end return t end

-- FLYING: +50% speed while above 50% health
do
    local a, e = pet("Flying"), pet("Beast"); a.speed = 70; e.speed = 100     -- slower on paper, 70 * 1.5 = 105 > 100
    ok(C.Speed(a) > C.Speed(e), "Flying above 50% health is 1.5x faster")
    a.hp = math.floor(a.max * 0.4); ok(C.Speed(a) < C.Speed(e), "Flying at or below 50% health loses the speed bonus")
end
-- HUMANOID: heals 4% of max health after dealing damage
do
    local a, e = pet("Humanoid", 10, hit(20)), pet("Beast"); local b = battle(a, e); a.hp = math.floor(a.max * 0.5); local hp0 = a.hp
    C.Round(b, "A1", "A1"); ok(a.hp == hp0 + math.floor(a.max * 0.04), "Humanoid heals 4% of max health after dealing damage: " .. hp0 .. " -> " .. a.hp)
end
-- BEAST: +25% damage below 50% health
do
    local function dmg(hpFrac) local a, e = pet("Beast", 10, hit(20)), pet("Beast"); local b = battle(a, e); a.hp = math.floor(a.max * hpFrac); return dmgOf(C.Round(b, "A1", "A1"), "P") end
    local full, low = dmg(1), dmg(0.4)
    ok(math.abs(low - full * 1.25) <= 2, "Beast deals +25% below 50% health: " .. full .. " -> " .. low)
end
-- DRAGONKIN: +50% damage the round AFTER it brings an enemy below 50% health
do
    local a, e = pet("Dragonkin", 10, hit(60)), pet("Beast"); local b = battle(a, e); e.max = e.max * 10; e.baseMax = e.max; e.hp = math.floor(e.max * 0.51)
    local d1 = dmgOf(C.Round(b, "A1", "A1"), "P"); local d2 = dmgOf(C.Round(b, "A1", "A1"), "P"); local d3 = dmgOf(C.Round(b, "A1", "A1"), "P")
    ok(e.hp < e.max * 0.5, "the first hit brought the enemy below 50%")
    ok(math.abs(d2 - d1 * 1.5) <= 3 and math.abs(d3 - d1) <= 3, "Dragonkin: +50% only the next round (" .. d1 .. " / " .. d2 .. " / " .. d3 .. ")")
end
-- MAGIC: a single attack can take at most 35% of max health
do
    local a, e = pet("Beast", 10, hit(900)), pet("Magic"); local b = battle(a, e); local max = e.max
    C.Round(b, "A1", "A1"); ok(max - e.hp == math.floor(max * 0.35), "Magic takes at most 35% of max health from one attack: lost " .. (max - e.hp) .. " of " .. max)
end
-- UNDEAD: returns to life once, for one round; then dies for real
do
    local a, e = pet("Beast", 10, hit(900)), pet("Undead"); e.abil = { hit(1) }; local b = C.NewBattle({ a }, { e, pet("Beast") }, dice(6))
    local ev = C.Round(b, "A1", "A1")
    ok(e.hp == 1 and e.revived and b.active.E == 1, "Undead returns to life with 1 health instead of fainting (hp " .. e.hp .. ")")
    local faintedFirst = false; for _, x in ipairs(ev) do if x.k == "faint" and x.side == "E" then faintedFirst = true end end
    ok(not faintedFirst, "the Undead's first death is NOT a faint event (it returns to life)")
    a.abil = { PASS }; ev = C.Round(b, "A1", "A1")
    ok(e.hp == 0 and b.active.E == 2, "after its extra round the Undead dies for real and the next pet comes out (active " .. b.active.E .. ")")
end
-- MECHANICAL: returns to life at 20% health, once
do
    local a, e = pet("Beast", 10, hit(900)), pet("Mechanical"); local b = C.NewBattle({ a }, { e, pet("Beast") }, dice(6))
    C.Round(b, "A1", "A1"); ok(e.hp == math.floor(e.max * 0.2) and b.active.E == 1, "Mechanical returns at 20% health (hp " .. e.hp .. " of " .. e.max .. ")")
    C.Round(b, "A1", "A1"); ok(e.hp == 0 and b.active.E == 2, "the second death is final")
end
-- CRITTER: immune to stun / root / sleep from enemies
do
    local bash; for entry in pairs(D.species) do for _, k in ipairs(C.Kit(entry)) do if k.ability.retailName == "Bash" then bash = k.ability end end end
    local function stunned(family) local a, e = pet("Beast", 10, bash), pet(family); local b = battle(a, e); local ev = C.Round(b, "A1", "A1"); local c = 0; for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "stunned" and x.side == "E" then c = c + 1 end end; for _, x in ipairs(ev) do if x.k == "stunned" and x.side == "E" then c = c + 1 end end return c end
    ok(stunned("Beast") >= 1, "control: a Beast is stunned by Bash"); ok(stunned("Critter") == 0, "Critter is immune to stun")
end
-- ELEMENTAL: ignores weather (Blizzard +25% damage for Elemental abilities does not apply to an Elemental attacker; Sandstorm hit chance does not apply)
do
    local function dmg(family, weather) local a, e = pet(family, 10, hit(20, 6)), pet("Beast"); local b = battle(a, e); if weather then b.weather = { id = 205, left = 5 } end; return dmgOf(C.Round(b, "A1", "A1"), "P") end
    ok(dmg("Beast", true) > dmg("Beast", false), "control: Blizzard raises an Elemental ability's damage for a normal pet (" .. dmg("Beast", false) .. " -> " .. dmg("Beast", true) .. ")")
    ok(dmg("Elemental", true) == dmg("Elemental", false), "an Elemental pet ignores the weather")
end
-- AQUATIC: damage over time on it lasts one round less
do
    local goo; for entry in pairs(D.species) do for _, k in ipairs(C.Kit(entry)) do if k.ability.retailName == "Acidic Goo" then goo = k.ability end end end
    local function left(family) local a, e = pet("Beast", 10, goo), pet(family); local b = battle(a, e); C.Round(b, "A1", "A1"); local m = 0; for _, au in ipairs(e.auras) do m = math.max(m, au.left) end return m end
    local normal, aquatic = left("Beast"), left("Aquatic")
    ok(normal > 0 and aquatic == normal - 1, "Aquatic: DoTs last one round less (" .. normal .. " vs " .. aquatic .. ")")
end
print(string.format("passives: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
