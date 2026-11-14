package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data")
local fails, n = 0, 0
local function eq(a, b, msg) n = n + 1; if a ~= b then fails = fails + 1; print("FAIL " .. (msg or "") .. ": got " .. tostring(a) .. " expected " .. tostring(b)) end end
-- Elwynn: retail 1-2, mobs 1-10 -> 1-5 = pet 1, 6-10 = pet 2
for l = 1, 5 do eq(D.PetLevel(l, 12), 1, "elwynn mob " .. l) end
for l = 6, 10 do eq(D.PetLevel(l, 12), 2, "elwynn mob " .. l) end
-- out-of-range mobs clamp to the zone's range
eq(D.PetLevel(0, 12), 1, "below min"); eq(D.PetLevel(40, 12), 2, "above max"); eq(D.PetLevel(nil, 12), 1, "nil level")
-- every enabled zone: monotonic, stays in lo..hi, hits both ends
for id, z in pairs(D.zones) do
    local prev, seenLo, seenHi = 0, false, false
    for l = z.minMob, z.maxMob do
        local p = D.PetLevel(l, id); eq(p >= z.lo and p <= z.hi, true, z.name .. " in range at " .. l); eq(p >= prev, true, z.name .. " monotonic at " .. l); prev = p
        seenLo = seenLo or p == z.lo; seenHi = seenHi or p == z.hi
    end
    eq(seenLo and seenHi, true, z.name .. " uses the whole range")
end
-- Westfall: retail 3-4, mobs 9-19: the level 1 critters clamp to 3, mobs 9-14 = 3, 15-19 = 4
eq(D.PetLevel(1, 40), 3, "westfall critter"); eq(D.PetLevel(9, 40), 3, "westfall mob 9"); eq(D.PetLevel(14, 40), 3, "westfall mob 14"); eq(D.PetLevel(15, 40), 4, "westfall mob 15"); eq(D.PetLevel(19, 40), 4, "westfall mob 19"); eq(D.PetLevel(26, 40), 4, "westfall above the range")
-- hypothetical wide zone (Feralas-like): retail 11-16 over mobs 40-49 spreads evenly, 6 levels over 10 mob levels
D.zones[9999] = { lo = 11, hi = 16, minMob = 40, maxMob = 49 }
local got = {}; for l = 40, 49 do got[#got + 1] = D.PetLevel(l, 9999) end
eq(table.concat(got, ","), "11,11,12,12,13,14,14,15,15,16", "wide zone spread")
-- single-level retail range collapses to one level; unknown zone falls back to the old proportional curve
D.zones[9998] = { lo = 5, hi = 5, minMob = 1, maxMob = 10 }; eq(D.PetLevel(9, 9998), 5, "single level range")
eq(D.PetLevel(80, 424242), 25, "unknown zone fallback 80 -> 25"); eq(D.PetLevel(80), 25, "no zone fallback")
print(string.format("levels: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
