-- Garrison module: wildlife. Placed creature decor (catalog items with wild = true, tab "Creatures") are harmless immortal beasts (templates 940001+, custom-sql/015:
-- friendly, non-attackable, immune). They are placed, moved and removed exactly like decor; this part only makes them LIVE: they walk, never run, rest 8-30 s,
-- then (60%) amble to a random spot within wildLeash yards of the spot they were placed at. One global 2 s timer, nothing per creature.
return function(G)
    local cfg, Loc, BY_KIND, active = G.cfg, G.locations.Get, G.BY_KIND, G.active
    local LEASH, REST_MIN, REST_MAX, CHANCE, TICK_MS = cfg.wildLeash, 8, 30, 0.6, 2000

    local function Tick()
        local now = os.time()
        for _, h in pairs(active) do
            if next(h.occ) then   -- nobody inside = nobody to see them: no work
                local loc = Loc(h.loc)
                for _, sp in ipairs(h.spawned) do
                    local def = BY_KIND[sp.kind]
                    if def and def.wild and sp.did then
                        local map = GetMapById(sp.map, 0)
                        local obj = map and map:GetWorldObject(sp.guid)
                        local row = h.decor[sp.did]
                        if obj and row then
                            if not sp.inited then   -- first look: passive, walking pace, first stroll after a short random pause
                                sp.inited = true; sp.nxt = now + math.random(2, 12)
                                pcall(function() obj:SetReactState(0) end)
                                pcall(function() obj:SetWalk(true) end)
                            elseif now >= sp.nxt then
                                sp.nxt = now + math.random(REST_MIN, REST_MAX)
                                if math.random() < CHANCE then
                                    local ang, dist = math.random() * 6.2832, 1 + math.random() * (LEASH - 1)
                                    local tx, ty = row.x + math.cos(ang) * dist, row.y + math.sin(ang) * dist
                                    if G.InsideArea(loc, tx, ty) then
                                        local tz = G.GroundZ(loc, tx, ty, obj:GetZ())
                                        pcall(function() obj:SetHomePosition(tx, ty, tz, obj:GetO()) end)
                                        pcall(function() obj:MoveTo(1, tx, ty, tz, false) end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    CreateLuaEvent(function() local ok, err = pcall(Tick); if not ok then print("[garrison] wildlife tick error: " .. tostring(err)) end end, TICK_MS, 0)
end
