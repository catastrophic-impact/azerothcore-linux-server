-- WILD PETS: tiny pets that appear next to the real mobs of a species, in enabled zones only (Elwynn Forest first).
-- Right-click one -> "Challenge to a pet battle" -> pb_battle.lua starts the fight against it.
-- Species with wild = "adopt" (critters) do not get a duplicate: the REAL critter becomes the wild pet (right-click menu + a heart marker).
-- Rules: one wild pet per species within SPACING yd (whoever is near), only species flagged wild=true in pb_data.lua, level = the level of the real mob it
-- stands next to, team = its own species + 2 from the species seen nearby (a level 1-2 wild pet fights ALONE). It is removed when nobody is near, after
-- LIFETIME seconds, or when a battle starts; the same spot has a COOLDOWN before that species shows up again.
local D = require("pb_data")
local Store = require("pb_store")

local ZONES = { [3483] = true, [3521] = true, [3519] = true, [3518] = true, [3522] = true, [3523] = true, [3520] = true, [3537] = true, [495] = true, [65] = true, [394] = true, [66] = true, [3711] = true, [67] = true, [210] = true, [2817] = true, [4197] = true, [36] = true, [493] = true, [618] = true, [361] = true, [15] = true, [17] = true, [16] = true, [28] = true, [8] = true, [33] = true, [139] = true, [41] = true, [4] = true, [406] = true, [1377] = true, [490] = true, [400] = true, [440] = true, [357] = true, [405] = true, [331] = true, [11] = true, [51] = true, [47] = true, [267] = true, [10] = true, [46] = true, [3] = true, [45] = true, [3525] = true, [3433] = true, [44] = true, [38] = true, [148] = true, [130] = true, [3524] = true, [3430] = true, [85] = true, [215] = true, [141] = true, [12] = true, [1] = true, [14] = true, [40] = true }   -- Elwynn Forest (12, includes Northshire Valley), Dun Morogh (1, includes Coldridge Valley), Durotar (14, includes Valley of Trials), Westfall (40). Add more zones here later (and a D.zones row in pb_data.lua).
-- Needs: mod-ale (built and tested with commit 84b85cc) and the shared core scripts acore_*.lua in the same lua_scripts folder.
for _, m in ipairs({ "acore_msg", "acore_prime", "acore_bus", "acore_util", "acore_settings" }) do if not pcall(require, m) then print("[Pet Battles] DISABLED: the shared core script " .. m .. ".lua is missing from lua_scripts (copy all acore_*.lua files, see the README)"); return true end end
local Msg = require("acore_msg")
local TICK_MS = 5000            -- the fill/despawn tick: cheap, because a player whose area is full (or who stands still with nothing to spawn) costs no world scan at all
local BLIP_MS = 1000            -- minimap blips for the wild pets around each player (only players that have any)
local SEARCH = 60               -- how far from a player real mobs are looked for
local SPACING = 90              -- at most one wild pet per species within this distance of each other
local MAX_AREA = 3              -- at most this many wild pets within SPACING of a player, all of DIFFERENT species (user: up to 3, never 2-3 of a kind)
local COOLDOWN = 90             -- seconds before the species re-appears around that spot after a battle
local LIFETIME = 600            -- an untouched wild pet disappears after this many seconds
local LEAVE = 90                -- ...or when no player has been within this distance for AWAY_GRACE seconds (running past and coming back must not wipe the area)
local AWAY_GRACE = 60
local MOVE_RESCAN = 25          -- a player below the cap is only rescanned after moving this far, or after RESCAN_IDLE seconds, when the last scan found nothing to spawn
local RESCAN_IDLE = 45
local TALK_RANGE = 12           -- how close you must be to challenge it
local SOLO_MAX_LEVEL = 2        -- wild pets up to this PET level (not mob level: mob level 6 is already pet level 2) fight alone
local MARKER = 62011            -- the old heart marker: no longer applied (the green friendly name is the cue); only removed from critters that still carry it

local wild = {}    -- creature LOW guid (a number; GetGUID() objects are never equal as table keys) -> { guid, species, level, map, x, y, z, born, types }
local cool = {}    -- list of { species, map, x, y, untilTime }: this species may not appear within SPACING of that spot before untilTime
PB_WILD = { IsWild = function(guid) return wild[guid] ~= nil end }

local function Cooling(species, map, x, y, now)
    for i = #cool, 1, -1 do
        local c = cool[i]
        if c.untilTime <= now then table.remove(cool, i)
        elseif c.species == species and c.map == map and (c.x - x) ^ 2 + (c.y - y) ^ 2 < SPACING * SPACING then return true end
    end
    return false
end
-- Template faction / NPC flags of the species we ADOPT: a critter marked by an earlier script instance (reload, crash) has lost its saved originals,
-- so a stray one is restored from the template.
local TEMPLATE = {}
do
    local ids = {}
    for species, sp in pairs(D.species) do if sp.wild == "adopt" or sp.critter then ids[#ids + 1] = species end end
    if #ids > 0 then
        local q = WorldDBQuery("SELECT entry, faction, npcflag FROM creature_template WHERE entry IN (" .. table.concat(ids, ",") .. ")")
        if q then repeat TEMPLATE[q:GetUInt32(0)] = { faction = q:GetUInt32(1), npcflag = q:GetUInt32(2) } until not q:NextRow() end
    end
end
local function Release(o, species, faction0, flags0)   -- give a critter back as a normal one
    local t = TEMPLATE[species] or {}
    pcall(function() o:RemoveAura(MARKER) end)
    pcall(function() o:SetNPCFlags(t.npcflag or flags0 or 0) end)
    local f = t.faction or faction0
    if f then pcall(function() o:SetFaction(f) end) end
end
local function Obj(w) local map = GetMapById(w.map, 0); return map and map:GetWorldObject(w.guid) end

-- Remove a wild pet. A spawned one is despawned. An ADOPTED real critter is given back (flags + marker removed) unless it was consumed by a battle,
-- in which case it despawns and returns on its normal respawn timer.
local function Remove(guid, startCooldown, consume, why)
    local w = wild[guid]
    if not w then return end
    local o = Obj(w)
    if o then
        if w.adopted and not consume then
            Release(o, w.species, w.faction0, w.flags0)   -- a normal neutral critter again
        else
            pcall(function() o:DespawnOrUnsummon(0) end)
        end
    end
    if startCooldown then cool[#cool + 1] = { species = w.species, map = w.map, x = w.x, y = w.y, untilTime = os.time() + COOLDOWN } end
    wild[guid] = nil
end

local function WildNear(species, map, x, y)
    for _, w in pairs(wild) do
        if w.species == species and w.map == map and (w.x - x) ^ 2 + (w.y - y) ^ 2 < SPACING * SPACING then return true end
    end
    return false
end

-- Where a wild pet appears: a random spot 5-50 yd from its mob (the user wants them spread out, not stacked on the mob). The ground there must exist and sit within
-- MAX_DZ of the mob's height (rejects cliffs, lake beds, spots under a roof/overhang); up to 8 tries, otherwise the old close spot (3 yd) so a spawn never fails.
local MIN_DIST, MAX_DIST, MAX_DZ, TRIES = 5, 50, 2.5, 8   -- MAX_DZ: the terrain only has to be roughly level with the mob (the creature then settles on the REAL floor, verified -1.5..+3 yd)
local function SpawnSpot(mx, my, mz, height, rand)
    rand = rand or math.random
    for _ = 1, TRIES do
        local ang, dist = rand() * 6.2832, MIN_DIST + rand() * (MAX_DIST - MIN_DIST)
        local x, y = mx + math.cos(ang) * dist, my + math.sin(ang) * dist
        local ok, h = pcall(height, x, y)
        if ok and h and h > -1000 and math.abs(h - mz) <= MAX_DZ then return x, y, mz + 1.0 end   -- spawn a yard above the mob's height; the heightmap is NOT the floor in mines/caves, the movement system finds the real one
    end
    local ang = rand() * 6.2832
    return mx + math.cos(ang) * 3, my + math.sin(ang) * 3, mz
end

local function Spawn(player, species, mob, types)
    local map = player:GetMapId()
    local x, y, z = SpawnSpot(mob:GetX(), mob:GetY(), mob:GetZ(), function(px, py) local m = mob:GetMap(); return m and m:GetHeight(px, py, 1) end)
    local obj = PerformIngameSpawn(1, D.StandIn(species) or species, map, 0, x, y, z, math.random() * 6.2832, false, 0, 1)   -- a stand-in clone is BORN at the pet scale (template DisplayScale): no full-size flash
    if not obj then return end
    local birthScale = obj:GetScale()   -- read BEFORE any SetScale: what the client gets in the create packet
    local g = obj:GetGUIDLow()
    wild[g] = { guid = obj:GetGUID(), species = species, level = mob:GetLevel(), zone = player:GetZoneId(), map = map, x = x, y = y, z = z, born = os.time(), types = types, birthScale = birthScale, birthLevel = obj:GetLevel(), birthDisplay = obj:GetDisplayId() }   -- registered first, configured after
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetFaction(35) end)                 -- friendly to everyone
    -- NO SetLevel: stand-in clones are level 80 on purpose (any level change on a visible creature plays the level-up animation). The wild pet's real level lives in wild[g].level (menu, blips, battle).
    local bornDisplay = obj:GetDisplayId()
    local wantScale = Store.ScaleOf(species, bornDisplay)   -- the scale of the model that spawned (each template model row carries its own DisplayScale)
    wild[g].wantScale = wantScale
    pcall(function() obj:SetScale(wantScale) end)
    CreateLuaEvent(function() local o = wild[g] and Obj(wild[g]); if o then pcall(function() o:SetScale(wantScale) end) end end, 700, 1)   -- once more shortly after the spawn
    pcall(function() local d = obj:GetDisplayId(); if d and d > 0 then wild[g].display = d end end)   -- the skin the player SEES is the skin they can recruit
    pcall(function() obj:SetNPCFlags(1) end)                 -- gossip: right-click works
    pcall(function() obj:SetPhaseMask(1, true) end)
    pcall(function() obj:MoveTo(1, x, y, z, true) end)   -- settle on the real floor
    pcall(function() obj:MoveRandom(3) end)
    return obj
end

-- strategy A: the real critter itself becomes the wild pet (no duplicate next to it)
local function Adopt(player, species, mob, types)
    local g = mob:GetGUIDLow()
    local flags0, faction0 = 0, nil
    pcall(function() flags0 = mob:GetNPCFlags() or 0 end)
    pcall(function() faction0 = mob:GetFaction() end)
    wild[g] = { guid = mob:GetGUID(), species = species, level = mob:GetLevel(), zone = player:GetZoneId(), map = player:GetMapId(), x = mob:GetX(), y = mob:GetY(), z = mob:GetZ(),
                born = os.time(), types = types, adopted = true, flags0 = flags0, faction0 = faction0 }   -- registered first, configured after
    pcall(function() mob:SetFaction(35) end)                   -- friendly (green): nobody can attack or kill the interactive critter
    pcall(function() mob:SetNPCFlags(flags0 % 2 == 1 and flags0 or flags0 + 1) end)   -- gossip bit ON (never add 1 to a flag that already has it: 1 + 1 = 2 is the quest giver bit)
end

local scanned = {}   -- player low guid -> { map, x, y, t, spawned }: when this player's surroundings were last searched
local function Scan(player, now)
    local map, px, py = player:GetMapId(), player:GetX(), player:GetY()
    local near, here = 0, {}   -- wild pets already around this player (within SPACING of him): the cap and the species that are taken
    for _, w in pairs(wild) do
        if w.map == map and (w.x - px) ^ 2 + (w.y - py) ^ 2 < SPACING * SPACING then near = near + 1; here[w.species] = true end
    end
    if near >= MAX_AREA then return end   -- full: no world query at all
    local low = player:GetGUIDLow(); local last = scanned[low]
    if last and last.map == map and not last.spawned and now - last.t < RESCAN_IDLE and (last.x - px) ^ 2 + (last.y - py) ^ 2 < MOVE_RESCAN * MOVE_RESCAN then return end   -- nothing was spawnable here a moment ago and he has not moved
    local found, types = {}, {}
    -- ONE range query (all creatures within SEARCH, both factions, alive), bucketed by entry: 20x cheaper than one query per species (measured live) and the same result set
    local ok, list = pcall(function() return player:GetCreaturesInRange(SEARCH, 0, 0, 1) end)
    if ok and list then
        for _, c in ipairs(list) do
            local species = c:GetEntry(); local sp = D.species[species]
            if sp and sp.wild then
                local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
                if okd and dbg and dbg > 0 and not c:IsInCombat() and not (sp.wild == "adopt" and wild[c:GetGUIDLow()]) then   -- real mobs only (a DB row), never script-spawned pets
                    if not found[species] then found[species] = {}; types[#types + 1] = species end
                    local l = found[species]; l[#l + 1] = c
                end
            end
        end
    end
    table.sort(types)   -- deterministic order (pairs() order would make the species pick random per run)
    local spawned = 0
    for _, species in ipairs(types) do
        if near >= MAX_AREA then break end   -- the whole area is filled in ONE pass (the old one-per-tick trickle made you wait)
        local mobs = found[species]
        local m = mobs[math.random(#mobs)]
        local mx, my = m:GetX(), m:GetY()
        if not here[species] and not WildNear(species, map, mx, my) and not Cooling(species, map, mx, my, now) then
            if D.species[species].wild == "adopt" then Adopt(player, species, m, types) else Spawn(player, species, m, types) end
            near = near + 1; here[species] = true; spawned = spawned + 1
        end
    end
    scanned[low] = { map = map, x = px, y = py, t = now, spawned = spawned > 0 }
end

-- critters left friendly/marked by an earlier script instance (reload / crash) that no registry entry owns: give them back
local function CleanLeftovers(player)
    local ok, list = pcall(function() return player:GetCreaturesInRange(SEARCH + 40, 0, 0, 1) end)   -- ONE range query, filtered by entry (was one query per critter species)
    if not (ok and list) then return end
    for _, c in ipairs(list) do
        local species = c:GetEntry(); local sp = D.species[species]
        if sp and (sp.wild == "adopt" or sp.critter) then   -- real critters that an earlier version (or the adopt option) may have left friendly / flagged
            local okf, fac = pcall(function() return c:GetFaction() end)
            local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
            -- a REAL critter (DB row) that is friendly (35) or still carries the old heart marker, but no registry entry owns it
            local hearts = false; pcall(function() hearts = c:HasAura(MARKER) end)
            if ((okf and fac == 35 and okd and dbg and dbg > 0) or hearts) and not wild[c:GetGUIDLow()] then
                Release(c, species); print("[pb_wild] released a leftover critter (" .. D.species[species].name .. ") low=" .. tostring(c:GetGUIDLow()))
            end
        end
    end
end

local cleaned = {}   -- player low guid -> true: leftovers around him were already looked for
local function Tick()
    local now = os.time()
    local players = {}
    for _, pl in ipairs(GetPlayersInWorld() or {}) do if Store.IsHuman(pl) then players[#players + 1] = pl end end   -- bots do not count
    for g, w in pairs(wild) do
        local live = Obj(w)
        if live then w.x, w.y = live:GetX(), live:GetY() end   -- a wandering critter moves
        if live and not w.adopted and (w.rescale or 0) < 3 then   -- the pet-sized scale again for the first ticks after the spawn (some pets showed full size for a while)
            w.rescale = (w.rescale or 0) + 1; pcall(function() live:SetScale(w.wantScale or Store.Scale(w.species)) end)
        end
        local near = false
        for _, pl in ipairs(players) do
            if pl:GetMapId() == w.map and (pl:GetX() - w.x) ^ 2 + (pl:GetY() - w.y) ^ 2 < LEAVE * LEAVE then near = true; break end
        end
        if near then w.away = nil elseif not w.away then w.away = now end
        local gone = (w.away and now - w.away >= AWAY_GRACE)
        if gone or now - w.born > LIFETIME or not live then Remove(g, false, false, (gone and "nobody near") or (not live and "object lookup failed") or "lifetime") end
    end
    for _, pl in ipairs(players) do
        if ZONES[pl:GetZoneId()] and not cleaned[pl:GetGUIDLow()] then cleaned[pl:GetGUIDLow()] = true; pcall(CleanLeftovers, pl) end   -- ONCE per player per script load (it was a world query every tick)
        if ZONES[pl:GetZoneId()] and pl:IsAlive() and Store.NormalWorld(pl) and not pl:IsInCombat()
           and not (PB_BATTLE and PB_BATTLE.InBattle(pl)) then
            local ok, err = pcall(Scan, pl, now)
            if not ok then print("[pb_wild] scan error: " .. tostring(err)) end
        end
    end
end
CreateLuaEvent(Tick, TICK_MS, 0)

-- MINIMAP BLIPS: each player gets the wild pets of his area as offsets in yards (east/north) so the addon can draw them on the minimap with our own icon.
-- "pbw|pets|<dxNorth>,<dyWest>,<species>,<level>,<name>;..."  sent every BLIP_MS while there are any, once more (empty) when the last one is gone.
local hadBlips = {}
local function BlipTick()
    for _, pl in ipairs(GetPlayersInWorld() or {}) do
        if Store.IsHuman(pl) then
            local map, px, py = pl:GetMapId(), pl:GetX(), pl:GetY()
            local parts = {}
            for _, w in pairs(wild) do
                local dx, dy = w.x - px, w.y - py
                if w.map == map and dx * dx + dy * dy < (SPACING + 40) ^ 2 then   -- close enough to matter: take the live position (the 5 s tick made blips lag behind a wandering pet)
                    local live = Obj(w); if live then w.x, w.y = live:GetX(), live:GetY(); dx, dy = w.x - px, w.y - py end
                end
                if w.map == map and dx * dx + dy * dy < SPACING * SPACING and #parts < MAX_AREA + 2 then
                    parts[#parts + 1] = string.format("%d,%d,%d,%d,%s", math.floor(dx + 0.5), math.floor(dy + 0.5), w.species, w.level or 1, D.species[w.species].name)
                end
            end
            local low = pl:GetGUIDLow()
            if #parts > 0 then Msg.Send(pl, "pbw", "pets", table.concat(parts, ";")); hadBlips[low] = true
            elseif hadBlips[low] then Msg.Send(pl, "pbw", "pets", "none"); hadBlips[low] = nil end
        end
    end
end
CreateLuaEvent(BlipTick, BLIP_MS, 0)

---------------------------------------------------------------- right-click menu
local function OnHello(event, player, creature)
    local w = wild[creature:GetGUIDLow()]
    if not w then return end                       -- a normal creature of this entry: leave the default behaviour alone
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Challenge " .. D.species[w.species].name .. " to a pet battle", 0, 1)
    player:GossipMenuAddItem(0, "Never mind", 0, 2)
    player:GossipSendMenu(1, creature)
    return true
end

local function E_ROLL() return PB_CORE and PB_CORE.RollQuality() or 1 end
local function BuildEnemies(w)
    local lv = D.PetLevel(w.level, w.zone)   -- mob level -> pet level, spread over the zone's retail range (see D.zones)
    local team = { { species = w.species, level = lv, display = w.display, quality = E_ROLL() } }
    if lv > SOLO_MAX_LEVEL then
        local pool = (w.types and #w.types > 0) and w.types or { w.species }
        for _ = 1, 2 do team[#team + 1] = { species = pool[math.random(#pool)], level = lv, quality = E_ROLL() } end
    end
    return team
end

local function OnSelect(event, player, creature, sender, intid)
    player:GossipComplete()
    if intid ~= 1 then return true end
    local g = creature:GetGUIDLow()
    local w = wild[g]
    if not w then return true end
    if (player:GetX() - creature:GetX()) ^ 2 + (player:GetY() - creature:GetY()) ^ 2 > TALK_RANGE * TALK_RANGE then
        player:SendBroadcastMessage("You are too far away from it."); return true
    end
    if PB_BATTLE and PB_BATTLE.Start(player, BuildEnemies(w)) then Remove(g, true, true) end   -- only consumed when the battle really started
    return true
end

for species, sp in pairs(D.species) do
    if sp.wild then
        RegisterCreatureGossipEvent(species, 1, OnHello)
        RegisterCreatureGossipEvent(species, 2, OnSelect)
        if D.StandIn(species) then RegisterCreatureGossipEvent(D.StandIn(species), 1, OnHello); RegisterCreatureGossipEvent(D.StandIn(species), 2, OnSelect) end
    end
end

-- test hooks (used by pet-battle/smoke_wild.lua)
PB_WILD.MARKER = MARKER
PB_WILD.SpawnSpot = SpawnSpot
PB_WILD.BlipTick, PB_WILD.Scanned, PB_WILD.Cleaned = BlipTick, scanned, cleaned
PB_WILD.Tick, PB_WILD.Count = Tick, function() local n = 0; for _ in pairs(wild) do n = n + 1 end; return n end
PB_WILD.OnHello, PB_WILD.OnSelect, PB_WILD.Wild = OnHello, OnSelect, wild

-- .pbcheck (GM only): spawns 8 wild pets around the caller through the REAL spawn path, then reports PASS/FAIL per pet in the chat: born at the pet scale (no full-size flash) and settled on a floor
-- (height within 4 yd of the caller). The pets stay 25 s so you can look, then are removed. Run it anywhere (e.g. inside a mine).
local function CheckSet()
    local ids = {}
    for sp, d in pairs(D.species) do if d.wild and D.StandIn(sp) then ids[#ids + 1] = sp end end
    table.sort(ids, function(a, b) return Store.Scale(a) < Store.Scale(b) end)
    local pick, seen = {}, {}
    local function add(sp) if sp and not seen[sp] and D.species[sp] then seen[sp] = true; pick[#pick + 1] = sp end end
    add(ids[1]); add(ids[#ids]); add(43); add(6827)   -- 6827 = Crab: 4 very different models
    for _, q in ipairs({ 0.25, 0.5, 0.75, 0.9 }) do add(ids[math.max(1, math.floor(#ids * q))]) end
    return pick
end
local function RunCheck(player)
    local pg = player:GetGUID()
    local px, py, pz = player:GetX(), player:GetY(), player:GetZ()
    local made = {}
    for _, sp in ipairs(CheckSet()) do
        for _ = 1, 2 do   -- twice: a species with several models shows a random one
            local ok, obj = pcall(Spawn, player, sp, player, { sp })
            if ok and obj then made[#made + 1] = { sp = sp, g = obj:GetGUIDLow() } else player:SendBroadcastMessage("[pbcheck] FAIL spawn " .. D.species[sp].name .. " " .. tostring(obj)) end
        end
    end
    print("[pbcheck] start"); player:SendBroadcastMessage("[pbcheck] spawned " .. #made .. " wild pets near you, measuring...")
    CreateLuaEvent(function()
        local pl = GetPlayerByGUID(pg); if not pl then return end
        local fails = 0
        for _, m in ipairs(made) do
            local w = wild[m.g]; local o = w and Obj(w)
            if not o then fails = fails + 1; pl:SendBroadcastMessage("[pbcheck] FAIL " .. D.species[m.sp].name .. ": pet gone")
            else
                local want, born, z = Store.ScaleOf(m.sp, w.birthDisplay), w.birthScale or -1, o:GetZ()
                local width = Store.SizeOf(m.sp, w.birthDisplay)
                local okS, okZ = math.abs(born - want) < 0.01 and o:GetLevel() == w.birthLevel and (not width or (D.species[m.sp].companion and width <= 0.91) or math.abs(width - 0.53) < 0.01), math.abs(z - pz) < 4
                if not (okS and okZ) then fails = fails + 1 end
                local line = string.format("[pbcheck] %s %-24s born-scale %.2f (want %.2f)  size %.2f yd  height %+.1f vs you", (okS and okZ) and "PASS" or "FAIL", D.species[m.sp].name, born, want, width or 0, z - pz); pl:SendBroadcastMessage(line); print(line)
            end
        end
        local sum = fails == 0 and ("[pbcheck] ALL " .. #made .. " PASS") or ("[pbcheck] " .. fails .. " FAILED (of " .. #made .. ")"); pl:SendBroadcastMessage(sum); print(sum)
    end, 3000, 1)
    CreateLuaEvent(function() for _, m in ipairs(made) do pcall(Remove, m.g, false, false, "pbcheck") end end, 25000, 1)
end
PB_WILD.Check = RunCheck
RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command or not command:match("^pbcheck%s*$") then return end
    if player:GetGMRank() < 2 then return end
    RunCheck(player)
end)


-- .pbsize <species id> (GM only): a size calibration lineup 4 yd in front of you, left to right: the Mine Spider (the reference you approved) and the species at 4 scales: x1 (what the formula says),
-- x0.5, x0.25, x0.1. Look at which one matches the spider; the chat says the order. Removed after 90 s.
local function RunSize(player, sp)
    local d = D.species[sp]
    if not (d and D.StandIn(sp)) then player:SendBroadcastMessage("[pbsize] unknown species " .. tostring(sp)) return end
    local x, y, z, o = player:GetX(), player:GetY(), player:GetZ(), player:GetO()
    local fx, fy, lx, ly = math.cos(o), math.sin(o), -math.sin(o), math.cos(o)
    local list = { { 43, nil, "Mine Spider (reference)" } }
    for _, f in ipairs({ 1, 0.5, 0.25, 0.1 }) do list[#list + 1] = { sp, f, d.name .. " x" .. f } end
    for i, e in ipairs(list) do
        local off = (i - 3) * 2.2
        local px, py = x + fx * 4 + lx * off, y + fy * 4 + ly * off
        local obj = PerformIngameSpawn(1, D.StandIn(e[1]), player:GetMapId(), 0, px, py, z + 1.0, o + 3.14159, false, 0, 1)
        if obj then
            pcall(function() obj:SetReactState(0); obj:SetFaction(35); obj:SetUnitFlags(0) end)
            local disp = obj:GetDisplayId()
            local sc = Store.ScaleOf(e[1], disp) * (e[2] or 1)
            pcall(function() obj:SetScale(sc) end)
            pcall(function() obj:MoveTo(1, px, py, z + 1.0, true) end)
            pcall(function() obj:RegisterEvent(function(ev, dl, n, c) c:DespawnOrUnsummon(0) end, 90000, 1) end)   -- removed after 90 s
            local line = string.format("[pbsize] %d. %s  scale %.3f  display %s", i, e[3], sc, tostring(disp)); player:SendBroadcastMessage(line); print(line)
        end
    end
    player:SendBroadcastMessage("[pbsize] left to right as listed. Which one matches the spider?")
end
PB_WILD.Size = RunSize
RegisterPlayerEvent(42, function(_, player, command)
    local id = command and command:match("^pbsize%s+(%d+)%s*$")
    if not player or not id then return end
    if player:GetGMRank() < 2 then return end
    RunSize(player, tonumber(id))
end)

-- .pbcrab (GM only): spawns ONLY the Crab (species 6827) 4 yd in front of you at its computed scale (screenshot it next to your character). Removed after 90 s.
local function RunCrab(player)
    local x, y, z, o = player:GetX(), player:GetY(), player:GetZ(), player:GetO()
    local obj = PerformIngameSpawn(1, D.StandIn(6827), player:GetMapId(), 0, x + math.cos(o) * 4, y + math.sin(o) * 4, z + 1.0, o + 3.14159, false, 0, 1)
    if not obj then player:SendBroadcastMessage("[pbcrab] spawn failed") return end
    pcall(function() obj:SetReactState(0); obj:SetFaction(35); obj:SetUnitFlags(0) end)
    local sc = Store.ScaleOf(6827, obj:GetDisplayId())
    pcall(function() obj:SetScale(sc) end)
    pcall(function() obj:MoveTo(1, x + math.cos(o) * 4, y + math.sin(o) * 4, z + 1.0, true) end)
    pcall(function() obj:RegisterEvent(function(ev, d, n, c) c:DespawnOrUnsummon(0) end, 90000, 1) end)
    local line = string.format("[pbcrab] Crab spawned in front of you, scale %.3f, display %s (removed in 90 s)", sc, tostring(obj:GetDisplayId())); player:SendBroadcastMessage(line); print(line)
end
PB_WILD.Crab = RunCrab
RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command or not command:match("^pbcrab%s*$") then return end
    if player:GetGMRank() < 2 then return end
    RunCrab(player)
end)

-- .pbk (GM only): display-scale calibration grid. Pets whose client display scale k runs from 0.1 to 0.8 (the client seems to ignore a tiny k: the Crab, k=0.1, was drawn ~10x too big), each at its
-- COMPUTED scale, 4 columns x 3 rows in front of you, nearest row first, left to right as listed in the chat. If k were honored they would all look the same size. Removed after 120 s.
local KSAMPLES = { { 6827, 0.1 }, { 1512, 0.1 }, { 1553, 0.15 }, { 1513, 0.2 }, { 3251, 0.25 }, { 1554, 0.3 }, { 30, 0.4 }, { 43, 0.55 }, { 3461, 0.5 }, { 113, 0.6 }, { 1120, 0.8 }, { 299, 0.4 } }
local function RunK(player)
    local x, y, z, o = player:GetX(), player:GetY(), player:GetZ(), player:GetO()
    local fx, fy, lx, ly = math.cos(o), math.sin(o), -math.sin(o), math.cos(o)
    for i, e in ipairs(KSAMPLES) do
        local sp = e[1]
        if D.species[sp] and D.StandIn(sp) then
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            local px, py = x + fx * (7 + row * 5) + lx * (col - 1.5) * 4.5, y + fy * (7 + row * 5) + ly * (col - 1.5) * 4.5
            local obj = PerformIngameSpawn(1, D.StandIn(sp), player:GetMapId(), 0, px, py, z + 1.0, o + 3.14159, false, 0, 1)
            if obj then
                pcall(function() obj:SetReactState(0); obj:SetFaction(35); obj:SetUnitFlags(0) end)
                local sc = Store.ScaleOf(sp, obj:GetDisplayId())
                pcall(function() obj:SetScale(sc) end)
                pcall(function() obj:MoveTo(1, px, py, z + 1.0, true) end)
                pcall(function() obj:RegisterEvent(function(ev, d, n, c) c:DespawnOrUnsummon(0) end, 120000, 1) end)
                local line = string.format("[pbk] %d. %s  client display scale %.2f  our scale %.3f", i, D.species[sp].name, e[2], sc); player:SendBroadcastMessage(line); print(line)
            end
        end
    end
    player:SendBroadcastMessage("[pbk] nearest row first, left to right. Take ONE screenshot with all of them in view.")
end
PB_WILD.K = RunK
RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command or not command:match("^pbk%s*$") then return end
    if player:GetGMRank() < 2 then return end
    RunK(player)
end)
print("[pb_wild] loaded")
return true
