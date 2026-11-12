-- Win-rate matrix of the retail pilot species (3 pets of one species vs 3 of another, same level/quality, random AI both sides, player-first ties): luajit pet-battle/sim_matrix.lua [games] [level]
package.path = "scripts/?.lua;" .. package.path
local D, C = require("pb_data"), require("pb_core")
local games, level = tonumber(arg[1]) or 400, tonumber(arg[2]) or 10
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local function team(e) local t = {}; for i = 1, 3 do t[i] = C.NewPet(e, level, nil, math.random, { quality = 1 }) end; return t end
local function play(a, b)
    local bt = C.NewBattle(team(a), team(b)); local status = "turn"
    for r = 1, 300 do
        local cmd
        if status == "force" then for i, p in ipairs(bt.P) do if p.hp > 0 then cmd = "S" .. i; break end end
        else local pet = bt.P[bt.active.P]; if pet.channel then cmd = "A" .. pet.channel.slot else local rdy = {}; for s = 1, 3 do if C.Ready(pet, s) then rdy[#rdy + 1] = s end end; cmd = "A" .. rdy[math.random(#rdy)] end end
        local _; _, status = C.Round(bt, cmd, C.AI(bt))
        if status == "win" then return 1, r elseif status == "loss" then return 0, r end
    end
    return 0.5, 300
end
math.randomseed(11)
io.write(string.format("%-20s", "win% vs ->")); for _, b in ipairs(ids) do io.write(string.format("%6d", b)) end io.write("   avg  rounds\n")
for _, a in ipairs(ids) do
    io.write(string.format("%-20s", D.species[a].name)); local tot, n, rs = 0, 0, 0
    for _, b in ipairs(ids) do
        local w = 0
        for g = 1, games do local r, rounds = play(a, b); w = w + r; rs = rs + rounds end
        io.write(string.format("%6.0f", w / games * 100)); tot = tot + w / games; n = n + 1
    end
    io.write(string.format("  %4.0f  %5.1f\n", tot / n * 100, rs / (n * games)))
end
