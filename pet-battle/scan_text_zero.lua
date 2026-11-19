-- Scan EVERY ability in the data for the text problems the presentation/describe tests reject, so the composed-kit pipeline can block them up front:
--   a number that resolves to zero ("for 0 rounds"), an unresolved token, the retail story text. (An ability naming itself is NOT scanned: the engine's Flavor() neutralizes that for renamed abilities.)
-- Usage (host, repo root): luajit pet-battle/scan_text_zero.lua >> pet-battle/ability_blocklist.txt     (prints "<base id>\t<reason>")
package.path = "scripts/?.lua;" .. package.path
local D, C = require("pb_data"), require("pb_core"); local R = require("pb_retail")
local pats = { "by 0%%", "dealing 0 ", "take 0 ", "next 0 ", "for 0 ", "deals 0 ", "by %?", "restoring 0 ", "Restores 0 " }
local seen = {}
for id, a in pairs(R.abilities) do
    local base = a.base or id; if not seen[base] then
        local tip = C.Describe(setmetatable({ id = id }, { __index = a }), 200); local why
        for _, p in ipairs(pats) do if tip:find(p) then why = "text resolves to zero/unknown (" .. p .. ")"; break end end
        if not why and (tip:find("%[") or tip:find("%?") or tip:find("nil")) then why = "unresolved text token" end
        if not why and (tip:find("brilliant light") or tip:find("cloud of spores")) then why = "retail story text" end
        if why then seen[base] = true; print(base .. "\t" .. why) end
    end
end
