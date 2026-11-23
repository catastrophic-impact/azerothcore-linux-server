-- Wild encounter test against the REAL pb_data / pb_store / pb_wild with a stubbed game API.  luajit pet-battle/smoke_wild.lua
package.path = "scripts/?.lua;" .. package.path
math.randomseed(7)
local fails, passes = {}, 0
local function check(cond, msg) if cond then passes = passes + 1 else fails[#fails + 1] = msg end end

-- world model -------------------------------------------------------------------------------------------
local objects, nextGuid, timers = {}, 1000, {}
local function newObject(entry, x, y, z, level)
    nextGuid = nextGuid + 1
    local o = { gone = false, db = false, faction = 35, guid = nextGuid, entry = entry, x = x, y = y, z = z, level = level or 1, flags = nil, scale = nil }
    o.GetGUID = function() return setmetatable({ id = o.guid }, { __index = function() return nil end }) end; o.GetGUIDLow = function() return o.guid end; o.GetX = function() return o.x end; o.GetY = function() return o.y end; o.GetZ = function() return o.z end
    o.GetEntry = function() return o.entry end
    o.GetLevel = function() return o.level end; o.GetDBTableGUIDLow = function() return o.db or 0 end; o.IsInCombat = function() return false end
    o.GetFaction = function() return o.faction or 35 end
    o.SetFaction = function(_, f) o.faction = f end; o.npcflags = 0; o.auras = {}; o.GetNPCFlags = function() return o.npcflags end; o.SetNPCFlags = function(_, f) o.npcflags = f end
    o.HasAura = function(_, id) return o.auras[id] == true end; o.CastSpell = function(_, _, id) o.auras[id] = true end; o.RemoveAura = function(_, id) o.auras[id] = nil end; o.SetScale = function(_, s) o.scale = s end
    o.DespawnOrUnsummon = function() objects[o.guid] = nil; o.gone = true end
    setmetatable(o, { __index = function() return function() end end })
    objects[o.guid] = o
    return o
end
local realMobs = {}   -- entry -> list of real (DB) mobs
local function realMob(entry, x, y, level) local m = newObject(entry, x, y, 0, level); m.db = 5000 + m.guid; m.faction = 14; realMobs[entry] = realMobs[entry] or {}; table.insert(realMobs[entry], m); return m end   -- real mobs stay in the world

local menu = {}
local player = { zone = 12, map = 0, x = 0, y = 0, alive = true }
setmetatable(player, { __index = function(t, k)
    local f = {
        GetZoneId = function() return t.zone end, GetMapId = function() return t.map end, GetX = function() return t.x end, GetY = function() return t.y end, GetZ = function() return 0 end,
        IsBot = function() return t.isBot == true end, IsAlive = function() return t.alive end, IsInCombat = function() return false end, GetPhaseMask = function() return 1 end, GetGUIDLow = function() return 77 end,
        GetGUID = function() return setmetatable({ id = 77 }, {}) end, GetCreaturesInRange = function(_, range, entry) RANGE_CALLS = (RANGE_CALLS or 0) + 1; local out = {}; local all = {}
            for _, o in pairs(objects) do if entry == 0 or o.entry == entry then all[#all + 1] = o end end   -- script-spawned creatures too (no DB row)
            for _, m in ipairs(all) do if (m.x - t.x) ^ 2 + (m.y - t.y) ^ 2 <= range * range then out[#out + 1] = m end end return out end,
        GossipClearMenu = function() menu = {} end, GossipMenuAddItem = function(_, _, text, _, id) menu[#menu + 1] = { text = text, id = id } end,
        GossipSendMenu = function() menu.sent = true end, GossipComplete = function() menu.sent = false end,
        SendBroadcastMessage = function(_, m) t.lastMsg = m end, HasSpell = function() return false end, GetSpeed = function() return 7 end,
    }
    return f[k] or function() end
end })

function GetPlayersInWorld() return player.online == false and {} or { player } end
function GetMapById() return { GetWorldObject = function(_, g) return objects[type(g) == 'table' and g.id or g] end } end   -- like the engine: a GUID object, resolved by value
function PerformIngameSpawn(_, entry, _, _, x, y, z) return newObject(entry, x, y, z) end
function CreateLuaEvent(f, ms) timers[#timers + 1] = f end
function WorldDBQuery(sql)   -- the critter template (rabbit: faction 14, no NPC flags)
    if sql:find("FROM creature_template WHERE entry IN") then local done = false; return { GetUInt32 = function(_, i) return ({ [0] = 721, 14, 0 })[i] end, NextRow = function() return false end } end
end
function CharDBQuery() return nil end
function CharDBExecute() end
function RegisterPlayerEvent() end
local gossip = {}
function RegisterCreatureGossipEvent(entry, ev, f) gossip[entry .. ":" .. ev] = f end
SENT = {}
package.loaded["acore_msg"] = { On = function() end, Send = function(_, m, a, payload) SENT[#SENT + 1] = { m = m, a = a, p = payload } end }

dofile("scripts/pb_data.lua"); dofile("scripts/pb_retail.lua"); dofile("scripts/pb_rules.lua"); dofile("scripts/pb_core.lua")
function PB_DATA_PETLEVEL(l, z) return require("pb_data").PetLevel(l, z) end
local Store = dofile("scripts/pb_store.lua"); package.loaded["pb_store"] = Store
dofile("scripts/pb_battle.lua")           -- the real battle script (its cleanup sweep must leave wild pets alone)
local Sweep = PB_BATTLE.Sweep
local spy
PB_BATTLE = { Start = function(p, en) spy = en; return true end, InBattle = function() return false end }
dofile("scripts/pb_wild.lua")
local W = PB_WILD
local function tick() W.Tick() end
local function species(g) return objects[g] and objects[g].entry end

-- scenario ---------------------------------------------------------------------------------------------------
realMob(299, 10, 0, 1); realMob(299, 20, 5, 1)          -- two Young Wolves (level 1)
realMob(69, -15, 8, 7)                                   -- a Timber Wolf, level 7 (so its wild pet brings a team)
realMob(257, 5, -12, 3)                                  -- a Kobold Worker (level 3)

tick(); check(W.Count() == 3, "ONE tick fills the whole area (max 3, one per species), got " .. W.Count())
tick(); tick(); check(W.Count() == 3, "no duplicates of a species nearby, got " .. W.Count())
-- COST: a full area costs NO world query; an empty one is not rescanned until the player moves
local calls0 = RANGE_CALLS or 0; tick(); tick(); check((RANGE_CALLS or 0) == calls0, "area full: no world query at all (" .. ((RANGE_CALLS or 0) - calls0) .. " calls)")
-- MINIMAP BLIPS: offsets in yards (north, west) of the pets in the area, with species, level and name
SENT = {}; W.BlipTick()
local bl = SENT[#SENT]; check(bl and bl.m == "pbw" and bl.a == "pets", "blip message sent to the player")
local nb = 0; for e in (bl and bl.p or ""):gmatch("[^;]+") do nb = nb + 1; check(e:match("^%-?%d+%.%d,%-?%d+%.%d,%d+,%d+,.+$") ~= nil, "blip entry format: " .. e) end
check(nb == 3, "one blip per wild pet in the area, got " .. nb)
check(#(bl and bl.p or "") < 240, "blip message fits one addon message")
local list = {}; for g, w in pairs(W.Wild) do list[w.species] = g end
check(list[299] and list[69] and list[257], "each species has its wild pet")
local wp = objects[list[299]]
check(wp.npcflags == 1, "wild pet has the gossip flag"); check(wp.scale and wp.scale > 0, "wild pet is scaled")
check(W.Wild[list[69]].level == 7 and W.Wild[list[299]].level == 1, "wild pet remembers the level of the real mob")

-- the battle script's leftover sweep removes strays (faction 35 species nobody owns) but must NEVER touch a live wild pet
local stray = newObject(299, 3, 3, 0); realMobs[299] = realMobs[299]   -- a leftover from a crash: not registered anywhere
local nBefore = W.Count()
local removed = Sweep(player, 200)
check(W.Count() == nBefore and not wp.gone, "sweep leaves live wild pets alone")
check(stray.gone == true, "sweep removes an unregistered stray pet")

-- right-click: menu only for wild pets, never for a normal creature of the same entry
check(W.OnHello(nil, player, realMobs[299][1]) == nil, "a real wolf gets no menu"); check(#menu == 0, "no menu items for a real wolf")
check(W.OnHello(nil, player, wp) == true and #menu == 2 and menu[1].id == 1, "wild pet shows Challenge / Never mind")

-- too far away
player.x, player.y = 500, 500; W.OnSelect(nil, player, wp, 0, 1); check(spy == nil, "too far: no battle"); check(player.lastMsg ~= nil, "too far: player told")
local function goTo(o) player.x, player.y = o.x + 1, o.y end   -- stand next to it
goTo(wp)

-- challenge a level 1 wild pet: SOLO
W.OnSelect(nil, player, wp, 0, 1)
check(spy and #spy == 1 and spy[1].species == 299 and spy[1].level == 1, "level 1-5 wild pet fights alone, pet level = D.PetLevel(mob level)")
check(wp.gone == true and W.Count() == 2, "the wild pet is consumed when the battle starts")
tick(); tick(); check(W.Count() == 2, "cooldown: it does not instantly reappear, got " .. W.Count())

-- challenge the level 7 timber wolf: pet level 2, still SOLO (3-pet teams start at pet level 3)
spy = nil; local tw = objects[list[69]]; goTo(tw); W.OnSelect(nil, player, tw, 0, 1)
check(spy and #spy == 1 and spy[1].species == 69, "level 7 wild pet (pet level 2) fights alone")
for _, e in ipairs(spy or {}) do check(e.level == PB_DATA_PETLEVEL(7, 12) and D_ok ~= false, "all enemy pets use the wild level") end

-- "Never mind" does nothing
spy = nil; local kb = objects[list[257]]; goTo(kb); W.OnSelect(nil, player, kb, 0, 2); check(spy == nil and not kb.gone, "Never mind keeps the wild pet (spy=" .. tostring(spy) .. " gone=" .. tostring(kb.gone) .. " kb=" .. tostring(kb) .. ")")

local PD = require("pb_data"); PD.species[721].wild = "adopt"   -- the adoption code path is kept (off by default): test it by switching it on
-- ADOPTION (critters): the real rabbit becomes the wild pet, no duplicate is spawned
player.zone = 12; player.online = true; player.x, player.y = 40, 40
local r1, r2, r3 = realMob(721, 41, 40, 1), realMob(721, 45, 42, 1), realMob(721, 38, 36, 1)
local scripted = function() local n = 0; for _, o in pairs(objects) do if o.entry == 721 and not o.db then n = n + 1 end end; return n end
for _ = 1, 6 do tick() end
local adopted = {}; for _, r in ipairs({ r1, r2, r3 }) do if r.npcflags == 1 then adopted[#adopted + 1] = r end end
check(#adopted == 1, "exactly one real rabbit is adopted, got " .. #adopted)
check(scripted() == 0, "no duplicate rabbit is spawned for an adopted critter")
local ar = adopted[1]
check(ar and not ar.auras[PB_WILD.MARKER], "no heart marker is applied any more")
check(ar and ar.faction == 35, "the adopted rabbit is friendly (green, cannot be attacked)")
local others = 0; for _, r in ipairs({ r1, r2, r3 }) do if r ~= ar and (r.npcflags ~= 0 or next(r.auras)) then others = others + 1 end end
check(others == 0, "the other rabbits are untouched")
local hostileKept = true; for _, r in ipairs({ r1, r2, r3 }) do if r ~= ar and r.faction ~= 14 then hostileKept = false end end
check(hostileKept, "the other rabbits keep their normal faction")
check(W.OnHello(nil, player, ar) == true and #menu == 2, "the adopted rabbit shows the challenge menu")
check(W.OnHello(nil, player, ar == r1 and r2 or r1) == nil, "a normal rabbit does not")
spy = nil; goTo(ar); W.OnSelect(nil, player, ar, 0, 1)
check(spy and #spy == 1 and spy[1].species == 721 and spy[1].level == 1, "level 1 rabbit fights alone")
check(ar.gone == true, "the adopted rabbit is consumed (despawns, real respawn timer brings it back)")
-- released without a battle: gets the critter back as it was (move the clock past the 90 s cooldown first)
local realTime = os.time; local clock = 200; os.time = function() return realTime() + clock end
for _ = 1, 8 do tick() end
local ar2; for _, r in ipairs({ r1, r2, r3 }) do if r.npcflags == 1 and not r.gone then ar2 = r end end
if ar2 then
    player.online = false; tick(); check(W.Count() > 0 and not ar2.gone and ar2.npcflags == 1, "nobody near for a moment: the pet is still there (grace period)")
    clock = clock + 100; tick()
    check(not ar2.gone and ar2.npcflags == 0 and not ar2.auras[PB_WILD.MARKER] and ar2.faction == 14, "released critter: flags, marker and faction restored, creature kept")
else check(false, "a second rabbit was not adopted after the cooldown window") end
player.online = true; os.time = realTime

PD.species[721].wild = true
-- LEFTOVER from an earlier script instance: marked (hearts, flag 1, friendly) but owned by no registry entry -> given back, not re-adopted into flag 2
local lo = realMob(721, 36, 44, 1); lo.npcflags = 1; lo.faction = 35; lo.auras[PB_WILD.MARKER] = true   -- left over from an older script (hearts)
player.online = true; for k in pairs(W.Cleaned) do W.Cleaned[k] = nil end; tick()   -- (leftovers are looked for once per player per script load)
check(lo.auras[PB_WILD.MARKER] == nil and lo.faction == 14 and lo.npcflags ~= 2, "leftover marked critter is released from the template (flags " .. tostring(lo.npcflags) .. ")")
for _, r in ipairs({ r1, r2, r3, lo }) do check(r.npcflags ~= 2, "no critter ever ends up with NPC flag 2 (quest giver) instead of gossip") end

-- wrong zone: nothing spawns; nobody near: everything is removed
player.zone = 1519; realMob(299, 1, 1, 1); local before = W.Count(); tick(); tick(); check(W.Count() <= before, "no new wild pets in a disabled zone")
player.online = false; os.time = function() return realTime() + clock end; tick(); local still = W.Count(); clock = clock + 100; tick(); check(still > 0 and W.Count() == 0, "nobody near: removed only after the grace period (" .. still .. " -> " .. W.Count() .. ")")
os.time = realTime
-- WESTFALL (zone 40, retail pet levels 3-4): the first zone with 3-pet fights. Mobs 9-14 give pet level 3, 15-19 give pet level 4; a wild pet brings a team of three at that level
player.zone = 40; player.online = true; player.x, player.y = 3000, 3000
local coyote = realMob(834, 3003, 3000, 14); local tusk = realMob(157, 3000, 3003, 15)
tick(); tick(); tick()
local wcoy, wtusk
for g, w in pairs(W.Wild) do if w.species == 834 then wcoy = objects[g] elseif w.species == 157 then wtusk = objects[g] end end
check(wcoy and wtusk, "Westfall mobs get their wild pets (zone 40 is enabled)")
if wcoy and wtusk then
    check(W.Wild[wcoy.guid].zone == 40, "the wild pet remembers its zone (40)")
    spy = nil; goTo(wcoy); W.OnSelect(nil, player, wcoy, 0, 1)
    check(spy and #spy == 3, "a level 3 Westfall pet fights with a team of THREE (got " .. tostring(spy and #spy) .. ")")
    for _, e in ipairs(spy or {}) do check(e.level == 3, "Coyote (mob 14) team is pet level 3, got " .. tostring(e.level)) end
    check(spy and spy[1].species == 834, "the first enemy is the wild pet's own species")
    spy = nil; goTo(wtusk); W.OnSelect(nil, player, wtusk, 0, 1)
    check(spy and #spy == 3, "Goretusk fights with three pets")
    for _, e in ipairs(spy or {}) do check(e.level == 4, "Goretusk (mob 15) team is pet level 4, got " .. tostring(e.level)) end
end
-- BOTS (playerbots) never get wild pets: a bot standing in a pet zone next to real mobs spawns nothing and keeps nothing alive
player.zone = 12; player.online = true; player.isBot = true; realMob(299, 1, 1, 1)
local botBefore = W.Count(); tick(); tick(); tick()
check(W.Count() == botBefore, "a playerbot next to wild mobs gets no wild pet (before " .. botBefore .. ", after " .. W.Count() .. ")")
player.isBot = false
-- IDLE GATING: a player below the cap with nothing spawnable is not rescanned while standing still, and is again after moving 25+ yd
do
    for g in pairs(W.Wild) do end
    local lonely = { x = 90000, y = 90000 }; player.x, player.y = lonely.x, lonely.y   -- nothing around here
    tick(); local c1 = RANGE_CALLS; tick(); tick(); check(RANGE_CALLS == c1, "standing still with nothing to spawn: no repeated world queries")
    player.x = player.x + 30; tick(); check(RANGE_CALLS == c1 + 1, "after moving 30 yd the surroundings are searched again")
    SENT = {}; W.BlipTick(); check(#SENT == 0 or SENT[#SENT].p == "none", "no pets nearby: no blips (or one clearing message)")
end
local leaked = 0; for _, o in pairs(objects) do if not o.db then leaked = leaked + 1 end end
check(leaked == 0, "no creature objects leaked, got " .. leaked)

-- area cap: at most 3 wild pets within 90 yd of a player, all different species (5 candidate species stand around him)
do
    player.online = false; tick(); tick()   -- clear everything from the scenarios above
    player.x, player.y, player.online = 6000, 6000, true
    for i, e in ipairs({ 299, 69, 257, 721, 883 }) do realMob(e, 6000 + i * 4, 6000 + i * 3, 1) end
    local worst, dup = 0, false
    for _ = 1, 14 do
        tick()
        local n, seen = 0, {}
        for _, w in pairs(W.Wild) do if (w.x - 6000) ^ 2 + (w.y - 6000) ^ 2 < 90 * 90 then n = n + 1; if seen[w.species] then dup = true end seen[w.species] = true end end
        worst = math.max(worst, n)
    end
    check(worst == 3, "area cap: exactly 3 wild pets fill the area (max seen " .. worst .. ")")
    check(not dup, "area cap: never two wild pets of the same species around one player")
    player.online = false; tick(); tick(); player.x, player.y, player.online = 0, 0, true
end

-- spawn spot: 5-50 yd from the mob, on ground within 5 yd of the mob's height; a lake (x > 20) and a cliff (y > 30) are rejected; no ground at all -> the close fallback
do
    local mx, my, mz = 100, 200, 10
    local function height(x, y) if x - mx > 20 then return mz - 40 end if y - my > 30 then return mz + 25 end return mz + 1 end   -- relative to the mob
    local minD, maxD, bad, close = 1e9, 0, 0, 0
    for _ = 1, 500 do
        local x, y, z = W.SpawnSpot(mx, my, mz, height)
        local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
        if d < 4.9 then close = close + 1 end
        minD, maxD = math.min(minD, d), math.max(maxD, d)
        if x - mx > 20 or y - my > 30 or math.abs(z - mz) > 5 then bad = bad + 1 end
    end
    check(bad == 0, "spawn spots: " .. bad .. " of 500 landed in the lake / on the cliff")
    check(close == 0 and minD >= 4.9 and maxD <= 50.1, "spawn spots stay 5-50 yd from the mob (min " .. string.format("%.1f", minD) .. " max " .. string.format("%.1f", maxD) .. ", close fallbacks " .. close .. ")")
    check(maxD > 35, "spawn spots reach far out (max " .. string.format("%.1f", maxD) .. ")")
    local x, y = W.SpawnSpot(mx, my, mz, function() return nil end)
    check(math.sqrt((x - mx) ^ 2 + (y - my) ^ 2) < 3.1, "no ground data: falls back to a close spot instead of failing")
    local errx = W.SpawnSpot(mx, my, mz, function() error("boom") end)
    check(errx ~= nil, "a failing height lookup does not break the spawn")
end

-- wild TEAMS: a 3-pet team = the challenged pet + 2 others drawn from the WHOLE zone (not only what stands nearby), different species, all at the same level
do
    local D2 = require("pb_data"); local ZS = require("pb_zone_species")
    local W = PB_WILD
    check(type(W.BuildEnemies) == "function", "PB_WILD.BuildEnemies is exposed")
    local zid                                   -- a zone with real 3-pet fights (pet level 3+: Elwynn pets are level 1-2 and fight alone) and a big roster
    for id, z in pairs(D2.zones) do if z.lo >= 5 and ZS[z.name] and #ZS[z.name] >= 20 and (not zid or id < zid) then zid = id end end
    assert(zid, "no suitable zone in the data")
    local zname = D2.zones[zid].name; local inzone = {}; for _, sp in ipairs(ZS[zname]) do inzone[sp] = true end
    local main = ZS[zname][1]
    -- the 'seen nearby' list is ONE other species: the old code could only ever pick that one (or the main species) for the two extras
    local w = { species = main, level = D2.zones[zid].maxMob, zone = zid, types = { main, ZS[zname][2] } }
    local seenOther, bad, dup, wrongLv, solo = {}, 0, 0, 0, 0
    for _ = 1, 400 do
        local t = W.BuildEnemies(w)
        if #t ~= 3 then bad = bad + 1 else
            if t[1].species ~= main then bad = bad + 1 end
            if t[2].species == t[3].species or t[2].species == main or t[3].species == main then dup = dup + 1 end
            for i = 2, 3 do
                if not inzone[t[i].species] then bad = bad + 1 end
                seenOther[t[i].species] = true
                if t[i].level ~= t[1].level then wrongLv = wrongLv + 1 end
            end
        end
    end
    local kinds = 0; for _ in pairs(seenOther) do kinds = kinds + 1 end
    check(bad == 0, "every extra pet belongs to the zone (" .. bad .. " bad teams)")
    check(dup == 0, "the 3 pets are 3 different species (" .. dup .. " teams with a repeat)")
    check(wrongLv == 0, "the extra pets have the challenged pet's level")
    check(kinds >= 20, "the extras come from across the whole zone, not just what stands nearby (" .. kinds .. " different species over 400 teams, zone has " .. #ZS[zname] .. ")")
    -- level 1-2 pets still fight alone; an unknown zone falls back to the species seen nearby
    local lowT = W.BuildEnemies({ species = ZS[D2.zones[12].name][1], level = 1, zone = 12, types = {} }); check(#lowT == 1, "a level 1-2 wild pet still fights alone")
    local fb = W.BuildEnemies({ species = main, level = D2.zones[zid].maxMob, zone = 99999, types = { main, ZS[zname][2], ZS[zname][3] } })
    check(#fb == 3 and (fb[2].species == ZS[zname][2] or fb[2].species == ZS[zname][3]), "an unknown zone falls back to the species seen nearby")
end

print(string.format("wild: %d checks passed, %d failed", passes, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
