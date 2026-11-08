-- Smoke test for the Minimap Drawer addon WITHOUT a client: the WoW frame API is faked (any method works, a few return real values),
-- then the addon is loaded, a few fake minimap buttons are collected, categories/labels/icons are edited and the layout is checked.
-- usage (build box): lua5.1 tools/test_minimap.lua       exit code 0 = all checks passed
local here = arg and arg[0]:match("^(.*)/tools/") or "."
local fails, total = 0, 0
local function check(c, m) total = total + 1; if not c then fails = fails + 1; print("FAIL: " .. m) end end

local Frame = {}
setmetatable(Frame, { __index = function(t, k)
    if type(k) == "string" and (k:match("^Set") or k:match("^Register") or k:match("^Enable") or k:match("^Highlight") or k:match("^Clear") or k:match("^Add")) then
        return function(self, ...) return self end
    end
end })   -- unknown method: do nothing
Frame.__index = Frame   -- like the real thing: the metatable's __index is a table of methods
local names = {}
function Frame:GetName() return self._name end
function Frame:GetChildren() return unpack(self._children or {}) end
function Frame:GetRegions() return unpack(self._regions or {}) end
function Frame:GetWidth() return self._w or 30 end
function Frame:GetHeight() return self._h or 30 end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:IsObjectType(t) return t == (self._type or "Frame") or (t == "Frame") end
function Frame:GetObjectType() return self._type or "Frame" end
function Frame:IsShown() return self._shown ~= false end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false; if self._onhide then self._onhide() end end
function Frame:SetShown(s) self._shown = s end
function Frame:SetParent(p) self._parent = p end
function Frame:GetParent() return self._parent end
function Frame:GetFrameLevel() return 5 end
function Frame:GetCenter() return 100, 100 end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:SetPoint(...) self._points = (rawget(self, '_points') or 0) + 1 end
function Frame:ClearAllPoints() end
function Frame:SetScript(k, fn) self._s = self._s or {}; self._s[k] = fn; if k == "OnHide" then self._onhide = fn end end
function Frame:GetScript(k) return self._s and self._s[k] end
function Frame:CreateTexture() return setmetatable({ _type = "Texture", _w = 20, _h = 20 }, Frame) end
function Frame:CreateFontString() return setmetatable({ _type = "FontString" }, Frame) end
function Frame:SetTexture(t) self._tex = t end
function Frame:GetTexture() return self._tex end
function Frame:SetTexCoord(...) self._coord = { ... } end
function Frame:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text or "" end
function Frame:GetEffectiveScale() return 1 end

local function mk(name, typ, opts)
    local f = setmetatable({ _name = name, _type = typ or "Frame", _children = {}, _regions = {} }, Frame)
    for k, v in pairs(opts or {}) do f[k] = v end
    if name then _G[name] = f end
    return f
end
local created = {}
function CreateFrame(typ, name, parent, tpl) local f = mk(name, typ); f._parent = parent; created[#created + 1] = f; return f end

UIParent = mk("UIParent"); UIParent._w, UIParent._h = 1920, 1080
Minimap = mk("Minimap"); Minimap._w, Minimap._h = 140, 140
MinimapCluster = mk("MinimapCluster"); MinimapBackdrop = mk("MinimapBackdrop")
-- fake icons
local zoom = mk("MinimapZoomIn", "Button")
local cal = mk("GameTimeFrame", "Button")
local atlasBtn = mk("AtlasButton", "Button")
local atlas = mk("AtlasButtonFrame", "Frame"); atlas._children = { atlasBtn }
local dbi = mk("LibDBIcon10_MyAddon", "Button")
local tex = setmetatable({ _type = "Texture", _w = 20, _h = 20, _tex = "Interface\\Icons\\Original" }, Frame); dbi._regions = { tex }
local bord = setmetatable({ _type = "Texture", _w = 53, _h = 53, _tex = "Interface\\Minimap\\MiniMap-TrackingBorder" }, Frame); table.insert(dbi._regions, 1, bord)
Minimap._children = { zoom, cal, atlas, dbi }
UIParent._children = {}
tinsert = table.insert
UISpecialFrames = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
StaticPopup_Visible = function() return nil end
ACCEPT, CANCEL, YES, NO = "OK", "Cancel", "Yes", "No"
SlashCmdList = {}
GameTooltip = mk("GameTooltip")
IsAddOnLoaded = function(a) return a == "wotlk_jukebox" or a == "wotlk_garrison" end
GetCursorPosition = function() return 0, 0 end
UIErrorsFrame = mk("UIErrorsFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
EasyMenu = function(list) _G.LASTMENU = list end
GetNumMacroIcons = function() return 100 end
GetMacroIconInfo = function(i) return "ICON_" .. i end
getmetatable_orig = getmetatable

local function run(path) local f = assert(loadfile(path)); return f() end
run(here .. "/addons/wotlk_minimap/Minimap.lua")


local drawer, btn, ev = WotlkMinimapDrawer, WotlkMinimapDrawerButton
for _, f in ipairs(created) do if f._s and f._s.OnEvent then ev = f end end
check(ev ~= nil, "event frame exists")
ev._s.OnEvent(ev, "ADDON_LOADED", "wotlk_minimap")
check(WotlkMinimapDB and #WotlkMinimapDB.cats == 2, "default categories created")
ev._s.OnEvent(ev, "PLAYER_ENTERING_WORLD")

btn._s.OnClick(btn)                      -- open the drawer: scan + layout
check(drawer:IsShown(), "drawer opens")
check(not zoom._parent or zoom._parent ~= drawer, "zoom button stays on the minimap")
check(not cal._parent or cal._parent ~= drawer, "calendar stays on the minimap")
check(atlas._parent == drawer, "Atlas wrapper frame is collected")
check(dbi._parent == drawer, "LibDBIcon button is collected")
check(SlashCmdList.WOTLKMMD ~= nil, "slash command registered")
local db = WotlkMinimapDB
-- labels
local lab = {}
for _, f in ipairs({ atlas, dbi }) do lab[f._name] = f end
local function labelOf(f) for _, c in ipairs(created) do end end
-- categories
SlashCmdList.WOTLKMMD("edit")
check(WotlkMinimapDB.cats[1] == "Other", "home category first")
-- add / rename / move / delete through the popup callbacks
local popups = {}
StaticPopup_Show = function(which, a, b, data) popups[#popups + 1] = data end
-- header buttons are created lazily: find the "+ Category" footer button by its click handler
local addBtn
for _, f in ipairs(created) do if f._text == "+ Category" then addBtn = f end end
check(addBtn ~= nil, "+ Category button exists")
addBtn._s.OnClick(addBtn)
popups[#popups].fn("Tools")
check(#db.cats == 3 and db.cats[3] == "Tools", "category added")
popups[#popups].fn("Tools")   -- duplicate ignored
check(#db.cats == 3, "duplicate category rejected")
-- move an icon via the right-click menu
local overlayFor
for _, c in ipairs(created) do end
SlashCmdList.WOTLKMMD("edit")
-- the menu is built from ItemMenu; call it through an overlay click
local over
for _, f in ipairs(created) do if f._s and f._s.OnClick and f._parent == drawer and f._w == 64 then over = f; break end end
check(over ~= nil, "edit-mode overlays exist")
over._s.OnClick(over)
check(LASTMENU and #LASTMENU > 5, "right-click menu built")
local moved
for _, e in ipairs(LASTMENU) do if e.text == "Move to: Tools" then e.func(); moved = true end end
check(moved, "menu offers the new category")
local count = 0
for k, v in pairs(db.assign) do if v == "Tools" then count = count + 1 end end
check(count == 1, "icon moved to the new category")
-- custom icon + reset
for _, e in ipairs(LASTMENU) do if e.text == "Choose icon..." then e.func() end end
local picker = WotlkMinimapIconPicker
check(picker and picker.target, "icon picker opens for the icon")
local k = picker.target
db.icon[k] = "Interface\\Icons\\INV_Misc_Bag_10"
btn._s.OnClick(btn); btn._s.OnClick(btn)
drawer._s.OnUpdate(drawer, 1)
local t = (k == "LibDBIcon10_MyAddon") and tex or nil
if t then check(t._tex == "Interface\\Icons\\INV_Misc_Bag_10", "custom icon applied to the button's texture"); end
db.icon[k] = nil
drawer._s.OnUpdate(drawer, 1)
if t then check(t._tex == "Interface\\Icons\\Original", "reset restores the original texture") end
-- rename a category: the icon assigned to it follows
SlashCmdList.WOTLKMMD("edit")
local function headerButton(text, cat)
    for _, f in ipairs(created) do
        if f._text == text and f._s and f._s.OnClick then
            local n = #popups
            f._s.OnClick(f)
            if #popups > n and (popups[#popups].text == cat or popups[#popups].fn) then
                if text == "Rename" and popups[#popups].text == cat then return f end
                if text == "Delete" then return f, popups[#popups] end
            end
        end
    end
end
local rb = headerButton("Rename", "Tools")
check(rb ~= nil, "Rename button for the category found")
popups[#popups].fn("Gadgets")
check(db.cats[3] == "Gadgets", "category renamed")
local moved2 = 0
for _, v in pairs(db.assign) do if v == "Gadgets" then moved2 = moved2 + 1 end end
check(moved2 == 1, "assigned icon follows the renamed category")
-- delete: confirm, icon falls back to the home category
StaticPopup_Show = function(which, a, b, data) data.title = a; popups[#popups + 1] = data end
local delOk
for _, f in ipairs(created) do
    if f._text == "Delete" and f._s and f._s.OnClick then
        f._s.OnClick(f)
        local d = popups[#popups]
        if d and d.fn and d.title and d.title:find('Gadgets') then d.fn(); delOk = true; break end
    end
end
check(#db.cats == 2 and db.cats[2] ~= "Gadgets", "category deleted")
local still = 0
for _, v in pairs(db.assign) do if v == "Gadgets" then still = still + 1 end end
check(still == 0, "deleted category leaves no icons assigned to it")
check(db.cats[1] == "Other", "home category is never deleted")
print(string.format("%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
