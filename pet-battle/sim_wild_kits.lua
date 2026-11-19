-- Sandbox check of the COMPOSED wild kits (pet-battle/.s/wild_kits.lua from gen_wild_kits.py). Does not touch the live data files.
-- Usage (host): luajit pet-battle/sim_wild_kits.lua [games per species] [level] [limit species]
package.path = "scripts/?.lua;" .. package.path
local D, C = require("pb_data"), require("pb_core")
local existing = arg[4] == "existing"   -- baseline: the SHIPPED wild species instead of the composed ones
if not existing then dofile("pet-battle/.s/wild_kits.lua") end
local games, level, limit = tonumber(arg[1]) or 12, tonumber(arg[2]) or 10, tonumber(arg[3]) or 1e9
local syn = {}; for e, s in pairs(D.species) do if (existing and s.wild and not s.synthetic) or (not existing and s.synthetic) then syn[#syn + 1] = e end end; table.sort(syn)
if #syn > limit then local t = {}; for i = 1, limit do t[i] = syn[math.floor((i - 1) * #syn / limit) + 1] end; syn = t end
-- 1. every species builds, all 3 slots present, tooltips render
local bad = 0
for _, e in ipairs(syn) do
    local ok, pet = pcall(C.NewPet, e, level, nil, math.random, { quality = 1 })
    if not ok then bad = bad + 1; if bad <= 5 then print("BUILD FAIL", e, D.species[e].name, pet) end
    elseif not (pet.abil[1] and pet.abil[2] and pet.abil[3]) then bad = bad + 1; if bad <= 5 then print("MISSING SLOT", e, D.species[e].name) end end
end
print(string.format("species %d, build failures %d", #syn, bad))
-- 2. balance: 3 pets of species A vs a random mixed team of 3 composed species (random AI both sides, as sim_matrix)
local function newteam(list) local t = {}; for i = 1, 3 do t[i] = C.NewPet(list[i], level, nil, math.random, { quality = 1 }) end; return t end
local function play(a, b)
    local bt = C.NewBattle(newteam(a), newteam(b)); local status = "turn"
    for r = 1, 200 do
        local cmd
        if status == "force" then for i, p in ipairs(bt.P) do if p.hp > 0 then cmd = "S" .. i; break end end
        else local pet = bt.P[bt.active.P]; if pet.channel then cmd = "A" .. pet.channel.slot else local rdy = {}; for s = 1, 3 do if C.Ready(pet, s) then rdy[#rdy + 1] = s end end; cmd = "A" .. (rdy[math.random(#rdy)] or 1) end end
        local _; _, status = C.Round(bt, cmd, C.AI(bt))
        if status == "win" then return 1, r elseif status == "loss" then return 0, r end
    end
    return 0.5, 200
end
math.randomseed(3)
local res, famw, famn, rounds, nrounds = {}, {}, {}, 0, 0
for _, e in ipairs(syn) do
    local w = 0
    for g = 1, games do
        local opp = {}; for i = 1, 3 do opp[i] = syn[math.random(#syn)] end
        local r, n = play({ e, e, e }, opp); w = w + r; rounds = rounds + n; nrounds = nrounds + 1
    end
    res[#res + 1] = { e = e, wr = w / games }
    local f = C.Family(e); famw[f] = (famw[f] or 0) + w / games; famn[f] = (famn[f] or 0) + 1
end
table.sort(res, function(a, b) return a.wr > b.wr end)
local hi, lo, mean = 0, 0, 0
for _, r in ipairs(res) do mean = mean + r.wr; if r.wr >= 0.75 then hi = hi + 1 end; if r.wr <= 0.25 then lo = lo + 1 end end
print(string.format("mean win %.1f%% | >=75%%: %d species | <=25%%: %d species | avg battle %.1f rounds", mean / #res * 100, hi, lo, rounds / nrounds))
local fl = {}; for f, v in pairs(famw) do fl[#fl + 1] = string.format("%s %.0f%%", f, v / famn[f] * 100) end; table.sort(fl); print("by family:", table.concat(fl, "  "))
for i = 1, math.min(8, #res) do print(string.format("TOP  %5.0f%%  %s", res[i].wr * 100, D.species[res[i].e].name)) end
for i = #res, math.max(1, #res - 7), -1 do print(string.format("LOW  %5.0f%%  %s", res[i].wr * 100, D.species[res[i].e].name)) end
local unk = {}; for p, n in pairs(C.unknown) do unk[#unk + 1] = p .. ":" .. n end; print("unimplemented effect hits:", #unk == 0 and "none" or table.concat(unk, " "))
