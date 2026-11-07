-- Garrison module 2/14: what can be placed. The list is generated (tools/gen_garrison_catalog.py -> garrison_catalog.lua).
return function(G)
    local CATALOG = require("garrison_catalog").items   -- { kind, t = "c"/"g", entry, name, multi, price, hid }
    local BY_KIND = {}
    for _, c in ipairs(CATALOG) do BY_KIND[c.kind] = c end
    G.CATALOG, G.BY_KIND = CATALOG, BY_KIND
    -- hid = true: category Removed / Unsorted (review shelves). Only GM level 3+ accounts (the admin tool users) can place those; players cannot.
    G.CanPlace = function(player, def) return def and def.multi and (not def.hid or player:GetGMRank() >= 3) end
end
