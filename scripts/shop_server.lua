-- ============================================================
-- Shop (server side). Client addon: addons/DadShop. All purchases are validated here.
-- Currency: Darkmoon Faire Prize Ticket (item 19182). Catalog is data in shop_catalog.lua.
-- ============================================================
local Msg = require("acore_msg")
local Catalog = require("shop_catalog")
local Settings = require("acore_settings")
local SH = Settings.shop
local GOLD_MODE = SH.currency == "gold"
local TICKET = SH.item or 19182
local KIND = { pets = "pet", mounts = "mount", toys = "toy", services = "service" }

local AT_LOGIN = { rename = 0x01, customize = 0x08, faction = 0x40, race = 0x80 }   -- AzerothCore AtLoginFlags
local byId = {}
for tab, list in pairs(Catalog.tabs) do
    for _, e in ipairs(list) do e.tab = tab; byId[e.id] = e end
end

-- balance = copper (gold mode) or item count (item mode)
local function Balance(player)
    if GOLD_MODE then return player:GetCoinage() end
    return player:GetItemCount(TICKET)
end
-- price in the active currency (copper or item count)
local function Price(e)
    if GOLD_MODE then return (SH.gold[KIND[e.tab]] or 0) * 10000 end
    if e.service then return SH.serviceItemCost or 0 end
    return e.cost
end

Msg.On("shop", "bal", function(player)
    Msg.Send(player, "shop", "bal", Balance(player))
end)
-- client needs to know how to display prices: mode;item;goldPet;goldMount;goldToy;goldService;serviceItemCost
Msg.On("shop", "cfg", function(player)
    local g = SH.gold
    Msg.Send(player, "shop", "cfg", table.concat({ GOLD_MODE and "gold" or "item", TICKET, g.pet, g.mount, g.toy, g.service, SH.serviceItemCost or 0 }, ";"))
end)

-- payload: "<entryId>"
Msg.On("shop", "buy", function(player, payload)
    local id = tonumber(payload)
    local e = id and byId[id]
    if not e then return Msg.Send(player, "shop", "res", "0;Unknown item") end
    local price = Price(e)
    local have = Balance(player)
    if e.service then   -- character services: flag the character, the client finishes it at the character screen
        local flag = AT_LOGIN[e.service]
        if not flag then return Msg.Send(player, "shop", "res", id .. ";Unknown service") end
        if player:HasAtLoginFlag(flag) then return Msg.Send(player, "shop", "res", id .. ";Already pending: log out to the character screen to complete it.") end
        if have < price then return Msg.Send(player, "shop", "res", id .. ";Not enough funds") end
        if price > 0 then
            if GOLD_MODE then player:ModifyMoney(-price) else player:RemoveItem(TICKET, price) end
            Msg.Send(player, "shop", "bal", Balance(player))
        end
        player:SetAtLoginFlag(flag)
        return Msg.Send(player, "shop", "res", id .. ";OK:" .. (e.message or "Log out to the character selection screen to complete it."))
    end
    if e.spell and player:HasSpell(e.spell) then return Msg.Send(player, "shop", "res", id .. ";You already know this") end
    if have < price then
        return Msg.Send(player, "shop", "res", id .. ";Not enough funds")
    end
    if GOLD_MODE then player:ModifyMoney(-price) else player:RemoveItem(TICKET, price) end
    if e.spell then player:LearnSpell(e.spell) end
    if e.item and not e.spell then player:AddItem(e.item, e.count or 1) end
    Msg.Send(player, "shop", "res", id .. ";OK")
    Msg.Send(player, "shop", "bal", Balance(player))
end)
return true
