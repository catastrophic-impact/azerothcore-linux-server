-- Garrison module 6/14: everything that puts NPCs / objects into the world for a garrison, and keeps the world and our records in step.
--  * every temporary spawn is recorded in dc_garrison_spawn, so a script reload or crash can never leave orphans (cleaned at load + every 5 minutes)
--  * the "entry check" runs whenever someone enters: tracked-but-gone things are respawned, our own untracked strays are removed
--  h (an open garrison) = { bit, loc, occ = {guidLow = ObjectGuid}, n, spawned = { {kind, did, t, guid, low, map} }, pets = {...}, rows = {kind = row}, decor = {did = row} }
return function(G)
    local store, Loc, BY_KIND, active = G.store, G.locations.Get, G.BY_KIND, G.active

    local function Reg(obj, t, map) store.RegSpawn(obj:GetGUIDLow(), t, obj:GetEntry(), map) end
    local function Unreg(t, low) store.UnregSpawn(t, low) end

    -- tracked = set of "<t><low>" still owned by a live garrison (audit mode); nil = clean everything (script load)
    local function CleanOrphans(tracked)
        local cleaned = 0
        for _, r in ipairs(store.ListSpawns()) do
            if not (tracked and tracked[r.t .. r.low]) then
                cleaned = cleaned + 1
                local map = GetMapById(r.map, 0)
                local obj = map and map:GetWorldObject(r.t == "g" and GetObjectGUID(r.low, r.entry) or GetUnitGUID(r.low, r.entry))
                if obj then if r.t == "g" then obj:RemoveFromWorld(false) else obj:DespawnOrUnsummon(0) end end
                if tracked then Unreg(r.t, r.low) end
            end
        end
        if not tracked then store.ClearSpawns() end
        return cleaned
    end
    CleanOrphans()   -- first thing on every (re)load

    local function SpawnOne(h, row)
        local def = BY_KIND[row.kind]
        if not def then return end
        local loc = Loc(h.loc)
        local obj = PerformIngameSpawn(def.t == "g" and 2 or 1, def.entry, loc.map, 0, row.x, row.y, row.z, row.o, false, 0, h.bit)
        if not obj then return end
        -- record it first: whatever happens next, it can always be found and removed again
        h.spawned[#h.spawned + 1] = { kind = row.kind, did = row.did, t = def.t, guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map }
        Reg(obj, def.t, loc.map)
        if row.did then h.decor[row.did] = row else h.rows[row.kind] = row end
        obj:SetPhaseMask(h.bit, true)   -- non-saved creature spawns ignore the phase argument
        if def.t ~= "g" then pcall(function() obj:SetFaction(35) end) end   -- stock trainers / vendors keep their Alliance or Horde faction: red names and no interaction for the other side. 35 = friendly to all
    end

    local function DespawnKind(h, kind, did)   -- kind = one single kind, did = one decor instance, neither = everything
        for i = #h.spawned, 1, -1 do
            local s = h.spawned[i]
            if (not kind and not did) or (kind and not s.did and s.kind == kind) or (did and s.did == did) then
                local map = GetMapById(s.map, 0)
                local obj = map and map:GetWorldObject(s.guid)
                if obj then
                    if s.t == "g" then obj:RemoveFromWorld(false) else obj:DespawnOrUnsummon(0) end
                end
                Unreg(s.t, s.low)
                table.remove(h.spawned, i)
            end
        end
    end

    -- ---- entry check: what the world REALLY holds in this garrison's phase vs what we track ----
    -- 1) tracked but gone  -> placed NPCs/objects are respawned, pets are dropped from the list
    -- 2) in the world, in this phase, one of OUR entries, but not tracked -> stray: removed
    -- (only our own entries with no owner are ever touched, so a player's own companion pet, totem or ritual is safe)
    G.COMPANIONS = store.CompanionMap()
    local OURS_C, OURS_G = {}, {}
    for _, c in ipairs(G.CATALOG) do if c.t == "g" then OURS_G[c.entry] = true else OURS_C[c.entry] = true end end
    for _, npc in pairs(G.COMPANIONS) do OURS_C[npc] = true end

    local function Verify(h, player)
        local loc = Loc(h.loc)
        local map = GetMapById(loc.map, 0)
        local fixed, removed = 0, 0
        for i = #h.spawned, 1, -1 do
            local sp = h.spawned[i]
            if not (map and map:GetWorldObject(sp.guid)) then
                local row = sp.did and h.decor[sp.did] or (not sp.did and h.rows[sp.kind])
                Unreg(sp.t, sp.low); table.remove(h.spawned, i)
                if row then SpawnOne(h, row); fixed = fixed + 1 end
            end
        end
        for i = #h.pets, 1, -1 do
            local pt = h.pets[i]
            if not (map and map:GetWorldObject(pt.guid)) then Unreg("c", pt.low); table.remove(h.pets, i) end
        end
        local tracked = {}
        for _, sp in ipairs(h.spawned) do tracked[sp.t .. sp.low] = true end
        for _, pt in ipairs(h.pets) do tracked["c" .. pt.low] = true end
        local range = loc.radius * 2 + 20
        for _, c in pairs(player:GetCreaturesInRange(range, 0, 0, 0) or {}) do
            if c:GetPhaseMask() == h.bit and OURS_C[c:GetEntry()] and not c:GetOwner() and not tracked["c" .. c:GetGUIDLow()] then
                c:DespawnOrUnsummon(0); removed = removed + 1
            end
        end
        for _, o in pairs(player:GetGameObjectsInRange(range, 0, 0) or {}) do
            if o:GetPhaseMask() == h.bit and OURS_G[o:GetEntry()] and not tracked["g" .. o:GetGUIDLow()] then
                o:RemoveFromWorld(false); removed = removed + 1
            end
        end
        if fixed > 0 or removed > 0 then print(string.format("[garrison] entry check: respawned %d missing, removed %d stray", fixed, removed)) end
    end
    G.OnEnter(function(player, h) Verify(h, player) end)

    -- ---- safety net: every 5 minutes any registered spawn that no live garrison owns is removed (should always find nothing) ----
    local lastAudit = 0
    local function Audit()
        local tracked = {}
        for _, h in pairs(active) do
            for _, sp in ipairs(h.spawned) do tracked[sp.t .. sp.low] = true end
            for _, pt in ipairs(h.pets) do tracked["c" .. pt.low] = true end
        end
        lastAudit = CleanOrphans(tracked) or 0
        if lastAudit > 0 then print("[garrison] audit removed " .. lastAudit .. " orphaned spawn(s)") end
    end
    CreateLuaEvent(Audit, 300000, 0)

    G.Reg, G.Unreg, G.CleanOrphans, G.SpawnOne, G.DespawnKind = Reg, Unreg, CleanOrphans, SpawnOne, DespawnKind
    G.LastAudit = function() return lastAudit end
end
