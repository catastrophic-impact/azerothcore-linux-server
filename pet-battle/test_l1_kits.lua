-- A level-1 pet must be able to fight: its level-1 basic ability may not have a cooldown of 2+ rounds (the Frenzy fish had only 'Feed', cd 4: a duel between two of them stalled 56% of the time).
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail")
local bad, n = {}, 0
for e, s in pairs(D.species) do
    local sp = R.species[s.retail]
    if sp then
        n = n + 1
        local a1; for _, a in ipairs(sp.abil) do if a[1] == 0 and a[2] == 1 then a1 = R.abilities[a[3]] end end
        if not a1 then bad[#bad + 1] = s.name .. " (" .. e .. ") has no level-1 basic ability"
        elseif a1.cd >= 2 then bad[#bad + 1] = s.name .. " (" .. e .. ") level-1 ability '" .. a1.name .. "' has cooldown " .. a1.cd end
    end
end
table.sort(bad)
print(string.format("level-1 kits: %d species checked, %d problems", n, #bad))
for _, b in ipairs(bad) do print("  FAIL " .. b) end
os.exit(#bad == 0 and 0 or 1)
