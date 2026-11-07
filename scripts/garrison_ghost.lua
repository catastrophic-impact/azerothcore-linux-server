-- Garrison module 10/14: placement mode. A solid, NON-saved "ghost" of the item floats dist yards in front of you (re-created 4x a second only when it moved).
-- Enter/Place = pconfirm puts the real item exactly there (price charged THEN); Esc/Cancel = pcancel. The ghost is not in dc_garrison_spawn and
-- is never saved, so a crash/restart removes it. It always ends when you leave the garrison, log out, change map or after GHOST_SECONDS.
-- Controls (client PlaceMode.lua): walk/turn to aim, Turn L/R (prot), Nearer/Further (pdist), Up/Down (pup, height above the ground).
return function(G)
    local Msg, Loc, BY_KIND, MyHouse = G.Msg, G.locations.Get, G.BY_KIND, G.MyHouse
    local GroundZ, InsideArea = G.GroundZ, G.InsideArea
    local GHOST_SECONDS, GHOST_MS = 300, 250
    local STILL_TICKS = 4   -- 4 x 250 ms without movement before the preview appears
    local ghosts, ghostEv = {}, nil   -- ghosts[playerGuidLow] = { kind, pguid, dist, rot, dz, guid, map, x, y, z, o, ok, t0, beat }

    local function GhostKill(g)   -- look the object up again by GUID (a held pointer goes stale); never errors
        if not g.guid then return end
        local guid, map = g.guid, g.map and GetMapById(g.map, 0)
        g.guid = nil
        local obj = map and map:GetWorldObject(guid)
        if obj then obj:RemoveFromWorld(false) end
    end
    local function GhostStop(low, player, msg)
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
        local z, go = GroundZ(loc, x, y, p:GetZ()) + g.dz, (o + math.pi + g.rot) % (2 * math.pi)
        local ok = InsideArea(loc, x, y)
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
    local function GhostTick()
        for low, g in pairs(ghosts) do
            if not pcall(GhostUpdate, low, g) then
                print("[garrison] placement ghost error, ending it")
                GhostStop(low, GetPlayerByGUID(g.pguid), "Placement ended (error).")
            end
        end
    end

    Msg.On("house", "pstart", function(player, kind)
        local h = MyHouse(player)
        local low = player:GetGUIDLow()
        if not h then return Msg.Send(player, "house", "res", "You must be inside your own garrison to place things.") end
        local def = BY_KIND[kind]
        if not G.CanPlace(player, def) then return Msg.Send(player, "house", "res", "Unknown decor item.") end
        local why = G.DecorLimit(h, kind)
        if why then return Msg.Send(player, "house", "res", why) end
        GhostStop(low)   -- replaces a running one
        ghosts[low] = { kind = kind, pguid = player:GetGUID(), dist = 6, rot = 0, dz = 0, t0 = os.time(), x = 0, y = 0, z = 0, o = 0 }
        if not ghostEv then ghostEv = CreateLuaEvent(GhostTick, GHOST_MS, 0) end
        Msg.Send(player, "house", "pstart", kind)
    end)
    -- The client tells us the moment its character stops (addon PlaceMode.lua): show the ghost now instead of waiting for STILL_TICKS quiet ticks.
    Msg.On("house", "pstill", function(player)
        local low = player:GetGUIDLow(); local g = ghosts[low]; if not g then return end
        g.px, g.py, g.po, g.still = player:GetX(), player:GetY(), player:GetO(), STILL_TICKS - 1   -- "unchanged since the last look", one quiet tick short
        if not pcall(GhostUpdate, low, g) then GhostStop(low, player, "Placement ended (error).") end
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
    Msg.On("house", "pup", function(player, amount)   -- relative change of the height above the ground in yards, clamped -5..20 (negative = sunk into the ground)
        local g = ghosts[player:GetGUIDLow()]; local n = tonumber(amount)
        if g and n then g.dz = math.max(-5, math.min(20, g.dz + math.max(-5, math.min(5, n)))) end
    end)
    Msg.On("house", "pconfirm", function(player)
        local low = player:GetGUIDLow()
        local g, h, owner = ghosts[low], G.MyHouse(player)
        if not g then return end
        if not h then return GhostStop(low, player, "Placement ended.") end
        if not g.guid then return Msg.Send(player, "house", "res", "Wait a moment, the preview is still appearing.") end
        if not g.ok then return Msg.Send(player, "house", "res", "That spot is outside your garrison.") end
        if G.PlaceDecorAt(player, h, owner, g.kind, BY_KIND[g.kind], g.x, g.y, g.z, g.o) then GhostStop(low, player, "")
        end   -- not placed (cannot afford, limit): the ghost stays so you can cancel or fix it
    end)
    RegisterPlayerEvent(4, function(event, player) GhostStop(player:GetGUIDLow()) end)    -- logout
    RegisterPlayerEvent(28, function(event, player) GhostStop(player:GetGUIDLow()) end)   -- map change
    G.OnLeave(function(guidLow, player) GhostStop(guidLow, player, "You left your garrison.") end)
    G.GhostStop = GhostStop
end
