-- Garrison module 3/14: money. Two prices: (1) placing an item (catalog price, config currency/currencyItem; refunded exactly when removed,
-- what was paid is stored on the row: paid, pcur) and (2) claiming a garrison (config cost; never refunded).
return function(G)
    local C = G.cfg
    local itemNames = {}
    local function ItemName(id)
        if not itemNames[id] then
            local q = WorldDBQuery("SELECT name FROM item_template WHERE entry=" .. math.floor(tonumber(id) or 0))
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
        if C.currency == "free" or amount <= 0 then return true, 0, "" end
        if C.currency == "gold" then
            if player:GetCoinage() < amount * 10000 then return false, 0, "", "You need " .. amount .. " gold to place " .. def.name .. "." end
            player:ModifyMoney(-amount * 10000); return true, amount, "g"
        end
        if player:GetItemCount(C.currencyItem) < amount then return false, 0, "", "You need " .. amount .. " x " .. ItemName(C.currencyItem) .. " to place " .. def.name .. "." end
        player:RemoveItem(C.currencyItem, amount); return true, amount, "i" .. C.currencyItem
    end
    local function Refund(player, row)   -- gives back what the row paid; returns a message fragment or ""
        local paid, pcur = row.paid or 0, row.pcur or ""
        if paid <= 0 or pcur == "" then return "" end
        if pcur == "g" then player:ModifyMoney(paid * 10000)
        else local id = tonumber(pcur:sub(2)); if not id then return "" end; player:AddItem(id, paid) end
        return " (refunded " .. Money(paid, pcur) .. ")"
    end
    -- claiming a garrison
    local k = C.claim
    local function ClaimText() return k.currency == "free" and "free" or (k.currency == "gold" and (k.amount .. " gold") or (k.amount .. " x " .. ItemName(k.item))) end
    local function ChargeClaim(player)   -- ok, failMessage
        if k.currency == "free" then return true end
        if k.currency == "gold" then
            if player:GetCoinage() < k.amount * 10000 then return false, "You need " .. k.amount .. " gold to claim a garrison." end
            player:ModifyMoney(-k.amount * 10000); return true
        end
        if player:GetItemCount(k.item) < k.amount then return false, "You need " .. k.amount .. " x " .. ItemName(k.item) .. " to claim a garrison." end
        player:RemoveItem(k.item, k.amount); return true
    end
    G.ItemName, G.Money, G.Charge, G.Refund, G.ClaimText, G.ChargeClaim = ItemName, Money, Charge, Refund, ClaimText, ChargeClaim
end
