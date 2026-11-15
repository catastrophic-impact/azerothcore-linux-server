package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail")
local bad, n = {}, 0
for e, s in pairs(D.species) do
  local sp = R.species[s.retail]
  if sp then
    n = n + 1
    local a1; for _, a in ipairs(sp.abil) do if a[1] == 0 and a[2] == 1 then a1 = R.abilities[a[3]] end end
    if a1 and a1.cd > 0 then bad[#bad + 1] = string.format("%s (%d) retail %d slot1 '%s' cd %d%s", s.name, e, s.retail, a1.name, a1.cd, s.companion and " [companion]" or "") end
  end
end
table.sort(bad); print(#bad .. " of " .. n .. " species have a level-1 basic ability with a cooldown")
for i = 1, math.min(#bad, 25) do print("  " .. bad[i]) end
