-- Garrison module 8/14: the portal NPC-object (Stormwind Mage Tower for Alliance, Orgrimmar for Horde; same menu, either faction may use either). A player without a garrison picks one of the enabled locations
-- (price: acore_settings garrison.cost); a player with one can enter it, visit a group member's, or abandon it (everything placed is lost, no refund).
-- Ownership is one location per account (dc_garrison_owner, cached in G.owners).
return function(G)
    local Msg, store, cfg, Say, dbg = G.Msg, G.store, G.cfg, G.Say, G.dbg
    local Loc, active, inside = G.locations.Get, G.active, G.inside
    local OWNER = store.LoadOwners()   -- account -> location id
    G.owners = OWNER

    local INT_HOME, INT_ABANDON, INT_PICK, INT_VISIT = 1, 2, 100, 1000

    local function OnHello(event, player, go)
        dbg("hello", player:GetName(), "inside=" .. tostring(inside[player:GetGUIDLow()]))
        if not Msg.Has(player, "garrison") then   -- no addon: no menu at all (nothing to claim, nothing to enter)
            Say(player, "You need the Garrison addon to use garrisons. Install it, then /reload.")
            player:GossipComplete()
            return true
        end
        local account = player:GetAccountId()
        local mine = OWNER[account]
        player:GossipClearMenu()
        if mine and not Loc(mine) then
            player:GossipMenuAddItem(0, "Your garrison location is not available right now.", 0, 99, false)
        elseif not mine then
            for _, l in ipairs(G.locations.List()) do
                player:GossipMenuAddItem(0, "Claim the garrison at " .. l.name .. " (" .. G.ClaimText() .. ")", 0, INT_PICK + l.id, false,
                    "Make " .. l.name .. " your garrison? Price: " .. G.ClaimText() .. ".\nYou can abandon it later, but everything you place there is lost.")
            end
        else
            player:GossipMenuAddItem(0, "Enter Garrison (" .. Loc(mine).name .. ")", 0, INT_HOME, false)
            local grp = player:GetGroup()
            if grp then
                for _, m in pairs(grp:GetMembers()) do
                    if m and not m:IsBot() and m:GetGUIDLow() ~= player:GetGUIDLow() then
                        local o = inside[m:GetGUIDLow()]
                        if o and o ~= account then player:GossipMenuAddItem(0, "Visit " .. m:GetName() .. "'s garrison", 0, INT_VISIT + o, false) end
                    end
                end
            end
            player:GossipMenuAddItem(0, "Abandon my garrison and choose another", 0, INT_ABANDON, false,
                "Abandon your garrison at " .. Loc(mine).name .. "?\nEVERYTHING you placed there is lost for good, it no longer belongs to you, and picking another one costs " .. G.ClaimText() .. ".")
        end
        player:GossipSendMenu(1, go)
        return true
    end

    local function Abandon(account)   -- everybody inside is sent out first; then the data goes (see garrison_store.lua for the order)
        for g, o in pairs(inside) do
            if o == account then
                local h = active[o]
                G.Leave(g, h and h.occ[g] and GetPlayerByGUID(h.occ[g]) or nil, "abandon")
            end
        end
        store.Abandon(account)
        OWNER[account] = nil
    end

    local function OnSelect(event, player, go, sender, intid)
        dbg("select", player:GetName(), "intid=" .. tostring(intid), "inside=" .. tostring(inside[player:GetGUIDLow()]))
        player:GossipComplete()
        if intid == 99 then return true end
        if inside[player:GetGUIDLow()] then Say(player, "You are already in a garrison."); return true end
        if not player:IsAlive() or player:IsInCombat() then Say(player, "You can't do that right now."); return true end
        local account = player:GetAccountId()
        if intid == INT_ABANDON then
            if not OWNER[account] then return true end
            Abandon(account)
            Say(player, "Your garrison is abandoned and everything in it is gone. Choose a new one at the portal.")
            return true
        elseif intid >= INT_PICK and intid < INT_VISIT then
            local l = Loc(intid - INT_PICK)
            if OWNER[account] or not (l and l.enabled) then return true end
            local ok, why = G.ChargeClaim(player)
            if not ok then Say(player, why); return true end
            OWNER[account] = l.id
            store.Claim(account, l.id)
            Say(player, "The garrison at " .. l.name .. " is yours. Use the portal to enter it.")
            return true
        end
        if G.GroupHasBots(player) then
            Say(player, "Dismiss your companions and playerbots first (Bot Manager: Remove All Companions). Bots can't enter a garrison.")
            return true
        end
        if intid == INT_HOME then
            local mine = OWNER[account]
            if mine then G.Enter(player, account, mine) end
        elseif intid > INT_VISIT then
            local o = intid - INT_VISIT
            if active[o] then G.Enter(player, o, active[o].loc) else Say(player, "That garrison is no longer open.") end
        end
        return true
    end
    for _, entry in ipairs({ cfg.portalEntry, cfg.portalEntryHorde }) do
        RegisterGameObjectGossipEvent(entry, 1, OnHello)
        RegisterGameObjectGossipEvent(entry, 2, OnSelect)
    end
end
