package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core"); local Rules = require("pb_rules")
math.randomseed(11)
local ids = {}; for e, s in pairs(D.species) do if s.wild then ids[#ids + 1] = e end end; table.sort(ids)
local function mirror(b) return { E = b.P, P = b.E, active = { E = b.active.P, P = b.active.E }, rng = b.rng } end
local function duel(a, la, qa, b2, lb, qb)   -- 1v1, random abilities both sides; true if a wins
    local pa = C.NewPet(a, la, nil, nil, { quality = qa }); local pb = C.NewPet(b2, lb, nil, nil, { quality = qb })
    local b = C.NewBattle({ pa }, { pb })
    for _ = 1, 300 do
        local m = mirror(b); local _, st = C.Round(b, C.AI(m), C.AI(b))
        if st == "win" then return true elseif st == "loss" then return false end
    end
end
local function run(label, la, qa, lb, qb, famOnly)
    local w, n = 0, 0
    for _ = 1, 4000 do
        local a, b2 = ids[math.random(#ids)], ids[math.random(#ids)]
        local fa, fb = C.Family(a), C.Family(b2)
        local m = Rules.Matchup(fa, fb)
        if not famOnly or (famOnly == "adv" and m > 1) or (famOnly == "dis" and m < 1) or (famOnly == "neutral" and m == 1) then
            local r = duel(a, la, qa, b2, lb, qb); if r ~= nil then n = n + 1; if r then w = w + 1 end end
        end
    end
    print(string.format("%-58s L%d q%d vs L%d q%d: win %5.1f%% (%d duels)", label, la, qa, lb, qb, 100 * w / n, n)); io.stdout:flush()
end
local s1, s2 = Rules.Stats({}, 1, 1), Rules.Stats({}, 2, 1)
print(string.format("base-8 pet common: L1 hp %d power %.1f | L2 hp %d power %.1f (hp +%d%%, power +%d%%)", s1.health, s1.power, s2.health, s2.power, 100 * (s2.health / s1.health - 1), 100 * (s2.power / s1.power - 1)))
run("L1 vs L2, same quality (all matchups)", 1, 1, 2, 1)
run("L1 vs L2, same quality, L1 has family ADVANTAGE", 1, 1, 2, 1, "adv")
run("L1 vs L2, same quality, L1 at family DISADVANTAGE", 1, 1, 2, 1, "dis")
run("L1 RARE vs L2 common (all matchups)", 1, 3, 2, 1)
run("L1 EPIC vs L2 common (all matchups)", 1, 4, 2, 1)
run("control: L10 vs L11 same quality", 10, 1, 11, 1)
run("control: L24 vs L25 same quality", 24, 1, 25, 1)
