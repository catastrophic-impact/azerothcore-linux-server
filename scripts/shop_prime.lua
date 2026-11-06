-- ============================================================
-- Creature-cache priming for the shop's 3D previews (EXPERIMENT).
-- The 3.3.5 client can only draw SetCreature(id) models for creatures it has cached. This pushes an
-- SMSG_CREATURE_QUERY_RESPONSE for every creature used by the shop, so the client has them cached.
-- Layout copied from AzerothCore CreatureTemplate::InitializeQueryData (src/server/game/Entities/Creature/Creature.cpp).
-- Client triggers it with the addon message  shop|prime  ; reply  shop|primed|<count>
-- ============================================================
local Msg = require("acore_msg")
local Catalog = require("shop_catalog")
local ok, GCat = pcall(require, "garrison_catalog")   -- garrison NPCs share the same priming
local SMSG_CREATURE_QUERY_RESPONSE = 0x061

local records = {}
local count = 0

local function Load()
    records, count = {}, 0
    local all = {}
    for _, e in ipairs(Catalog.npcs or {}) do all[#all + 1] = e end
    if ok and GCat and GCat.npcs then for _, e in ipairs(GCat.npcs) do all[#all + 1] = e end end
    if #all == 0 then return end
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
    print("[shop_prime] " .. count .. " creature records ready")
end
Load()

local function Send(player)
    for entry, r in pairs(records) do
        local p = CreatePacket(SMSG_CREATURE_QUERY_RESPONSE, 160)
        p:WriteULong(entry)
        p:WriteString(r.name)
        p:WriteUByte(0); p:WriteUByte(0); p:WriteUByte(0)       -- name2..name4 (always empty)
        p:WriteString(r.sub)
        p:WriteString(r.icon)
        p:WriteULong(r.typeFlags); p:WriteULong(r.type); p:WriteULong(r.family); p:WriteULong(r.rank)
        p:WriteULong(r.kc1); p:WriteULong(r.kc2)
        for i = 1, 4 do p:WriteULong(r.models[i]) end
        p:WriteFloat(r.hp); p:WriteFloat(r.mana)
        p:WriteUByte(r.racial)
        p:WriteULong(r.move)
        player:SendPacket(p)
    end
end

local last = {}
local function Prime(module)
    return function(player)
        local g, now = player:GetGUIDLow(), os.time()
        if last[g] and now - last[g] < 5 then return end   -- cheap flood guard
        last[g] = now
        Send(player)
        Msg.Send(player, module, "primed", count)
    end
end
RegisterPlayerEvent(4, function(event, player) last[player:GetGUIDLow()] = nil end)   -- logout: do not keep per-player entries forever
Msg.On("shop", "prime", Prime("shop"))
Msg.On("house", "prime", Prime("house"))
return true
