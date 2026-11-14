-- BALANCE SWEEP: every species plays 1v1 duels against random species of the same level (both sides use the engine AI, order-averaged), at the levels of the early zones.
-- Flags species that almost never win / almost always win (broken kit) and duels that stall.  luajit pet-battle/sim_balance.lua [duelsPerSpecies] [levels e.g. 1,2,3,4]
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); require("pb_retail"); require("pb_rules"); local C = require("pb_core")
math.randomseed(12345)
local N = tonumber(arg and arg[1]) or 60
local levels = {}; for l in (arg and arg[2] or "1,2,3,4"):gmatch("%d+") do levels[#levels + 1] = tonumber(l) end
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local function mirror(b) return { E = b.P, P = b.E, active = { E = b.active.P, P = b.active.E }, rng = b.rng } end
local stallLog = {}
local function duel(a, b2)   -- returns "A" if species a wins, "B" if b2 wins, "S" for a stall
    local pa = C.NewPet(a, LEVEL, nil, nil, { quality = 2 }); local pb = C.NewPet(b2, LEVEL, nil, nil, { quality = 2 })
    local b = C.NewBattle({ pa }, { pb })
    for _ = 1, 300 do
        local m = mirror(b)
        local ev, status = C.Round(b, C.AI(m), C.AI(b))
        if status == "win" then return "A" elseif status == "loss" then return "B" end
    end
    stallLog[#stallLog + 1] = D.species[a].name .. " (" .. a .. ") vs " .. D.species[b2].name .. " (" .. b2 .. ") level " .. LEVEL
    return "S"
end
local stats = {}
for _, lv in ipairs(levels) do
    LEVEL = lv
    for _, a in ipairs(ids) do
        local w, l, s = 0, 0, 0
        for i = 1, N do
            local opp = ids[math.random(#ids)]
            local r = (i % 2 == 0) and duel(a, opp) or ({ A = "B", B = "A", S = "S" })[duel(opp, a)]   -- order-averaged: half the duels with the species acting as the "player" side, half as the enemy side
            if r == "A" then w = w + 1 elseif r == "B" then l = l + 1 else s = s + 1 end
        end
        local t = stats[a] or { w = 0, l = 0, s = 0, perLevel = {} }; t.w, t.l, t.s = t.w + w, t.l + l, t.s + s; t.perLevel[lv] = w / math.max(1, w + l); stats[a] = t
    end
end
local rows = {}
for _, a in ipairs(ids) do local t = stats[a]; rows[#rows + 1] = { id = a, name = D.species[a].name, rate = t.w / math.max(1, t.w + t.l), stalls = t.s } end
table.sort(rows, function(x, y) return x.rate < y.rate end)
local flagged = 0
print(string.format("balance sweep: %d species, %d duels per species per level, levels %s", #ids, N, table.concat(levels, ",")))
for _, r in ipairs(rows) do
    if r.rate < 0.22 or r.rate > 0.78 or r.stalls > 0 then flagged = flagged + 1; print(string.format("  %-28s (%5d) win rate %3d%%  stalls %d", r.name, r.id, math.floor(r.rate * 100 + 0.5), r.stalls)) end
end
for i = 1, math.min(8, #stallLog) do print("  STALL " .. stallLog[i]) end
local mid = rows[math.floor(#rows / 2)]
print(string.format("median win rate %d%%, lowest %s %d%%, highest %s %d%%, %d flagged", math.floor(mid.rate * 100 + 0.5), rows[1].name, math.floor(rows[1].rate * 100 + 0.5), rows[#rows].name, math.floor(rows[#rows].rate * 100 + 0.5), flagged))
