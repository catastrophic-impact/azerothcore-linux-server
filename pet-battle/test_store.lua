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
local handlers, outbox = {}, {}
package.loaded["acore_msg"] = { On = function(m, a, f) handlers[m .. "|" .. a] = f end, Send = function(_, m, a, payload) outbox[#outbox + 1] = { m = m, a = a, p = tostring(payload) } end }
local D, Eng = require("pb_data"), require("pb_core")
local Store = dofile("scripts/pb_store.lua")
local player = setmetatable({}, { __index = function(_, k) if k == "GetGUIDLow" then return function() return 42 end end return function() end end })
local realTime = os.time
local function at(t) os.time = function() return t end end

test("the journal ability list: every ability of every species has a clean, complete text that fits the 240 character message limit", function()
    for entry in pairs(D.species) do
        outbox = {}; handlers["pbj|abil"](player, tostring(entry))
        eq(#outbox, #Eng.Kit(entry), "one message per ability for species " .. entry)
        for _, o in ipairs(outbox) do
            local text = o.m .. "|" .. o.a .. "|" .. o.p
            truthy(#text <= 240, "message too long (" .. #text .. "): " .. text:sub(1, 80))
            local tip = o.p:match("^[^|]*|[^#]*#[^#]*#([^#]*)#")
            truthy(tip and tip ~= "", "empty tip: " .. o.p:sub(1, 80))
            truthy(not tip:find("[%[%]]") and not tip:find("|4") and not tip:find("%?") and not tip:find("nil") and not tip:find(" , "), "unresolved text in the journal tip: " .. tip)
        end
    end
end)
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
test("Compare: not collected / upgrade / same-or-better, same rule as Capture; Capture reports kept + quality", function()
    local pl2 = player
    local st0 = Store.Compare(pl2, 9699, 2, 5); eq(st0, 0, "uncollected species -> 0")
    local _, kept, kq = Store.Capture(pl2, { species = 9699, name = "Fire Beetle", level = 5, quality = 2, display = 1 }); eq(kept, true, "first capture kept"); eq(kq, 2, "kept quality returned")
    local a, oq, ol = Store.Compare(pl2, 9699, 2, 5); eq(a, 2, "same quality same level -> not an upgrade"); eq(oq, 2, "owned quality"); eq(ol, 5, "owned level")
    eq((Store.Compare(pl2, 9699, 2, 6)), 1, "same quality higher level -> upgrade"); eq((Store.Compare(pl2, 9699, 3, 1)), 1, "higher quality -> upgrade")
    eq((Store.Compare(pl2, 9699, 1, 40)), 2, "lower quality never an upgrade")
    local _, kept2 = Store.Capture(pl2, { species = 9699, name = "Fire Beetle", level = 4, quality = 2, display = 1 }); eq(kept2, false, "worse capture released -> not kept")
end)
test("Rename (nickname): validation, persistence, wire name 'nick|species', clear restores", function()
    eq(Store.CleanNick("  Fluffy  Boy "), "Fluffy Boy", "trims and collapses spaces"); eq(Store.CleanNick(""), "", "empty clears"); eq(Store.CleanNick("ThisNameIsWayTooLong"), nil, "over 12 characters refused")
    eq(Store.CleanNick("Bob'); DROP"), nil, "punctuation refused"); eq(Store.CleanNick("R2D2"), nil, "digits refused")
    Store.AddPet(player, 2442, 3, nil, 1, 0)
    eq(Store.SetNick(player, 2442, "Bessie"), true, "set"); eq(Store.Nick(player, 2442), "Bessie", "stored")
    eq(Store.SetNick(player, 99999, "Nope"), false, "unowned species refused"); eq(Store.SetNick(player, 2442, "bad!"), false, "invalid refused"); eq(Store.Nick(player, 2442), "Bessie", "invalid keeps the old name")
    eq(Store.SetNick(player, 2442, ""), true, "clear"); eq(Store.Nick(player, 2442), nil, "cleared")
end)
test("SyncCompanions: a known companion spell adds ONE level-1 journal pet; repeated syncs never duplicate or reset it", function()
    Store.COMP[1933] = { 55501 }
    local known = {}; local pl = setmetatable({ HasSpell = function(_, sp) return known[sp] == true end }, { __index = player })
    eq(Store.SyncCompanions(pl), 0, "spell not known: nothing added"); eq(Store.Pets(pl)[1933], nil, "no pet yet")
    known[55501] = true
    eq(Store.SyncCompanions(pl), 1, "spell known: one pet added"); eq(Store.Pets(pl)[1933].level, 1, "level 1")
    Store.SetHp(42, 1933, 1)
    local p = Store.Pets(pl)[1933]; p.level = 7
    for _ = 1, 5 do eq(Store.SyncCompanions(pl), 0, "repeat sync adds nothing") end
    eq(Store.Pets(pl)[1933].level, 7, "a leveled pet is never reset by a sync")
    local n = 0; for sp in pairs(Store.Pets(pl)) do if sp == 1933 then n = n + 1 end end; eq(n, 1, "exactly one row for the species")
    Store.COMP[1933] = nil
end)
test("a level up fully heals the pet; a win without a level up keeps the health", function()
    Store.AddPet(player, 2442, 1, nil, 1, 0); at(9500)
    local max = Eng.MaxHp(2442, 1, 1); Store.SetHp(42, 2442, 20)
    local p = Store.Pets(player)[2442]; p.xp = 0
    local gain, lv, ups = Store.GrantXP(player, 2442, 1)   -- level 1 enemy: not enough XP for level 2 at once
    if ups == 0 then eq(Store.Pets(player)[2442].hp ~= nil, true, "no level up: the damaged health is kept") end
    p.xp = Eng.XPNeeded(p.level) - 1; local _, _, ups2 = Store.GrantXP(player, 2442, p.level)
    truthy(ups2 and ups2 >= 1, "a level up happened"); eq(Store.Pets(player)[2442].hp, nil, "level up: health back to full (nil = full)")
end)
test("XP gain keeps the pet's current health value", function()
    Store.AddPet(player, 257, 10, nil, 1, 0); at(9000); Store.SetHp(42, 257, 50)
    local p = Store.Pets(player)[257]; Store.GrantXP(player, 257, 10)
    eq(p.hp, 50, "health untouched by xp"); os.time = realTime
end)
print(string.format("store: %d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do print("  FAIL " .. f) end
os.exit(#failed == 0 and 0 or 1)
