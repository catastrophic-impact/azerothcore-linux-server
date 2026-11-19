-- Minimap blips (addons/wotlk_pets/WildBlips.lua): the placement math, the wire format, clamping, clearing.  luajit pet-battle/test_ui_blips.lua
local fails, passes = 0, 0
local function ok(c, m) if c then passes = passes + 1 else fails = fails + 1; print("FAIL " .. m) end end
local function near(a, b, m) ok(math.abs(a - b) < 0.01, m .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local handlers = {}
AcoreLib = { On = function(m, a, f) handlers[m .. "|" .. a] = f end }
local now = 100; function GetTime() return now end
local zoom = 3
local function proxy() return setmetatable({}, { __index = function(t, k) return function() return t end end }) end
Minimap = setmetatable({ GetZoom = function() return zoom end, SetZoom = function(_, z) zoom = z end, GetWidth = function() return 140 end, GetFrameLevel = function() return 1 end }, { __index = function() return function() end end })
local cv = { minimapZoom = "3", minimapInsideZoom = "3", rotateMinimap = "0" }
function GetCVar(k) if k == "minimapZoom" then return tostring(zoom) end return cv[k] end
local frames = {}
function CreateFrame(kind, name, parent)
    local f = { kind = kind, shown = false, points = {}, scripts = {}, alpha = 1 }
    f.SetSize = function() end; f.SetFrameLevel = function() end; f.SetScript = function(self, n, fn) self.scripts[n] = fn end; f.RegisterEvent = function() end
    f.CreateTexture = function() return proxy() end; f.Hide = function(self) self.shown = false end; f.Show = function(self) self.shown = true end
    f.ClearAllPoints = function(self) self.points = {} end; f.SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end; f.SetAlpha = function(self, a) self.alpha = a end
    frames[#frames + 1] = f; return f
end
GameTooltip = proxy(); DEFAULT_CHAT_FRAME = { AddMessage = function() end }; SlashCmdList = {}
local menuAdds = {}; local initfn
function hooksecurefunc(name, fn) if name == "MiniMapTrackingDropDown_Initialize" then initfn = fn end end
MiniMapTrackingDropDown_Initialize = function() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_AddButton(i) menuAdds[#menuAdds + 1] = i end
dofile("addons/wotlk_pets/WildBlips.lua")
local B = WotlkBlips
ok(handlers["pbw|pets"], "handler registered")
-- placement: 100 yd radius, 60 px radius: a pet 50 yd NORTH is up, 50 yd WEST is left, east is right
local x, y = B.Place(50, 0, 100, 60, nil); near(x, 0, "north: x"); near(y, 30, "north: up")
x, y = B.Place(0, 50, 100, 60, nil); near(x, -30, "west: left"); near(y, 0, "west: y")
x, y = B.Place(0, -50, 100, 60, nil); near(x, 30, "east: right")
-- rotating minimap: facing WEST (90 degrees counter-clockwise from north): a pet to the west is straight AHEAD = up
x, y = B.Place(0, 50, 100, 60, math.pi / 2); near(x, 0, "rotated, facing west: pet in the west is ahead (x)"); near(y, 30, "rotated: ahead is up")
x, y = B.Place(50, 0, 100, 60, math.pi / 2); near(x, 30, "rotated, facing west: a pet in the north is on the RIGHT")
x, y = B.Place(50, 0, 100, 60, math.pi); near(y, -30, "rotated, facing south: a pet in the north is behind (down)")
-- beyond the map: pinned to the rim, same direction
local ex, ey, edge = B.Place(200, 0, 100, 60, nil); near(ey, 60, "far pet pinned to the rim"); ok(edge, "edge flag set")
local _, _, edge2 = B.Place(50, 0, 100, 60, nil); ok(not edge2, "near pet is not on the rim")
-- wire format
handlers["pbw|pets"]("50,0,299,3,Young Wolf;0,40,69,7,Timber Wolf")
local d = B.Data(); ok(#d == 2 and d[1][3] == 299 and d[1][5] == "Young Wolf" and d[2][2] == 40 and d[2][4] == 7, "two blips parsed")
local bl = B.Blips(); ok(bl[1].shown and bl[2].shown, "both blips shown"); ok(bl[1].y > 0 and bl[2].x < 0, "blip 1 above the centre, blip 2 left of it")
handlers["pbw|pets"]("garbage;1,2"); ok(#B.Data() == 0, "malformed entries ignored")
handlers["pbw|pets"]("10,10,5,1,Rabbit"); ok(bl[1].shown and not bl[2].shown, "one blip: the second is hidden again")
handlers["pbw|pets"]("none"); ok(#B.Data() == 0 and not bl[1].shown, "'none' clears every blip")
-- stale data expires when the server goes quiet
handlers["pbw|pets"]("10,10,5,1,Rabbit"); local driver; for _, f in ipairs(frames) do if f.scripts.OnUpdate then driver = f end end
now = now + 10; driver.scripts.OnUpdate(driver, 0.2); ok(#B.Data() == 0 and not bl[1].shown, "no message for 6 s: blips disappear")
-- indoors uses the small radius table: same pet is pinned to the rim indoors at the same zoom
zoom = 3; cv.minimapInsideZoom = "1"   -- zoom != inside zoom -> outdoors
handlers["pbw|pets"]("100,0,5,1,Rabbit"); Minimap.GetZoom = function() return zoom end
-- tracking menu toggle
ok(initfn, "hooked the minimap tracking menu"); initfn(); local ent = menuAdds[#menuAdds]
ok(ent and ent.text == "Wild Pets" and ent.isNotRadio and ent.checked == true, "tracking menu has a ticked 'Wild Pets' entry")
handlers["pbw|pets"]("10,10,5,1,Rabbit"); ok(B.Blips()[1].shown, "blip shown while on")
ent.func(); ok(WotlkPetsDB.blips == false and not B.Blips()[1].shown, "unticking hides the blips and saves the choice")
handlers["pbw|pets"]("10,10,5,1,Rabbit"); ok(not B.Blips()[1].shown, "new messages do not show blips while off")
menuAdds = {}; initfn(); ok(menuAdds[#menuAdds].checked == false, "menu shows it unticked")
SlashCmdList["PETBLIPS"](); ok(WotlkPetsDB.blips == true and B.Blips()[1].shown, "/petblips turns them back on")
print(string.format("ui blips: %d assertions, %d failures", passes + fails, fails))
os.exit(fails == 0 and 0 or 1)
