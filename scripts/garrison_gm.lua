-- Garrison module 14/14 (part 2): GM chat commands (.garrison ...). GM level 2+ for the inspection commands, 3+ for the ones that create or reload locations.
--   .garrison locs | info | phase | markers | status | purge | rename <name> | addloc <name> | reload
--   shape (GM level 3): addpoint | delpoint | points | clearpoints      (an area is a outline of 3+ points traced in order; a brand-new location is a temporary circle until it has 3)
-- info/rename act on the garrison you stand in, else on the nearest location on this map.
return function(G)
    local Say, Loc, active, inside, store = G.Say, G.locations.Get, G.active, G.inside, G.store
    local pending = {}   -- location id -> outline points collected by .garrison addpoint but not saved yet (fewer than 3)

    local HELP = {
        "|cffffd100Garrison commands|r  (.garrison <option>)",
        "  |cff66ccffLooking around|r (GM level 2)",
        "  locs - list all garrison locations",
        "  info - details of the garrison you stand in (or the nearest location on this map)",
        "  points - the outline points of that location",
        "  status - open garrisons, occupants, tracked objects",
        "  decor - decor count of the garrison you stand in: in memory (what the limit uses) vs the database",
        "  phase - your phase vs the garrison's phase bit",
        "  markers - report on the border markers (Show garrison radius)",
        "  purge - remove every garrison spawn, everyone inside is moved out",
        "  |cff66ccffMaking and shaping locations|r (GM level 3)",
        "  addloc <name> - new location where you stand (players arrive here)",
        "  addpoint - add your spot as the next outline point (3 or more; walk the border in order)",
        "  delpoint - remove the last outline point",
        "  clearpoints - remove all outline points of the location",
        "  rename <name> - rename the location",
        "  reload - reload the locations from the database",
        "  help - this list",
    }

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
            loc.id, loc.name, loc.map, loc.points and (#loc.points .. "-point outline") or "circle", loc.cx, loc.cy, loc.radius, loc.portal.x, loc.portal.y, loc.portal.z,
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
        elseif cmd == "decor" then   -- what the placement limit counts, against what is stored
            local owner = inside[player:GetGUIDLow()]
            local h = owner and active[owner]
            if not h then Say(player, "Stand inside a garrison first."); return false end
            local mem, perKind, spawnedDecor = 0, {}, 0
            for _, r in pairs(h.decor) do mem = mem + 1; perKind[r.kind] = (perKind[r.kind] or 0) + 1 end
            for _, sp in ipairs(h.spawned) do if sp.did then spawnedDecor = spawnedDecor + 1 end end
            local top, topN = "-", 0
            for k, n in pairs(perKind) do if n > topN then top, topN = k, n end end
            local rows = store.LoadDecor(owner, h.loc)
            local unknown = 0
            for _, r in ipairs(rows) do if not G.BY_KIND[r.kind] then unknown = unknown + 1 end end
            Say(player, string.format("decor in memory (the limit counts this): %d of %d; spawned in the world: %d; most of one item: %s x%d; database rows: %d (%d of an unknown kind: stored, not counted)",
                mem, G.cfg.maxDecor, spawnedDecor, top, topN, #rows, unknown))
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
            Say(player, "Added location " .. l.id .. " '" .. l.name .. "' (radius 100). Walk the border and use .garrison addpoint at each spot, in order (3 or more). It shows at the portal at once.")
            return false
        end
        if cmd == "" or cmd == "help" then   -- the command list needs no location
            for _, l in ipairs(HELP) do Say(player, l) end
            return false
        end
        local loc = Target(player)
        if not loc then Say(player, "No garrison location on this map."); return false end
        local shape = cmd == "addpoint" or cmd == "delpoint" or cmd == "points" or cmd == "clearpoints"
        if shape then
            if rank < 3 and cmd ~= "points" then Say(player, "That needs GM level 3."); return false end
            -- outline points are collected here until there are 3 (an area needs at least 3); from then on they are saved at once
            local pts = loc.points or pending[loc.id]
            if cmd == "points" then
                Say(player, loc.name .. ": " .. (loc.points and (#loc.points .. " outline points (saved)") or (pending[loc.id] and (#pending[loc.id] .. " outline points collected, not saved yet (need 3)") or "no outline points yet (temporary circle)")))
                for i, p in ipairs(pts or {}) do Say(player, string.format("  %d: %.1f, %.1f", i, p[1], p[2])) end
                return false
            elseif cmd == "clearpoints" then
                pending[loc.id] = nil
                G.locations.SetPoints(loc, nil)
                Say(player, loc.name .. ": all outline points removed. The area is a temporary circle until you add 3 or more points (.garrison addpoint).")
            elseif cmd == "addpoint" then
                local list = loc.points or pending[loc.id] or {}
                list[#list + 1] = { player:GetX(), player:GetY() }
                if loc.points or #list >= 3 then
                    pending[loc.id] = nil
                    G.locations.SetPoints(loc, list)
                else
                    pending[loc.id] = list
                    Say(player, "Point " .. #list .. " noted (not saved yet: an outline needs 3 or more). Walk along the border to the next spot and repeat; the last point joins back to the first.")
                    return false
                end
            elseif cmd == "delpoint" then
                if not pts or #pts == 0 then Say(player, "No points."); return false end
                table.remove(pts)
                if loc.points then G.locations.SetPoints(loc, pts) else pending[loc.id] = pts end   -- below 3 points a saved area becomes a circle again
            end
            if loc.points and not G.locations.Inside(loc, loc.portal.x, loc.portal.y) then Say(player, "|cffff8080Warning: the arrival point is outside this area.|r") end
            G.locations.Save(loc)
            Describe(player, loc)
            return false
        end
        -- (.garrison center / radius / arrive were removed on purpose: every player shares a location's area, so it is only changed together with the developer)
        if cmd == "rename" then
            if rank < 3 or arg == "" then Say(player, "Usage (GM level 3): .garrison rename <new name>"); return false end
            loc.name = arg
        elseif cmd ~= "info" then
            Say(player, "Unknown option '" .. cmd .. "'. Type .garrison help for the list."); return false
        end
        if cmd ~= "info" then G.locations.Save(loc) end
        Describe(player, loc)
        return false
    end)
end
