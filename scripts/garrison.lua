-- ============================================================
-- Garrison (housing) - proof of concept at Northshire Abbey.
-- * A portal gameobject (entry 900002, spawned by custom-sql/002_garrison.sql) offers "Enter Garrison".
-- * Home = the player's own phase bit: normal world (phase 1) is hidden, only our spawns exist.
-- * Leaving the location radius, dying, logging out or changing map phases the player back to normal.
-- * Layout (one of each kind) is stored per ACCOUNT in acore_characters.dc_garrison_object and spawned (NOT saved to
--   the world DB) when the first occupant arrives, despawned when the last leaves.
-- * Bots are never inside: the portal refuses while playerbots are in your group.
-- Entry/exit mechanism is isolated in Enter()/Leave() so an instanced-map version can replace it later.
-- ============================================================
local Msg = require("acore_msg")
local Settings = require("acore_settings")
if Settings.garrison and Settings.garrison.enabled == false then return true end

local PORTAL_ENTRY = 900002
local DEBUG = Settings.garrison and Settings.garrison.debug
local function dbg(...) if DEBUG then print("[garrison:debug] " .. table.concat({ ... }, " ")) end end

-- ---- locations (center/radius can be overridden in game: .garrison center / .garrison radius N) ----
local LOCATIONS = {
    [1] = {
        id = 1, name = "Northshire Abbey", map = 0,
        cx = -8940.0, cy = -115.0, radius = 119.0,      -- rough; tune in game
        portal = { x = -9036.052, y = -55.42181, z = 89.495094, o = 6.0482984 },
    },
}
local DEFAULT_LOC = 1
local ARRIVE_DIST = 20   -- yards inside from the portal where you appear

-- ---- what can be placed: generated from garrison-config.json (tools/gen_garrison_catalog.py) ----
local CATALOG = require("garrison_catalog").items   -- { kind, t = "c"/"g", entry, name }
local BY_KIND = {}
for _, c in ipairs(CATALOG) do BY_KIND[c.kind] = c end

-- ---- prices: pay per placement, refunded when the item is removed. acore_settings.garrison.currency = "free" | "gold" | "item" (+ currencyItem) ----
-- Each catalog entry may carry price = <amount in the currency> (gold: whole gold; item: item count). What was paid is stored on the placed row (paid, pcur)
-- so the refund is exactly what was paid even if the config or the price changes later. Moving something already placed is free.
local CURRENCY = (Settings.garrison and Settings.garrison.currency) or "free"
local CURRENCY_ITEM = (Settings.garrison and Settings.garrison.currencyItem) or 0
if CURRENCY == "item" and CURRENCY_ITEM == 0 then print("[garrison] currency = item but currencyItem is 0: treating as free"); CURRENCY = "free" end
for _, t in ipairs({ "dc_garrison_object", "dc_garrison_decor" }) do   -- add the columns on first run (synchronous, before anything reads them)
    if not CharDBQuery("SHOW COLUMNS FROM " .. t .. " LIKE 'paid'") then
        CharDBQuery("ALTER TABLE " .. t .. " ADD COLUMN paid INT UNSIGNED NOT NULL DEFAULT 0, ADD COLUMN pcur VARCHAR(16) NOT NULL DEFAULT ''")
    end
end
local itemNames = {}
local function ItemName(id)
    if not itemNames[id] then
        local q = WorldDBQuery("SELECT name FROM item_template WHERE entry=" .. id)
        itemNames[id] = q and q:GetString(0) or ("item " .. id)
    end
    return itemNames[id]
end
local function Money(paid, pcur)   -- "5 gold" / "3 x Darkmoon Ticket"
    if pcur == "g" then return paid .. " gold" end
    return paid .. " x " .. ItemName(tonumber(pcur:sub(2)) or 0)
end
-- returns ok, paid, pcur, failMessage
local function Charge(player, def)
    local amount = def.price or 0
    if CURRENCY == "free" or amount <= 0 then return true, 0, "" end
    if CURRENCY == "gold" then
        if player:GetCoinage() < amount * 10000 then return false, 0, "", "You need " .. amount .. " gold to place " .. def.name .. "." end
        player:ModifyMoney(-amount * 10000); return true, amount, "g"
    end
    if player:GetItemCount(CURRENCY_ITEM) < amount then return false, 0, "", "You need " .. amount .. " x " .. ItemName(CURRENCY_ITEM) .. " to place " .. def.name .. "." end
    player:RemoveItem(CURRENCY_ITEM, amount); return true, amount, "i" .. CURRENCY_ITEM
end
local function Refund(player, row)   -- gives back what the row paid; returns a message fragment or ""
    local paid, pcur = row.paid or 0, row.pcur or ""
    if paid <= 0 or pcur == "" then return "" end
    if pcur == "g" then player:ModifyMoney(paid * 10000)
    else local id = tonumber(pcur:sub(2)); if not id then return "" end; player:AddItem(id, paid) end
    return " (refunded " .. Money(paid, pcur) .. ")"
end
-- placements saved for kinds that were retired from the catalog would respawn forever with no Remove button: purge them
do
    local ks = {}
    for _, c in ipairs(CATALOG) do ks[#ks + 1] = "'" .. c.kind .. "'" end
    CharDBExecute("DELETE FROM dc_garrison_object WHERE kind NOT IN (" .. table.concat(ks, ",") .. ")")
    CharDBExecute("DELETE FROM dc_garrison_decor WHERE kind NOT IN (" .. table.concat(ks, ",") .. ")")
    -- kinds that became multi-instance decor (e.g. gryphonroost) may still have an old single-instance row: it would respawn unmanaged
    local ms = {}
    for _, c in ipairs(CATALOG) do if c.multi then ms[#ms + 1] = "'" .. c.kind .. "'" end end
    if #ms > 0 then CharDBExecute("DELETE FROM dc_garrison_object WHERE kind IN (" .. table.concat(ms, ",") .. ")") end
end
local MAX_DECOR = (Settings.garrison and Settings.garrison.maxDecor) or 100            -- all decor in one garrison
local MAX_PER_KIND = (Settings.garrison and Settings.garrison.maxPerKind) or 10        -- of the same decor item
local nextDid = 1                                                                        -- decor ids are handed out by us (no DB round trip)
do local q = CharDBQuery("SELECT IFNULL(MAX(id),0) FROM dc_garrison_decor"); if q then nextDid = q:GetUInt32(0) + 1 end end

-- ---- phase bits: every bit not already used by stock spawns on map 0 (scanned from the world DB) ----
local USED = { [1] = true, [2] = true, [64] = true, [128] = true, [256] = true, [8192] = true, [65536] = true, [131072] = true, [262144] = true }
local FREE_BITS = {}
for i = 2, 30 do
    local b = math.floor(2 ^ i)
    if not USED[b] then FREE_BITS[#FREE_BITS + 1] = b end
end

-- ---- state (everything keyed by GUID/account; never hold Player objects across ticks) ----
local active = {}     -- ownerAccount -> { bit, loc, occ = {guidLow = ObjectGuid}, n, spawned = { {kind, t, guid, map} } }
local inside = {}     -- player guidLow -> ownerAccount
local pollId = nil
local Menagerie = {}   -- filled in below: Menagerie.Roll(h, owner, guidLow), Menagerie.Clear(h)

local function Say(player, text) player:SendBroadcastMessage("|cff66ccffGarrison:|r " .. text) end

local function Loc(id) return LOCATIONS[id] end

local function LoadOverrides()
    local q = CharDBQuery("SELECT id, cx, cy, radius FROM dc_garrison_location")
    if q then repeat
        local l = LOCATIONS[q:GetUInt32(0)]
        if l then l.cx, l.cy, l.radius = q:GetFloat(1), q:GetFloat(2), q:GetFloat(3) end
    until not q:NextRow() end
end
LoadOverrides()

-- ---- spawn registry: every temporary spawn is recorded in dc_garrison_spawn so a script reload / crash can never leave orphans behind ----
local function Reg(obj, t, map)
    CharDBExecute(string.format("REPLACE INTO dc_garrison_spawn (low, t, entry, map) VALUES (%d,'%s',%d,%d)", obj:GetGUIDLow(), t, obj:GetEntry(), map))
end
local function Unreg(t, low) CharDBExecute(string.format("DELETE FROM dc_garrison_spawn WHERE low=%d AND t='%s'", low, t)) end
local function CleanOrphans(tracked)   -- tracked = set of "<t><low>" still owned by a live garrison (audit mode); nil = clean everything (script load)
    local q = CharDBQuery("SELECT low, t, entry, map FROM dc_garrison_spawn")
    local cleaned = 0
    if q then repeat
        local low, t, entry, mapId = q:GetUInt32(0), q:GetString(1), q:GetUInt32(2), q:GetUInt32(3)
        if not (tracked and tracked[t .. low]) then
            cleaned = cleaned + 1
            local map = GetMapById(mapId, 0)
            local obj = map and map:GetWorldObject(t == "g" and GetObjectGUID(low, entry) or GetUnitGUID(low, entry))
            if obj then if t == "g" then obj:RemoveFromWorld(false) else obj:DespawnOrUnsummon(0) end end
            if tracked then Unreg(t, low) end
        end
    until not q:NextRow() end
    if not tracked then CharDBExecute("DELETE FROM dc_garrison_spawn") end
    return cleaned
end
CleanOrphans()   -- first thing on every (re)load


-- ---- layout storage ----
local function LoadLayout(account, locId)
    local rows = {}
    local q = CharDBQuery(string.format("SELECT kind, x, y, z, o, paid, pcur FROM dc_garrison_object WHERE account=%d AND location=%d", account, locId))
    if q then repeat
        rows[#rows + 1] = { kind = q:GetString(0), x = q:GetFloat(1), y = q:GetFloat(2), z = q:GetFloat(3), o = q:GetFloat(4), paid = q:GetUInt32(5), pcur = q:GetString(6) }
    until not q:NextRow() end
    return rows
end

local function LoadDecor(account, locId)
    local rows = {}
    local q = CharDBQuery(string.format("SELECT id, kind, x, y, z, o, paid, pcur FROM dc_garrison_decor WHERE account=%d AND location=%d", account, locId))
    if q then repeat
        rows[#rows + 1] = { did = q:GetUInt32(0), kind = q:GetString(1), x = q:GetFloat(2), y = q:GetFloat(3), z = q:GetFloat(4), o = q:GetFloat(5), paid = q:GetUInt32(6), pcur = q:GetString(7) }
    until not q:NextRow() end
    return rows
end

-- ---- spawning ----
local function SpawnOne(h, row)
    local def = BY_KIND[row.kind]
    if not def then return end
    local loc = Loc(h.loc)
    local obj = PerformIngameSpawn(def.t == "g" and 2 or 1, def.entry, loc.map, 0, row.x, row.y, row.z, row.o, false, 0, h.bit)
    if not obj then return end
    -- record it first: whatever happens next, it can always be found and removed again
    h.spawned[#h.spawned + 1] = { kind = row.kind, did = row.did, t = def.t, guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map }
    Reg(obj, def.t, loc.map)
    if row.did then h.decor[row.did] = row else h.rows[row.kind] = row end
    obj:SetPhaseMask(h.bit, true)   -- non-saved creature spawns ignore the phase argument
end

local function DespawnKind(h, kind, did)   -- kind = one single kind, did = one decor instance, neither = everything
    for i = #h.spawned, 1, -1 do
        local s = h.spawned[i]
        if (not kind and not did) or (kind and not s.did and s.kind == kind) or (did and s.did == did) then
            local map = GetMapById(s.map, 0)
            local obj = map and map:GetWorldObject(s.guid)
            if obj then
                if s.t == "g" then obj:RemoveFromWorld(false) else obj:DespawnOrUnsummon(0) end
            end
            Unreg(s.t, s.low)
            table.remove(h.spawned, i)
        end
    end
end

-- ---- enter / leave (the only phasing-specific code) ----
local function AllocBit()
    local taken = {}
    for _, h in pairs(active) do taken[h.bit] = true end
    for _, b in ipairs(FREE_BITS) do if not taken[b] then return b end end
end

local function StartPoll() end   -- forward decl
local GhostStop = function() end   -- forward decl: placement-mode ghost (defined with the decor code)

local function Enter(player, owner, locId)
    local g = player:GetGUIDLow()
    local h = active[owner]
    if not h then
        local bit = AllocBit()
        if not bit then Say(player, "All garrisons are busy right now, try again in a moment."); return end
        h = { bit = bit, loc = locId, occ = {}, n = 0, spawned = {}, pets = {}, rows = {}, decor = {} }
        active[owner] = h
        for _, row in ipairs(LoadLayout(owner, locId)) do SpawnOne(h, row) end
        for _, row in ipairs(LoadDecor(owner, locId)) do SpawnOne(h, row) end
    end
    h.occ[g] = player:GetGUID(); h.n = h.n + 1
    inside[g] = owner
    if player:GetAccountId() == owner then Menagerie.Roll(h, owner, g) end   -- the owner phases in: fresh set of pets
    player:SetPhaseMask(h.bit, true)
    -- arrive ARRIVE_DIST yards inside so the poll does not immediately push us back out (and not inside a wall)
    local loc, p = Loc(locId), Loc(locId).portal
    local dx, dy = loc.cx - p.x, loc.cy - p.y
    local d = math.sqrt(dx * dx + dy * dy)
    local ex, ey = p.x + dx / d * ARRIVE_DIST, p.y + dy / d * ARRIVE_DIST
    player:Teleport(loc.map, ex, ey, p.z + 1, p.o)
    Menagerie.Verify(h, player)   -- compare the real world with our records (see "entry check" below)
    Msg.Send(player, "jukebox", "garrison", "1")
    if h.track then Msg.Send(player, "jukebox", "play", h.track) end   -- the garrison jukebox is already playing
    StartPoll()
end

local function Leave(guidLow, player)
    local owner = inside[guidLow]
    if not owner then return end
    dbg("leave", "guid=" .. guidLow, debug.traceback("", 2):gsub("\n", " "):sub(1, 160))
    inside[guidLow] = nil
    GhostStop(guidLow, player, "You left your garrison.")
    local h = active[owner]
    if player then
        player:SetPhaseMask(1, true)
        Msg.Send(player, "jukebox", "garrison", "0")
    end
    if h then
        if h.occ[guidLow] then h.occ[guidLow] = nil; h.n = h.n - 1 end
        if h.controller == guidLow then
            h.controller, h.track = nil, nil
            for _, guid in pairs(h.occ) do local p = GetPlayerByGUID(guid); if p then Msg.Send(p, "jukebox", "stop", "") end end
        end
        if h.n <= 0 then Menagerie.Clear(h); DespawnKind(h); active[owner] = nil end
    end
end

local function Poll()
    local any = false
    for g, owner in pairs(inside) do
        any = true
        local h = active[owner]
        local player = h and h.occ[g] and GetPlayerByGUID(h.occ[g])
        if not player then
            Leave(g, nil)
        else
            local loc = Loc(h.loc)
            local dx, dy = player:GetX() - loc.cx, player:GetY() - loc.cy
            if not player:IsAlive() or player:GetMapId() ~= loc.map or (dx * dx + dy * dy) > loc.radius * loc.radius then
                Leave(g, player)
            elseif player:GetPhaseMask() ~= h.bit and not player:IsGM() then
                Leave(g, player)                   -- phase got reset (e.g. .gm off): treat it as having left the garrison
                Say(player, "You have left your garrison.")
            end
        end
    end
    if not any and pollId then RemoveEventById(pollId); pollId = nil end
end
StartPoll = function()
    if not pollId then pollId = CreateLuaEvent(function() Poll() end, 1000, 0) end
end

-- ---- group helpers ----
local function GroupHasBots(player)
    local grp = player:GetGroup()
    if not grp then return false end
    for _, m in pairs(grp:GetMembers()) do if m and m:IsBot() then return true end end
    return false
end

-- ---- portal gossip ----
local INT_HOME, INT_VISIT = 1, 1000
local function OnHello(event, player, go)
    dbg("hello", player:GetName(), "inside=" .. tostring(inside[player:GetGUIDLow()]))
    local owner = player:GetAccountId()
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "Enter Garrison", 0, INT_HOME, false)
    local grp = player:GetGroup()
    if grp then
        for _, m in pairs(grp:GetMembers()) do
            if m and not m:IsBot() and m:GetGUIDLow() ~= player:GetGUIDLow() then
                local o = inside[m:GetGUIDLow()]
                if o and o ~= owner then player:GossipMenuAddItem(0, "Visit " .. m:GetName() .. "'s garrison", 0, INT_VISIT + o, false) end
            end
        end
    end
    player:GossipSendMenu(1, go)
    return true
end

local function OnSelect(event, player, go, sender, intid)
    dbg("select", player:GetName(), "intid=" .. tostring(intid), "inside=" .. tostring(inside[player:GetGUIDLow()]), "alive=" .. tostring(player:IsAlive()), "combat=" .. tostring(player:IsInCombat()), "bots=" .. tostring(GroupHasBots(player)))
    player:GossipComplete()
    if inside[player:GetGUIDLow()] then Say(player, "You are already in a garrison."); return true end
    if not player:IsAlive() or player:IsInCombat() then Say(player, "You can't do that right now."); return true end
    if GroupHasBots(player) then
        Say(player, "Dismiss your companions and playerbots first (Bot Manager: Remove All Companions). Bots can't enter a garrison.")
        return true
    end
    if intid == INT_HOME then dbg("enter"); Enter(player, player:GetAccountId(), DEFAULT_LOC); dbg("entered", "inside=" .. tostring(inside[player:GetGUIDLow()]))
    elseif intid > INT_VISIT then
        local o = intid - INT_VISIT
        if active[o] then Enter(player, o, DEFAULT_LOC) else Say(player, "That garrison is no longer open.") end
    end
    return true
end
RegisterGameObjectGossipEvent(PORTAL_ENTRY, 1, OnHello)
RegisterGameObjectGossipEvent(PORTAL_ENTRY, 2, OnSelect)

-- ---- cleanup hooks ----
RegisterPlayerEvent(4, function(event, player)   -- logout: remember it so the next login puts you at the portal, not in the middle of the valley
    local g = player:GetGUIDLow()
    if inside[g] then CharDBExecute("REPLACE INTO dc_garrison_logout (guid) VALUES (" .. g .. ")") end
    Leave(g, player)
end)
RegisterPlayerEvent(3, function(event, player)   -- login (phase always starts at 1)
    local g = player:GetGUIDLow()
    local q = CharDBQuery("SELECT guid FROM dc_garrison_logout WHERE guid=" .. g)
    if not q then return end
    CharDBExecute("DELETE FROM dc_garrison_logout WHERE guid=" .. g)
    local guid = player:GetGUID()
    CreateLuaEvent(function()
        local p = GetPlayerByGUID(guid)
        if p then
            local pt = Loc(DEFAULT_LOC).portal
            p:Teleport(Loc(DEFAULT_LOC).map, pt.x, pt.y, pt.z + 1, pt.o)
            Say(p, "You logged out inside your garrison; welcome back to the portal.")
        end
    end, 2000, 1)
end)
RegisterPlayerEvent(28, function(event, player)                                          -- map change
    local g = player:GetGUIDLow()
    local owner = inside[g]
    if owner and active[owner] and player:GetMapId() ~= Loc(active[owner].loc).map then Leave(g, player) end
end)

-- ---- placement (client addon wotlk_garrison) ----
local function MyHouse(player)
    local g = player:GetGUIDLow()
    local owner = inside[g]
    if owner and owner == player:GetAccountId() and active[owner] then return active[owner], owner end
end

Msg.On("house", "list", function(player)
    -- the client has the static catalog; we only tell it whether you are home and which kinds are placed (chunked: ~240 char limit)
    local h = MyHouse(player)
    Msg.Send(player, "house", "head", h and "1" or "0")
    Msg.Send(player, "house", "cur", CURRENCY .. "," .. CURRENCY_ITEM)
    if not h then return end
    local chunk = ""
    local dchunk = ""
    for _, sp in ipairs(h.spawned) do
        if sp.did then
            local item = sp.did .. ":" .. sp.kind
            if #dchunk + #item + 1 > 200 then Msg.Send(player, "house", "dplaced", dchunk); dchunk = "" end
            dchunk = dchunk .. (dchunk == "" and "" or ",") .. item
        else
            if #chunk + #sp.kind + 1 > 200 then Msg.Send(player, "house", "placed", chunk); chunk = "" end
            chunk = chunk .. (chunk == "" and "" or ",") .. sp.kind
        end
    end
    if chunk ~= "" then Msg.Send(player, "house", "placed", chunk) end
    if dchunk ~= "" then Msg.Send(player, "house", "dplaced", dchunk) end
end)

Msg.On("house", "place", function(player, kind)
    local h, owner = MyHouse(player)
    if not h then return Msg.Send(player, "house", "res", "You must be inside your own garrison to place things.") end
    local def = BY_KIND[kind]
    if not def then return Msg.Send(player, "house", "res", "Unknown item.") end
    if def.multi then return Msg.Send(player, "house", "res", "Use 'Place new' for decor.") end
    local row = { kind = kind, x = player:GetX(), y = player:GetY(), z = player:GetZ(), o = player:GetO(), paid = 0, pcur = "" }
    local old = h.rows[kind]
    if old then row.paid, row.pcur = old.paid or 0, old.pcur or ""    -- placing again = moving: free, keeps what was paid
    else
        local ok, paid, pcur, why = Charge(player, def)
        if not ok then return Msg.Send(player, "house", "res", why) end
        row.paid, row.pcur = paid, pcur
    end
    DespawnKind(h, kind)    -- one of each kind: placing again moves it
    CharDBExecute(string.format("REPLACE INTO dc_garrison_object (account, location, kind, x, y, z, o, paid, pcur) VALUES (%d,%d,'%s',%f,%f,%f,%f,%d,'%s')",
        owner, h.loc, kind, row.x, row.y, row.z, row.o, row.paid, row.pcur))
    SpawnOne(h, row)
    if kind == "menagerie" then Menagerie.Roll(h, owner, player:GetGUIDLow()) end
    Msg.Send(player, "house", "res", (old and "Moved: " or "Placed: ") .. def.name .. (row.paid > 0 and not old and (" (paid " .. Money(row.paid, row.pcur) .. ")") or ""))
end)

Msg.On("house", "remove", function(player, kind)
    local h, owner = MyHouse(player)
    if not h or not BY_KIND[kind] then return end
    local old = h.rows[kind]
    DespawnKind(h, kind)
    if kind == "menagerie" then Menagerie.Clear(h); h.rows["menagerie"] = nil end
    CharDBExecute(string.format("DELETE FROM dc_garrison_object WHERE account=%d AND location=%d AND kind='%s'", owner, h.loc, kind))
    Msg.Send(player, "house", "res", "Removed: " .. BY_KIND[kind].name .. (old and Refund(player, old) or ""))
end)



-- ---- decor: many instances, each can be nudged / rotated / removed later (only inside YOUR garrison) ----
local function CountDecor(h, kind)
    local total, ofKind = 0, 0
    for did, r in pairs(h.decor) do total = total + 1; if r.kind == kind then ofKind = ofKind + 1 end end
    return total, ofKind
end
local function GroundZ(loc, x, y, z)   -- snap to terrain unless that would jump onto a roof / under a floor (>3 yards away)
    local map = GetMapById(loc.map, 0)
    local gz = map and map:GetHeight(x, y, 1)
    if gz and math.abs(gz - z) <= 3 then return gz end
    return z
end
local function InsideRadius(loc, x, y)
    local dx, dy = x - loc.cx, y - loc.cy
    return dx * dx + dy * dy <= loc.radius * loc.radius
end

-- shared by "dplace" (instant, 3 yards ahead) and placement mode ("pconfirm"): limits, price, row, spawn. Returns true when placed.
local function PlaceDecorAt(player, h, owner, kind, def, x, y, z, o)
    local total, ofKind = CountDecor(h, kind)
    if total >= MAX_DECOR then Msg.Send(player, "house", "res", "Garrison decor limit reached (" .. MAX_DECOR .. ")."); return false end
    if ofKind >= MAX_PER_KIND then Msg.Send(player, "house", "res", "You already have " .. MAX_PER_KIND .. " of those."); return false end
    local ok, paid, pcur, why = Charge(player, def)
    if not ok then Msg.Send(player, "house", "res", why); return false end
    local row = { did = nextDid, kind = kind, x = x, y = y, z = z, o = o, paid = paid, pcur = pcur }
    nextDid = nextDid + 1
    CharDBExecute(string.format("INSERT INTO dc_garrison_decor (id, account, location, kind, x, y, z, o, paid, pcur) VALUES (%d,%d,%d,'%s',%f,%f,%f,%f,%d,'%s')",
        row.did, owner, h.loc, kind, row.x, row.y, row.z, row.o, paid, pcur))
    SpawnOne(h, row)
    Msg.Send(player, "house", "dnew", tostring(row.did))
    Msg.Send(player, "house", "res", "Placed: " .. def.name .. " (" .. (total + 1) .. "/" .. MAX_DECOR .. ")" .. (paid > 0 and (" - paid " .. Money(paid, pcur)) or ""))
    return true
end

Msg.On("house", "dplace", function(player, kind)
    local h, owner = MyHouse(player)
    if not h then return Msg.Send(player, "house", "res", "You must be inside your own garrison to place things.") end
    local def = BY_KIND[kind]
    if not def or not def.multi then return Msg.Send(player, "house", "res", "Unknown decor item.") end
    local loc, o = Loc(h.loc), player:GetO()
    local x, y = player:GetX() + math.cos(o) * 3, player:GetY() + math.sin(o) * 3
    if not InsideRadius(loc, x, y) then x, y = player:GetX(), player:GetY() end
    PlaceDecorAt(player, h, owner, kind, def, x, y, GroundZ(loc, x, y, player:GetZ()), (o + math.pi) % (2 * math.pi))
end)

-- ---- placement mode: a solid, NON-saved "ghost" of the item floats DIST yards in front of you (re-created 4x a second only when it moved).
-- Enter/Place = pconfirm puts the real item exactly there (price charged THEN); Esc/Cancel = pcancel. The ghost is not in dc_garrison_spawn and
-- is never saved, so a crash/restart removes it. It always ends when you leave the garrison, log out, change map or after GHOST_SECONDS.
local GHOST_SECONDS, GHOST_MS = 300, 250
local STILL_TICKS = 4   -- 4 x 250 ms without movement before the preview appears
local ghosts, ghostEv = {}, nil   -- ghosts[playerGuidLow] = { kind, pguid, dist, rot, guid, map, x, y, z, o, ok, t0, beat }
local function GhostKill(g)   -- look the object up again by GUID (a held pointer goes stale); never errors
    if not g.guid then return end
    local guid, map = g.guid, g.map and GetMapById(g.map, 0)
    g.guid = nil
    local obj = map and map:GetWorldObject(guid)
    if obj then obj:RemoveFromWorld(false) end
end
local GhostTick
GhostStop = function(low, player, msg)
    local g = ghosts[low]; if not g then return end
    ghosts[low] = nil
    pcall(GhostKill, g)
    if player and msg then Msg.Send(player, "house", "pend", msg) end
    if next(ghosts) == nil and ghostEv then RemoveEventById(ghostEv); ghostEv = nil end
end
local function GhostUpdate(low, g)
    local p = GetPlayerByGUID(g.pguid)
    local h = p and MyHouse(p)
    if not h or p:GetMapId() ~= Loc(h.loc).map then return GhostStop(low, p, "Placement ended.") end
    if os.time() - g.t0 > GHOST_SECONDS then return GhostStop(low, p, "Placement timed out.") end
    local loc, o = Loc(h.loc), p:GetO()
    local x, y = p:GetX() + math.cos(o) * g.dist, p:GetY() + math.sin(o) * g.dist
    local z, go = GroundZ(loc, x, y, p:GetZ()), (o + math.pi + g.rot) % (2 * math.pi)
    local ok = InsideRadius(loc, x, y)
    if ok ~= g.ok then g.ok = ok; Msg.Send(p, "house", "pok", ok and "1" or "0") end
    g.beat = (g.beat or 0) + 1
    if g.beat % 4 == 0 then Msg.Send(p, "house", "pbeat", "1") end   -- lets the client end its mode if the server stops answering
    -- Player movement reaches the server in bursts (~every 0.5 s), so one unchanged tick does not mean "standing still".
    -- Moving or turning resets the counter and removes the ghost; a new one is only made after STILL_TICKS quiet ticks in a row.
    local px, py, po = p:GetX(), p:GetY(), p:GetO()
    if g.px and (math.abs(px - g.px) > 0.02 or math.abs(py - g.py) > 0.02 or math.abs(po - g.po) > 0.01) then g.still = 0
    else g.still = (g.still or 0) + 1 end
    g.px, g.py, g.po = px, py, po
    if g.still < STILL_TICKS then GhostKill(g); return end
    local moved = not g.guid or math.abs(x - g.x) > 0.15 or math.abs(y - g.y) > 0.15 or math.abs(z - g.z) > 0.15 or math.abs(go - g.o) > 0.03
    if not moved then return end
    GhostKill(g)
    g.x, g.y, g.z, g.o = x, y, z, go
    local obj = PerformIngameSpawn(2, BY_KIND[g.kind].entry, loc.map, 0, x, y, z, go, false, 0, h.bit)
    if obj then obj:SetPhaseMask(h.bit, true); g.guid, g.map = obj:GetGUID(), loc.map end
end
GhostTick = function()
    for low, g in pairs(ghosts) do
        if not pcall(GhostUpdate, low, g) then
            print("[garrison] placement ghost error, ending it")
            GhostStop(low, GetPlayerByGUID(g.pguid), "Placement ended (error).")
        end
    end
end

Msg.On("house", "pstart", function(player, kind)
    local h, owner = MyHouse(player)
    local low = player:GetGUIDLow()
    if not h then return Msg.Send(player, "house", "res", "You must be inside your own garrison to place things.") end
    local def = BY_KIND[kind]
    if not def or not def.multi then return Msg.Send(player, "house", "res", "Unknown decor item.") end
    local total, ofKind = CountDecor(h, kind)
    if total >= MAX_DECOR then return Msg.Send(player, "house", "res", "Garrison decor limit reached (" .. MAX_DECOR .. ").") end
    if ofKind >= MAX_PER_KIND then return Msg.Send(player, "house", "res", "You already have " .. MAX_PER_KIND .. " of those.") end
    GhostStop(low)   -- replaces a running one
    ghosts[low] = { kind = kind, pguid = player:GetGUID(), dist = 6, rot = 0, t0 = os.time(), x = 0, y = 0, z = 0, o = 0 }
    if not ghostEv then ghostEv = CreateLuaEvent(GhostTick, GHOST_MS, 0) end
    Msg.Send(player, "house", "pstart", kind)
end)
Msg.On("house", "pcancel", function(player) GhostStop(player:GetGUIDLow(), player, "Placement cancelled.") end)
Msg.On("house", "pdist", function(player, amount)   -- relative change in yards, clamped 2..15
    local g = ghosts[player:GetGUIDLow()]; local n = tonumber(amount)
    if g and n then g.dist = math.max(2, math.min(15, g.dist + math.max(-5, math.min(5, n)))) end
end)
Msg.On("house", "prot", function(player, amount)   -- relative turn in degrees
    local g = ghosts[player:GetGUIDLow()]; local n = tonumber(amount)
    if g and n then g.rot = (g.rot + math.rad(math.max(-180, math.min(180, n)))) % (2 * math.pi) end
end)
Msg.On("house", "pconfirm", function(player)
    local low = player:GetGUIDLow()
    local g, h, owner = ghosts[low], MyHouse(player)
    if not g then return end
    if not h then return GhostStop(low, player, "Placement ended.") end
    if not g.guid then return Msg.Send(player, "house", "res", "Wait a moment, the preview is still appearing.") end
    if not g.ok then return Msg.Send(player, "house", "res", "That spot is outside your garrison.") end
    if PlaceDecorAt(player, h, owner, g.kind, BY_KIND[g.kind], g.x, g.y, g.z, g.o) then GhostStop(low, player, "")
    end   -- not placed (cannot afford, limit): the ghost stays so you can cancel or fix it
end)
RegisterPlayerEvent(4, function(event, player) GhostStop(player:GetGUIDLow()) end)    -- logout
RegisterPlayerEvent(28, function(event, player) GhostStop(player:GetGUIDLow()) end)   -- map change

-- payload "<id>,<action>,<amount>": f/b/l/r move relative to the way YOU face, u/d height, rl/rr rotate (degrees), me = move to your spot
Msg.On("house", "dmove", function(player, payload)
    local h, owner = MyHouse(player)
    if not h then return end
    local id, act, amt = payload:match("^([%w_]+),(%a+),([%d%.]+)$")
    local did = id and id:match("^%d+$") and tonumber(id)          -- digits = decor instance, anything else = a single-instance kind
    local row = id and (did and h.decor[did] or (not did and BY_KIND[id] and h.rows[id]))
    if not row then return Msg.Send(player, "house", "res", "That item is gone.") end
    amt = math.max(0.05, math.min(tonumber(amt) or 1, (act == "rl" or act == "rr") and 180 or 30))
    local o, x, y, z, ro = player:GetO(), row.x, row.y, row.z, row.o
    if act == "f" then x, y = x + math.cos(o) * amt, y + math.sin(o) * amt
    elseif act == "b" then x, y = x - math.cos(o) * amt, y - math.sin(o) * amt
    elseif act == "l" then x, y = x + math.cos(o + math.pi / 2) * amt, y + math.sin(o + math.pi / 2) * amt
    elseif act == "r" then x, y = x + math.cos(o - math.pi / 2) * amt, y + math.sin(o - math.pi / 2) * amt
    elseif act == "u" then z = z + amt
    elseif act == "d" then z = z - amt
    elseif act == "rl" then ro = (ro + math.rad(amt)) % (2 * math.pi)
    elseif act == "rr" then ro = (ro - math.rad(amt)) % (2 * math.pi)
    elseif act == "me" then x, y, z = player:GetX(), player:GetY(), player:GetZ()
    elseif act == "snap" then z = GroundZ(Loc(h.loc), x, y, z)
    else return end
    if not InsideRadius(Loc(h.loc), x, y) then return Msg.Send(player, "house", "res", "That is outside the garrison.") end
    row.x, row.y, row.z, row.o = x, y, z, ro
    if did then
        CharDBExecute(string.format("UPDATE dc_garrison_decor SET x=%f, y=%f, z=%f, o=%f WHERE id=%d AND account=%d", x, y, z, ro, did, owner))
        DespawnKind(h, nil, did)
    else
        CharDBExecute(string.format("UPDATE dc_garrison_object SET x=%f, y=%f, z=%f, o=%f WHERE account=%d AND location=%d AND kind='%s'",
            x, y, z, ro, owner, h.loc, id))
        DespawnKind(h, id)
    end
    SpawnOne(h, row)
    if id == "menagerie" then Menagerie.Roll(h, owner, player:GetGUIDLow()) end
end)

Msg.On("house", "dremove", function(player, did)
    local h, owner = MyHouse(player)
    did = tonumber(did)
    local row = h and did and h.decor[did]
    if not row then return end
    DespawnKind(h, nil, did)
    h.decor[did] = nil
    CharDBExecute(string.format("DELETE FROM dc_garrison_decor WHERE id=%d AND account=%d", did, owner))
    Msg.Send(player, "house", "res", "Removed: " .. BY_KIND[row.kind].name .. Refund(player, row))
end)

Msg.On("house", "dclear", function(player)
    local h, owner = MyHouse(player)
    if not h then return end
    local n, back = 0, {}
    for did, r in pairs(h.decor) do
        DespawnKind(h, nil, did); n = n + 1
        if (r.paid or 0) > 0 then back[r.pcur] = (back[r.pcur] or 0) + r.paid end
    end
    -- sweep: any decor object still tracked (e.g. its row was lost or its kind is no longer in the catalog)
    local left = {}
    for _, s in ipairs(h.spawned) do if s.did then left[#left + 1] = s.did end end
    for _, did in ipairs(left) do DespawnKind(h, nil, did) end
    h.decor = {}
    local refunded = ""
    for pcur, paid in pairs(back) do refunded = refunded .. Refund(player, { paid = paid, pcur = pcur }) end
    CharDBExecute(string.format("DELETE FROM dc_garrison_decor WHERE account=%d AND location=%d", owner, h.loc))
    Msg.Send(player, "house", "res", "Removed all decor (" .. n .. ")." .. refunded)
end)

-- ---- Menagerie (NPC 900003 "Breanni - Menagerie") ----
-- Needs the Menagerie placed. Up to MAX_PETS of the OWNER-account character's learned companions are spawned (temporary, never saved)
-- and wander around the Menagerie; re-rolled every time the owner phases in. The owner can send them "home" (none spawned) via the NPC.
math.randomseed(os.time())
local MAX_PETS = (Settings.garrison and Settings.garrison.maxPets) or 5     -- pets out at once (owner setting garrison.maxPets)
local PET_SPREAD, PET_WANDER = 7, 40
local COMPANIONS = {}   -- companion spell -> creature entry (world.dc_companion, generated by tools/gen_companions.py)
do
    local q = WorldDBQuery("SELECT spell, npc FROM dc_companion")
    if q then repeat COMPANIONS[q:GetUInt32(0)] = q:GetUInt32(1) until not q:NextRow() end
end

local function RoamEnabled(owner, locId)
    local q = CharDBQuery(string.format("SELECT roam FROM dc_garrison_setting WHERE account=%d AND location=%d", owner, locId))
    return not q or q:GetUInt32(0) ~= 0     -- default: pets explore
end
local function SetRoam(owner, locId, on)
    CharDBExecute(string.format("REPLACE INTO dc_garrison_setting (account, location, roam) VALUES (%d,%d,%d)", owner, locId, on and 1 or 0))
end

local function KnownPets(guidLow)
    local seen, list = {}, {}
    local q = CharDBQuery("SELECT spell FROM character_spell WHERE guid=" .. guidLow)
    if q then repeat
        local npc = COMPANIONS[q:GetUInt32(0)]
        if npc and not seen[npc] then seen[npc] = true; list[#list + 1] = npc end
    until not q:NextRow() end
    return list
end

local function DespawnPets(h)
    for i = #h.pets, 1, -1 do
        local pet = h.pets[i]
        local map = GetMapById(pet.map, 0)
        local obj = map and map:GetWorldObject(pet.guid)
        if obj then obj:DespawnOrUnsummon(0) end
        Unreg("c", pet.low)
        h.pets[i] = nil
    end
end

local function RollPets(h, owner, guidLow, forceOn)
    DespawnPets(h)
    local row = h.rows and h.rows["menagerie"]
    if not row or not (forceOn or RoamEnabled(owner, h.loc)) then return end   -- forceOn: the setting write is still queued, so do not re-read it
    local pool = KnownPets(guidLow)
    for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
    local loc = Loc(h.loc)
    for i = 1, math.min(MAX_PETS, #pool) do
        local ang, dist = math.random() * 6.2832, 1.5 + math.random() * PET_SPREAD
        local obj = PerformIngameSpawn(1, pool[i], loc.map, 0, row.x + math.cos(ang) * dist, row.y + math.sin(ang) * dist, row.z + 0.3, math.random() * 6.2832, false, 0, h.bit)
        if obj then
            h.pets[#h.pets + 1] = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map }   -- track first, configure after
            Reg(obj, "c", loc.map)
            obj:SetPhaseMask(h.bit, true)
            obj:SetReactState(0)             -- passive
            obj:MoveRandom(PET_WANDER)
        end
    end
end


-- ---- entry check: what the world REALLY holds in this garrison's phase vs what we track ----
-- 1) tracked but gone  -> placed NPCs/objects are respawned, pets are dropped from the list
-- 2) in the world, in this phase, one of OUR entries, but not tracked -> stray: removed
-- (only our own entries with no owner are ever touched, so a player's own companion pet, totem or ritual is safe)
local OURS_C, OURS_G = {}, {}
for _, c in ipairs(CATALOG) do if c.t == "g" then OURS_G[c.entry] = true else OURS_C[c.entry] = true end end
for _, npc in pairs(COMPANIONS) do OURS_C[npc] = true end

local function Verify(h, player)
    local loc = Loc(h.loc)
    local map = GetMapById(loc.map, 0)
    local fixed, removed = 0, 0
    for i = #h.spawned, 1, -1 do
        local sp = h.spawned[i]
        if not (map and map:GetWorldObject(sp.guid)) then
            local row = sp.did and h.decor[sp.did] or (not sp.did and h.rows[sp.kind])
            Unreg(sp.t, sp.low); table.remove(h.spawned, i)
            if row then SpawnOne(h, row); fixed = fixed + 1 end
        end
    end
    for i = #h.pets, 1, -1 do
        local pt = h.pets[i]
        if not (map and map:GetWorldObject(pt.guid)) then Unreg("c", pt.low); table.remove(h.pets, i) end
    end
    local tracked = {}
    for _, sp in ipairs(h.spawned) do tracked[sp.t .. sp.low] = true end
    for _, pt in ipairs(h.pets) do tracked["c" .. pt.low] = true end
    local range = loc.radius * 2 + 20
    for _, c in pairs(player:GetCreaturesInRange(range, 0, 0, 0) or {}) do
        if c:GetPhaseMask() == h.bit and OURS_C[c:GetEntry()] and not c:GetOwner() and not tracked["c" .. c:GetGUIDLow()] then
            c:DespawnOrUnsummon(0); removed = removed + 1
        end
    end
    for _, o in pairs(player:GetGameObjectsInRange(range, 0, 0) or {}) do
        if o:GetPhaseMask() == h.bit and OURS_G[o:GetEntry()] and not tracked["g" .. o:GetGUIDLow()] then
            o:RemoveFromWorld(false); removed = removed + 1
        end
    end
    if fixed > 0 or removed > 0 then print(string.format("[garrison] entry check: respawned %d missing, removed %d stray", fixed, removed)) end
end
Menagerie.Verify = Verify

Menagerie.Roll, Menagerie.Clear = RollPets, DespawnPets
-- ---- pick marker: while you have an item selected on the addon's Placed tab, a Hunter's-Mark arrow floats above it ----
-- an invisible stalker is spawned above the object and given the Hunter's Mark aura; it is tracked in h.pets (same leak-proof registry) and
-- despawns by itself after MARK_SECONDS. Settings: acore_settings.garrison.markerNpc / markerSpell / markerSeconds.
local MARK_NPC = (Settings.garrison and Settings.garrison.markerNpc) or 900010     -- custom-sql/007: "Garrison Marker" (a Wisp copy; invisible stalkers show no aura to normal players)
local MARK_SPELL = (Settings.garrison and Settings.garrison.markerSpell) or 1130    -- Hunter's Mark
local MARK_SECONDS = (Settings.garrison and Settings.garrison.markerSeconds) or 30
local function ClearMarker(h)
    for i = #h.pets, 1, -1 do
        local pt = h.pets[i]
        if pt.marker then
            local map = GetMapById(pt.map, 0)
            local obj = map and map:GetWorldObject(pt.guid)
            if obj then obj:DespawnOrUnsummon(0) end
            Unreg("c", pt.low); table.remove(h.pets, i)
        end
    end
end
-- payload "<id or kind>,<height>": height = how far above the object's origin its top is (the addon knows the model size)
Msg.On("house", "mark", function(player, payload)
    local h = MyHouse(player)
    if not h then return end
    local id, top = payload:match("^([%w_]+),([%d%.]+)$")
    local did = id and id:match("^%d+$") and tonumber(id)
    local row = id and (did and h.decor[did] or (not did and h.rows[id]))
    ClearMarker(h)
    if not row then return end
    top = math.max(0, math.min(tonumber(top) or 2, 40))
    local loc = Loc(h.loc)
    local obj = PerformIngameSpawn(1, MARK_NPC, loc.map, 0, row.x, row.y, row.z + top + 0.5, 0, false, MARK_SECONDS * 1000, h.bit)
    if not obj then return end
    h.pets[#h.pets + 1] = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map, marker = true }   -- track first, configure after
    Reg(obj, "c", loc.map)
    obj:SetPhaseMask(h.bit, true)
    obj:SetReactState(0)
    obj:AddAura(MARK_SPELL, obj)
end)
Msg.On("house", "unmark", function(player)
    local h = MyHouse(player)
    if h then ClearMarker(h) end
end)

-- ---- radius ring: a circle of marker wisps on the garrison edge so the owner can SEE the radius ("house|ring" 1/0 from the addon checkbox) ----
local RING_POINTS, RING_SECONDS = 48, 180
local function ClearRing(h)
    for i = #h.pets, 1, -1 do
        local pt = h.pets[i]
        if pt.ring then
            local map = GetMapById(pt.map, 0)
            local obj = map and map:GetWorldObject(pt.guid)
            if obj then obj:DespawnOrUnsummon(0) end
            Unreg("c", pt.low); table.remove(h.pets, i)
        end
    end
end
Msg.On("house", "ring", function(player, payload)
    local h = MyHouse(player)
    if not h then return end
    ClearRing(h)
    if payload ~= "1" then return end
    local loc = Loc(h.loc)
    local map = GetMapById(loc.map, 0)
    for i = 0, RING_POINTS - 1 do
        local a = (i / RING_POINTS) * 2 * math.pi
        local x, y = loc.cx + math.cos(a) * loc.radius, loc.cy + math.sin(a) * loc.radius
        local z = map and map:GetHeight(x, y, 1) or player:GetZ()
        if not z or z < -1000 then z = player:GetZ() end
        local obj = PerformIngameSpawn(1, MARK_NPC, loc.map, 0, x, y, z + 1.0, 0, false, RING_SECONDS * 1000, h.bit)
        if obj then
            h.pets[#h.pets + 1] = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map, ring = true }   -- track first, configure after
            Reg(obj, "c", loc.map)
            obj:SetPhaseMask(h.bit, true)
            obj:SetReactState(0)
        end
    end
end)

local MEN_NPC = 900003
RegisterCreatureGossipEvent(MEN_NPC, 1, function(event, player, creature)
    local owner = inside[player:GetGUIDLow()]
    local h = owner and active[owner]
    if not h then Say(player, "The Menagerie only works inside a garrison."); return true end
    player:GossipClearMenu()
    if owner ~= player:GetAccountId() then
        player:GossipMenuAddItem(0, "Only the garrison owner can change this.", 0, 99, false)
    elseif RoamEnabled(owner, h.loc) then
        player:GossipMenuAddItem(0, "Have all pets stay home", 0, 2, false)
        player:GossipMenuAddItem(0, "Pick a new set of pets", 0, 3, false)
    else
        player:GossipMenuAddItem(0, "Allow pets to explore the garrison", 0, 1, false)
    end
    player:GossipSendMenu(1, creature)
    return true
end)
RegisterCreatureGossipEvent(MEN_NPC, 2, function(event, player, creature, sender, intid)
    player:GossipComplete()
    local owner = inside[player:GetGUIDLow()]
    local h = owner and active[owner]
    if not h or owner ~= player:GetAccountId() or intid == 99 then return true end
    if intid == 1 then SetRoam(owner, h.loc, true); RollPets(h, owner, player:GetGUIDLow(), true); Say(player, "Your pets are exploring the garrison.")
    elseif intid == 2 then SetRoam(owner, h.loc, false); DespawnPets(h); Say(player, "Your pets are staying home.")
    elseif intid == 3 then RollPets(h, owner, player:GetGUIDLow()); Say(player, "A new set of pets arrives.") end
    return true
end)

-- ---- garrison jukebox (NPC 900004 "Sig Nicious - Jukebox") ----
-- One CONTROLLER per garrison: whoever last chose "Choose music" at the NPC. Only the controller's client picks/advances songs
-- (it runs the repeat/shuffle/favorites logic and sends each song here); we just validate and broadcast to everyone inside.
-- Controller leaves/logs out, or anyone uses "Stop the music" -> music stops for everyone. Late joiners hear the current song.
local JUKE_NPC = 900004

local function BroadcastJuke(h, action, payload)
    for _, guid in pairs(h.occ) do
        local p = GetPlayerByGUID(guid)
        if p then Msg.Send(p, "jukebox", action, payload or "") end
    end
end

RegisterCreatureGossipEvent(JUKE_NPC, 1, function(event, player, creature)
    player:GossipClearMenu()
    player:GossipMenuAddItem(6, "Choose music for the garrison", 0, 1, false)
    player:GossipMenuAddItem(0, "Stop the music", 0, 2, false)
    player:GossipSendMenu(1, creature)
    return true
end)
RegisterCreatureGossipEvent(JUKE_NPC, 2, function(event, player, creature, sender, intid)
    player:GossipComplete()
    local g = player:GetGUIDLow()
    local owner = inside[g]
    local h = owner and active[owner]
    if not h then Say(player, "The jukebox only plays inside a garrison."); return true end
    if intid == 1 then
        if h.controller and h.controller ~= g then          -- take over: tell the previous controller to let go
            local old = h.occ[h.controller] and GetPlayerByGUID(h.occ[h.controller])
            if old then Msg.Send(old, "jukebox", "release", "") end
        end
        h.controller = g
        Msg.Send(player, "jukebox", "open", "")
    elseif intid == 2 then
        h.controller, h.track = nil, nil
        BroadcastJuke(h, "stop")
    end
    return true
end)

local function ValidTrack(path)
    return type(path) == "string" and #path <= 200 and path:sub(1, 12) == "Sound\\Music\\" and not path:find("..", 1, true) and path:lower():find("%.mp3$")
end
Msg.On("jukebox", "play", function(player, path)
    local g = player:GetGUIDLow()
    local owner = inside[g]
    local h = owner and active[owner]
    if not h or h.controller ~= g or not ValidTrack(path) then return end
    h.track = path
    BroadcastJuke(h, "play", path)
end)
Msg.On("jukebox", "stop", function(player)
    local g = player:GetGUIDLow()
    local owner = inside[g]
    local h = owner and active[owner]
    if not h or h.controller ~= g then return end
    h.track = nil
    BroadcastJuke(h, "stop")
end)

-- ---- self-heal: a script reload forgets who is inside, but players keep their phase. Put anyone left in one of our phase bits back to 1. ----
local OUR_BITS = {}
for _, b in ipairs(FREE_BITS) do OUR_BITS[b] = true end
local function HealStrays()
    for _, p in pairs(GetPlayersInWorld() or {}) do
        if p and not inside[p:GetGUIDLow()] and OUR_BITS[p:GetPhaseMask()] then
            p:SetPhaseMask(1, true)
            Msg.Send(p, "jukebox", "garrison", "0")
        end
    end
end
HealStrays()
RegisterPlayerEvent(3, function(event, player)   -- login: phase never survives a logout, but be safe
    if OUR_BITS[player:GetPhaseMask()] then player:SetPhaseMask(1, true) end
end)

-- ---- test items: anything placed whose kind is now in Removed/Unsorted (hidden from the catalog) is deleted when its owner logs in. Remove this block to undo. ----
local HIDDEN = require("garrison_catalog").hidden or {}
RegisterPlayerEvent(3, function(event, player)
    local acct = player:GetAccountId()
    for _, t in ipairs({ { "dc_garrison_decor", "id" }, { "dc_garrison_object", "kind" } }) do
        local q = CharDBQuery(string.format("SELECT kind, %s FROM %s WHERE account=%d", t[2], t[1], acct))
        if q then repeat
            local kind = q:GetString(0)
            if HIDDEN[kind] then
                CharDBExecute(string.format("DELETE FROM %s WHERE account=%d AND %s='%s'", t[1], acct, t[2], t[2] == "id" and q:GetUInt32(1) or kind))
                print(string.format("[garrison] cleared hidden item %s from account %d", kind, acct))
            end
        until not q:NextRow() end
    end
end)

-- ---- used objects (doors etc.): many models vanish on the client after their open animation. A few seconds after any placed
-- object is used, if its state changed, it is removed and spawned again (same as the "To me" button). Remove this block to undo. ----
local RESET_MS = 4000   -- used when the model has no Open animation
local ANIMS = require("garrison_anims")   -- entry -> { open animation ms, hasClose } (generated by claude_tools/door_anims.py)
local function Closes(entry) local a = ANIMS[entry]; return a and a[3] > 0 end   -- door closes by itself (autoclose): only these vanish
local function ResetDelay(entry)   -- closing doors: wait for open -> autoclose -> close animation; everything else: fixed delay
    local a = ANIMS[entry]
    return Closes(entry) and math.max(1500, math.min(10000, a[3] + a[2] + 500)) or RESET_MS
end
local function FindSpawn(guid)
    for _, h in pairs(active) do
        for _, s in ipairs(h.spawned) do if s.guid == guid then return h, s end end
    end
end
local function ResetUsed(guid)
    local h, s = FindSpawn(guid)
    if not h then return end
    local map = GetMapById(s.map, 0)
    local obj = map and map:GetWorldObject(guid)
    if not obj then return end
    local state = obj:GetGoState()
    print(string.format("[garrison] used object kind=%s state=%d%s", s.kind, state, (state ~= 1 or Closes(obj:GetEntry())) and " -> reset" or " (unchanged)"))
    if state == 1 and not Closes(obj:GetEntry()) then return end   -- closing doors are reset even though the server says closed (the vanish is client-side)
    local row = s.did and h.decor[s.did] or h.rows[s.kind]
    if not row then return end
    if s.did then DespawnKind(h, nil, s.did) else DespawnKind(h, s.kind) end
    SpawnOne(h, row)
end
local usedHooked = {}
for _, def in pairs(BY_KIND) do
    if def.t == "g" and not usedHooked[def.entry] then
        usedHooked[def.entry] = true
        RegisterGameObjectEvent(def.entry, 14, function(event, go, player)   -- GAMEOBJECT_EVENT_ON_USE; no return = normal use still happens
            local guid = go:GetGUID()
            CreateLuaEvent(function() ResetUsed(guid) end, ResetDelay(go:GetEntry()), 1)
        end)
    end
end

-- ---- safety net: every 5 minutes any registered spawn that no live garrison owns is removed (should always find nothing) ----
local lastAudit = 0
local function Audit()
    local tracked = {}
    for _, h in pairs(active) do
        for _, sp in ipairs(h.spawned) do tracked[sp.t .. sp.low] = true end
        for _, pt in ipairs(h.pets) do tracked["c" .. pt.low] = true end
    end
    lastAudit = CleanOrphans(tracked) or 0
    if lastAudit > 0 then print("[garrison] audit removed " .. lastAudit .. " orphaned spawn(s)") end
end
CreateLuaEvent(Audit, 300000, 0)

-- ---- GM tuning: .garrison info | center | radius N ----
RegisterPlayerEvent(42, function(event, player, command)
    if not player or not command then return end
    local cmd, arg = command:match("^garrison%s*(%a*)%s*(%S*)")
    if not cmd then return end
    if player:GetGMRank() < 2 then return end
    local loc = Loc(DEFAULT_LOC)
    if cmd == "center" then
        loc.cx, loc.cy = player:GetX(), player:GetY()
    elseif cmd == "radius" and tonumber(arg) then
        loc.radius = tonumber(arg)
    elseif cmd == "status" then
        local gar, occ, sp, pets = 0, 0, 0, 0
        for _, h in pairs(active) do gar = gar + 1; occ = occ + h.n; sp = sp + #h.spawned; pets = pets + #h.pets end
        local q = CharDBQuery("SELECT COUNT(*) FROM dc_garrison_spawn")
        Say(player, string.format("open garrisons %d, occupants %d, tracked NPCs/objects %d, pets %d, registry rows %d (should equal tracked), last audit removed %d", gar, occ, sp, pets, q and q:GetUInt32(0) or -1, lastAudit))
        return false
    elseif cmd == "purge" then
        Say(player, "Purge: removing every garrison spawn. Everyone inside is moved out first.")
        for g, owner in pairs(inside) do
            local h = active[owner]
            Leave(g, h and h.occ[g] and GetPlayerByGUID(h.occ[g]) or nil)
        end
        CleanOrphans(); return false
    elseif cmd ~= "info" then
        Say(player, ".garrison info | status | purge | center (use your position) | radius <yards>"); return false
    end
    if cmd == "center" or cmd == "radius" then
        CharDBExecute(string.format("REPLACE INTO dc_garrison_location (id, cx, cy, radius) VALUES (%d,%f,%f,%f)", loc.id, loc.cx, loc.cy, loc.radius))
    end
    local dx, dy = player:GetX() - loc.cx, player:GetY() - loc.cy
    Say(player, string.format("%s: center %.1f, %.1f radius %.1f (you are %.1f from center)", loc.name, loc.cx, loc.cy, loc.radius, math.sqrt(dx * dx + dy * dy)))
    return false
end)

print("[garrison] loaded (" .. #(function() local n = {} for k in pairs(COMPANIONS) do n[#n + 1] = k end return n end)() .. " companion spells, " .. #CATALOG .. " placeable kinds, " .. #FREE_BITS .. " phase bits)")
return true
