package.path = "scripts/?.lua;" .. package.path
local R = require("pb_rules")
local fails, n = 0, 0
local function eq(a, b, msg) n = n + 1; if a ~= b then fails = fails + 1; print("FAIL " .. (msg or "") .. ": got " .. tostring(a) .. " expected " .. tostring(b)) end end
-- retail check: a level 25 rare (quality 3) pet with base stats 8/8/8 has 1400 health, 260 power, 260 speed
local s = R.Stats({}, 25, 3); eq(s.health, 1400, "L25 rare health"); eq(s.power, 260, "L25 rare power"); eq(s.speed, 260, "L25 rare speed")
-- level 1 common (quality 1): 8*1*1.1*5+100 = 144 health
eq(R.Stats({}, 1, 1).health, 144, "L1 common health")
-- Snowshoe Rabbit: power -2, speed +2 (hundredths 200)
local r = R.Stats({ Stat_Power = -200, Stat_Speed = 200, Stat_Stamina = 0 }, 25, 3); eq(r.power, 195, "rabbit power"); eq(r.speed, 325, "rabbit speed")
-- the 10 families form a ring of strong-against; every family is strong against exactly one and weak against exactly one
for _, f in ipairs(R.FAMILIES) do
    eq(R.STRONG[f] ~= nil, true, f .. " strong"); eq(R.WEAK[f] ~= nil, true, f .. " weak")
    eq(R.Matchup(f, R.STRONG[f]), 1.5, f .. " x1.5"); eq(R.Matchup(f, R.WEAK[f]) < 0.67 + 1e-9, true, f .. " x0.67")
end
eq(R.Matchup("Beast", "Critter"), 1.5, "beast>critter"); eq(R.Matchup("Critter", "Beast") , 1, "critter vs beast neutral")
-- damage = points * (1 + power/20): a 20-point hit at power 260 = 280; and the pace is constant: a basic hit is about 20% of health at every level
eq(R.Damage(20, 260, "Beast", "Beast"), 280, "standard hit"); eq(R.Damage(10, 260, "Beast", "Beast"), 140, "half hit"); eq(R.Damage(20, 260, "Beast", "Critter"), 420, "strong hit")
for _, lv in ipairs({ 1, 10, 25 }) do local st = R.Stats({}, lv, 3); local ratio = R.Damage(20, st.power, "Beast", "Beast") / st.health; eq(ratio > 0.17 and ratio < 0.23, true, "pace at level " .. lv .. ": " .. ratio) end
print(string.format("rules: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
