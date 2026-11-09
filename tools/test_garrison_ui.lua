-- Offline check of the garrison window's category grouping (subcategories). Run in the build box: lua5.1 tools/test_garrison_ui.lua
local checks, fails = 0, 0
local function check(c, w) checks = checks + 1; if not c then fails = fails + 1; print("FAIL: " .. w) end end
CreateFrame = function() local o = setmetatable({}, { __index = function() return function() end end }); return o end; GetTime = function() return 0 end
local sent, handlers = {}, {}
AcoreLib = { Announce = function() end, Send = function(m, a, p) sent[#sent + 1] = m .. "|" .. a .. "|" .. tostring(p) end, On = function(m, a, fn) handlers[m .. "|" .. a] = fn end }
WotlkGarrisonCatalog = { tabs = { { key = "npcs", cats = {} }, { key = "objects", cats = { "Beds", "Lights", "Unsorted", "Removed" } } }, catprice = { Lights = 3 },
    items = { { kind = "d1", tab = "objects", cat = "Unsorted", name = "Chair", model = "World\\A.m2", npc = 0, hid = 1, vs = 1, vy = 0, vz = 0 },
              { kind = "d2", tab = "objects", cat = "Beds", name = "Bed", model = "World\\B.m2", npc = 0, ip = 5 } } }
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
-- curator: the curation layer over the generated catalog (Curate.lua)
StaticPopupDialogs = {}; DEFAULT_CHAT_FRAME = { AddMessage = function() end }; WotlkGarrisonDB = {}
G.Refresh = function() end; G.AdvanceFrom = function() end; G.GoTo = function() end
dofile("addons/wotlk_garrison/Curate.lua")
local d1, d2 = G.ItemByKind("d1"), G.ItemByKind("d2")
G.st.curator = true
G.ApplyCur()
check(d1.hidden == true and d2.hidden == nil, "Unsorted is hidden from players")
WotlkGarrisonDB.curatorOn = true; G.ApplyCur()
check(d1.hidden == nil, "a curator sees Unsorted")
check(G.CurEdit(d1, { cat = "Lights" }) and d1.cat == "Lights" and d1.price == 3, "moving an item applies at once; price comes from the new category")
check(sent[#sent] == "house|ciset|d1~Lights~~", "the move is sent to the server (" .. tostring(sent[#sent]) .. ")")
check(G.CurEdit(d2, { price = 8, name = "Big Bed" }) and d2.price == 8 and d2.name == "Big Bed", "item price and name overrides")
check(not G.CurEdit(d2, { name = "Big Bed" }), "an unchanged edit is not sent twice")
G.CurUndo(); check(d2.price == 5 and d2.name == "Bed", "undo restores the previous override")
G.CurUndo(); G.CurUndo(); check(d1.cat == "Unsorted" and d2.name == "Bed" and d2.price == 5, "undo all: back to the generated values")
handlers["house|curd"]("1;i~d1~Beds~~"); check(WotlkGarrisonDB.cur.rev == 0 or d1.cat == "Unsorted", "a delta from the wrong revision is not applied (resync asked)")
WotlkGarrisonDB.cur.rev = 4
handlers["house|curd"]("5;i~d1~Beds~Sofa~2"); check(d1.cat == "Beds" and d1.name == "Sofa" and d1.price == 2 and WotlkGarrisonDB.cur.rev == 5, "a delta in order applies")
handlers["house|curfull"]("1/1;r~9;k;c~Zed~4;c~Beds~0;c~Unsorted~0;c~Removed~0;i~d2~Zed~~")
check(G.TabDef("objects").cats[1] == "Beds" and G.TabDef("objects").cats[2] == "Zed" and d2.cat == "Zed" and d2.price == 5 and d1.cat == "Unsorted" and WotlkGarrisonDB.cur.rev == 9, "a full sync replaces categories, items and revision")
G.st.curator = false; G.ApplyCur(); check(d1.hidden == true, "without the GM right everything hidden stays hidden")
print(string.format("%d checks, %d failed", checks, fails)); os.exit(fails == 0 and 0 or 1)
