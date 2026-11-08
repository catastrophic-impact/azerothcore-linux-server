-- Garrison module 5/14: WHERE garrisons are, and which phase bits they may use.
--  * Locations live in the WORLD database (table garrison_location, created here, seeded with the two built-in ones) so adding one needs no code:
--      stand where players should appear and type   .garrison addloc <name>      (GM level 3; then walk the border with .garrison addpoint along the border, in order)
--    New locations show up at the portal after   .garrison reload   (garrisons that are already open are not touched).
--  * Shape: a circle (cx, cy, radius) or, when it has 3+ boundary points, a polygon (world table garrison_location_point). Everything that
--    asks "is this spot inside?" calls L.Inside(loc, x, y); for a polygon cx, cy, radius are DERIVED (middle and farthest outline point) and only
--    used as a bounding circle (visibility range of the entry check, nearest-location lookup).
--      .garrison addpoint (append your spot) | delpoint | points | clearpoints
--  * An owner whose location row is missing keeps their data; the portal just treats them as having no garrison until the row is back.
--  * Phase bits: every bit not used by a stock creature/gameobject spawn on the location's map (scanned from the world database).
--    Bits are handed out per location (see garrison_session.lua), so far-apart garrisons can share one.
return function(G)
    local L = {}
    G.locations = L
    local byId = {}

    -- seeded when the table is empty (a fresh install): id, name, map, cx, cy, radius, arrival x, y, z, o, outline points of the area (nil = circle)
    local DEFAULTS = {
        { 1, "Northshire Abbey", 0, -8940.0, -115.0, 119.0, -9036.052, -55.42181, 89.495094, 6.0482984,
          { { -9031.57, 7.96 }, { -9048.98, -101.79 }, { -9124.59, -193.84 }, { -8980.17, -341.57 }, { -8795.14, -400.64 }, { -8677.91, -199.0 }, { -8663.63, -44.88 }, { -8880.75, 21.58 }, { -8952.43, -3.68 }, { -9031.49, 12.5 } } },
        { 2, "Arathi Shore", 0, -1777.2, -4121.4, 276.0, -1860.9, -4148.67, 9.61398, 3.23143,
          { { -1569.75, -4232.62 }, { -1679.4, -4320.1 }, { -1784.83, -4309.21 }, { -1863.12, -4261.71 }, { -1955.67, -4199.95 }, { -2017.11, -4109.82 }, { -2024.02, -4022.91 }, { -1911.01, -4033.95 }, { -1831.35, -4044.2 }, { -1530.37, -4220.01 } } },
        { 3, "Fenris Isle", 0, 885.9, 583.0, 347.8, 949.49, 689.13, 59.74, 3.169,
          { { 1061.61, 809.58 }, { 966.19, 829.66 }, { 805.87, 770.43 }, { 706.47, 780.77 }, { 582.93, 625.31 }, { 587.1, 411.45 }, { 664.5, 314.75 }, { 728.66, 380.11 }, { 748.23, 534.11 }, { 1062.22, 494.76 }, { 1079.46, 382.68 }, { 1149.13, 421.83 }, { 1180.17, 589.98 }, { 1079.72, 816.7 } } },
    }
    local function Q(s) return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "''") .. "'" end

    local function Init()
        WorldDBQuery("CREATE TABLE IF NOT EXISTS garrison_location (id INT UNSIGNED NOT NULL, name VARCHAR(60) NOT NULL, map INT UNSIGNED NOT NULL, " ..
            "cx FLOAT NOT NULL, cy FLOAT NOT NULL, radius FLOAT NOT NULL, ax FLOAT NOT NULL, ay FLOAT NOT NULL, az FLOAT NOT NULL, ao FLOAT NOT NULL, " ..
            "enabled TINYINT NOT NULL DEFAULT 1, PRIMARY KEY (id)) ENGINE=InnoDB")
        WorldDBQuery("CREATE TABLE IF NOT EXISTS garrison_location_point (location INT UNSIGNED NOT NULL, seq INT UNSIGNED NOT NULL, x FLOAT NOT NULL, y FLOAT NOT NULL, PRIMARY KEY (location, seq)) ENGINE=InnoDB")
        local q = WorldDBQuery("SELECT COUNT(*) FROM garrison_location")
        if q and q:GetUInt32(0) == 0 then
            for _, d in ipairs(DEFAULTS) do
                WorldDBExecute(string.format("INSERT INTO garrison_location (id,name,map,cx,cy,radius,ax,ay,az,ao) VALUES (%d,%s,%d,%f,%f,%f,%f,%f,%f,%f)",
                    d[1], Q(d[2]), d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10]))
                for i, pt in ipairs(d[11] or {}) do
                    WorldDBExecute(string.format("INSERT IGNORE INTO garrison_location_point (location, seq, x, y) VALUES (%d,%d,%f,%f)", d[1], i, pt[1], pt[2]))
                end
            end
        end
    end

    local function Bounds(l)   -- polygon: derive the bounding circle from the outline points
        local pts = l.points
        if not pts or #pts < 3 then return end
        local sx, sy = 0, 0
        for _, p in ipairs(pts) do sx, sy = sx + p[1], sy + p[2] end
        l.cx, l.cy = sx / #pts, sy / #pts
        local r = 0
        for _, p in ipairs(pts) do r = math.max(r, math.sqrt((p[1] - l.cx) ^ 2 + (p[2] - l.cy) ^ 2)) end
        l.radius = r
    end

    function L.Reload()
        local fresh = {}
        local q = WorldDBQuery("SELECT id, name, map, cx, cy, radius, ax, ay, az, ao, enabled FROM garrison_location")
        if q then repeat
            local id = q:GetUInt32(0)
            fresh[id] = { id = id, name = q:GetString(1), map = q:GetUInt32(2), cx = q:GetFloat(3), cy = q:GetFloat(4), radius = q:GetFloat(5),
                portal = { x = q:GetFloat(6), y = q:GetFloat(7), z = q:GetFloat(8), o = q:GetFloat(9) }, enabled = q:GetUInt32(10) ~= 0 }
        until not q:NextRow() end
        if next(fresh) == nil then   -- the table could not be read: keep what we had (or the built-in ones on the first load)
            if next(byId) ~= nil then print("[garrison] garrison_location could not be read, keeping the current list"); return end
            for _, d in ipairs(DEFAULTS) do
                fresh[d[1]] = { id = d[1], name = d[2], map = d[3], cx = d[4], cy = d[5], radius = d[6], portal = { x = d[7], y = d[8], z = d[9], o = d[10] }, enabled = true, points = d[11] }
            end
        end
        local pq = WorldDBQuery("SELECT location, x, y FROM garrison_location_point ORDER BY location, seq")
        if pq then repeat
            local l = fresh[pq:GetUInt32(0)]
            if l then l.points = l.points or {}; l.points[#l.points + 1] = { pq:GetFloat(1), pq:GetFloat(2) } end
        until not pq:NextRow() end
        for _, l in pairs(fresh) do Bounds(l) end
        byId = fresh
    end
    function L.Get(id) return byId[id] end
    function L.List()   -- enabled locations, by id
        local out = {}
        for _, l in pairs(byId) do if l.enabled then out[#out + 1] = l end end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end
    -- is the spot inside the garrison area?
    function L.Inside(l, x, y)
        local pts = l.points
        if pts and #pts >= 3 then
            local inside, j = false, #pts
            for i = 1, #pts do
                local a, b = pts[i], pts[j]
                if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then inside = not inside end
                j = i
            end
            return inside
        end
        local dx, dy = x - l.cx, y - l.cy
        return dx * dx + dy * dy <= l.radius * l.radius
    end
    -- how far outside the area a spot is, in yards (0 = inside)
    function L.OutsideDistance(l, x, y)
        if L.Inside(l, x, y) then return 0 end
        local pts = l.points
        if pts and #pts >= 3 then
            local best = 1e9
            for i = 1, #pts do
                local a, b = pts[i], pts[i % #pts + 1]
                local dx, dy = b[1] - a[1], b[2] - a[2]
                local len2 = dx * dx + dy * dy
                local t = len2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / len2)) or 0
                best = math.min(best, math.sqrt((x - a[1] - t * dx) ^ 2 + (y - a[2] - t * dy) ^ 2))
            end
            return best
        end
        return math.sqrt((x - l.cx) ^ 2 + (y - l.cy) ^ 2) - l.radius
    end
    -- points on the boundary, about `step` yards apart: { {x, y}, ... } (for the radius preview)
    function L.EdgePoints(l, step)
        local out, pts = {}, l.points
        if pts and #pts >= 3 then
            for i = 1, #pts do
                local a, b = pts[i], pts[i % #pts + 1]
                local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
                local n = math.max(1, math.floor(len / step + 0.5))
                for k = 0, n - 1 do out[#out + 1] = { a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n } end
            end
        else
            local n = math.max(12, math.floor(2 * math.pi * l.radius / step + 0.5))
            for k = 0, n - 1 do
                local a = k / n * 2 * math.pi
                out[#out + 1] = { l.cx + math.cos(a) * l.radius, l.cy + math.sin(a) * l.radius }
            end
        end
        return out
    end
    function L.SetPoints(l, pts)   -- nil / fewer than 3 points = back to a circle (cx, cy, radius stay as they are in the database)
        WorldDBExecute("DELETE FROM garrison_location_point WHERE location=" .. math.floor(l.id))
        l.points = nil
        if pts and #pts >= 3 then
            for i, p in ipairs(pts) do
                WorldDBExecute(string.format("INSERT INTO garrison_location_point (location, seq, x, y) VALUES (%d,%d,%f,%f)", l.id, i, p[1], p[2]))
            end
            l.points = pts
            Bounds(l)
        end
    end

    function L.Save(l)   -- center, radius and arrival point of one location
        WorldDBExecute(string.format("UPDATE garrison_location SET name=%s, cx=%f, cy=%f, radius=%f, ax=%f, ay=%f, az=%f, ao=%f, enabled=%d WHERE id=%d",
            Q(l.name), l.cx, l.cy, l.radius, l.portal.x, l.portal.y, l.portal.z, l.portal.o, l.enabled and 1 or 0, l.id))
    end
    function L.Add(name, map, x, y, z, o)   -- new location centered on a spot; returns it
        local id = 0
        for k in pairs(byId) do if k > id then id = k end end
        id = id + 1
        local l = { id = id, name = name, map = map, cx = x, cy = y, radius = 100.0, portal = { x = x, y = y, z = z, o = o }, enabled = true }
        WorldDBExecute(string.format("INSERT INTO garrison_location (id,name,map,cx,cy,radius,ax,ay,az,ao) VALUES (%d,%s,%d,%f,%f,%f,%f,%f,%f,%f)", id, Q(name), map, x, y, 100.0, x, y, z, o))
        byId[id] = l
        return l
    end

    -- ---- phase bits ----
    -- A bit is free on a map when no stock creature/gameobject spawn on THAT map uses it (Northrend uses many, Eastern Kingdoms few).
    local BASE_USED = { 1, 2, 64, 128, 256, 8192, 65536, 131072, 262144 }   -- known stock (quest) phases: never handed out
    local pools = {}   -- map -> { list = {bit...}, set = {[bit] = true} }
    local function Pool(map)
        if pools[map] then return pools[map] end
        local used = {}
        for _, b in ipairs(BASE_USED) do used[b] = true end
        for _, t in ipairs({ "creature", "gameobject" }) do
            local q = WorldDBQuery("SELECT DISTINCT phaseMask FROM " .. t .. " WHERE map=" .. math.floor(map))
            if q then repeat
                local m = q:GetUInt32(0)
                if m ~= 4294967295 then   -- "all phases" spawns do not reserve a bit
                    for i = 1, 30 do local b = math.floor(2 ^ i); if math.floor(m / b) % 2 == 1 then used[b] = true end end
                end
            until not q:NextRow() end
        end
        local pool = { list = {}, set = {} }
        for i = 2, 30 do local b = math.floor(2 ^ i); if not used[b] then pool.list[#pool.list + 1] = b; pool.set[b] = true end end
        pools[map] = pool
        return pool
    end
    function L.FreeBits(map) return Pool(map).list end
    function L.IsOurBit(map, mask)   -- is this phase mask one of the bits we hand out on a map that has a garrison location? (never true elsewhere)
        for _, l in pairs(byId) do if l.map == map then return Pool(map).set[mask] == true end end
        return false
    end

    Init()
    L.Reload()
end
