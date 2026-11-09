-- Smoke test for the garrison scripts WITHOUT a server: ALE is faked (database, players, events), then the whole system is installed and a
-- player is walked through claim -> enter -> area check -> leave prompt -> place decor -> abandon.  Catches wrong names between the parts,
-- broken SQL strings (they are printed with -v), and logic slips like the "area check sends you back before the teleport lands" bug.
-- usage (build box): lua5.1 tools/test_garrison.lua [-v]      exit code 0 = all checks passed
local VERBOSE = arg and arg[1] == "-v"
local here = (arg[0]:match("^(.*)/tools/") or ".")
package.path = here .. "/scripts/?.lua;" .. package.path

local fails, checks = 0, 0
local function check(cond, what) checks = checks + 1; if not cond then fails = fails + 1; print("FAIL: " .. what) elseif VERBOSE then print("ok:   " .. what) end end

-- Lua 5.1 has no bit operators
local function band(a, b) local r, bit = 0, 1; while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + bit end; a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2 end; return r end
local function bor(a, b) return a + b - band(a, b) end

-- ---- fake time ----
local clock = 1000000
os.time = function() return clock end

-- ---- fake database ----
local sqlLog = {}
local function Result(rows)
    if not rows or #rows == 0 then return nil end
    local i, r = 1, setmetatable({}, {})
    function r:GetString(c) return tostring(rows[i][c + 1]) end
    function r:GetUInt32(c) return math.floor(tonumber(rows[i][c + 1]) or 0) end
    function r:GetFloat(c) return tonumber(rows[i][c + 1]) or 0 end
    function r:NextRow() i = i + 1; return rows[i] ~= nil end
    return r
end
local answers = {   -- Lua pattern on the SQL text -> rows
    { "FROM garrison_location", { { 1, "Northshire Abbey", 0, -8940, -115, 119, -9036, -55, 89, 6 }, { 2, "Arathi Shore", 0, -1860.9, -4148.67, 100, -1860.9, -4148.67, 9.6, 3.2, 1 } } },
    { "COUNT%(%*%) FROM garrison_location", { { 2 } } },
    { "SELECT DISTINCT phaseMask FROM creature", { { 1 }, { 64 }, { 4294967295 } } },
    { "SELECT DISTINCT phaseMask FROM gameobject", { { 1 }, { 101 } } },
    { "COUNT%(%*%) FROM account", { { 5 } } },
    { "SELECT id FROM account WHERE id=", { { 5 } } },
    { "IFNULL%(MAX%(id%),0%)", { { 0 } } },
}
local function query(sql)
    sqlLog[#sqlLog + 1] = sql
    for _, a in ipairs(answers) do
        if sql:find(a[1]) then
            -- the garrison_location SELECT has 11 columns (the 10 above + enabled); pad the seed rows
            if a[1] == "FROM garrison_location" and not sql:find("COUNT") then
                local rows = {}
                for _, r in ipairs(a[2]) do local c = {}; for k = 1, 10 do c[k] = r[k] end; c[11] = 1; rows[#rows + 1] = c end
                return Result(rows)
            end
            return Result(a[2])
        end
    end
    return nil
end
CharDBQuery, WorldDBQuery, AuthDBQuery = query, query, query
CharDBExecute = function(s) sqlLog[#sqlLog + 1] = s end
WorldDBExecute = CharDBExecute

-- ---- fake engine ----
local handlers = { player = {}, gossipGo = {}, gossipCreature = {} }
RegisterServerEvent = function() end
RegisterPlayerEvent = function(ev, fn) handlers.player[ev] = handlers.player[ev] or {}; table.insert(handlers.player[ev], fn) end
RegisterGameObjectGossipEvent = function(entry, ev, fn) handlers.gossipGo[entry .. ":" .. ev] = fn end
RegisterCreatureGossipEvent = function(entry, ev, fn) handlers.gossipCreature[entry .. ":" .. ev] = fn end
RegisterGameObjectEvent = function() end
local timers = {}
CreateLuaEvent = function(fn, delay, reps) timers[#timers + 1] = { fn = fn, delay = delay, reps = reps, id = #timers + 1 }; return #timers end
RemoveEventById = function(id) if timers[id] then timers[id].dead = true end end
local players, nextGuid = {}, 100
local world = { objs = {} }
GetMapById = function() return { GetHeight = function(_, x) if x > -1800 then return -64 end; return 10 end, GetWorldObject = function(_, guid) return world.objs[guid] end } end
GetPlayersInWorld = function() local t = {}; for _, p in pairs(players) do t[#t + 1] = p end; return t end
GetPlayerByGUID = function(guid) return players[guid] end
GetObjectGUID = function(low) return low end
GetUnitGUID = function(low) return low end
PerformIngameSpawn = function(t, entry, map, inst, x, y, z, o, save, dur, phase)
    nextGuid = nextGuid + 1
    local obj = { guid = nextGuid, entry = entry, phase = phase, z = z, x = x, y = y }
    function obj:GetGUID() return self.guid end
    function obj:GetGUIDLow() return self.guid end
    function obj:GetEntry() return self.entry end
    function obj:SetPhaseMask(m) self.phase = m end
    function obj:GetPhaseMask() return self.phase end
    function obj:RemoveFromWorld() world.objs[self.guid] = nil end
    function obj:DespawnOrUnsummon() world.objs[self.guid] = nil end
    function obj:SetReactState() end
    function obj:AddAura() end
    function obj:MoveRandom() end
    function obj:GetGoState() return 1 end
    function obj:SetDisableGravity() end
    function obj:IsInWater()
        if DRY_CELLS and self.y < -4100 and self.y > -4200 then return false end
        local level = WATER_FN and WATER_FN(self.x, self.y) or WATER_LEVEL
        return level ~= nil and self.z < level
    end
    function obj:GetZ() return self.z end
    function obj:NearTeleport(_, _, nz) self.z = nz end
    world.objs[obj.guid] = obj
    return obj
end

local sent = {}   -- addon messages to players: sent[guid] = { "house|leaveask|", ... }
local function NewPlayer(guid, acct, name)
    local p = { guid = guid, acct = acct, name = name, map = 0, x = -8981.65, y = 855.01, z = 29.6, o = 3, phase = 1, flags = 0, gm = 3, rest = 0, menu = {}, said = {}, tele = nil }
    function p:GetGUIDLow() return self.guid end
    function p:GetGUID() return self.guid end
    function p:GetAccountId() return self.acct end
    function p:GetName() return self.name end
    function p:IsAlive() return true end
    function p:IsInWater() return false end
    function p:IsInCombat() return false end
    function p:IsGM() return false end
    function p:GetGMRank() return self.gm end
    function p:IsBot() return false end
    function p:GetGroup() return nil end
    function p:GetMapId() return self.map end
    function p:GetX() return self.x end
    function p:GetY() return self.y end
    function p:GetZ() return self.z end
    function p:GetO() return self.o end
    function p:GetLevel() return 40 end
    function p:GetPhaseMask() return self.phase end
    function p:SetPhaseMask(m) self.phase = m end
    function p:Teleport(map, x, y, z, o) self.tele = { map, x, y, z, o } end   -- lands only when the test says so (land())
    function p:SendBroadcastMessage(t) self.said[#self.said + 1] = t end
    function p:SendAddonMessage(prefix, text) sent[self.guid] = sent[self.guid] or {}; table.insert(sent[self.guid], text) end
    function p:GossipClearMenu() self.menu = {} end
    function p:GossipMenuAddItem(icon, text, sender, intid) self.menu[#self.menu + 1] = { text = text, intid = intid } end
    function p:GossipSendMenu() end
    function p:GossipComplete() end
    function p:SetPlayerFlag(f) self.flags = bor(self.flags, f) end
    function p:RemovePlayerFlag(f) self.flags = self.flags - band(self.flags, f) end
    function p:HasFlag(_, f) return band(self.flags, f) ~= 0 end
    function p:GetUInt32Value() return 100000 end
    function p:GetRestBonus() return self.rest end
    function p:SetRestBonus(v) self.rest = v end
    function p:GetCoinage() return 0 end
    function p:GetCreaturesInRange() return {} end
    function p:GetGameObjectsInRange() return {} end
    players[guid] = p
    return p
end
local function fireTimers(delay) for _, t in ipairs(timers) do if not t.dead and t.delay == delay then if t.reps == 1 then t.dead = true end; t.fn() end end end
local function land(p) fireTimers(400); if p.tele then p.map, p.x, p.y, p.z, p.o = p.tele[1], p.tele[2], p.tele[3], p.tele[4], p.tele[5]; p.tele = nil end end
local function poll() for _, t in ipairs(timers) do if not t.dead and t.delay == 1000 then t.fn() end end end
local function msgs(p, pat) local n = 0; for _, m in ipairs(sent[p.guid] or {}) do if m:find(pat, 1, true) then n = n + 1 end end; return n end
local function Msg() return ACORE.Msg end

-- ---- install ----
GARRISON_TEST = true
local ok, res = pcall(dofile, here .. "/scripts/garrison.lua")
check(ok and res == true, "garrison.lua installs all parts" .. (ok and "" or (": " .. tostring(res))))
if not (ok and res == true) then os.exit(1) end

local p = NewPlayer(1, 5, "Tester")
ACORE.Msg.handlers["core|hello"](p, "garrison,jukebox")   -- the client has our addons (the portal and Enter refuse players without them)
local OnHello, OnSelect = handlers.gossipGo["900002:1"], handlers.gossipGo["900002:2"]
check(OnHello and OnSelect, "portal gossip registered")

-- a client without the addon gets no menu and cannot enter (the hello handshake)
local q = NewPlayer(2, 6, "NoAddon")
OnHello(1, q, {})
check(#q.menu == 0, "portal shows no menu to a player without the Garrison addon")
ACORE_G.Enter(q, 6, 1)
check(q.phase == 1 and not ACORE_G.inside[q.guid], "Enter refuses a player without the Garrison addon")

-- claim
OnHello(1, p, {}); local claims = {}
for _, m in ipairs(p.menu) do if m.text:find("Claim") then claims[#claims + 1] = m end end
check(#claims == 2, "portal offers 2 locations to a player without a garrison (got " .. #claims .. ")")
OnSelect(1, p, {}, 0, 102)
OnHello(1, p, {}); local enter
for _, m in ipairs(p.menu) do if m.text:find("Enter Garrison") then enter = m end end
check(enter and enter.text:find("Arathi"), "after claiming, the portal offers to enter Arathi Shore")

-- enter: the area check must NOT throw the player out while the teleport has not landed
OnSelect(1, p, {}, 0, 1)
check(p.phase ~= 1, "entering sets the garrison phase bit (" .. tostring(p.phase) .. ")")
fireTimers(400); check(p.tele and math.abs(p.tele[2] - -1860.9) < 25, "teleport goes to the Arathi arrival point")
check(p.flags ~= 0, "instant-logout flag set inside")
poll(); poll()
check(p.phase ~= 1, "area check leaves a player alone while the teleport is still on its way")
land(p); clock = clock + 12; poll()
check(p.phase ~= 1 and msgs(p, "leaveask") == 0, "inside the area: no prompt, still phased")
check(p.rest > 0, "rested XP accumulates inside (" .. p.rest .. ")")

-- walk out -> countdown -> back inside resets it -> out again -> countdown runs out
p.x = -1860.9 + 105; poll()
check(msgs(p, "house|leaveask|5") == 1, "outside the radius: the 5 second countdown starts (sent once)")
poll(); check(msgs(p, "house|leaveask") == 1, "countdown message is not repeated every second")
p.x = -1860.9; poll()
check(msgs(p, "house|leavecancel") == 1 and p.phase ~= 1, "walking back inside cancels the countdown")
p.x = -1860.9 + 105; poll(); check(msgs(p, "house|leaveask") == 2, "leaving again starts a fresh countdown")
clock = clock + 3; poll(); check(p.phase ~= 1, "after 3 of 5 seconds the player is still inside")
clock = clock + 3; poll()
check(p.phase == 1 and p.flags == 0, "countdown over: back to the normal phase, resting flag removed")
check(p.tele and p.tele[2] == -8981.65, "countdown over: sent to the Mage Tower")
land(p)

-- keep running during the countdown: forced out
OnSelect(1, p, {}, 0, 1); land(p); poll(); p.x = -1860.9 + 105; poll()
check(msgs(p, "house|leaveask") >= 3, "countdown before the forced exit")
p.x = -1860.9 + 150; poll()
check(p.phase == 1 and p.tele and p.tele[2] == -8981.65, "running more than the limit past the border during the countdown forces the player out to the Mage Tower")
land(p)
-- exit button
OnSelect(1, p, {}, 0, 1); land(p); poll()
Msg().handlers["house|exit"](p, "")
check(p.phase == 1 and p.tele and p.tele[2] == -8981.65, "Exit Garrison button: out to the Mage Tower")
land(p)


-- polygon area + border preview
local L = ACORE_G.locations
local loc2 = L.Get(2)
L.SetPoints(loc2, { { -2000, -4000 }, { -1700, -4000 }, { -1700, -4300 }, { -2000, -4300 } })
check(math.abs(L.OutsideDistance(loc2, -1670, -4150) - 30) < 0.01 and L.OutsideDistance(loc2, -1860, -4148) == 0, "polygon: distance outside the border is measured to the nearest edge")
check(L.Inside(loc2, -1860, -4148) and not L.Inside(loc2, -1600, -4148) and not L.Inside(loc2, -1860, -3900), "polygon: inside / outside decided by the corners, not a circle")
OnSelect(1, p, {}, 0, 1); land(p); poll()
p.x = -1980   -- near the west border: the preview only draws the part of the border within 130 yards of the player
local before = 0; for _ in pairs(world.objs) do before = before + 1 end
Msg().handlers["house|ring"](p, "1")
local after = 0; for _ in pairs(world.objs) do after = after + 1 end
check(after > before, "border preview spawns marker wisps along the polygon (" .. (after - before) .. ")")
local lo, hi = 1e9, -1e9
for _, o in pairs(world.objs) do if o.entry == 900010 then lo, hi = math.min(lo, o.z), math.max(hi, o.z) end end
check(lo > 10 and hi - lo < 0.1, "land: all border markers hang at the same height above the ground (" .. lo .. ")")
Msg().handlers["house|ring"](p, "0")
-- over water the markers must hang a fixed height above the SURFACE, not above the sea floor
DRY_CELLS = true   -- part of the east border has no liquid data (the engine calls it dry although it is sea)
WATER_LEVEL = 0   -- the east side is deep sea in this fake map: the floor is 64 below the surface, far below the player
p.x = -1710; Msg().handlers["house|ring"](p, "1")   -- the east border: spots the land check above did not use (heights are cached per spot)
lo, hi = 1e9, -1e9
for _, o in pairs(world.objs) do if o.entry == 900010 then lo, hi = math.min(lo, o.z), math.max(hi, o.z) end end
check(math.abs(lo - 1.5) < 0.1 and hi - lo < 0.01, string.format("water: every marker hangs 1.5 above a flat surface at 0, even over a very deep sea floor and spots with no liquid data (z %.3f..%.3f)", lo, hi))
WATER_LEVEL, DRY_CELLS = nil, nil
-- two water levels in one area (a lake at 33 and the sea at 0): every marker must follow ITS water, not the first level that was learned
Msg().handlers["house|ring"](p, "0")
WATER_FN = function(x, y) if y > -4150 then return 33 end; return 0 end
p.x = -1990; Msg().handlers["house|ring"](p, "1")     -- west border first (floor +10 there: land), so nothing is learned yet
p.x = -1710; Msg().handlers["house|ring"](p, "0"); Msg().handlers["house|ring"](p, "1")
local wrong, lakeN, seaN = 0, 0, 0
for _, o in pairs(world.objs) do
    if o.entry == 900010 and o.x == -1700 then
        local want = (o.y > -4150) and 34.5 or 1.5
        if o.y > -4150 then lakeN = lakeN + 1 else seaN = seaN + 1 end
        if math.abs(o.z - want) > 0.1 then wrong = wrong + 1 end
    end
end
check(wrong == 0 and lakeN > 0 and seaN > 0, string.format("two water levels: all %d lake markers 1.5 above 33 and all %d sea markers 1.5 above 0 (%d wrong)", lakeN, seaN, wrong))
WATER_FN = nil
Msg().handlers["house|ring"](p, "0")
local gone = 0; for _ in pairs(world.objs) do gone = gone + 1 end
check(gone == before, "border preview off removes them again")
local asks = msgs(p, "house|leaveask")
p.x = -1670; poll(); check(msgs(p, "house|leaveask") == asks + 1, "walking out of the polygon starts the countdown")
p.x = -1860; poll(); check(msgs(p, "house|leavecancel") >= 2, "walking back inside the polygon cancels it")
p.x = -1670; poll(); clock = clock + 6; poll(); check(p.phase == 1, "countdown over outside the polygon: out"); land(p)
L.SetPoints(loc2, nil); loc2.cx, loc2.cy, loc2.radius = -1860.9, -4148.67, 100   -- back to the original circle

-- placement + abandon
OnSelect(1, p, {}, 0, 1); land(p); poll()
local kind
local cat = require("garrison_catalog").items
for _, c in ipairs(cat) do if c.multi and not c.hid and not c.price then kind = c.kind; break end end
Msg().handlers["house|dplace"](p, kind)
local inserted = false
for _, s in ipairs(sqlLog) do if s:find("INSERT INTO dc_garrison_decor") and s:find("'" .. kind .. "'") then inserted = true end end
check(inserted, "dplace writes the decor row to the database")
do   -- the per-item limit, then "Remove all decor" must free the slots
    local function lastRes() local t = sent[p.guid] or {}; for i = #t, 1, -1 do if t[i]:find("^house|res|") then return t[i] end end end
    for i = 1, 12 do Msg().handlers["house|dplace"](p, kind) end
    check((lastRes() or ""):find("already have") ~= nil, "the 11th copy of one item is refused (" .. tostring(lastRes()) .. ")")
    Msg().handlers["house|dclear"](p, "")
    Msg().handlers["house|dplace"](p, kind)
    check((lastRes() or ""):find("^house|res|Placed") ~= nil, "after Remove all decor you can place again (" .. tostring(lastRes()) .. ")")
end
do   -- an Unsorted / Removed item (hid): a GM 3 can place it, anyone else is refused
    local function lastRes() local t = sent[p.guid] or {}; for i = #t, 1, -1 do if t[i]:find("^house|res|") then return t[i] end end end
    local hidKind; for _, c in ipairs(cat) do if c.multi and c.hid and c.cat == "Unsorted" then hidKind = c.kind; break end end
    local keep = p.gm
    p.gm = 3; Msg().handlers["house|dplace"](p, hidKind)
    check((lastRes() or ""):find("^house|res|Placed") ~= nil, "a GM 3 can place an Unsorted item (" .. tostring(lastRes()) .. ")")
    p.gm = 0; Msg().handlers["house|dplace"](p, hidKind)
    check((lastRes() or ""):find("Unknown decor item") ~= nil, "a normal player cannot place an Unsorted item (" .. tostring(lastRes()) .. ")")
    p.gm = keep
end
Msg().handlers["house|pstart"](p, kind)
check(msgs(p, "house|pstart") >= 1, "placement mode starts")
Msg().handlers["house|pup"](p, "1"); Msg().handlers["house|pcancel"](p, "")
Msg().handlers["house|list"](p, "")
check(msgs(p, "house|dplaced") >= 1, "list reports the placed decor")
OnHello(1, p, {}); local ab
for _, m in ipairs(p.menu) do if m.text:find("Abandon") then ab = m end end
check(ab ~= nil, "owner sees Abandon (while inside the portal is still usable in the test)")
p.tele = nil
-- a player standing in the garrison cannot use the portal ("already in a garrison"), so leave first
Msg().handlers["house|exit"](p, ""); land(p)
OnSelect(1, p, {}, 0, 2)
local owners = 0
for _, s in ipairs(sqlLog) do if s:find("DELETE FROM dc_garrison_owner") then owners = owners + 1 end end
check(owners >= 1, "abandon deletes the ownership row")
local last_owner_delete, last_data_delete = 0, 0
for i, s in ipairs(sqlLog) do
    if s:find("DELETE FROM dc_garrison_owner") then last_owner_delete = i end
    if s:find("DELETE FROM dc_garrison_decor WHERE account") then last_data_delete = i end
end
check(last_data_delete > 0 and last_owner_delete > last_data_delete, "abandon removes the data BEFORE the ownership row")

-- GM area commands on a brand-new location: addloc, addpoint x3 (saved only at the 3rd), points, clearpoints
do
    local function cmd(text) for _, fn in ipairs(handlers.player[42]) do fn(42, p, text) end end
    local keep = { p.gm, p.x, p.y }
    p.gm = 3; p.x, p.y = 9000, 9000
    cmd("garrison addloc TestPlace")
    local nl; for _, l in ipairs(ACORE_G.locations.List()) do if l.name == "TestPlace" then nl = l end end
    check(nl ~= nil, "addloc creates a location")
    if nl then
        cmd("garrison addpoint"); p.x = 9100; cmd("garrison addpoint")
        check(nl.points == nil, "two points are not saved yet")
        p.y = 9100; cmd("garrison addpoint")
        check(nl.points and #nl.points == 3, "the third addpoint saves the area (3 points)")
        p.x = 9000; cmd("garrison addpoint")
        check(nl.points and #nl.points == 4, "further addpoints append a point")
        cmd("garrison clearpoints")
        check(nl.points == nil, "clearpoints returns the location to a circle")
    end
    p.gm, p.x, p.y = keep[1], keep[2], keep[3]
end

-- curator operations (scripts/garrison_curate.lua): category / name / price overrides, hid, category list edits, GM-only
do
    local on = function(a) return Msg().handlers["house|" .. a] end
    local G = ACORE_G
    local def; for _, c in ipairs(G.CATALOG) do if c.obj and c.basecat ~= "Removed" and c.basecat ~= "Unsorted" then def = c; break end end
    check(def ~= nil, "catalog has curatable decor")
    if def then
        local keep = p.gm
        p.gm = 0; on("ciset")(p, def.kind .. "~Removed~~")
        check(def.cat == def.basecat, "a non-GM cannot curate")
        p.gm = 3
        on("ciset")(p, def.kind .. "~Removed~Renamed Thing~7")
        check(def.cat == "Removed" and def.hid == true, "moving to Removed hides the item from players")
        check(def.name == "Renamed Thing" and def.price == 7, "name and price overrides apply")
        on("ciset")(p, def.kind .. "~" .. def.basecat .. "~~")
        check(def.cat == def.basecat and not def.hid and def.name == def.basename, "back to the base category clears the overrides")
        on("ccadd")(p, "Curated Test")
        local function Has(n) for _, c in ipairs(G.curate.cats or {}) do if c.name == n then return true end end end
        check(Has("Curated Test"), "category added")
        on("ccadd")(p, "Aaa First"); on("ccadd")(p, "Aaa First > Zed"); on("ccadd")(p, "Aaa First > bee")
        local at = {}; for i, c in ipairs(G.curate.cats) do at[c.name] = i end
        check(at["Aaa First"] == 1 and at["Aaa First > bee"] == 2 and at["Aaa First > Zed"] == 3, "categories sort alphabetically, subcategories after their parent")
        local last = G.curate.cats[#G.curate.cats]
        check(last.name == "Removed" and G.curate.cats[#G.curate.cats - 1].name == "Unsorted", "Unsorted and Removed stay last")
        on("ciset")(p, def.kind .. "~Curated Test~~")
        on("ccren")(p, "Curated Test~Curated Renamed")
        check(def.cat == "Curated Renamed" and Has("Curated Renamed") and not Has("Curated Test"), "renaming a category moves its items")
        on("ccprice")(p, "Curated Renamed~9")
        check(def.price == 9, "category price applies to its items")
        on("ccdel")(p, "Curated Renamed")
        check(def.cat == "Unsorted" and def.hid == true and not Has("Curated Renamed"), "deleting a category sends its items to Unsorted")
        on("ccren")(p, "Unsorted~Foo")
        check(Has("Unsorted") and not Has("Foo"), "Unsorted cannot be renamed")
        on("ciset")(p, def.kind .. "~~~")
        on("cfset")(p, "world\\test\\thing.m2~1.5~0.1~0.2~0.61")
        check(G.curate.fit["world\\test\\thing.m2"] ~= nil, "a view fit is stored")
        on("cfclr")(p, "world\\test\\thing.m2")
        check(G.curate.fit["world\\test\\thing.m2"] == nil, "a view fit is cleared")
        p.gm = keep
    end
end

-- no SQL may contain an unquoted/unfilled value
for _, s in ipairs(sqlLog) do
    if s:find("nil") or s:find("%%d") or s:find("%%s") then check(false, "bad SQL: " .. s) end
end
if VERBOSE then for _, s in ipairs(sqlLog) do print("sql: " .. s:sub(1, 150)) end end
print(string.format("%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
