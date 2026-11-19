package.path = "scripts/?.lua;" .. package.path
local R = require("pb_retail"); local C = require("pb_core")
local ids = {}; for id, a in pairs(R.abilities) do if not (a.base and a.base ~= id) then ids[#ids+1] = id end end; table.sort(ids)   -- family clones (pb_wild_kits.lua) are presented like their base ability (pb_core MakeAbility)
local DM = {[24]=1,[222]=1,[96]=1,[62]=1,[384]=1,[385]=1,[27]=1,[59]=1,[141]=1,[66]=1,[226]=1,[68]=1,[197]=1,[29]=1}
for _, id in ipairs(ids) do
  local a = R.abilities[id]; local dmg, heal, side, n = false, false, nil, 0
  for _, t in ipairs(a.turns or {}) do if t.event == 255 or true then for _, f in ipairs(t.fx) do
    if DM[f.prop] then dmg = true end
    if f.prop == 23 or f.prop == 63 then heal = true end
    if (f.prop == 26 or f.prop == 63 or f.prop == 50 or f.prop == 52 or f.prop == 54 or f.prop == 172 or f.prop == 178) and f.aura and not side then side = C.AuraIsSelf(f.prop, f.aura) and "self" or "enemy" end
  end end end
  print(table.concat({id, a.name, tostring(a.family), dmg and 1 or 0, heal and 1 or 0, side or "-", a.cd or 0}, "\t"))
end
