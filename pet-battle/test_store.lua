-- Storage rules with the REAL pb_store (stubbed database): quality, saved health + slow recovery, saved skin, replacing a pet.  luajit pet-battle/test_store.lua
package.path = "scripts/?.lua;" .. package.path
local passed, failed = 0, {}
local function test(name, fn) local ok, err = pcall(fn); if ok then passed = passed + 1 else failed[#failed + 1] = name .. "\n      " .. tostring(err) end end
local function truthy(a, m) if not a then error("expected truthy: " .. tostring(m)) end end
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
function CharDBExecute() end; function CharDBQuery() return nil end; function WorldDBQuery() return nil end
function RegisterPlayerEvent() end; function GetPlayersInWorld() return {} end; function CreateLuaEvent() end
local sent = {}
SHOP_PRIME = { SendOne = function(_, entry, display) sent[#sent + 1] = entry .. ":" .. display end }
package.loaded["acore_msg"] = { On = function() end, Send = function() end }
local D, Eng = require("pb_data"), require("pb_core")
local Store = dofile("scripts/pb_store.lua")
local player = setmetatable({}, { __index = function(_, k) if k == "GetGUIDLow" then return function() return 42 end end return function() end end })
local realTime = os.time
local function at(t) os.time = function() return t end end

test("a recruited pet keeps its quality and skin, starts at full health", function()
    Store.AddPet(player, 721, 1, { 1, 2, 1 }, 3, 777)
    local p = Store.Pets(player)[721]
    eq(p.quality, 3); eq(p.display, 777); eq(sent[#sent], "721:777", "the journal preview was told about the skin")
    local team = Store.ActiveTeam(player)
    eq(team[1].quality, 3); eq(team[1].display, 777); eq(team[1].hp, select(2, Store.PetHp(721, p)), "full health")
end)
test("REPLACING a pet takes the new quality and the NEW skin (white replaced by brown stays brown)", function()
    Store.AddPet(player, 721, 1, nil, 1, 111)   -- white
    Store.AddPet(player, 721, 1, nil, 2, 222)   -- brown, better
    local p = Store.Pets(player)[721]; eq(p.quality, 2); eq(p.display, 222); eq(sent[#sent], "721:222")
end)
test("the skin is saved once and never changes by chance", function()
    Store.AddPet(player, 299, 5, nil, 1, 0)                 -- no skin known yet
    Store.SetDisplay(player, 299, 555); eq(Store.PetDisplay(player, 299), 555)
    Store.SetDisplay(player, 299, 999); eq(Store.PetDisplay(player, 299), 555, "a later random skin must not overwrite it")
end)
test("health is kept after a battle and recovers 1% of max every 10 seconds (also offline)", function()
    Store.AddPet(player, 69, 10, nil, 1, 0)
    local p = Store.Pets(player)[69]; local _, max = Store.PetHp(69, p)
    at(1000); Store.SetHp(42, 69, 100)
    eq(Store.PetHp(69, p, 1000), 100, "right after the battle")
    local tick = math.floor(max * 0.01)
    eq(Store.PetHp(69, p, 1009), 100, "9 s: nothing yet"); eq(Store.PetHp(69, p, 1010), 100 + tick, "10 s: +1%"); eq(Store.PetHp(69, p, 1100), 100 + 10 * tick, "100 s: +10%")
    eq(Store.PetHp(69, p, 1000 + 100000), max, "recovers fully in time, never above max")
    os.time = realTime
end)
test("fainted pets come back with 1 HP, never 0", function()
    at(5000); Store.SetHp(42, 69, 0); eq(Store.PetHp(69, Store.Pets(player)[69], 5000), 1); os.time = realTime
end)
test("a pet at full health is stored as full (no hp row to recover)", function()
    local p = Store.Pets(player)[69]; local _, max = Store.PetHp(69, p)
    Store.SetHp(42, 69, max + 500); eq(p.hp, nil)
end)
test("quality adds 10% (retail) to health in the journal numbers too", function()
    Store.AddPet(player, 299, 10, nil, 1, 0); local c = Store.Pets(player)[299]; local _, m1 = Store.PetHp(299, c)
    c.quality = 4; local _, m4 = Store.PetHp(299, c)
    eq(m4, Eng.MaxHp(299, 10, 4), "epic health"); eq(m1, Eng.MaxHp(299, 10, 1), "common health")
    eq(m4 > m1, true, "epic has more health")
end)
test("capture keeps the wild pet's level, quality and skin; a worse capture of an owned species is released", function()
    local pet = { species = 883, name = "Deer", level = 7, quality = 3, display = 4321 }
    local msg = Store.Capture(player, pet); local c = Store.Pets(player)[883]
    eq(c.level, 7, "keeps level"); eq(c.quality, 3, "keeps quality"); eq(c.display, 4321, "keeps skin"); truthy(msg:find("captured Deer"), "message")
    local worse = Store.Capture(player, { species = 883, name = "Deer", level = 5, quality = 2, display = 9 })
    truthy(worse:find("better one"), "released"); eq(Store.Pets(player)[883].level, 7, "owned one untouched")
    local better = Store.Capture(player, { species = 883, name = "Deer", level = 9, quality = 3, display = 5 })
    truthy(better:find("replaces"), "replaced"); eq(Store.Pets(player)[883].level, 9, "better level replaces")
end)
test("XP gain keeps the pet's current health value", function()
    Store.AddPet(player, 257, 10, nil, 1, 0); at(9000); Store.SetHp(42, 257, 50)
    local p = Store.Pets(player)[257]; Store.GrantXP(player, 257, 10)
    eq(p.hp, 50, "health untouched by xp"); os.time = realTime
end)
print(string.format("store: %d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do print("  FAIL " .. f) end
os.exit(#failed == 0 and 0 or 1)
