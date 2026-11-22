-- ============================================================
-- ACORE creature-cache priming (CORE service; used by any addon that draws 3D creature previews).
-- The 3.3.5 client can only draw SetCreature(id) models for creatures it has cached. This pushes an
-- SMSG_CREATURE_QUERY_RESPONSE for every registered creature so the client has them cached.
-- Layout copied from AzerothCore CreatureTemplate::InitializeQueryData (src/server/game/Entities/Creature/Creature.cpp).
--
-- Each addon registers ONLY ITS OWN creatures and never reads another addon's data:
--   local Prime = require("acore_prime")
--   Prime.Register("shop", function() return { 123, 456 } end)   -- name + id list (or a function returning one: evaluated lazily)
--   Prime.Enable("shop")                                         -- answers the client message  shop|prime  with  shop|primed|<count>
--   Prime.SetDisplayResolver(function(player, entry) return displayId or 0 end)   -- optional: per-player skin for an entry
-- Everything registered by the addons that are installed is sent together, so a missing addon only means fewer previews.
-- Other API: Prime.SendOne(player, entry, display)   Prime.SendAs(player, asEntry, entry, display)
-- ============================================================
ACORE = ACORE or {}
if ACORE.Prime then return ACORE.Prime end   -- already loaded (safe against double load)

local Msg = require("acore_msg")
local SMSG_CREATURE_QUERY_RESPONSE = 0x061

local Prime = {}
ACORE.Prime = Prime

local sources = {}          -- name -> ids table or function
local records, count = {}, 0
local dirty = true
local resolver

function Prime.Register(name, ids) sources[name] = ids; dirty = true end
function Prime.SetDisplayResolver(fn) resolver = fn end

local function Load()
    records, count, dirty = {}, 0, false
    local all, seen = {}, {}
    for name, src in pairs(sources) do
        local ok, list = pcall(function() if type(src) == "function" then return src() end return src end)
        if not ok then print("[acore_prime] source '" .. name .. "' failed: " .. tostring(list)) end
        for _, e in ipairs(ok and type(list) == "table" and list or {}) do
            if not seen[e] then seen[e] = true; all[#all + 1] = e end
        end
    end
    if #all == 0 or not WorldDBQuery then return end
    local ids = table.concat(all, ",")
    local q = WorldDBQuery("SELECT entry, name, IFNULL(subname,''), IFNULL(IconName,''), type_flags, type, family, `rank`, KillCredit1, KillCredit2, " ..
                           "HealthModifier, ManaModifier, RacialLeader, movementId FROM creature_template WHERE entry IN (" .. ids .. ")")
    if q then
        repeat
            records[q:GetUInt32(0)] = { name = q:GetString(1), sub = q:GetString(2), icon = q:GetString(3), typeFlags = q:GetUInt32(4),
                type = q:GetUInt32(5), family = q:GetUInt32(6), rank = q:GetUInt32(7), kc1 = q:GetUInt32(8), kc2 = q:GetUInt32(9),
                hp = q:GetFloat(10), mana = q:GetFloat(11), racial = q:GetUInt32(12), move = q:GetUInt32(13), models = { 0, 0, 0, 0 } }
            count = count + 1
        until not q:NextRow()
    end
    local m = WorldDBQuery("SELECT CreatureID, Idx, CreatureDisplayID FROM creature_template_model WHERE CreatureID IN (" .. ids .. ") AND Idx < 4")
    if m then
        repeat
            local r = records[m:GetUInt32(0)]
            if r then r.models[m:GetUInt32(1) + 1] = m:GetUInt32(2) end
        until not m:NextRow()
    end
    print("[acore_prime] " .. count .. " creature records ready")
end
local function Ready() if dirty then Load() end end

local function SendRecord(player, entry, r, display)
    local p = CreatePacket(SMSG_CREATURE_QUERY_RESPONSE, 160)
    p:WriteULong(entry)
    p:WriteString(r.name)
    p:WriteUByte(0); p:WriteUByte(0); p:WriteUByte(0)       -- name2..name4 (always empty)
    p:WriteString(r.sub)
    p:WriteString(r.icon)
    p:WriteULong(r.typeFlags); p:WriteULong(r.type); p:WriteULong(r.family); p:WriteULong(r.rank)
    p:WriteULong(r.kc1); p:WriteULong(r.kc2)
    if display and display > 0 then p:WriteULong(display); for _ = 2, 4 do p:WriteULong(0) end else for i = 1, 4 do p:WriteULong(r.models[i]) end end
    p:WriteFloat(r.hp); p:WriteFloat(r.mana)
    p:WriteUByte(r.racial)
    p:WriteULong(r.move)
    player:SendPacket(p)
end

function Prime.SendOne(player, entry, display) Ready(); if records[entry] then SendRecord(player, entry, records[entry], display) end end
-- the same record under another entry id with ONE model (battle preview of an exact skin)
function Prime.SendAs(player, asEntry, entry, display) Ready(); if records[entry] then SendRecord(player, asEntry, records[entry], display) end end

local function Send(player)
    Ready()
    for entry, r in pairs(records) do
        local d = 0
        if resolver then local ok, v = pcall(resolver, player, entry); if ok and v then d = v end end   -- e.g. a battle pet shows the skin YOU own
        SendRecord(player, entry, r, d)
    end
end

local last = {}
function Prime.Enable(module)
    Msg.On(module, "prime", function(player)
        local g, now = player:GetGUIDLow(), os.time()
        if last[g] and now - last[g] < 5 then return end   -- cheap flood guard
        last[g] = now
        Send(player)
        Msg.Send(player, module, "primed", count)
    end)
end
if RegisterPlayerEvent then RegisterPlayerEvent(4, function(event, player) last[player:GetGUIDLow()] = nil end) end   -- logout: do not keep per-player entries forever

return Prime
