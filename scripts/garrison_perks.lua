-- Garrison module 14/14 (part 1): perks while inside a garrison. Plugged in through the session hooks, nothing else knows about them.
--  * instantLogout: the player gets the "resting" flag (PLAYER_FLAGS_RESTING), exactly what an inn gives: /logout is instant, and a character that
--    logs out inside is saved as "logged out resting" (the core then gives it the faster offline rested-XP rate).
--  * rested: the core only adds rested XP for resting players that went through its own inn code, so we add it ourselves with the core's formula:
--    every 10 s  += seconds * (XP to next level / 72000) * 0.125 * restedRate   (= 5% of a level per 8 hours at rate 1.0)
-- The flag is removed again on leaving. A character that logged out inside gets it removed at the next login (the saved flag would otherwise
-- keep /logout instant everywhere); a flag left behind by a crash is removed at login unless the character is resting in a real tavern.
-- Settings: acore_settings.lua -> garrison.perks = { instantLogout, rested, restedRate }.
return function(G)
    local perks, store = G.cfg.perks, G.store
    local PLAYER_FLAGS, PLAYER_NEXT_LEVEL_XP, FLAG_RESTING = 150, 635, 0x20
    if not (perks.instantLogout or perks.rested) then return end
    local lastRest = {}   -- player guidLow -> time of the last rested-XP step

    G.OnEnter(function(player)
        player:SetPlayerFlag(FLAG_RESTING)
        lastRest[player:GetGUIDLow()] = os.time()
    end)
    G.OnLeave(function(guidLow, player, h, reason)
        lastRest[guidLow] = nil
        if player and reason ~= "logout" then player:RemovePlayerFlag(FLAG_RESTING) end   -- on logout the flag is saved (offline rested XP) and cleared at the next login
    end)
    G.OnTick(function(player, h, now)
        if not perks.rested then return end
        local g = player:GetGUIDLow()
        local last = lastRest[g] or now
        if now - last < 10 then return end
        lastRest[g] = now
        if player:GetLevel() >= 80 then return end
        local perSec = (player:GetUInt32Value(PLAYER_NEXT_LEVEL_XP) / 72000) * 0.125 * perks.restedRate
        player:SetRestBonus(player:GetRestBonus() + (now - last) * perSec)
    end)
    G.OnLogin(function(player, wasInside)
        if not player:HasFlag(PLAYER_FLAGS, FLAG_RESTING) then return end
        if wasInside or store.InnTrigger(player:GetGUIDLow()) == 0 then player:RemovePlayerFlag(FLAG_RESTING) end
    end)
    G.OnStray(function(player) player:RemovePlayerFlag(FLAG_RESTING) end)   -- after a script reload: left behind in a garrison phase
end
