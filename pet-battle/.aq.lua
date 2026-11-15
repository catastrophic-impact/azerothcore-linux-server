package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail")
local used = {}; for e, s in pairs(D.species) do used[s.retail] = (used[s.retail] or 0) + 1 end
local list = {}
for id, sp in pairs(R.species) do
  if sp.family == "Aquatic" then
    local a1 = nil; for _, a in ipairs(sp.abil) do if a[1] == 0 and a[2] == 1 then a1 = R.abilities[a[3]] end end
    if a1 and a1.cd == 0 then list[#list + 1] = string.format("%d %s slot1=%s (used by %d)", id, sp.name, a1.name, used[id] or 0) end
  end
end
table.sort(list); for _, l in ipairs(list) do print(l) end
