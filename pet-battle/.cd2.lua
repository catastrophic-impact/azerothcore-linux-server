package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local C = require("pb_core")
for _, e in ipairs({ 1867, 4389, 2375 }) do print(e, D.species[e].name, D.species[e].retail, R.species[D.species[e].retail].family) end
local used = {}; for e, s in pairs(D.species) do used[s.retail] = (used[s.retail] or 0) + 1 end
for _, fam in ipairs({ "Humanoid", "Aquatic", "Magic" }) do
  local out = {}
  for id, sp in pairs(R.species) do if sp.family == fam and (used[id] or 0) > 0 then
    local a1; for _, a in ipairs(sp.abil) do if a[1] == 0 and a[2] == 1 then a1 = R.abilities[a[3]] end end
    if a1 and a1.cd == 0 then out[#out + 1] = id .. ":" .. sp.name .. "/" .. a1.name end end end
  table.sort(out); print(fam, table.concat(out, ", "):sub(1, 400))
end
