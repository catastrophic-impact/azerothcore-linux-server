-- WILD PETS: tiny pets that appear next to the real mobs of a species, in enabled zones only (Elwynn Forest first).
-- Right-click one -> "Challenge to a pet battle" -> pb_battle.lua starts the fight against it.
-- Species with wild = "adopt" (critters) do not get a duplicate: the REAL critter becomes the wild pet (right-click menu + a heart marker).
-- Rules: one wild pet per species within SPACING yd (whoever is near), only species flagged wild=true in pb_data.lua, level = the level of the real mob it
-- stands next to, team = its own species + 2 from the species seen nearby (a level 1-2 wild pet fights ALONE). It is removed when nobody is near, after
-- LIFETIME seconds, or when a battle starts; the same spot has a COOLDOWN before that species shows up again.
local D = require("pb_data")
local Store = require("pb_store")

local ZONES = { [12] = true }   -- Elwynn Forest (the zone id includes Northshire Valley). Add more zones here later.
local TICK_MS = 12000
local SEARCH = 60               -- how far from a player real mobs are looked for
local SPACING = 90              -- at most one wild pet per species within this distance of each other
local COOLDOWN = 90             -- seconds before the species re-appears around that spot after a battle
local LIFETIME = 600            -- an untouched wild pet disappears after this many seconds
local LEAVE = 110               -- ...or when no player is within this distance
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

local function Spawn(player, species, mob, types)
    local map = player:GetMapId()
    local ang, dist = math.random() * 6.2832, 2 + math.random() * 1.5
    local x, y, z = mob:GetX() + math.cos(ang) * dist, mob:GetY() + math.sin(ang) * dist, mob:GetZ()
    local obj = PerformIngameSpawn(1, species, map, 0, x, y, z, math.random() * 6.2832, false, 0, 1)
    if not obj then return end
    local g = obj:GetGUIDLow()
    wild[g] = { guid = obj:GetGUID(), species = species, level = mob:GetLevel(), map = map, x = x, y = y, z = z, born = os.time(), types = types }   -- registered first, configured after
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetFaction(35) end)                 -- friendly to everyone
    pcall(function() obj:SetScale(Store.Scale(species)) end)
    pcall(function() local d = obj:GetDisplayId(); if d and d > 0 then wild[g].display = d end end)   -- the skin the player SEES is the skin they can recruit
    pcall(function() obj:SetNPCFlags(1) end)                 -- gossip: right-click works
    pcall(function() obj:SetPhaseMask(1, true) end)
    pcall(function() obj:MoveRandom(3) end)
end

-- strategy A: the real critter itself becomes the wild pet (no duplicate next to it)
local function Adopt(player, species, mob, types)
    local g = mob:GetGUIDLow()
    local flags0, faction0 = 0, nil
    pcall(function() flags0 = mob:GetNPCFlags() or 0 end)
    pcall(function() faction0 = mob:GetFaction() end)
    wild[g] = { guid = mob:GetGUID(), species = species, level = mob:GetLevel(), map = player:GetMapId(), x = mob:GetX(), y = mob:GetY(), z = mob:GetZ(),
                born = os.time(), types = types, adopted = true, flags0 = flags0, faction0 = faction0 }   -- registered first, configured after
    pcall(function() mob:SetFaction(35) end)                   -- friendly (green): nobody can attack or kill the interactive critter
    pcall(function() mob:SetNPCFlags(flags0 % 2 == 1 and flags0 or flags0 + 1) end)   -- gossip bit ON (never add 1 to a flag that already has it: 1 + 1 = 2 is the quest giver bit)
end

local function Scan(player, now)
    local map, px, py = player:GetMapId(), player:GetX(), player:GetY()
    local found, types = {}, {}
    for species, sp in pairs(D.species) do
        if sp.wild then
            local ok, list = pcall(function() return player:GetCreaturesInRange(SEARCH, species, 0, 1) end)   -- both factions, alive
            local mobs = {}
            if ok and list then
                for _, c in ipairs(list) do
                    local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
                    if okd and dbg and dbg > 0 and not c:IsInCombat() then mobs[#mobs + 1] = c end   -- real mobs only (a DB row), never script-spawned pets
                end
            end
            if sp.wild == "adopt" then   -- never adopt a critter that already is a wild pet
                local free = {}
                for _, m in ipairs(mobs) do if not wild[m:GetGUIDLow()] then free[#free + 1] = m end end
                mobs = free
            end
            if #mobs > 0 then found[species] = mobs; types[#types + 1] = species end
        end
    end
    for _, species in ipairs(types) do
        local mobs = found[species]
        local m = mobs[math.random(#mobs)]
        local mx, my = m:GetX(), m:GetY()
        if not WildNear(species, map, mx, my) and not Cooling(species, map, mx, my, now) then
            if D.species[species].wild == "adopt" then Adopt(player, species, m, types) else Spawn(player, species, m, types) end
            return   -- at most one new wild pet per player per tick: they trickle in
        end
    end
end

-- critters left friendly/marked by an earlier script instance (reload / crash) that no registry entry owns: give them back
local function CleanLeftovers(player)
    for species, sp in pairs(D.species) do
        if sp.wild == "adopt" or sp.critter then   -- real critters that an earlier version (or the adopt option) may have left friendly / flagged
            local ok, list = pcall(function() return player:GetCreaturesInRange(SEARCH + 40, species, 0, 1) end)
            if ok and list then
                for _, c in ipairs(list) do
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
    end
end

local function Tick()
    local now = os.time()
    local players = GetPlayersInWorld() or {}
    for g, w in pairs(wild) do
        local live = Obj(w)
        if live then w.x, w.y = live:GetX(), live:GetY() end   -- a wandering critter moves
        local near = false
        for _, pl in ipairs(players) do
            if pl:GetMapId() == w.map and (pl:GetX() - w.x) ^ 2 + (pl:GetY() - w.y) ^ 2 < LEAVE * LEAVE then near = true; break end
        end
        if not near or now - w.born > LIFETIME or not live then Remove(g, false, false, (not near and "nobody near") or (not live and "object lookup failed") or "lifetime") end
    end
    for _, pl in ipairs(players) do
        if ZONES[pl:GetZoneId()] then pcall(CleanLeftovers, pl) end
        if ZONES[pl:GetZoneId()] and pl:IsAlive() and Store.NormalWorld(pl) and not pl:IsInCombat()
           and not (PB_BATTLE and PB_BATTLE.InBattle(pl)) then
            local ok, err = pcall(Scan, pl, now)
            if not ok then print("[pb_wild] scan error: " .. tostring(err)) end
        end
    end
end
CreateLuaEvent(Tick, TICK_MS, 0)

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
    local lv = D.PetLevel(w.level)   -- mob level (1-80) -> pet level (1-25)
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
    end
end

-- test hooks (used by pet-battle/smoke_wild.lua)
PB_WILD.MARKER = MARKER
PB_WILD.Tick, PB_WILD.Count = Tick, function() local n = 0; for _ in pairs(wild) do n = n + 1 end; return n end
PB_WILD.OnHello, PB_WILD.OnSelect, PB_WILD.Wild = OnHello, OnSelect, wild
print("[pb_wild] loaded")
return true
