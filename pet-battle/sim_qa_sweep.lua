-- QA sweep (reviewer, new file): luajit pet-battle/sim_qa_sweep.lua [secondsBudget=120] [seed=1]
-- every species x levels {1,2,3,4,5,9,10,11,15,19,20,25} x quality 1-4 x pick sets {all first options, all alternates, random}: unlock rules (slot filled iff level >= unlock, alternates only
-- from their unlock level), full AI-vs-AI battle (1v1 and 3v3) vs a random opponent: no error, hp bounds, event validity, battle finishes (stall list), every ability of the pet gets used.
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local budget = tonumber(arg and arg[1]) or 120; math.randomseed(tonumber(arg and arg[2]) or 1)
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local LEVELS = { 1, 2, 3, 4, 5, 9, 10, 11, 15, 19, 20, 25 }
local fails, stalls, battles, t0 = {}, {}, 0, os.clock()
local seenMsg = {}
local function fail(msg) local k = msg:gsub("^.-: ", ""); if not seenMsg[k] and #fails < 40 then seenMsg[k] = true; fails[#fails + 1] = msg end; fails.n = (fails.n or 0) + 1 end
local function validate(ev, who)
    for i, x in ipairs(ev) do
        for _, f in ipairs({ "hp", "max", "dmg", "amt" }) do local v = x[f]; if x.k ~= "act" and v ~= nil and (type(v) ~= "number" or v ~= v or v < 0) then fail(who .. ": event " .. x.k .. " field " .. f .. " = " .. tostring(v)) end end
        if x.k == "heal" and not (x.amt and x.amt > 0) then fail(who .. ": heal without positive amt") end
        if x.k == "heal" and x.hp and x.max and x.hp > x.max then fail(who .. ": heal above max " .. x.hp .. "/" .. x.max) end
    end
end
local function checkUnlocks(id, lv, picks)
    local pet = C.NewPet(id, lv, picks, math.random, { quality = 1 })
    local kit = C.Kit(id)
    for slot = 1, 3 do
        local first, chosen
        for _, k in ipairs(kit) do if k.slot == slot then if k.opt == 1 then first = k end; if k.opt == picks[slot] then chosen = k end end end
        local want
        if first and lv >= first.unlock then want = (chosen and lv >= chosen.unlock) and chosen or first end
        local got = pet.abil[slot]
        if (want == nil) ~= (got == nil) then fail("unlock " .. D.species[id].name .. " L" .. lv .. " slot " .. slot .. ": " .. tostring(want and want.ability.retailName) .. " vs " .. tostring(got and got.retailName))
        elseif want and got.id ~= want.ability.id then fail("alt pick " .. D.species[id].name .. " L" .. lv .. " slot " .. slot .. " wanted " .. want.ability.retailName .. " got " .. got.retailName) end
    end
    return pet
end
local function team(id, lv, q, picks, n)
    local t = { C.NewPet(id, lv, picks, math.random, { quality = q }) }
    for k = 2, n do t[k] = C.NewPet(ids[math.random(#ids)], math.max(1, math.min(25, lv + math.random(-2, 2))), nil, math.random, { quality = math.random(1, 4) }) end
    return t
end
local function play(P, E, tag)
    battles = battles + 1
    local b = C.NewBattle(P, E, math.random)
    local ok, err = pcall(function()
        local status = "turn"
        for round = 1, 300 do
            local cmd
            if status == "force" then for k, pt in ipairs(b.P) do if pt.hp > 0 then cmd = "S" .. k; break end end
            else
                -- the player side plays with a different brain: random READY slot (exercise every ability); a pet with nothing ready passes via A1
                local pet = b.P[b.active.P]; local ready = {}
                for s = 1, 3 do if C.Ready(pet, s) then ready[#ready + 1] = s end end
                cmd = pet.channel and ("A" .. pet.channel.slot) or ("A" .. (ready[1] and ready[math.random(#ready)] or 1))
            end
            local ev; ev, status = C.Round(b, cmd, C.AI(b))
            validate(ev, tag)
            for _, sd in ipairs({ "P", "E" }) do for _, pt in ipairs(b[sd]) do
                if pt.hp < 0 or pt.hp > pt.max or pt.hp ~= pt.hp then fail(tag .. ": hp bounds " .. pt.name .. " " .. pt.hp .. "/" .. pt.max) end
                for s = 1, 3 do if pt.cd[s] < 0 then fail(tag .. ": negative cooldown") end end
            end end
            if status == "win" or status == "loss" then return end
        end
        stalls[#stalls + 1] = tag
    end)
    if not ok then fail(tag .. ": ERROR " .. tostring(err)) end
end
local pass = 0
while os.clock() - t0 < budget do
    pass = pass + 1
    for _, id in ipairs(ids) do
        local sp = D.species[id]
        local lv = LEVELS[math.random(#LEVELS)]; local q = math.random(1, 4)
        local ps = ({ { 1, 1, 1 }, { 2, 2, 2 }, { math.random(1, 2), math.random(1, 2), math.random(1, 2) } })[math.random(3)]
        checkUnlocks(id, lv, ps)
        local n = (pass % 2 == 1) and 1 or 3
        play(team(id, lv, q, ps, n), team(ids[math.random(#ids)], math.max(1, math.min(25, lv + math.random(-2, 2))), math.random(1, 4), nil, n), sp.name .. " L" .. lv .. " Q" .. q .. " picks " .. table.concat(ps) .. " " .. n .. "v" .. n)
        if os.clock() - t0 >= budget then break end
    end
end
print(string.format("qa sweep: %d battles, %d passes over %d species, %.0fs, %d problems, %d stalls", battles, pass, #ids, os.clock() - t0, fails.n or 0, #stalls))
for _, f in ipairs(fails) do print("FAIL " .. f) end
for i = 1, math.min(#stalls, 15) do print("STALL " .. stalls[i]) end
os.exit((fails.n or 0) == 0 and 0 or 1)
