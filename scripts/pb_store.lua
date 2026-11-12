-- Pet battle STORAGE + journal server side (module "pbj"). One row per owned species per character (a duplicate recruit REPLACES it).
-- Tables (acore_characters): dc_battlepet(guid, species, level, xp, a1, a2, a3)   dc_battleteam(guid, team, slot, species)   dc_battleplayer(guid, active_team)
-- Client -> server: pbj|list  pbj|abil|<species>  pbj|setabil|<species>,<slot>,<opt>  pbj|setteam|<team>,<s1>,<s2>,<s3>  pbj|active|<team>  pbj|grant (TEMP test: gives the pilot pets)
-- Server -> client: pbj|pet|..., pbj|team|..., pbj|active|n, pbj|done, pbj|abl|...
local Msg = require("acore_msg")
local D = require("pb_data")
local Eng = require("pb_core")

if PB_STORE then return PB_STORE end   -- the server runs every script AND require() may load it again: keep ONE instance (one cache)
local Store = {}
PB_STORE = Store
local Info   -- forward declaration (defined below, used by the XP code)
local TEAMS = 3
local cache = {}   -- guidLow -> { pets = { [species] = {level, xp, a = {1,1,1}} }, teams = { [n] = {s1,s2,s3} }, active = 1 }

CharDBExecute("CREATE TABLE IF NOT EXISTS dc_battlepet (guid INT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, level TINYINT UNSIGNED NOT NULL DEFAULT 1, xp INT UNSIGNED NOT NULL DEFAULT 0, a1 TINYINT NOT NULL DEFAULT 1, a2 TINYINT NOT NULL DEFAULT 1, a3 TINYINT NOT NULL DEFAULT 1, quality TINYINT UNSIGNED NOT NULL DEFAULT 1, display INT UNSIGNED NOT NULL DEFAULT 0, hp INT UNSIGNED NOT NULL DEFAULT 0, hp_at INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (guid, species)) ENGINE=InnoDB")
-- older installs: add the columns that came later (hp 0 = full health)
for _, c in ipairs({ { "quality", "TINYINT UNSIGNED NOT NULL DEFAULT 1" }, { "display", "INT UNSIGNED NOT NULL DEFAULT 0" }, { "hp", "INT UNSIGNED NOT NULL DEFAULT 0" }, { "hp_at", "INT UNSIGNED NOT NULL DEFAULT 0" } }) do
    if not CharDBQuery("SHOW COLUMNS FROM dc_battlepet LIKE '" .. c[1] .. "'") then CharDBExecute("ALTER TABLE dc_battlepet ADD COLUMN " .. c[1] .. " " .. c[2]) end
end
CharDBExecute("CREATE TABLE IF NOT EXISTS dc_battleteam (guid INT UNSIGNED NOT NULL, team TINYINT UNSIGNED NOT NULL, slot TINYINT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, PRIMARY KEY (guid, team, slot)) ENGINE=InnoDB")
CharDBExecute("CREATE TABLE IF NOT EXISTS dc_battlefollower (guid INT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, PRIMARY KEY (guid)) ENGINE=InnoDB")
CharDBExecute("CREATE TABLE IF NOT EXISTS dc_battleplayer (guid INT UNSIGNED NOT NULL, active_team TINYINT UNSIGNED NOT NULL DEFAULT 1, PRIMARY KEY (guid)) ENGINE=InnoDB")

local function Load(guid)
    if cache[guid] then return cache[guid] end
    local c = { pets = {}, teams = {}, active = 1 }
    for n = 1, TEAMS do c.teams[n] = { 0, 0, 0 } end
    local q = CharDBQuery("SELECT species, level, xp, a1, a2, a3, quality, display, hp, hp_at FROM dc_battlepet WHERE guid=" .. guid)
    if q then repeat
        c.pets[q:GetUInt32(0)] = { level = q:GetUInt32(1), xp = q:GetUInt32(2), a = { q:GetUInt32(3), q:GetUInt32(4), q:GetUInt32(5) },
                                   quality = math.max(1, q:GetUInt32(6)), display = q:GetUInt32(7), hp = q:GetUInt32(8) > 0 and q:GetUInt32(8) or nil, hpAt = q:GetUInt32(9) }
    until not q:NextRow() end
    q = CharDBQuery("SELECT team, slot, species FROM dc_battleteam WHERE guid=" .. guid)
    if q then repeat
        local t, sl = q:GetUInt32(0), q:GetUInt32(1)
        if c.teams[t] and sl >= 1 and sl <= 3 then c.teams[t][sl] = q:GetUInt32(2) end
    until not q:NextRow() end
    q = CharDBQuery("SELECT active_team FROM dc_battleplayer WHERE guid=" .. guid)
    if q then c.active = q:GetUInt32(0) end
    cache[guid] = c
    return c
end

local function SavePet(guid, sp, p)
    CharDBExecute(string.format("REPLACE INTO dc_battlepet (guid, species, level, xp, a1, a2, a3, quality, display, hp, hp_at) VALUES (%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d)",
        guid, sp, p.level, p.xp, p.a[1], p.a[2], p.a[3], p.quality or 1, p.display or 0, p.hp or 0, p.hpAt or 0))
end

-- Health: stored as the value at time hpAt (nil = full); it recovers 1% of max every 10 seconds, also while offline. Computed on demand, nothing ticks.
local function MaxHp(sp, p)
    return Eng.MaxHp(sp, math.min(p.level, D.MAX_LEVEL), p.quality or 1)
end
local function CurHp(sp, p, now)
    local max = MaxHp(sp, p)
    if not p.hp then return max end
    local ticks = math.floor(((now or os.time()) - (p.hpAt or 0)) / D.REGEN_SECONDS)
    return math.min(max, p.hp + math.max(0, ticks) * math.max(1, math.floor(max * D.REGEN_PCT / 100)))
end
function Store.PetHp(sp, p, now) return CurHp(sp, p, now), MaxHp(sp, p) end
-- after a battle: fainted pets are back with 1 HP, everyone else keeps what is left (by guid, the player may be gone)
function Store.SetHp(guid, species, hp)
    local c = Load(guid); local p = c.pets[species]
    if not p then return end
    local max = MaxHp(species, p)
    hp = math.max(1, math.floor(hp))
    if hp >= max then p.hp, p.hpAt = nil, 0 else p.hp, p.hpAt = hp, os.time() end
    SavePet(guid, species, p)
end

-- admin: every owned pet back to full health (nil hp = full)
function Store.HealAll(player)
    local guid = player:GetGUIDLow(); local c = Load(guid); local n = 0
    for species, p in pairs(c.pets) do
        p.hp, p.hpAt = nil, 0; SavePet(guid, species, p); n = n + 1
        pcall(Msg.Send, player, "pbj", "pet", Info(species, p))   -- refresh the open journal
    end
    return n
end
RegisterPlayerEvent(42, function(_, player, command)   -- .pbheal (GM only)
    if not player or not command or not command:match("^pbheal%s*$") then return end
    if player:GetGMRank() < 2 then return end
    player:SendBroadcastMessage("Healed " .. Store.HealAll(player) .. " battle pets to full health.")
    return false
end)

-- Recruiting: a duplicate species REPLACES the owned one (better versions). Returns true when stored.
function Store.AddPet(player, species, level, picks, quality, display)
    if not D.species[species] then return false end
    local g = player:GetGUIDLow(); local c = Load(g)
    c.pets[species] = { level = level or 1, xp = 0, a = { (picks and picks[1]) or 1, (picks and picks[2]) or 1, (picks and picks[3]) or 1 },
                        quality = math.max(1, math.min(4, quality or 1)), display = display or 0 }
    SavePet(g, species, c.pets[species])
    if (display or 0) > 0 and SHOP_PRIME and SHOP_PRIME.SendOne then SHOP_PRIME.SendOne(player, species, display) end   -- the journal preview shows THIS skin
    return true
end
-- CAPTURE (retail trap): the captured pet keeps its level, quality and skin. One per species: a better version (quality, then level) replaces the owned one, otherwise the capture is released.
function Store.Capture(player, pet)
    local c = Load(player:GetGUIDLow()); local owned = c.pets[pet.species]
    local q, lvl = pet.quality or 1, math.min(pet.level, D.MAX_LEVEL)
    if owned and ((owned.quality or 1) > q or ((owned.quality or 1) == q and owned.level >= lvl)) then
        return "You captured " .. pet.name .. ", but you already own a better one, so it was released."
    end
    Store.AddPet(player, pet.species, lvl, { math.random(1, 2), math.random(1, 2), math.random(1, 2) }, q, pet.display)
    Msg.Send(player, "pbj", "pet", Info(pet.species, Load(player:GetGUIDLow()).pets[pet.species]))
    return "You captured " .. pet.name .. "!" .. (owned and " It replaces the one you had." or "")
end
-- the skin of the pet you own (one per species): saved the first time it is seen so it never changes by chance
function Store.PetDisplay(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and p.display or 0 end
function Store.SetDisplay(player, species, display)
    local g = player:GetGUIDLow(); local p = Load(g).pets[species]
    if p and (p.display or 0) == 0 and display and display > 0 then
        p.display = display; SavePet(g, species, p)
        if SHOP_PRIME and SHOP_PRIME.SendOne then SHOP_PRIME.SendOne(player, species, display) end
    end
end

-- Real companion journal -> battle pets: every companion the character knows whose creature is a defined species becomes a level 1 pet
-- (never overwrites an owned one). Spell -> creature map = world.dc_companion (tools/gen_companions.py).
local COMP = {}   -- species entry -> { spells }
do
    local q = WorldDBQuery("SELECT spell, npc FROM dc_companion")
    if q then repeat
        local npc = q:GetUInt32(1)
        if D.species[npc] then COMP[npc] = COMP[npc] or {}; table.insert(COMP[npc], q:GetUInt32(0)) end
    until not q:NextRow() end
end
function Store.SyncCompanions(player)
    local g = player:GetGUIDLow(); local c = Load(g); local added = 0
    for npc, spells in pairs(COMP) do
        if not c.pets[npc] then
            for _, sp in ipairs(spells) do
                if player:HasSpell(sp) then Store.AddPet(player, npc, 1); added = added + 1; break end
            end
        end
    end
    return added
end

-- XP: reward depends on the PET's level vs the enemy level; a pet must have acted in the battle (checked by the caller)
function Store.XPReward(petLevel, enemyLevel)
    local base = Eng.XPPerWin(enemyLevel)   -- retail table: a win is worth the XpPerWin of the enemy's level
    local diff = petLevel - enemyLevel
    if diff <= 0 then return base end
    local f = 1 - diff * D.XP_STEP   -- our rule: -20% per level the enemy is BELOW the pet, nothing at 5+ below (no power leveling)
    return f > 0.001 and math.floor(base * f + 0.5) or 0
end
-- returns gained xp, new level, levels gained (nil if the pet is not owned)
function Store.GrantXP(player, species, enemyLevel)
    local g = player:GetGUIDLow(); local c = Load(g); local p = c.pets[species]
    if not p then return nil end
    if p.level >= D.MAX_LEVEL then return 0, p.level, 0 end
    local gain, start = Store.XPReward(p.level, enemyLevel), p.level
    p.xp = p.xp + gain
    while p.xp >= Eng.XPNeeded(p.level) and p.level < D.MAX_LEVEL do p.xp = p.xp - Eng.XPNeeded(p.level); p.level = p.level + 1 end
    if p.level >= D.MAX_LEVEL then p.xp = 0 end
    SavePet(g, species, p)
    Msg.Send(player, "pbj", "pet", Info(species, p))
    return gain, p.level, p.level - start
end
function Store.Pets(player) return Load(player:GetGUIDLow()).pets end   -- (tests)
function Store.OwnedQuality(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and (p.quality or 1) or 0 end
function Store.OwnedLevel(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and p.level or 0 end

-- the active team as engine input: { {species, level, picks}, ... } (empty slots dropped)
local function SaveTeam(g, n, sl)
    CharDBExecute("DELETE FROM dc_battleteam WHERE guid=" .. g .. " AND team=" .. n)
    for i = 1, 3 do if sl[i] ~= 0 then CharDBExecute(string.format("INSERT INTO dc_battleteam (guid, team, slot, species) VALUES (%d,%d,%d,%d)", g, n, i, sl[i])) end end
end
function Store.ActiveTeam(player)
    local g = player:GetGUIDLow(); local c = Load(g)
    -- no team set up yet: use (and save) the three highest level pets so a battle is never a dead end
    local have = false
    for _, sp in ipairs(c.teams[c.active] or {}) do if sp ~= 0 and c.pets[sp] then have = true end end
    if not have then
        local list = {}
        for sp, p in pairs(c.pets) do list[#list + 1] = sp end
        table.sort(list, function(a, b) if c.pets[a].level ~= c.pets[b].level then return c.pets[a].level > c.pets[b].level end return a < b end)
        if #list > 0 then
            local sl = { list[1] or 0, list[2] or 0, list[3] or 0 }
            c.teams[c.active] = sl; SaveTeam(g, c.active, sl)
            Msg.Send(player, "pbj", "team", c.active .. "," .. sl[1] .. "," .. sl[2] .. "," .. sl[3])
            Msg.Send(player, "pbt", "msg", "No team was set up: using your highest level pets. Change it in /pets > Teams.")
        end
    end
    local out = {}
    for _, sp in ipairs(c.teams[c.active] or {}) do
        local p = c.pets[sp]
        if sp ~= 0 and p then out[#out + 1] = { species = sp, level = p.level, picks = { p.a[1], p.a[2], p.a[3] }, quality = p.quality or 1, display = p.display or 0, hp = CurHp(sp, p) } end
    end
    return out
end

function Info(sp, p)
    local s = D.species[sp]
    local lvl = math.min(p.level, D.MAX_LEVEL)
    local st = Eng.Stats(sp, lvl, p.quality or 1)
    local cur, max = CurHp(sp, p), MaxHp(sp, p)
    return string.format("%d,%d,%d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%s", sp, lvl, p.xp, p.a[1], p.a[2], p.a[3], Eng.Family(sp), s.icon,
        max, math.floor(st.power + 0.5), p.quality or 1, cur, Eng.XPNeeded(lvl), s.name)
end

local function SendAll(player)
    local c = Load(player:GetGUIDLow())
    for sp, p in pairs(c.pets) do if D.species[sp] then Msg.Send(player, "pbj", "pet", Info(sp, p)) end end
    for n = 1, TEAMS do Msg.Send(player, "pbj", "team", n .. "," .. c.teams[n][1] .. "," .. c.teams[n][2] .. "," .. c.teams[n][3]) end
    Msg.Send(player, "pbj", "active", c.active)
    Msg.Send(player, "pbj", "follow", Store.Follower and Store.Follower(player) or 0)
    Msg.Send(player, "pbj", "done", "")
end

Msg.On("pbj", "list", function(player) Store.SyncCompanions(player); SendAll(player) end)
Msg.On("pbj", "abil", function(player, payload)   -- the 6 abilities of one species (2 options per slot)
    local sp = tonumber(payload); local s = sp and D.species[sp]
    if not s then return end
    for _, k in ipairs(Eng.Kit(sp)) do
        local a = k.ability
        Msg.Send(player, "pbj", "abl", sp .. "," .. k.slot .. "," .. k.opt .. "|" .. a.icon .. "#" .. a.name .. "#" .. a.tip .. "#" .. a.cd .. "#" .. k.unlock)
    end
end)
Msg.On("pbj", "setabil", function(player, payload)
    local sp, slot, opt = payload:match("^(%d+),(%d),(%d)$"); sp, slot, opt = tonumber(sp), tonumber(slot), tonumber(opt)
    local g = player:GetGUIDLow(); local c = Load(g)
    if not (sp and c.pets[sp] and slot and slot >= 1 and slot <= 3 and (opt == 1 or opt == 2)) then return end
    c.pets[sp].a[slot] = opt; SavePet(g, sp, c.pets[sp])
    Msg.Send(player, "pbj", "pet", Info(sp, c.pets[sp]))
end)
Msg.On("pbj", "setteam", function(player, payload)
    local n, a, b, d = payload:match("^(%d),(%d+),(%d+),(%d+)$"); n = tonumber(n)
    local g = player:GetGUIDLow(); local c = Load(g)
    if not (n and c.teams[n]) then return end
    local sl, seen = { tonumber(a), tonumber(b), tonumber(d) }, {}
    for i = 1, 3 do
        if sl[i] ~= 0 and (not c.pets[sl[i]] or seen[sl[i]]) then SendAll(player); return end   -- not owned / twice: resend the truth
        seen[sl[i]] = true
    end
    c.teams[n] = sl
    SaveTeam(g, n, sl)
    Msg.Send(player, "pbj", "team", n .. "," .. sl[1] .. "," .. sl[2] .. "," .. sl[3])
end)
Msg.On("pbj", "active", function(player, payload)
    local n = tonumber(payload); local g = player:GetGUIDLow(); local c = Load(g)
    if not (n and c.teams[n]) then return end
    c.active = n
    CharDBExecute(string.format("REPLACE INTO dc_battleplayer (guid, active_team) VALUES (%d,%d)", g, n))
    Msg.Send(player, "pbj", "active", n)
end)
Msg.On("pbj", "grant", function(player)   -- TEMPORARY test helper: one of each pilot species at level 10
    for sp in pairs(D.species) do Store.AddPet(player, sp, 10) end
    SendAll(player)
end)
RegisterPlayerEvent(4, function(_, player) cache[player:GetGUIDLow()] = nil end)   -- logout

-- ---------------------------------------------------------------- size normalization (shared by battle + follower): bounding radius from the DB
local TARGET_RADIUS = 0.40
local SCALE = {}
for entry, sp in pairs(D.species) do
    local q = WorldDBQuery("SELECT cmi.BoundingRadius FROM creature_template_model m JOIN creature_model_info cmi ON cmi.DisplayID=m.CreatureDisplayID WHERE m.CreatureID=" .. entry .. " AND m.Idx=0")
    local r = q and q:GetFloat(0) or 0
    SCALE[entry] = sp.scale or (r > 0.05 and math.max(0.2, math.min(1.5, TARGET_RADIUS / r)) or 0.4)
end
function Store.Scale(entry) return SCALE[entry] or 0.4 end

-- ---------------------------------------------------------------- FOLLOWER: the summoned pet that walks behind you
-- One per player. Desired only while: alive, not mounted, normal world phase (garrison = Menagerie instead), not in a battle.
-- A single 2 s tick keeps it right (respawns it after a teleport / zone change / dismount). Not saved to the world DB.
local follow = {}        -- guidLow -> { species, obj = creature guid, map = id }
local suppressed = {}    -- guidLow -> true while a battle runs
local tickEv
local FOLLOW_LEAVE = 22  -- farther than this (or other map) = respawn next to the player

-- GMs have the "all phases" mask (0xFFFFFFFF) instead of 1: that still counts as the normal world; garrison phases are single other bits
local function NormalWorld(player) local m = player:GetPhaseMask(); return m == 1 or m < 0 or m >= 0x7FFFFFFF end
Store.NormalWorld = NormalWorld

function Store.IsFollower(low) for _, f in pairs(follow) do if f.low == low then return true end end return false end   -- low = numeric low guid (GUID objects never compare equal)
function Store.SetSuppressed(player, on) suppressed[player:GetGUIDLow()] = on or nil end

local function Despawn(f)
    if f.obj then
        local map = f.map and GetMapById(f.map, 0)
        local o = map and map:GetWorldObject(f.obj)
        if o then pcall(function() o:DespawnOrUnsummon(0) end) end
    end
    f.obj, f.low, f.map = nil, nil, nil
end

-- every follower runs faster than its owner (30 % + a floor), whatever the creature template says: no pet falls behind
local function Pace(obj, pl)
    local rate = math.max(1.4, (pl:GetSpeed(1) / 7) * 1.3)
    pcall(function() obj:SetWalk(false) end)
    pcall(function() obj:SetSpeed(1, rate, true) end)
end

local function SpawnFollower(player, f)
    local x, y, z, o = player:GetX(), player:GetY(), player:GetZ(), player:GetO()
    local px, py = x - math.cos(o) * 2 + math.cos(o + 1.57) * 1, y - math.sin(o) * 2 + math.sin(o + 1.57) * 1
    local obj = PerformIngameSpawn(1, f.species, player:GetMapId(), 0, px, py, z, o, false, 0, 1)
    if not obj then return end
    f.obj, f.low, f.map = obj:GetGUID(), obj:GetGUIDLow(), player:GetMapId()     -- registered immediately, configured after
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetFaction(35) end)
    local disp = Store.PetDisplay(player, f.species)
    if disp > 0 then pcall(function() obj:SetDisplayId(disp) end)   -- the follower wears the pet's real skin
    else local okd, d = pcall(function() return obj:GetDisplayId() end); if okd and d and d > 0 then Store.SetDisplay(player, f.species, d) end end
    pcall(function() obj:SetScale(Store.Scale(f.species)) end)
    pcall(function() obj:SetPhaseMask(1, true) end)
    Pace(obj, player)
    pcall(function() obj:MoveFollow(player, 1.8, 2.6) end)
end

local function Tick()
    local any = false
    for g, f in pairs(follow) do
        any = true
        local pl = GetPlayerByGUID(f.pguid)
        if not pl then Despawn(f); follow[g] = nil
        else
            local want = pl:IsAlive() and not pl:IsMounted() and NormalWorld(pl) and not suppressed[g]
            local obj
            if f.obj then local map = GetMapById(f.map, 0); obj = map and map:GetWorldObject(f.obj) end
            if not want then Despawn(f)
            elseif not obj or pl:GetMapId() ~= f.map or pl:GetDistance(obj) > FOLLOW_LEAVE then Despawn(f); SpawnFollower(pl, f)
            else
                Pace(obj, pl)
                if pl:GetDistance(obj) > 4 then pcall(function() obj:MoveFollow(pl, 1.8, 2.6) end) end
            end
        end
    end
    if not any and tickEv then RemoveEventById(tickEv); tickEv = nil end
end

local function SendFollow(player, species) Msg.Send(player, "pbj", "follow", species or 0) end
local function SetFollower(player, species)   -- species 0 / nil = dismiss
    local g = player:GetGUIDLow()
    if follow[g] then Despawn(follow[g]); follow[g] = nil end
    if species and species ~= 0 then
        follow[g] = { species = species, pguid = player:GetGUID() }
        if not tickEv then tickEv = CreateLuaEvent(Tick, 2000, 0) end
        CreateLuaEvent(Tick, 200, 1)   -- appear right away
        CharDBExecute(string.format("REPLACE INTO dc_battlefollower (guid, species) VALUES (%d,%d)", g, species))
    else CharDBExecute("DELETE FROM dc_battlefollower WHERE guid=" .. g) end
    SendFollow(player, species)
end
function Store.Follower(player) local f = follow[player:GetGUIDLow()]; return f and f.species or 0 end

Msg.On("pbj", "summon", function(player, payload)
    local sp = tonumber(payload); local c = Load(player:GetGUIDLow())
    if sp and c.pets[sp] then SetFollower(player, sp) end
end)
Msg.On("pbj", "dismiss", function(player) SetFollower(player, 0) end)

local function Restore(player)   -- login / script load: bring the last summoned pet back
    local g = player:GetGUIDLow()
    if follow[g] then return end
    local q = CharDBQuery("SELECT species FROM dc_battlefollower WHERE guid=" .. g)
    if q and D.species[q:GetUInt32(0)] then
        local c = Load(g)
        if c.pets[q:GetUInt32(0)] then SetFollower(player, q:GetUInt32(0)) end
    end
end
RegisterPlayerEvent(3, function(_, player) Restore(player) end)
RegisterPlayerEvent(4, function(_, player)   -- logout: remove the follower
    local g = player:GetGUIDLow()
    if follow[g] then Despawn(follow[g]); follow[g] = nil end
    suppressed[g] = nil
end)
pcall(function() for _, pl in ipairs(GetPlayersInWorld()) do Restore(pl) end end)   -- script reload: pets come back


return Store
