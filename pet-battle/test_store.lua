-- Storage rules with the REAL pb_store (stubbed database): quality, saved health + slow recovery, saved skin, replacing a pet.  luajit pet-battle/test_store.lua
package.path = "scripts/?.lua;" .. package.path
local passed, failed = 0, {}
local function test(name, fn) local ok, err = pcall(fn); if ok then passed = passed + 1 else failed[#failed + 1] = name .. "\n      " .. tostring(err) end end
local function truthy(a, m) if not a then error("expected truthy: " .. tostring(m)) end end
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
function CharDBExecute() end; function CharDBQuery() return nil end; function WorldDBQuery() return nil end
function RegisterPlayerEvent() end; function GetPlayersInWorld() return {} end; function CreateLuaEvent() end
local sent = {}
package.loaded["acore_prime"] = { Register = function() end, SetDisplayResolver = function() end, Enable = function() end, SendOne = function(_, entry, display) sent[#sent + 1] = entry .. ":" .. display end }
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
test("teams: 3 to start, add up to 30, delete shifts the later ones and the active team", function()
    local function count() outbox = {}; handlers["pbj|addteam"](player, ""); for _, o in ipairs(outbox) do if o.a == "nteams" then return tonumber(o.p) end end end
    eq(count(), 4, "first add -> 4 teams")
    for _ = 5, 30 do count() end   -- ends at exactly 30
    eq(count(), nil, "at 30 teams nothing more is added")
    Store.AddPet(player, 721, 1, { 1, 1, 1 }, 1, 0)
    handlers["pbj|setteam"](player, "12,721,0,0"); handlers["pbj|active"](player, "12")
    outbox = {}; handlers["pbj|delteam"](player, "5")
    local n, act; for _, o in ipairs(outbox) do if o.a == "nteams" then n = o.p end if o.a == "active" then act = o.p end end
    eq(n, "29", "one team fewer"); eq(act, "11", "active team 12 moved up to 11")
    local t11; for _, o in ipairs(outbox) do if o.a == "team" and o.p:match("^11,") then t11 = o.p end end
    eq(t11, "11,721,0,0", "the team moved up with its pets")
    for _ = 1, 28 do handlers["pbj|delteam"](player, "1") end   -- 29 -> 1
    outbox = {}; handlers["pbj|delteam"](player, "1"); eq(#outbox, 0, "the last team cannot be deleted")
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
-- ---------------------------------------------------------------- feeding (well fed)
local FOODS = { [1001] = 1, [1002] = 25, [1003] = 10 }   -- entry -> food level (RequiredLevel; 0 counts as 1); anything else is not food (or a drink)
function WorldDBQuery(sql)
    local e = tonumber(sql:match("entry=(%d+)")); local lv = FOODS[e]
    if not lv then return nil end
    return { GetUInt32 = function() return lv end }
end
local bag = { [1001] = 5, [1002] = 5, [1003] = 5 }; local removed = {}
local feeder = setmetatable({ GetItemCount = function(_, e) return bag[e] or 0 end, RemoveItem = function(_, e, n) bag[e] = bag[e] - n; removed[#removed + 1] = e end,
                              GetGUID = function() return 42 end }, { __index = player })
local FEEDSP = {}; do local ids = {}; for e in pairs(D.species) do if e > 100000 or e > 5000 then ids[#ids + 1] = e end end table.sort(ids); for i = 1, 5 do FEEDSP[500 + i - 1] = ids[i] end end
local function pet(sp, lvl, hp, t) sp = FEEDSP[sp] or sp; Store.AddPet(player, sp, lvl, nil, 1, 0); at(t); Store.SetHp(42, sp, hp); return Store.Pets(player)[sp] end
test("feeding: food of a lower level than the pet is refused and NOT consumed", function()
    local p = pet(500, 10, 100, 2000); removed = {}
    local ok, msg = Store.Feed(feeder, FEEDSP[500], 1001)
    eq(ok, false); truthy(msg:find("too weak"), msg); eq(#removed, 0, "no food used"); eq(p.fed, nil)
end)
test("feeding: good food consumes ONE item and heals 10% of max every 2 s for 20 s", function()
    local p = pet(501, 10, 100, 3000); local _, max = Store.PetHp(FEEDSP[501], p, 3000); removed = {}
    local ok, msg = Store.Feed(feeder, FEEDSP[501], 1002)
    eq(ok, true, msg); eq(#removed, 1); eq(bag[1002], 4)
    local step = math.floor(max * 0.10)
    eq(Store.PetHp(FEEDSP[501], p, 3001), 100, "1 s: no step yet"); eq(Store.PetHp(FEEDSP[501], p, 3002), 100 + step, "2 s: +10%")
    eq(Store.PetHp(FEEDSP[501], p, 3008), 100 + 4 * step, "8 s: +40% (regen adds nothing yet: 10 s)")
    local a, b = Store.PetHp(FEEDSP[501], p, 3020), Store.PetHp(FEEDSP[501], p, 3100)
    truthy(a >= 100 + 10 * step or a == max, "20 s: ten steps"); eq(b, math.min(max, 100 + 10 * step + math.floor((3100 - 3000) / 10) * math.floor(max * 0.01)), "after the buff only the slow regen continues")
    os.time = realTime
end)
test("feeding: not food, drinks, missing item, full health, unowned pet and a running battle are all refused", function()
    local p = pet(502, 10, 100, 4000)
    eq((Store.Feed(feeder, FEEDSP[502], 9999)), false, "not food"); bag[1003] = 0; eq((Store.Feed(feeder, FEEDSP[502], 1003)), false, "no item"); bag[1003] = 5
    eq((Store.Feed(feeder, 77777, 1002)), false, "unowned pet")
    Store.SetHp(42, FEEDSP[502], 10000); at(4000); eq((Store.Feed(feeder, FEEDSP[502], 1002)), false, "full health")
    Store.SetHp(42, FEEDSP[502], 100); PB_BATTLE = { InBattle = function() return true end }; eq((Store.Feed(feeder, FEEDSP[502], 1002)), false, "in battle"); PB_BATTLE = nil
    os.time = realTime
end)
test("feeding: the journal gets a fresh pet message at every 2 s step, even though ALE invalidates the Player object once the call returns", function()
    -- real ALE: a Player userdata kept past the end of the call is INVALID (calling a method on it raises 'bad self ... invalidated object'); a GUID value stays good.
    local live = true; local GUID = {}
    local p6 = setmetatable({ GetItemCount = function(_, e) return bag[e] or 0 end, RemoveItem = function(_, e, n) bag[e] = bag[e] - n end,
        GetGUID = function() if not live then error("calling 'GetGUID' on bad self (Player expected, got pointer to nonexisting (invalidated) object)") end return GUID end },
        { __index = player })
    local sp = FEEDSP[504]; Store.AddPet(player, sp, 10, nil, 1, 0); at(6000); Store.SetHp(42, sp, 100)
    local events, savedCS, savedGP = {}, CreateLuaEvent, GetPlayerByGUID
    function CreateLuaEvent(fn, delay, repeats) events[#events + 1] = { fn = fn, delay = delay, repeats = repeats } end
    function GetPlayerByGUID(g) if g == GUID then return player end end   -- the stored GUID value finds the online player again
    outbox = {}
    local ok, msg = Store.Feed(p6, sp, 1002); eq(ok, true, msg)
    live = false                                    -- the call has returned: the Player object is now invalid
    eq(#events, 1, "one timed push registered"); eq(events[1].delay, 2000, "every 2 s"); eq(events[1].repeats, 11, "for the whole buff plus one")
    local curs = {}
    for k = 1, events[1].repeats do
        at(6000 + 2 * k); outbox = {}
        local okc, err = pcall(events[1].fn); eq(okc, true, "push " .. k .. " raised: " .. tostring(err))
        local m = outbox[1]; truthy(m and m.m == "pbj" and m.a == "pet", "push " .. k .. " sent no pbj|pet message")
        curs[#curs + 1] = tonumber(m.p:match("^%d+,%d+,%d+,%d+,%d+,%d+,%a+,[^,]+,%d+,%d+,%d+,(%d+)"))
    end
    truthy(curs[1] > 100, "the first push already shows healing"); truthy(curs[5] > curs[1], "health keeps climbing"); truthy(curs[10] >= curs[5], "never goes down")
    CreateLuaEvent, GetPlayerByGUID = savedCS, savedGP; os.time = realTime
end)
test("feeding: a battle result or a level up cancels the remaining buff; feeding again restarts it", function()
    local p = pet(503, 10, 100, 5000); Store.Feed(feeder, FEEDSP[503], 1002)
    at(5004); local mid = Store.PetHp(FEEDSP[503], p, 5004); truthy(mid > 100, "buff running")
    Store.SetHp(42, FEEDSP[503], 100); at(5010); eq(Store.PetHp(FEEDSP[503], p, 5010), 100, "after a battle the old buff is gone (only regen after 10 s)")
    Store.Feed(feeder, FEEDSP[503], 1002); at(5015)
    local ok, msg = Store.Feed(feeder, FEEDSP[503], 1002); eq(ok, true, msg); eq(p.fed.from, 5015, "a re-feed restarts the buff")
    os.time = realTime
end)
test("feeding: the client message pbj|feed answers with the result text", function()
    pet(504, 10, 100, 6000); outbox = {}; handlers["pbj|feed"](feeder, FEEDSP[504] .. ",1001")
    local last = outbox[#outbox]; eq(last.m, "pbt"); truthy(last.p:find("too weak"), last.p)
    outbox = {}; handlers["pbj|feed"](feeder, "garbage"); eq(#outbox, 0)
    os.time = realTime
end)
test("pet size: tall thin models are capped by HEIGHT, not scaled up past their normal size (Defias Bandit was 1.3x)", function()
    local S = Store.ScaleFor
    truthy(S(0.306, 1.5) < 0.6, "Defias Bandit (radius .306, reach 1.5): " .. S(0.306, 1.5))
    truthy(S(0.235, 1.0) < 0.8, "Rabbit: " .. S(0.235, 1.0))
    eq(S(1.05, 0.875) == 0.4 / 1.05, true, "a wolf is still sized by its radius (it was already small)")
    eq(S(0, 0), 0.4, "no model data: default")
    eq(S(3, 4) >= 0.1, true, "never below the minimum"); truthy(7.5 * S(1.5, 7.5) <= 0.95, "Great Wavethrasher (reach 7.5) is small too")
    for _, m in ipairs({ { 0.306, 1.5 }, { 0.208, 1.5 }, { 0.376, 1.5 }, { 0.235, 1 }, { 2.5, 3.75 }, { 0.5, 2.25 }, { 0.3, 2.9 } }) do
        local sc = S(m[1], m[2]); truthy(m[2] * sc <= 0.95, "final height " .. m[2] * sc .. " for reach " .. m[2])
    end
end)
test("pet size: every pet has the same true visible size; companions keep their natural size (never resized); the Dun Morogh Cub was microscopic", function()
    local DIM = require("pb_scale_caps"); local n, m = 0, 0
    for entry, sp in pairs(D.species) do
        local d = DIM[entry]
        if d and d[3] > 0.01 then
            local S = d[3]
            if sp.companion then n = n + 1; local base = sp.scale or 1.0; eq(math.max(0.02, math.min(8.0, base)), Store.Scale(entry), sp.name)
            else
                local want = 0.53 / S; eq(math.max(0.02, math.min(8.0, want)), Store.Scale(entry), sp.name)
                if want >= 0.02 and want <= 8.0 then m = m + 1; truthy(math.abs(Store.Width(entry) - 0.53) < 0.001, sp.name .. " true size " .. tostring(Store.Width(entry))) end
            end
        end
    end
    truthy(n > 200, "companions checked: " .. n); truthy(m > 3000, "pets at exactly the pet size: " .. m); eq(Store.Scale(33194) <= 1.0 and Store.Scale(33194) > 0.5, true, "Dun Morogh Cub keeps a sane size")
end)
test("pet size follows the displayed model (the Twilight Flamereaver has 3 models of different size)", function()
    local DSZ = require("pb_scale_displays")
    for _, d in ipairs({ 2895, 2896, 2897 }) do
        truthy(DSZ[d] ~= nil, "display " .. d .. " measured")
        if DSZ[d] then truthy(math.abs(Store.SizeOf(15201, d) - 0.53) < 0.001, "model " .. d .. " size " .. tostring(Store.SizeOf(15201, d))) end
    end
    truthy(DSZ[2895] and DSZ[2896] and math.abs(DSZ[2895] - DSZ[2896]) > 0.3, "the models really differ in size (" .. tostring(DSZ[2895]) .. " vs " .. tostring(DSZ[2896]) .. ")")
    truthy(Store.ScaleOf(15201, 2895) ~= Store.ScaleOf(15201, 2896), "different models of one species get different scales")
end)
print(string.format("store: %d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do print("  FAIL " .. f) end
os.exit(#failed == 0 and 0 or 1)
