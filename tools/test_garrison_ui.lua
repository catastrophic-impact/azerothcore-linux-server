-- Offline check of the garrison window's category grouping (subcategories). Run in the build box: lua5.1 tools/test_garrison_ui.lua
local checks, fails = 0, 0
local function check(c, w) checks = checks + 1; if not c then fails = fails + 1; print("FAIL: " .. w) end end
CreateFrame = function() local o = setmetatable({}, { __index = function() return function() end end }); return o end; GetTime = function() return 0 end
AcoreLib = { Announce = function() end, Send = function() end, On = function() end }
WotlkGarrisonCatalog = { tabs = { { key = "npcs", cats = {} }, { key = "objects", cats = {} } }, items = {} }
dofile("addons/wotlk_garrison/Core.lua")
local G = WotlkGarrison

local p, c = G.SplitCat("Holiday > Winter Veil"); check(p == "Holiday" and c == "Winter Veil", "split a subcategory")
p, c = G.SplitCat("Beds"); check(p == "Beds" and c == nil, "a plain category has no parent")
p, c = G.SplitCat("A > B > C"); check(p == "A" and c == "B > C", "only one level: the rest stays in the child name")

local names = { "Beds", "Holiday > Winter Veil", "Holiday > Valentines", "Banners", "Lights", "Lights > Candles" }
local rows = G.CategoryRows(names, {})
check(#rows == 4, "collapsed: Beds, Holiday, Banners, Lights (got " .. #rows .. ")")
check(rows[2].label == "+ Holiday" and rows[2].parent == "Holiday" and rows[2].cat == "Holiday > Winter Veil", "a parent without own items selects its first child when opened")
check(rows[4].label == "+ Lights" and rows[4].cat == "Lights", "a parent WITH its own items selects them")
rows = G.CategoryRows(names, { Holiday = true })
check(#rows == 6 and rows[2].label == "- Holiday" and rows[3].indent and rows[3].label == "Winter Veil" and rows[3].cat == "Holiday > Winter Veil" and rows[4].label == "Valentines", "open parent lists its children indented")
rows = G.CategoryRows(names, { Holiday = true, Lights = true })
check(#rows == 7 and rows[7].label == "Candles", "several open parents")
print(string.format("%d checks, %d failed", checks, fails)); os.exit(fails == 0 and 0 or 1)
