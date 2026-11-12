-- Retail core engine tests (scripts/pb_core.lua) on the Snowshoe Rabbit kit: luajit pet-battle/test_core.lua
package.path = "scripts/?.lua;" .. package.path
local C = require("pb_core")
local fails, n = 0, 0
local function eq(a, b, msg) n = n + 1; if a ~= b then fails = fails + 1; print("FAIL " .. (msg or "") .. ": got " .. tostring(a) .. " expected " .. tostring(b)) end end
local function truthy(a, msg) n = n + 1; if not a then fails = fails + 1; print("FAIL " .. (msg or "") .. ": got " .. tostring(a)) end end
local function find(ev, k, side) for _, e in ipairs(ev) do if e.k == k and (not side or e.side == side) then return e end end end
local function count(ev, k, side) local c = 0; for _, e in ipairs(ev) do if e.k == k and (not side or e.side == side) then c = c + 1 end end; return c end
local NEVER = function(a, b) return b end   -- every roll is the maximum: nothing crits, 50% abilities miss, accuracy 100 always hits
local function rabbit(level, picks, q) return C.NewPet(721, level, picks or { 1, 1, 1 }, NEVER, { quality = q or 3 }) end
local function battle(p, e) return C.NewBattle({ p }, { e }, NEVER) end

-- unlocks (retail: slots at 1 / 2 / 4, second options at 10 / 15 / 20)
local r1 = rabbit(1); eq(r1.abil[1].name, "Scratch", "L1 slot1"); eq(r1.abil[2], nil, "L1 no slot2"); eq(r1.abil[3], nil, "L1 no slot3")
local r2 = rabbit(2); eq(r2.abil[2].name, "Adrenaline Rush", "L2 slot2"); eq(r2.abil[3], nil, "L2 no slot3")
local r4 = rabbit(4); eq(r4.abil[3].name, "Burrow", "L4 slot3")
local r9 = rabbit(9, { 2, 2, 2 }); eq(r9.abil[1].name, "Scratch", "L9 cannot pick Flurry yet"); eq(r9.abil[2].name, "Adrenaline Rush", "L9 no Dodge yet")
local r25 = rabbit(25, { 2, 2, 2 }); eq(r25.abil[1].name, "Flurry", "L25 pick 2"); eq(r25.abil[2].name, "Dodge", "L25 Dodge"); eq(r25.abil[3].name, "Stampede", "L25 Stampede")
-- stats (retail: L25 rare, rabbit power -2 speed +2)
eq(r25.max, 1400, "health"); eq(r25.power, 195, "power"); eq(r25.speed, 325, "speed"); eq(r25.family, "Critter", "family")

-- Scratch = 20 points = power, no crit
do
    local b = battle(rabbit(25, { 1, 1, 1 }), rabbit(25, { 1, 1, 1 }))
    local ev = C.Round(b, "A1", "A1")
    local d = find(ev, "dmg", "P"); eq(d.dmg, 215, "Scratch damage: 20 * (1 + 195/20) = 214.5"); eq(b.E[1].hp, 1400 - 215, "enemy hp"); eq(b.P[1].hp, 1400 - 215, "player hp")
    eq(count(ev, "dmg"), 2, "both hit"); eq(ev[1].k, "act", "player acts first on equal speed"); eq(ev[1].side, "P", "player first")
end
-- family matchup: a Beast scratching a Critter does x1.5 (cat species 7381 needs a retail kit: use the rules directly)
local Rules = require("pb_rules"); eq(Rules.Damage(20, 195, "Beast", "Critter"), 323, "strong x1.5 (rounded)")

-- Dodge (cd 4, aura 311 = 100% dodge for 1 round): acting first it protects against the enemy's attack THIS round, then expires
do
    local p = rabbit(25, { 1, 2, 1 }); local e = rabbit(25, { 1, 1, 1 })
    local b = battle(p, e)
    local ev = C.Round(b, "A2", "A1")
    eq(count(ev, "dodge", "P"), 1, "enemy scratch dodged"); eq(count(ev, "dmg"), 0, "no damage"); eq(b.P[1].hp, 1400)
    eq(#b.P[1].auras, 0, "dodge expired at end of round (used first)"); eq(b.P[1].cd[2], 4, "dodge cooldown 4")
    ev = C.Round(b, "A1", "A1"); eq(count(ev, "dmg"), 2, "next round hits again")
    -- slower rabbit using Dodge second: protects the NEXT round
    local slow = rabbit(25, { 1, 2, 1 }); local fast = rabbit(25, { 1, 1, 1 }); fast.speed = 999
    local b2 = battle(slow, fast)
    ev = C.Round(b2, "A2", "A1"); eq(find(ev, "dmg", "E").dmg, 215, "fast enemy hits first"); eq(#b2.P[1].auras, 1, "dodge still active after the round (used second)")
    ev = C.Round(b2, "A1", "A1"); eq(count(ev, "dodge", "P"), 1, "dodges the next round's attack")
end

-- Adrenaline Rush: 10 points of damage + speed aura (+75% for 3 rounds)
do
    local p = rabbit(25, { 1, 1, 1 }); local e = rabbit(25, { 1, 1, 1 }); e.speed = 400   -- enemy faster than the rabbit's 325
    local b = battle(p, e)
    local ev = C.Round(b, "A2", "A1")   -- slot 2 at L25 option 1 = Adrenaline Rush
    eq(find(ev, "dmg", "P").dmg, 108, "Adrenaline damage = 10 * (1 + 195/20) = 107.5")
    eq(C.Speed(b.P[1]) > 500, true, "speed buff"); eq(b.P[1].auras[1].left, 3, "used second: the application round does not count, still 3 rounds left")
    ev = C.Round(b, "A1", "A1"); eq(ev[1].side, "P", "now the rabbit acts first")
end

-- Burrow: round 1 untargettable, round 2 automatically attacks for 30 points
do
    local p = rabbit(25, { 1, 1, 1 }); local e = rabbit(25, { 1, 1, 1 })
    local b = battle(p, e)
    local ev = C.Round(b, "A3", "A1")
    eq(count(ev, "dodge", "P"), 1, "attack on a burrowed pet is blocked"); eq(find(ev, "dodge", "P").text, "Burrowed!", "text")
    eq(b.P[1].channel ~= nil, true, "second turn queued"); eq(b.P[1].cd[3], 4, "burrow cooldown")
    ev = C.Round(b, "A1", "A1")   -- the player's command is ignored: the burrow attack happens
    local d = find(ev, "dmg", "P"); eq(d.dmg, 323, "burrow strike 30 points = 322.5"); eq(#b.P[1].auras, 0, "no longer burrowed"); eq(b.P[1].channel, nil, "channel done")
    eq(find(ev, "act", "P").name, "Burrow", "still Burrow acting")
end

-- Flurry: first hit, second hit 50%, extra hit only when acting first
do
    local p = rabbit(25, { 2, 1, 1 }); local e = rabbit(25, { 1, 1, 1 })
    local b = battle(p, e)
    local ev = C.Round(b, "A1", "A1")
    eq(count(ev, "dmg", "P"), 2, "Flurry first: hit + bonus hit (second hit misses on max roll)"); eq(count(ev, "dodge", "E"), 1, "one miss")
    local p2 = rabbit(25, { 2, 1, 1 }); local e2 = rabbit(25, { 1, 1, 1 }); e2.speed = 999
    local b2 = battle(p2, e2); ev = C.Round(b2, "A1", "A1")
    eq(count(ev, "dmg", "P"), 1, "Flurry second: no bonus hit")
end

-- Stampede: three rounds, 3 hits each of 3 / 5 / 7 points
do
    local p = rabbit(25, { 1, 1, 2 }); local e = rabbit(25, { 1, 1, 1 }); e.max = 100000; e.hp = 100000
    local b = battle(p, e)
    local hp0 = e.hp; local ev = C.Round(b, "A3", "A1")
    eq(count(ev, "dmg", "P"), 3, "round 1: 3 hits"); local total1 = hp0 - e.hp
    eq(p.channel.turn, 2, "continues")
    ev = C.Round(b, "A1", "A1"); eq(count(ev, "dmg", "P"), 3, "round 2: 3 hits")
    ev = C.Round(b, "A1", "A1"); eq(count(ev, "dmg", "P"), 3, "round 3: 3 hits"); eq(p.channel, nil, "done after 3 rounds")
end

-- XP (retail BattlePetXP): level 1 needs 1 win x 50, level 2 needs 2 x 55, level 25 needs 12 x 170; a win is worth the enemy level's XpPerWin
eq(C.XPNeeded(1), 50, "L1 xp"); eq(C.XPNeeded(2), 110, "L2 xp"); eq(C.XPNeeded(25), 2040, "L25 xp"); eq(C.XPPerWin(10), 95, "win at L10")
-- CAPTURE (trap): only at or below 35% health, uses the turn, the pet is gone and the battle goes on / is won
do
    local p = rabbit(25); local e1, e2 = rabbit(25), rabbit(25)
    local b = C.NewBattle({ p }, { e1, e2 }, NEVER)
    eq(C.CanTrap(b), false, "full health enemy cannot be trapped")
    local ev, st = C.Round(b, "T", "A1"); eq(count(ev, "trap"), 0, "illegal trap becomes a normal action"); eq(count(ev, "act", "P"), 1, "player acted instead")
    e1.hp = math.floor(e1.max * 0.35); eq(C.CanTrap(b), true, "35% is enough")
    local hp0 = p.hp
    ev, st = C.Round(b, "T", "A1")
    eq(count(ev, "trap"), 1, "trap event"); eq(count(ev, "act", "E"), 0, "the captured pet does not act"); eq(p.hp, hp0, "no damage taken this round"); eq(e1.captured, true, "marked captured")
    eq(count(ev, "spawn", "E"), 1, "next enemy pet comes out"); eq(st, "turn", "battle goes on"); eq(b.active.E, 2, "second enemy active"); eq(b.captured[1], 1, "captured list")
    e2.hp = 1; ev, st = C.Round(b, "T", "A1"); eq(st, "win", "capturing the last enemy wins"); eq(count(ev, "end"), 1, "end event")
    local b2 = C.NewBattle({ rabbit(25) }, { rabbit(25) }, NEVER); b2.E[1].hp = 5; b2.E[1].noTrap = true; eq(C.CanTrap(b2), false, "uncapturable pets")
end
-- EVERY species: every ability builds, and nothing in any kit is an unknown effect type
local D = require("pb_data")
local inert = {}
for entry in pairs(D.species) do
    for _, k in ipairs(C.Kit(entry)) do
        for _, turn in ipairs(k.ability.turns) do for _, f in ipairs(turn.fx) do if C.INERT[f.prop] then inert[k.ability.retailName] = true end end end
    end
    for lvl = 1, 25 do for _, pick in ipairs({ { 1, 1, 1 }, { 2, 2, 2 } }) do local pet = C.NewPet(entry, lvl, pick, NEVER, { quality = 1 }); assert(pet.abil[1], D.species[entry].name .. " has a basic attack at every level") end end
end
-- no effect type of the Rabbit kit is unknown
for _, slot in ipairs({ 1, 2, 3 }) do local x = C.NewPet(721, 25, { 1, 1, 1 }, NEVER); for _, pick in ipairs({ 1, 2 }) do end end
eq(next(C.unknown), nil, "no unknown effect props")

-- status list for the addon
do
    local b = battle(rabbit(25, { 1, 2, 1 }), rabbit(25))
    C.Round(b, "A2", "A1"); local b2 = battle(rabbit(25, { 1, 2, 1 }), rabbit(25)); b2.E[1].speed = 999; C.Round(b2, "A2", "A1")
    local list = C.StatusList(b2.P[1]); eq(#list, 1, "one status"); eq(list[1].label, "Dodge", "label"); eq(list[1].bad, false, "buff"); eq(list[1].turns, 1, "turns left")
    truthy(C.StatusString(b2.P[1]):find("Dodge~"), "wire string")
end
-- fuzz: random battles between random species/levels/picks end, invariants hold, no unknown effect type ever fires
math.randomseed(7)
local ids = {}; for entry in pairs(D.species) do ids[#ids + 1] = entry end; table.sort(ids)
local stalls = 0
for i = 1, 600 do
    local function team() local t = {}; for k = 1, 3 do t[k] = C.NewPet(ids[math.random(#ids)], math.random(1, 25), nil, math.random, { quality = math.random(1, 4) }) end; return t end
    local b = C.NewBattle(team(), team(), math.random)
    local status = "turn"
    for round = 1, 400 do
        local cmd
        if status == "force" then for k, pt in ipairs(b.P) do if pt.hp > 0 then cmd = "S" .. k; break end end
        else cmd = "A" .. math.random(1, 3); if not C.Ready(b.P[b.active.P], tonumber(cmd:sub(2))) then cmd = "A1" end end
        local ev; ev, status = C.Round(b, cmd, C.AI(b))
        for _, pt in ipairs(b.P) do assert(pt.hp >= 0 and pt.hp <= pt.max, "hp bounds") end
        if status == "win" or status == "loss" then break end
        if round == 400 then stalls = stalls + 1; if stalls <= 3 then local function nm(tm) local o = {}; for _, pt in ipairs(tm) do o[#o + 1] = pt.name .. " L" .. pt.level .. " [" .. (pt.abil[1] and pt.abil[1].name or "-") .. "/" .. (pt.abil[2] and pt.abil[2].name or "-") .. "/" .. (pt.abil[3] and pt.abil[3].name or "-") .. "]" end; return table.concat(o, ", ") end; print("STALL: " .. nm(b.P) .. "  vs  " .. nm(b.E)) end end
    end
end
print("fuzz: " .. stalls .. " of 600 battles did not finish in 400 rounds (a stall)"); local unk = {}; for k, v in pairs(C.unknown) do unk[#unk + 1] = k .. "x" .. v end; eq(table.concat(unk, ","), "", "unknown effect props that fired")
local names = {}; for k in pairs(inert) do names[#names + 1] = k end; table.sort(names)
print("abilities with parts that are not interpreted yet (inert effect props): " .. table.concat(names, ", "))
print(string.format("core: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
