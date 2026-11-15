-- run from project root: luajit pet-battle/.audit_vis.lua  -> pet-battle/.audit_vis.tsv
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local VISNAMES = {}  -- retail-name VIS table is local to pb_core; detect source by comparing with override
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local out = assert(io.open("pet-battle/.audit_vis.tsv", "w"))
out:write("species\tspname\tfamily\tretail\tdisplay\tvis\tranged\ticon\tsource\tabfamily\tslot\topt\tdesc\n")
local n = 0
for _, id in ipairs(ids) do
  local ok, kit = pcall(C.Kit, id)
  if ok then
    for _, k in ipairs(kit) do
      local a = k.ability
      local ov = D.rename[id] and D.rename[id][a.retailName] or {}
      local src
      if ov.vis then src = "override" elseif a.vis then src = (a.vis == 133 and a.ranged or a.vis == 49966) and "FALLBACK?" or "VIS" else src = "none" end
      -- disambiguate: VIS table values (17253,16827,35290) vs fallback (133 ranged, 49966)
      if src == "FALLBACK?" then src = "FALLBACK" end
      if src == "VIS" and not (a.vis == 17253 or a.vis == 16827 or a.vis == 35290) then src = "FALLBACK" end
      if ov.vis == nil and a.vis == 49966 then
        local nm = a.retailName
        local V = { Punch=1, Clobber=1, Takedown=1, Crush=1, Jab=1, Slam=1 }
        src = V[nm] and "VIS" or "FALLBACK"
      end
      local d = (a.tip or ""):gsub("[\t\n]", " ")
      out:write(table.concat({ id, D.species[id].name, tostring(C.Family(id)), a.retailName, a.name, tostring(a.vis or ""), tostring(a.ranged or ""), a.icon, src, tostring(a.family), k.slot, k.opt, d }, "\t"), "\n")
      n = n + 1
    end
  else io.stderr:write("kit fail " .. id .. " " .. tostring(kit) .. "\n") end
end
out:close(); print("rows", n)
