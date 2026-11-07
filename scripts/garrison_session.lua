-- Garrison module 7/14: who is inside which garrison. Enter / Leave, the once-a-second area check, the leave countdown,
-- login / logout / map-change handling and the phase-bit allocation. This is the only module that changes a player's phase for a garrison.
-- Other modules plug in through the hooks (G.OnEnter / OnLeave / OnClose / OnTick / OnLogin, set up in garrison.lua); they never edit this file.
-- A script reload forgets who is inside but players keep their phase: HealStrays() puts anyone left in one of our bits back to normal.
return function(G)
    local Msg, store, cfg, Say, dbg = G.Msg, G.store, G.cfg, G.Say, G.dbg
    local Loc, active, inside, hub = G.locations.Get, G.active, G.inside, G.cfg.hub
    local arriving = {}   -- player guidLow -> time until which "still outside the radius" is normal (the teleport has not landed yet)
    local asking = {}     -- player guidLow -> time at which an unanswered "leaving your garrison?" prompt counts as Leave
    local pollId = nil

    local function AllocBit(locId)   -- bits are per location: two garrisons in different places can share a bit (too far apart to ever see each other)
        local taken = {}
        for _, h in pairs(active) do if h.loc == locId then taken[h.bit] = true end end
        local loc = Loc(locId)
        for _, b in ipairs(G.locations.FreeBits(loc.map)) do if not taken[b] then return b end end
    end

    local function MyHouse(player)   -- the open garrison the player is standing in, if it is their own
        local owner = inside[player:GetGUIDLow()]
        if owner and owner == player:GetAccountId() and active[owner] then return active[owner], owner end
    end
    local function GroupHasBots(player)
        local grp = player:GetGroup()
        if not grp then return false end
        for _, m in pairs(grp:GetMembers()) do if m and m:IsBot() then return true end end
        return false
    end
    local function SendToHub(player) player:Teleport(hub.map, hub.x, hub.y, hub.z + 1, hub.o) end

    local StartPoll
    local function Enter(player, owner, locId)
        local loc = Loc(locId)
        if not loc then Say(player, "That garrison location is not available."); return end
        local g = player:GetGUIDLow()
        local h = active[owner]
        if not h then
            local bit = AllocBit(locId)
            if not bit then Say(player, "All garrisons here are busy right now, try again in a moment."); return end
            h = { bit = bit, loc = locId, occ = {}, n = 0, spawned = {}, pets = {}, rows = {}, decor = {} }
            active[owner] = h
            for _, row in ipairs(store.LoadLayout(owner, locId)) do G.SpawnOne(h, row) end
            for _, row in ipairs(store.LoadDecor(owner, locId)) do G.SpawnOne(h, row) end
        end
        h.occ[g] = player:GetGUID(); h.n = h.n + 1
        inside[g] = owner
        player:SetPhaseMask(h.bit, true)
        print(string.format("[garrison] %s enters '%s': phase bit %d (mask is now %d)", player:GetName(), loc.name, h.bit, player:GetPhaseMask()))
        arriving[g] = os.time() + cfg.arriveGrace
        -- arrive up to arriveDist yards inside (towards the center), not inside a wall
        local p = loc.portal
        local dx, dy = loc.cx - p.x, loc.cy - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        local ex, ey = p.x, p.y
        if d >= 1 then ex, ey = p.x + dx / d * math.min(cfg.arriveDist, d), p.y + dy / d * math.min(cfg.arriveDist, d) end
        player:Teleport(loc.map, ex, ey, p.z + 1, p.o)
        G.Fire("enter", player, h, owner)
        StartPoll()
    end

    -- reason: nil | "logout" | "died" ... (passed on to the hooks)
    local function Leave(guidLow, player, reason)
        local owner = inside[guidLow]
        if not owner then return end
        inside[guidLow] = nil
        arriving[guidLow], asking[guidLow] = nil, nil
        local h = active[owner]
        if player then
            player:SetPhaseMask(1, true)
            Msg.Send(player, "house", "head", "0")   -- closes an open /garrison window
        end
        if h and h.occ[guidLow] then h.occ[guidLow] = nil; h.n = h.n - 1 end
        G.Fire("leave", guidLow, player, h, reason)
        if h and h.n <= 0 then
            G.Fire("close", h, owner)
            G.DespawnKind(h)
            active[owner] = nil
        end
    end

    -- ---- the once-a-second area check ----
    local function CheckOne(g, owner)   -- one occupant
        local h = active[owner]
        local player = h and h.occ[g] and GetPlayerByGUID(h.occ[g])
        if not player then return Leave(g, nil) end
        local loc, now = Loc(h.loc), os.time()
        if not loc or not player:IsAlive() or player:GetMapId() ~= loc.map then return Leave(g, player, "away") end
        local outside = not G.locations.Inside(loc, player:GetX(), player:GetY())
        if not outside then
            if arriving[g] then   -- the teleport has landed: make sure the phase survived it (log it, put it right if not)
                arriving[g] = nil
                local mask = player:GetPhaseMask()
                if mask ~= h.bit then
                    print(string.format("[garrison] %s arrived with phase mask %d, expected %d: setting it again", player:GetName(), mask, h.bit))
                    player:SetPhaseMask(h.bit, true)
                else
                    print(string.format("[garrison] %s arrived in phase %d as expected", player:GetName(), mask))
                end
            end
            if asking[g] then asking[g] = nil; Msg.Send(player, "house", "leavecancel", "") end   -- walked back in by themselves
            if player:GetPhaseMask() ~= h.bit and not player:IsGM() then
                Leave(g, player, "phase")              -- phase got reset (e.g. .gm off): treat it as having left the garrison
                Say(player, "You have left your garrison.")
            else
                G.Fire("tick", player, h, now)
            end
        elseif arriving[g] then
            if now > arriving[g] then                  -- the teleport never landed inside the area: give up
                Leave(g, player, "away"); SendToHub(player); Say(player, "Could not enter the garrison area.")
            end
        elseif not asking[g] then
            asking[g] = now + cfg.leaveSeconds         -- first second outside: start the countdown (the client shows it), do not move the player yet
            Msg.Send(player, "house", "leaveask", tostring(cfg.leaveSeconds))
        elseif now >= asking[g] or G.locations.OutsideDistance(loc, player:GetX(), player:GetY()) > cfg.leaveLimit then   -- the countdown ran out, or kept running: out to the Mage Tower
            Leave(g, player, "away"); SendToHub(player); Say(player, "You left the garrison area and were returned to the Mage Tower.")
        end
    end
    local function Poll()
        local any = false
        for g, owner in pairs(inside) do
            any = true
            local ok, err = pcall(CheckOne, g, owner)
            if not ok then print("[garrison] poll error: " .. tostring(err)); Leave(g, nil, "error") end
        end
        if not any and pollId then RemoveEventById(pollId); pollId = nil end
    end
    StartPoll = function() if not pollId then pollId = CreateLuaEvent(Poll, 1000, 0) end end

    Msg.On("house", "exit", function(player)   -- the "Exit Garrison" button in the garrison window
        local g = player:GetGUIDLow()
        if not inside[g] then return end
        Leave(g, player, "exit"); SendToHub(player); Say(player, "You left your garrison and were returned to the Mage Tower.")
    end)

    -- ---- login / logout / map change ----
    RegisterPlayerEvent(4, function(event, player)   -- logout: remember it so the next login puts you at the portal, not in the middle of the valley
        local g = player:GetGUIDLow()
        if inside[g] then store.MarkLogout(g) end
        Leave(g, player, "logout")
    end)
    RegisterPlayerEvent(3, function(event, player)   -- login (phase always starts at 1)
        if G.locations.IsOurBit(player:GetMapId(), player:GetPhaseMask()) then player:SetPhaseMask(1, true) end
        local was = store.ConsumeLogout(player:GetGUIDLow())
        G.Fire("login", player, was)
        if not was then return end
        local guid = player:GetGUID()
        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if p then SendToHub(p); Say(p, "You logged out inside your garrison; welcome back to the portal.") end
        end, 2000, 1)
    end)
    RegisterPlayerEvent(28, function(event, player)   -- map change
        local g = player:GetGUIDLow()
        local owner = inside[g]
        local loc = owner and active[owner] and Loc(active[owner].loc)
        if loc and player:GetMapId() ~= loc.map then Leave(g, player, "away") end
    end)
    G.HealStrays = function()   -- called by garrison.lua once everything is installed (after a script reload)
        for _, p in pairs(GetPlayersInWorld() or {}) do
            if p and not inside[p:GetGUIDLow()] and G.locations.IsOurBit(p:GetMapId(), p:GetPhaseMask()) then
                p:SetPhaseMask(1, true)
                G.Fire("stray", p)
            end
        end
    end

    G.Enter, G.Leave, G.MyHouse, G.GroupHasBots, G.SendToHub = Enter, Leave, MyHouse, GroupHasBots, SendToHub
end
