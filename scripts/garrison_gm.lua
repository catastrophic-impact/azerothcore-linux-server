-- Garrison module 14/14 (part 2): GM chat commands (.garrison ...). GM level 2+ for the tuning commands, 3+ for the ones that create or reload locations.
--   .garrison locs | info | phase | markers | status | purge | center | radius <yards> | arrive | rename <name> | addloc <name> | reload
--   shape (GM level 3): addpoint | delpoint | points | poly <tele name prefix> | circle      (a garrison area is a circle, or a polygon of 3+ points)
-- info/center/radius/arrive act on the garrison you stand in, else on the nearest location on this map.
return function(G)
    local Say, Loc, active, inside, store = G.Say, G.locations.Get, G.active, G.inside, G.store

    local function Target(player)
        local h = active[inside[player:GetGUIDLow()] or -1]
        if h and Loc(h.loc) then return Loc(h.loc) end
        local best, bd
        for _, l in ipairs(G.locations.List()) do
            if l.map == player:GetMapId() then
                local d = (player:GetX() - l.cx) ^ 2 + (player:GetY() - l.cy) ^ 2
                if not bd or d < bd then best, bd = l, d end
            end
        end
        return best
    end
    local function Describe(player, loc)
        local dx, dy = player:GetX() - loc.cx, player:GetY() - loc.cy
        Say(player, string.format("[%d] %s: map %d, %s, middle %.1f, %.1f, farthest %.1f, arrival %.1f, %.1f, %.1f, you are %s, %.1f from the middle",
            loc.id, loc.name, loc.map, loc.points and (#loc.points .. "-corner polygon") or "circle", loc.cx, loc.cy, loc.radius, loc.portal.x, loc.portal.y, loc.portal.z,
            G.locations.Inside(loc, player:GetX(), player:GetY()) and "inside" or "outside", math.sqrt(dx * dx + dy * dy)))
    end

    RegisterPlayerEvent(42, function(event, player, command)
        if not player or not command then return end
        local cmd, arg = command:match("^garrison%s*(%a*)%s*(.-)%s*$")
        if not cmd then return end
        local rank = player:GetGMRank()
        if rank < 2 then return end
        if cmd == "locs" then
            for _, l in ipairs(G.locations.List()) do Say(player, string.format("[%d] %s (map %d, radius %.0f)", l.id, l.name, l.map, l.radius)) end
            return false
        elseif cmd == "phase" then   -- proves what the server believes: your phase mask vs the garrison's bit
            local owner = inside[player:GetGUIDLow()]
            local h = owner and active[owner]
            Say(player, string.format("your phase mask: %d, GM mode: %s, inside a garrison: %s%s", player:GetPhaseMask(), tostring(player:IsGM()), h and "yes" or "no",
                h and string.format(" (its bit: %d, %s)", h.bit, player:GetPhaseMask() == h.bit and "you ARE in it" or "you are NOT in it") or ""))
            return false
        elseif cmd == "markers" then   -- the border preview as the engine really holds it (also written to the world log)
            local h = active[inside[player:GetGUIDLow()] or -1]
            if not (h and h.ringIdx) then Say(player, "Switch on \"Show garrison radius\" inside your garrison first."); return false end
            Say(player, (G.RingReport(h):gsub("^%[garrison%] ", "")))
            return false
        elseif cmd == "status" then
            local gar, occ, sp, pets = 0, 0, 0, 0
            for _, h in pairs(active) do gar = gar + 1; occ = occ + h.n; sp = sp + #h.spawned; pets = pets + #h.pets end
            Say(player, string.format("open garrisons %d, occupants %d, tracked NPCs/objects %d, pets %d, registry rows %d (should equal tracked), last audit removed %d",
                gar, occ, sp, pets, store.CountSpawns(), G.LastAudit()))
            return false
        elseif cmd == "purge" then
            Say(player, "Purge: removing every garrison spawn. Everyone inside is moved out first.")
            for g, owner in pairs(inside) do
                local h = active[owner]
                G.Leave(g, h and h.occ[g] and GetPlayerByGUID(h.occ[g]) or nil, "purge")
            end
            G.CleanOrphans(); return false
        elseif cmd == "reload" or cmd == "addloc" then
            if rank < 3 then Say(player, "That needs GM level 3."); return false end
            if cmd == "reload" then G.locations.Reload(); Say(player, "Locations reloaded; garrisons that are open keep their old settings until they close."); return false end
            if arg == "" then Say(player, "Usage: .garrison addloc <name>   (stand where players should appear)"); return false end
            local l = G.locations.Add(arg, player:GetMapId(), player:GetX(), player:GetY(), player:GetZ(), player:GetO())
            Say(player, "Added location " .. l.id .. " '" .. l.name .. "' (radius 100). Tune it with .garrison radius N / center / arrive. It shows at the portal at once.")
            return false
        end
        local loc = Target(player)
        if not loc then Say(player, "No garrison location on this map."); return false end
        local shape = cmd == "addpoint" or cmd == "delpoint" or cmd == "points" or cmd == "poly" or cmd == "circle"
        if shape then
            if rank < 3 and cmd ~= "points" then Say(player, "That needs GM level 3."); return false end
            local pts = loc.points
            if cmd == "points" then
                Say(player, loc.name .. ": " .. (pts and (#pts .. " corner points") or "a circle"))
                for i, p in ipairs(pts or {}) do Say(player, string.format("  %d: %.1f, %.1f", i, p[1], p[2])) end
                return false
            elseif cmd == "circle" then G.locations.SetPoints(loc, nil)
            elseif cmd == "addpoint" then
                pts = pts or {}; pts[#pts + 1] = { player:GetX(), player:GetY() }
                G.locations.SetPoints(loc, pts)   -- fewer than 3 points: kept as a circle until the third arrives
                if #pts < 3 then loc.points = nil; Say(player, "Point " .. #pts .. " noted, but not saved yet: it needs 3 or more (walk around the border and repeat).") ; return false end
            elseif cmd == "delpoint" then
                if not pts then Say(player, "No points."); return false end
                table.remove(pts); G.locations.SetPoints(loc, pts)
            elseif cmd == "poly" then
                if arg == "" then Say(player, "Usage: .garrison poly <tele name prefix>   e.g. teles radius1, radius2, ... -> .garrison poly radius"); return false end
                local list = {}
                for i = 1, 200 do
                    local q = WorldDBQuery(string.format("SELECT map, position_x, position_y FROM game_tele WHERE name='%s%d'", arg:gsub("[^%w_]", ""), i))
                    if not q then break end
                    if q:GetUInt32(0) == loc.map then list[#list + 1] = { q:GetFloat(1), q:GetFloat(2) } end
                end
                if #list < 3 then Say(player, "Found only " .. #list .. " teles named " .. arg .. "1, " .. arg .. "2, ... on this map (need 3).") ; return false end
                G.locations.SetPoints(loc, list)
            end
            if loc.points and not G.locations.Inside(loc, loc.portal.x, loc.portal.y) then Say(player, "|cffff8080Warning: the arrival point is outside this area.|r") end
            G.locations.Save(loc)
            Describe(player, loc)
            return false
        end
        if cmd == "center" then loc.cx, loc.cy = player:GetX(), player:GetY()
        elseif cmd == "radius" and tonumber(arg) then loc.radius = tonumber(arg); G.locations.SetPoints(loc, nil)   -- a radius means a circle again
        elseif cmd == "rename" then
            if rank < 3 or arg == "" then Say(player, "Usage (GM level 3): .garrison rename <new name>"); return false end
            loc.name = arg
        elseif cmd == "arrive" then loc.portal = { x = player:GetX(), y = player:GetY(), z = player:GetZ(), o = player:GetO() }
        elseif cmd ~= "info" then
            Say(player, ".garrison locs | info | phase | markers | status | purge | center | radius <yards> | arrive | rename <name> | addloc <name> | reload | addpoint | delpoint | points | poly <prefix> | circle"); return false
        end
        if cmd ~= "info" then G.locations.Save(loc) end
        Describe(player, loc)
        return false
    end)
end
