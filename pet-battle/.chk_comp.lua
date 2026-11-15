package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local BAD = { [529]=1,[632]=1,[223]=1,[226]=1,[768]=1,[612]=1,[774]=1,[760]=1,[670]=1,[636]=1 }
local R = require("pb_retail")
for e, sp in pairs(D.species) do
  if sp.companion then
    local r = R.species[sp.retail]; local hit = {}
    for _, a in ipairs(r.abil) do if BAD[a[3]] then hit[#hit+1] = a[3] end end
    if #hit > 0 then print(e, sp.name, "retail", sp.retail, r.name, r.family, table.concat(hit, ",")) end
  end
end
