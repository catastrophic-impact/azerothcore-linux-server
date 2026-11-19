-- GOLDEN LOG: plays a fixed seeded corpus of battles and hashes every event, so a refactor of pb_core must reproduce the engine EXACTLY.
--   luajit pet-battle/golden.lua            -> prints the hash;  luajit pet-battle/golden.lua check -> compares with pet-battle/golden.txt
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local function mirror(b) return { E = b.P, P = b.E, active = { E = b.active.P, P = b.active.E }, rng = b.rng } end
local h, n = 5381, 0
local function mix(s) for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end end
-- presentation-only fields (which spell/mode is shown) are not part of the engine hash: changing a visual must not look like a behaviour change
local PRES = { vis = true, ranged = true, vm = true, vpre = true, vhop = true, vdmg = true }
local function ser(t) local k = {}; for key in pairs(t) do if not PRES[key] then k[#k + 1] = key end end; table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
    local o = {}; for _, key in ipairs(k) do local v = t[key]; o[#o + 1] = tostring(key) .. "=" .. (type(v) == "table" and "{}" or tostring(v)) end; return table.concat(o, ",") end
for seed = 1, 4000 do
    math.randomseed(seed)
    local lv = ({ 1, 5, 10, 15, 20, 25 })[seed % 6 + 1]
    local function mk() return C.NewPet(ids[math.random(#ids)], lv, nil, nil, { quality = math.random(1, 4) }) end
    local b = C.NewBattle({ mk(), mk(), mk() }, { mk(), mk(), mk() })
    for r = 1, 80 do
        local pc = (b.P[b.active.P].hp <= 0) and ("S" .. (function() for i, p in ipairs(b.P) do if p.hp > 0 then return i end end return 1 end)()) or C.AI(mirror(b))
        local ev, st = C.Round(b, pc, C.AI(b))
        for _, e in ipairs(ev) do mix(ser(e)); n = n + 1 end
        if st == "win" or st == "loss" then mix(st); break end
    end
end
local out = string.format("%d events %d", n, h)
if arg[1] == "check" then
    local want = io.open("pet-battle/golden.txt"):read("*l")
    if want == out then print("golden: identical (" .. out .. ")") else print("golden: DIFFERENT  want " .. want .. "  got " .. out); os.exit(1) end
else print(out); local f = io.open("pet-battle/golden.txt", "w"); f:write(out .. "\n"); f:close() end
