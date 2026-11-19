package.path = "pet-battle/lab/?.lua;" .. package.path
local L = require("pb_abilab_data")
for _, e in ipairs(L) do
  for i, c in ipairs(e.cands) do
    print(table.concat({e.id, e.mode, tostring(e.hop or ""), e.hits or 1, c.kind, tostring(c.spell or ""), c.mode or "", tostring(c.pre or ""), tostring(c.dmg or "")}, "\t"))
  end
end
