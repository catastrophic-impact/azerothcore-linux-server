-- Garrison module 13/14: garrison jukebox (NPC 900004 "Sig Nicious - Jukebox").
-- One CONTROLLER per garrison: whoever last chose "Choose music" at the NPC. Only the controller's client picks/advances songs
-- (it runs the repeat/shuffle/favorites logic and sends each song here); we just validate and broadcast to everyone inside.
-- Controller leaves/logs out, or anyone uses "Stop the music" -> music stops for everyone. Late joiners hear the current song.
-- DEFAULT music: the garrison OWNER's client plays their default (song / playlist) when nothing else plays. It claims the controller slot with
-- jukebox|default|<path> (allowed only for the owner and only while nothing is playing); anyone choosing music at the NPC takes over as usual.
-- 'stop' carries why: "end" = a song ended / random was switched off (the default may resume), "" = a guest pressed Stop, "owner" = the owner pressed Stop
-- (the owner's client then switches its saved default mode to Off; a guest's Stop only keeps the default quiet for this visit).
return function(G)
    local Msg, Say, active, inside = G.Msg, G.Say, G.active, G.inside
    local JUKE_NPC = 900004

    local function Broadcast(h, action, payload)
        for _, guid in pairs(h.occ) do
            local p = GetPlayerByGUID(guid)
            if p then Msg.Send(p, "jukebox", action, payload or "") end
        end
    end

    RegisterCreatureGossipEvent(JUKE_NPC, 1, function(event, player, creature)
        if not Msg.Has(player, "jukebox") then
            Say(player, "You need the Jukebox addon to use the jukebox. Install it, then /reload.")
            player:GossipComplete()
            return true
        end
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
            Broadcast(h, "stop", player:GetAccountId() == owner and "owner" or "")
        end
        return true
    end)

    local function ValidTrack(path)
        return type(path) == "string" and #path <= 200 and path:sub(1, 12) == "Sound\\Music\\" and not path:find("..", 1, true) and path:lower():find("%.mp3$")
    end
    local function Controlled(player)   -- the garrison whose jukebox this player controls
        local g = player:GetGUIDLow()
        local owner = inside[g]
        local h = owner and active[owner]
        if h and h.controller == g then return h end
    end
    Msg.On("jukebox", "play", function(player, path)
        local h = Controlled(player)
        if not h or not ValidTrack(path) then return end
        h.track = path
        Broadcast(h, "play", path)
    end)
    Msg.On("jukebox", "stop", function(player, why)
        local h = Controlled(player)
        if not h then return end
        h.track = nil
        if why ~= "end" then why = (player:GetAccountId() == inside[player:GetGUIDLow()]) and "owner" or "" end
        Broadcast(h, "stop", why)
    end)
    -- the owner's default music: only the owner, only while nothing plays
    Msg.On("jukebox", "default", function(player, path)
        local g = player:GetGUIDLow()
        local owner = inside[g]
        local h = owner and active[owner]
        if not h or owner ~= player:GetAccountId() or not ValidTrack(path) then return end
        if h.track and h.controller ~= g then return end                 -- somebody else is playing music
        if h.controller and h.controller ~= g then                       -- an idle controller (a guest between songs) gives way
            local old = h.occ[h.controller] and GetPlayerByGUID(h.occ[h.controller])
            if old then Msg.Send(old, "jukebox", "release", "") end
        end
        h.controller, h.track = g, path
        Broadcast(h, "play", path)
    end)

    -- a client that just reloaded / zoned asks where it is (the answer is the same message sent on entering)
    Msg.On("jukebox", "state", function(player)
        local g = player:GetGUIDLow()
        local owner = inside[g]
        local h = owner and active[owner]
        if not h then Msg.Send(player, "jukebox", "garrison", "0"); return end
        Msg.Send(player, "jukebox", "garrison", owner == player:GetAccountId() and "o" or "1")
        if h.track then Msg.Send(player, "jukebox", "play", h.track) end
    end)

    -- the client addon needs to know whether it is inside a garrison (it hides parts of the jukebox window otherwise)
    G.OnEnter(function(player, h, owner)
        Msg.Send(player, "jukebox", "garrison", (owner and owner == player:GetAccountId()) and "o" or "1")   -- "o" = this is your own garrison
        if h.track then Msg.Send(player, "jukebox", "play", h.track) end   -- the garrison jukebox is already playing
    end)
    G.OnLeave(function(guidLow, player, h)
        if player then Msg.Send(player, "jukebox", "garrison", "0") end
        if h and h.controller == guidLow then
            h.controller, h.track = nil, nil
            for _, guid in pairs(h.occ) do local p = GetPlayerByGUID(guid); if p then Msg.Send(p, "jukebox", "stop", "end") end end
        end
    end)
    G.OnStray(function(player) Msg.Send(player, "jukebox", "garrison", "0") end)
end
