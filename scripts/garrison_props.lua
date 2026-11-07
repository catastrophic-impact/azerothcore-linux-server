-- Garrison module 12/14: small helpers around placed things.
--  * pick marker: while you have an item selected on the addon's Placed tab, a Hunter's-Mark arrow floats above it
--  * radius ring: a circle of marker wisps on the garrison edge so the owner can SEE the radius (house|ring 1/0 from the addon checkbox)
--  * used objects (doors etc.): many models vanish on the client after their open animation, so a few seconds after any placed object is used it
--    is removed and spawned again
-- Markers and ring wisps are temporary NPCs tracked in h.pets (the same leak-proof registry as the Menagerie pets).
return function(G)
    local Msg, cfg, Loc, active, MyHouse = G.Msg, G.cfg, G.locations.Get, G.active, G.MyHouse
    local Reg, Unreg, SpawnOne, DespawnKind = G.Reg, G.Unreg, G.SpawnOne, G.DespawnKind
    local MARK_NPC, MARK_SPELL, MARK_SECONDS = cfg.markerNpc, cfg.markerSpell, cfg.markerSeconds

    local function ClearTagged(h, tag)
        for i = #h.pets, 1, -1 do
            local pt = h.pets[i]
            if pt[tag] then
                local map = GetMapById(pt.map, 0)
                local obj = map and map:GetWorldObject(pt.guid)
                if obj then obj:DespawnOrUnsummon(0) end
                Unreg("c", pt.low); table.remove(h.pets, i)
            end
        end
    end

    -- ---- pick marker. payload "<id or kind>,<height>": height = how far above the object's origin its top is (the addon knows the model size)
    Msg.On("house", "mark", function(player, payload)
        local h = MyHouse(player)
        if not h then return end
        local id, top = payload:match("^([%w_]+),([%d%.]+)$")
        local did = id and id:match("^%d+$") and tonumber(id)
        local row = id and (did and h.decor[did] or (not did and h.rows[id]))
        ClearTagged(h, "marker")
        if not row then return end
        top = math.max(0, math.min(tonumber(top) or 2, 40))
        local loc = Loc(h.loc)
        local obj = PerformIngameSpawn(1, MARK_NPC, loc.map, 0, row.x, row.y, row.z + top + 0.5, 0, false, MARK_SECONDS * 1000, h.bit)
        if not obj then return end
        h.pets[#h.pets + 1] = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map, marker = true }   -- track first, configure after
        Reg(obj, "c", loc.map)
        obj:SetPhaseMask(h.bit, true)
        obj:SetReactState(0)
        obj:AddAura(MARK_SPELL, obj)
    end)
    Msg.On("house", "unmark", function(player)
        local h = MyHouse(player)
        if h then ClearTagged(h, "marker") end
    end)

    -- ---- border preview. house|ring 1/0 from the addon checkbox. Marker wisps are spawned along the border only within RING_RANGE yards of
    -- the player (the client cannot see further anyway) and follow the player as they walk: a long border costs nothing.
    local RING_STEP, RING_RANGE, RING_SECONDS = 8, 130, 3600
    local RING_ABOVE = 1.5   -- yards above the ground, or above the water surface where there is water
    local ringOn = {}        -- player guidLow -> { x, y } where the ring was last updated
    -- Height rule: water is flat, so a location learns its water level(s) (waterLevels; a lake and the sea can both be in one area). A marker is at
    --   (nearest known water level above the ground, else the ground) + RING_ABOVE,
    -- i.e. over water exactly the same height everywhere, over land just above the ground. Levels are learned from the engine's own water test
    -- (a marker that is in water is lifted until it is out; the surface is then found to ~0.02 yards); levels within 0.3 yards are one level.
    -- A known level is verified with the engine at each new spot, but a spot the engine calls dry although its floor is below the level (the
    -- map data has no liquid cell there while the client draws water) is trusted to be water.
    local waterLevels = {}   -- location id -> { level, ... }
    local function Levels(locId) waterLevels[locId] = waterLevels[locId] or {}; return waterLevels[locId] end
    local function Above(locId, ground)   -- the known levels above the ground, lowest first
        local out = {}
        for _, L in ipairs(Levels(locId)) do if L > ground then out[#out + 1] = L end end
        table.sort(out)
        return out
    end
    local function Learn(locId, s, x, y)   -- remember a level (merging near-equal ones); returns the level to use
        for _, L in ipairs(Levels(locId)) do if math.abs(L - s) <= 0.3 then return L end end
        table.insert(Levels(locId), s)
        print(string.format("[garrison] border markers: water surface at %.2f (location %d, near %.0f, %.0f)", s, locId, x, y))
        return s
    end
    local function FindSurface(obj, x, y, z)   -- obj is in water at z: climb until out of it, then halve the gap
        local function inWater(zz) obj:NearTeleport(x, y, zz, 0); return obj:IsInWater() end
        local lo, hi, n = z, z + 2, 0
        while inWater(hi) and n < 40 do lo, hi, n = hi, hi + 2, n + 1 end
        if n >= 40 then return nil end
        for _ = 1, 7 do local mid = (lo + hi) / 2; if inWater(mid) then lo = mid else hi = mid end end
        return hi
    end
    -- puts the marker (any height) where it belongs; returns its height and whether it is over water
    local function Settle(obj, locId, x, y, ground)
        local function inWater(zz) obj:NearTeleport(x, y, zz, 0); return obj:IsInWater() end
        local function put(zz, wet) obj:NearTeleport(x, y, zz, 0); return zz, wet end
        local cands = Above(locId, ground)
        for _, L in ipairs(cands) do   -- the water here is the known level whose surface the engine confirms (in water just below it, out of it just above)
            if inWater(L - 0.5) and not inWater(L + 0.5) then return put(L + RING_ABOVE, true) end
        end
        if #cands > 0 then
            if not inWater(ground + RING_ABOVE) then return put(cands[1] + RING_ABOVE, true) end   -- no water found at all: missing liquid data, trust the lowest level above the floor
        elseif not inWater(ground + RING_ABOVE) then
            return put(ground + RING_ABOVE, false)                                           -- dry land
        end
        local s = FindSurface(obj, x, y, ground + RING_ABOVE)                                -- water at a level we have not seen: find it
        if not s then return put(ground + RING_ABOVE, false) end
        return put(Learn(locId, s, x, y) + RING_ABOVE, true)
    end
    local function Report(h, why)   -- what the markers REALLY are: read back from the world (positions the engine kept), summed up in the log
        local n, lo, hi, wet, wlo, whi = 0, 1e9, -1e9, 0, 1e9, -1e9
        for _, pt in pairs(h.ringIdx or {}) do
            local m = GetMapById(pt.map, 0)
            local obj = m and m:GetWorldObject(pt.guid)
            if obj then
                local z = obj:GetZ()
                n = n + 1; lo, hi = math.min(lo, z), math.max(hi, z)
                if pt.water then wet = wet + 1; wlo, whi = math.min(wlo, z), math.max(whi, z) end
            end
        end
        local line = string.format("[garrison] border markers (%s): %d alive, z %.2f..%.2f; over water: %d, z %.2f..%.2f; water surface(s) %s", why, n,
            n > 0 and lo or 0, n > 0 and hi or 0, wet, wet > 0 and wlo or 0, wet > 0 and whi or 0, table.concat(Levels(h.loc), ", "))
        print(line)
        return line
    end
    G.RingReport = function(h) return Report(h, "now") end
    local function RingUpdate(player, h)
        local loc = Loc(h.loc)
        local map = GetMapById(loc.map, 0)
        h.ringEdge = h.ringEdge or G.locations.EdgePoints(loc, RING_STEP)
        h.ringIdx = h.ringIdx or {}
        local px, py, pz = player:GetX(), player:GetY(), player:GetZ()
        local want = {}
        for i, e in ipairs(h.ringEdge) do
            if (e[1] - px) ^ 2 + (e[2] - py) ^ 2 <= RING_RANGE * RING_RANGE then want[i] = true end
        end
        for i, pt in pairs(h.ringIdx) do   -- too far now (or already gone, e.g. the pets were re-rolled): forget it
            local m = GetMapById(pt.map, 0)
            local obj = m and m:GetWorldObject(pt.guid)
            if obj and want[i] then
                -- still there and still wanted
            else
                if obj then obj:DespawnOrUnsummon(0) end
                Unreg("c", pt.low)
                for k = #h.pets, 1, -1 do if h.pets[k] == pt then table.remove(h.pets, k) end end
                h.ringIdx[i] = nil
            end
        end
        local spawned = 0
        for i in pairs(want) do   -- new in range: spawn
            if not h.ringIdx[i] then
                local e = h.ringEdge[i]
                local ground = map and map:GetHeight(e[1], e[2], 1)
                if not ground or ground < -1000 then ground = pz end   -- no terrain data there: use the player's height
                local obj = PerformIngameSpawn(1, MARK_NPC, loc.map, 0, e[1], e[2], ground + RING_ABOVE, 0, false, RING_SECONDS * 1000, h.bit)
                if obj then
                    local pt = { guid = obj:GetGUID(), low = obj:GetGUIDLow(), map = loc.map, ring = true, water = false, ground = ground, x = e[1], y = e[2] }   -- track first, configure after
                    h.pets[#h.pets + 1] = pt; h.ringIdx[i] = pt
                    Reg(obj, "c", loc.map)
                    obj:SetPhaseMask(h.bit, true)
                    obj:SetReactState(0)
                    pcall(obj.SetDisableGravity, obj, true)    -- hangs in the air at exactly this height
                    local known = #Levels(loc.id)
                    pt.z, pt.water = Settle(obj, loc.id, e[1], e[2], ground)
                    if #Levels(loc.id) > known then   -- a new water level was found: markers placed earlier as "dry" below it may belong to it
                        for _, other in pairs(h.ringIdx) do
                            if not other.water and other.ground < Levels(loc.id)[#Levels(loc.id)] then
                                local m = GetMapById(other.map, 0)
                                local o = m and m:GetWorldObject(other.guid)
                                if o then other.z, other.water = Settle(o, loc.id, other.x, other.y, other.ground) end
                            end
                        end
                    end
                    spawned = spawned + 1
                end
            end
        end
        if spawned > 0 then CreateLuaEvent(function() if h.ringIdx then pcall(Report, h, "2 s after spawning") end end, 2000, 1) end
        ringOn[player:GetGUIDLow()] = { px, py }
    end
    local function RingOff(h)
        ClearTagged(h, "ring")
        h.ringIdx = nil
    end
    Msg.On("house", "ring", function(player, payload)
        local h = MyHouse(player)
        if not h then return end
        RingOff(h)
        if payload == "1" then RingUpdate(player, h) else ringOn[player:GetGUIDLow()] = nil end
    end)
    G.OnTick(function(player, h)   -- follow the player: refresh once they moved 20 yards
        local last = ringOn[player:GetGUIDLow()]
        if last and (player:GetX() - last[1]) ^ 2 + (player:GetY() - last[2]) ^ 2 > 400 then RingUpdate(player, h) end
    end)
    G.OnLeave(function(guidLow) ringOn[guidLow] = nil end)
    G.OnClose(function(h) h.ringIdx, h.ringEdge = nil, nil end)
    -- on every entry the client re-sends its "Show garrison radius" checkbox, so the preview is back after leaving and coming in again
    G.OnEnter(function(player, h, owner) if player:GetAccountId() == owner then Msg.Send(player, "house", "ringreq", "") end end)

    -- ---- used objects. ANIMS: entry -> { open ms, close ms, autoclose ms } (generated by claude_tools/door_anims.py)
    local RESET_MS = 4000   -- used when the model has no Open animation
    local ANIMS = require("garrison_anims")
    local function Closes(entry) local a = ANIMS[entry]; return a and a[3] > 0 end   -- door closes by itself (autoclose): only these vanish
    local function ResetDelay(entry)   -- closing doors: wait for open -> autoclose -> close animation; everything else: fixed delay
        local a = ANIMS[entry]
        return Closes(entry) and math.max(1500, math.min(10000, a[3] + a[2] + 500)) or RESET_MS
    end
    local function FindSpawn(guid)
        for _, h in pairs(active) do
            for _, s in ipairs(h.spawned) do if s.guid == guid then return h, s end end
        end
    end
    local function ResetUsed(guid)
        local h, s = FindSpawn(guid)
        if not h then return end
        local map = GetMapById(s.map, 0)
        local obj = map and map:GetWorldObject(guid)
        if not obj then return end
        local state = obj:GetGoState()
        print(string.format("[garrison] used object kind=%s state=%d%s", s.kind, state, (state ~= 1 or Closes(obj:GetEntry())) and " -> reset" or " (unchanged)"))
        if state == 1 and not Closes(obj:GetEntry()) then return end   -- closing doors are reset even though the server says closed (the vanish is client-side)
        local row = s.did and h.decor[s.did] or h.rows[s.kind]
        if not row then return end
        if s.did then DespawnKind(h, nil, s.did) else DespawnKind(h, s.kind) end
        SpawnOne(h, row)
    end
    local hooked = {}
    for _, def in pairs(G.BY_KIND) do
        if def.t == "g" and not hooked[def.entry] then
            hooked[def.entry] = true
            RegisterGameObjectEvent(def.entry, 14, function(event, go, player)   -- GAMEOBJECT_EVENT_ON_USE; no return = normal use still happens
                local guid = go:GetGUID()
                CreateLuaEvent(function() ResetUsed(guid) end, ResetDelay(go:GetEntry()), 1)
            end)
        end
    end
end
