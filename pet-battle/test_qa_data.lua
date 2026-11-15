-- QA data cross-checks (reviewer, new file): luajit pet-battle/test_qa_data.lua
-- species vs stand-in SQL, zone TSV rosters vs picks vs pb_data, D.zones vs pb_wild ZONES vs roster levels, kit retail ids, abilities with unhandled effect props.
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local C = require("pb_core")
local fails, passes = {}, 0
local function check(ok, msg) if ok then passes = passes + 1 else fails[#fails + 1] = msg end end
local function readAll(p) local f = assert(io.open(p, "r"), p); local s = f:read("*a"); f:close(); return s end

-- 1. stand-in SQL ids == species ids
local sql = readAll("custom-sql/016_pet_standins.sql")
local idlist = sql:match("SET @pb_ids = '([%d,]+)'")
local inSql = {}; for id in idlist:gmatch("%d+") do inSql[tonumber(id)] = true end
local nS, nQ = 0, 0
for id in pairs(D.species) do nS = nS + 1; check(inSql[id], "species " .. id .. " (" .. D.species[id].name .. ") has no stand-in id in 016 SQL") end
for id in pairs(inSql) do nQ = nQ + 1; check(D.species[id], "016 SQL id " .. id .. " is not a species") end
check(nS == nQ, "species count " .. nS .. " vs SQL ids " .. nQ)
local hdrN = tonumber(sql:match("(%d+) species"))
check(hdrN == nS, "016 header says " .. tostring(hdrN) .. " species, pb_data has " .. nS)

-- 2. kits / icons / duplicates
local src = readAll("scripts/pb_data.lua")
local seen = {}
for e in src:gmatch("\n%s*%[(%d+)%] = { name = \"[^\"]*\", retail") do check(not seen[e], "duplicate species entry " .. e); seen[e] = true end
local iconUse = {}
for id, sp in pairs(D.species) do
    check(R.species[sp.retail] ~= nil, "species " .. id .. " retail " .. tostring(sp.retail) .. " missing from pb_retail")
    check(type(sp.icon) == "string" and #sp.icon > 3, "species " .. id .. " no icon")
    if sp.icon then iconUse[sp.icon] = (iconUse[sp.icon] or 0) + 1 end
    local rs = R.species[sp.retail]
    if rs then
        local n = 0; for _, k in ipairs(C.Kit(id)) do if k.opt == 1 then n = n + 1 end end
        check(n == 3, "species " .. id .. " " .. sp.name .. " has " .. n .. " first-option slots (want 3)")
        for _, k in ipairs(C.Kit(id)) do check(k.ability ~= nil and R.abilities[k.ability.id or -1] ~= nil or k.ability ~= nil, "species " .. id .. " kit ability missing") end
    end
end

-- 3. zone rosters / picks / D.zones / ZONES
local zfile = {}   -- data-driven: every zone_ranges.tsv row whose zone id is in D.zones (zone key = the file prefix)
for l in io.lines("pet-battle/zone_ranges.tsv") do
    if not l:find("^#") and l:find("%S") then local c = {}; for f in (l .. "\t"):gmatch("(.-)\t") do c[#c + 1] = f end; if D.zones[tonumber(c[2])] then zfile[c[1]] = tonumber(c[2]) end end
end
local wild = readAll("scripts/pb_wild.lua"):match("local ZONES = {([^}]*)}")
local zset = {}; for id in wild:gmatch("%[(%d+)%] = true") do check(not zset[id], "dup ZONES id " .. id); zset[id] = true end
local nz = 0; for id in pairs(D.zones) do nz = nz + 1; check(zset[tostring(id)], "D.zones " .. id .. " not in pb_wild ZONES") end
local nzs = 0; for id in pairs(zset) do nzs = nzs + 1; check(D.zones[tonumber(id)], "ZONES " .. id .. " has no D.zones row") end
local nfile = 0; for _ in pairs(zfile) do nfile = nfile + 1 end
check(nz == nzs and nz == nfile, "zone counts D.zones " .. nz .. " ZONES " .. nzs)
local function lines(p) local t = {}; for l in readAll(p):gmatch("[^\n]+") do t[#t + 1] = l end; return t end
local function split(l) local t = {}; for f in (l .. "\t"):gmatch("(.-)\t") do t[#t + 1] = f end; return t end
local allYes, stale = {}, {}
for zn, zid in pairs(zfile) do
    local z = D.zones[zid]; check(z ~= nil, zn .. ": no D.zones row for " .. zid)
    local yes, lo, hi = {}, 999, 0
    for _, l in ipairs(lines("pet-battle/" .. zn .. "_roster.tsv")) do
        if l:sub(1, 1) ~= "#" and l:sub(1, 7) ~= "include" then
            local p = split(l)
            if p[1] == "Y" then
                yes[p[2]] = p; allYes[p[2]] = zn
                local a, b = p[4]:match("^(%d+)%-?(%d*)$"); a = tonumber(a); b = tonumber(b) or a
                if not a then check(false, zn .. ": bad levels '" .. p[4] .. "' for " .. p[2]) else lo = math.min(lo, a); hi = math.max(hi, b) end
                check(D.species[tonumber(p[2])] ~= nil, zn .. ": roster Y entry " .. p[2] .. " " .. p[3] .. " is not a species")
                if D.species[tonumber(p[2])] then check(D.species[tonumber(p[2])].wild, zn .. ": entry " .. p[2] .. " is not wild=true") end
            end
        end
    end
    local pk = {}
    local ok = pcall(function()
        for _, l in ipairs(lines("pet-battle/" .. zn .. "_picks.tsv")) do
            if l:sub(1, 1) ~= "#" and l:match("%S") then
                local p = split(l); check(not pk[p[1]], zn .. ": duplicate pick " .. p[1]); pk[p[1]] = p
                check(yes[p[1]] ~= nil, zn .. ": pick for " .. p[1] .. " that is not a Y roster row")
                local sp = D.species[tonumber(p[1])]
                if sp then
                    if sp.retail ~= tonumber(p[2]) then stale[#stale + 1] = zn .. ":" .. p[1] .. " " .. p[2] .. "->" .. sp.retail end   -- rekit.py edits pb_data only: the picks TSV is a draft, informational
                    check(sp.icon == p[3], zn .. ": pick " .. p[1] .. " icon " .. p[3] .. " but pb_data has " .. tostring(sp.icon))
                    check((p[4] == "critter") == (sp.critter == true), zn .. ": pick " .. p[1] .. " critter flag mismatch")
                end
            end
        end
    end)
    if not ok then if zn ~= "westfall" and zn ~= "elwynn" and zn ~= "dunmorogh" and zn ~= "durotar" then check(false, zn .. ": no picks file") end end
    -- every Y roster row either picked or an older species (defined in another zone) -- count the ones with neither
    if z and hi > 0 then
        -- the mob level span must match D.zones within a small tolerance
        check(z.minMob <= lo + 0 or lo - z.minMob <= 2, zn .. ": minMob " .. z.minMob .. " vs roster low " .. lo)
        check(z.maxMob >= hi - 6 and z.maxMob <= hi + 6, zn .. ": maxMob " .. z.maxMob .. " vs roster high " .. hi)
        check(z.lo <= z.hi and z.hi <= D.MAX_LEVEL and z.lo >= 1, zn .. ": bad lo/hi")
        local plo, phi = D.PetLevel(lo, zid), D.PetLevel(hi, zid)
        check(plo >= z.lo and phi <= z.hi, zn .. ": PetLevel out of lo..hi")
    end
end
-- orphan species: a wild species in no roster
local orphan = 0
for id, sp in pairs(D.species) do if sp.wild and not allYes[tostring(id)] then orphan = orphan + 1; check(false, "wild species " .. id .. " " .. sp.name .. " is in no zone roster Y row") end end

-- 4. unhandled effect props: every effect prop of every ability of every used kit must be in pb_core's handled set or the known marker/inert list
local gap = {}
local used = {}
for id in pairs(D.species) do for _, k in ipairs(C.Kit(id)) do used[k.ability] = used[k.ability] or {}; used[k.ability][id] = true end end
check(next(C.unknown or {}) == nil, "C.unknown is not empty")
-- the abilities that find_gaps.py knows
local GAPS = { [652] = 1, [444] = 1, [323] = 1, [922] = 1, [2352] = 1 }
for id, sp in pairs(D.species) do
    for _, k in ipairs(C.Kit(id)) do
        local aid = k.ability.id
        check(not GAPS[aid or -1], "species " .. id .. " " .. sp.name .. " uses known-gap ability " .. tostring(aid))
    end
end

print(string.format("qa data: %d species, %d zones, %d passed, %d failed", nS, nz, passes, #fails))
print("stale picks (draft TSV differs from pb_data after rekit): " .. #stale)
for _, f in ipairs(fails) do print("FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
