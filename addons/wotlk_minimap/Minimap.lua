-- Minimap Drawer: one movable button on the minimap; clicking it opens a drawer that holds every other minimap icon
-- (addon buttons and Blizzard's tracking / mail / battleground / LFG icons), except zoom in/out and the calendar.
-- The drawer is organised in categories; every icon has a label under it like a desktop icon. Press "Edit" in the drawer to add,
-- rename, move and delete categories, and to rename an icon, move it to another category or pick its picture (or go back to the default).
-- Client-only. /mmd = open, /mmd edit | list | ignore <name> | unignore <name> | reset
local ADDON = "wotlk_minimap"
local DB
local COLS, CELL_W, CELL_H, PAD, HDR, FOOT = 5, 68, 58, 10, 24, 30

-- never collected: zoom, calendar, and things on the minimap that are not icons (zone text, clock, our own button)
local SKIP = {
    MinimapZoomIn = true, MinimapZoomOut = true, GameTimeFrame = true,
    MinimapZoneTextButton = true, TimeManagerClockButton = true, MinimapBackdrop = true, MinimapCluster = true,
    Minimap = true, MiniMapPing = true, WotlkMinimapDrawerButton = true, WotlkMinimapDrawer = true,
}
-- Blizzard icons that are plain frames, not buttons
local KNOWN = { "MiniMapTracking", "MiniMapMailFrame", "MiniMapBattlefieldFrame", "MiniMapLFGFrame", "MiniMapWorldMapButton", "MiniMapInstanceDifficulty", "MiniMapVoiceChatFrame" }
local NICE = {   -- labels for the icons that have ugly frame names
    MiniMapTracking = "Tracking", MiniMapMailFrame = "Mail", MiniMapBattlefieldFrame = "Battleground", MiniMapLFGFrame = "Dungeon Finder",
    MiniMapWorldMapButton = "World Map", MiniMapInstanceDifficulty = "Difficulty", MiniMapVoiceChatFrame = "Voice Chat",
}
local FALLBACK_ICONS = { "INV_Misc_Bag_10", "INV_Misc_Note_01", "INV_Misc_Map_01", "INV_Misc_Gear_01", "INV_Misc_Key_14", "INV_Misc_Book_09",
    "INV_Misc_Coin_01", "INV_Letter_15", "INV_Misc_QuestionMark", "Ability_Hunter_BeastCall", "Spell_Arcane_PortalStormWind", "Spell_Holy_HolyBolt",
    "INV_Sword_04", "INV_Shield_05", "INV_Potion_54", "INV_Misc_Gem_01", "Achievement_Dungeon_ClassicDungeonMaster", "Spell_Nature_Heal" }

local function noop() end
local function Key(f) return f:GetName() or tostring(f) end

-- ---- the drawer ----
local drawer = CreateFrame("Frame", "WotlkMinimapDrawer", UIParent)
drawer:SetFrameStrata("DIALOG"); drawer:SetClampedToScreen(true); drawer:Hide()
drawer:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
drawer:SetBackdropColor(0, 0, 0, 0.9)
tinsert(UISpecialFrames, "WotlkMinimapDrawer")   -- Esc closes it
local empty = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("CENTER"); empty:SetText("No minimap icons"); empty:Hide()

local btn = CreateFrame("Button", "WotlkMinimapDrawerButton", Minimap)
btn:SetSize(31, 31); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp"); btn:RegisterForDrag("LeftButton")
local border = btn:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53); border:SetPoint("TOPLEFT")
local icon = btn:CreateTexture(nil, "BACKGROUND"); icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mail = btn:CreateTexture(nil, "OVERLAY"); mail:SetTexture("Interface\\Icons\\INV_Letter_15")
mail:SetSize(12, 12); mail:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 4); mail:Hide()

-- ---- button position: an angle around the minimap, saved ----
local function Place()
    local a = math.rad(DB and DB.angle or 225)
    local w, h = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local x, y = math.cos(a), math.sin(a)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "ROUND" then x, y = x * (w + 5), y * (h + 5)
    else x, y = math.max(-w, math.min(w, x * w * 1.42)), math.max(-h, math.min(h, y * h * 1.42)) end
    btn:ClearAllPoints(); btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        DB.angle = math.deg(math.atan2(py / s - my, px / s - mx)) % 360
        Place()
    end)
end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

-- ---- collecting ----
local captured, order = {}, {}   -- captured[frame] = { set, clear, label = fontstring, tex, orig, over }
local function Ignored(name) return SKIP[name] or (DB and DB.ignore[name]) end

local function NewLabel()
    local fs = drawer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(CELL_W - 4); fs:SetHeight(24); fs:SetJustifyH("CENTER"); fs:SetJustifyV("TOP")
    fs:Hide()
    return fs
end

local function Capture(f)
    if captured[f] then return end
    local meta = getmetatable(f)
    local idx = meta and meta.__index
    if not idx or not idx.SetPoint then return end
    captured[f] = { set = idx.SetPoint, clear = idx.ClearAllPoints, label = NewLabel() }
    order[#order + 1] = f
    f:SetParent(drawer)
    f:SetFrameStrata("DIALOG"); f:SetFrameLevel(drawer:GetFrameLevel() + 2)
    pcall(f.RegisterForDrag, f)          -- no more dragging out of the drawer
    f.SetPoint, f.ClearAllPoints = noop, noop   -- the owner addon may try to put it back on the minimap
end

local function Small(f)
    local w, h = f:GetWidth(), f:GetHeight()
    return w and h and w > 4 and h > 4 and w <= 48 and h <= 48
end

-- Buttons are always taken. Plain frames (Atlas wraps its button in one) and buttons parented to UIParent but anchored
-- to the minimap are taken when they are icon-sized.
local function Candidate(f, strict)
    if not f or f == btn or f == drawer then return end
    local name = f:GetName()
    if not name or Ignored(name) then return end
    if strict then   -- found outside the minimap: only if it hangs on the minimap and looks like an icon
        local _, rel = f:GetPoint(1)
        return rel == Minimap and Small(f)
    end
    return f:IsObjectType("Button") or Small(f)
end

-- ---- our own launchers (shown only when that addon is installed) ----
local launchers = {}
local function Launcher(key, addon, iconPath, title, slash)
    local f = CreateFrame("Button", "WotlkMinimapLauncher" .. key, drawer)
    f:SetSize(31, 31)
    local bd = f:CreateTexture(nil, "OVERLAY"); bd:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); bd:SetSize(53, 53); bd:SetPoint("TOPLEFT")
    local ic = f:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(iconPath); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1)
    f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    f:SetScript("OnClick", function()
        drawer:Hide()
        local fn = SlashCmdList[slash]
        if fn then fn("") end
    end)
    f:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(title); GameTooltip:Show() end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.addon, f.icon, f.title = addon, ic, title
    local idx = getmetatable(f).__index
    captured[f] = { set = idx.SetPoint, clear = idx.ClearAllPoints, label = NewLabel() }
    launchers[#launchers + 1] = f
    return f
end
Launcher("Garrison", "wotlk_garrison", "Interface\\Icons\\Spell_Arcane_PortalStormWind", "Garrison", "WOTLKGARRISON")
Launcher("Jukebox", "wotlk_jukebox", "Interface\\Icons\\INV_Misc_Note_01", "Jukebox", "WOTLKJUKEBOX")
Launcher("Bots", "wotlk_botmanager", "Interface\\Icons\\Ability_Hunter_BeastCall", "Bot Manager", "WOTLKBOTS")
Launcher("Shop", "wotlk_shop", "Interface\\Icons\\INV_Misc_Coin_01", "Shop", "WOTLKSHOP")
local LAUNCHER_HOME = "Server"

-- ---- labels ----
local function DefaultLabel(f)
    local name = f:GetName() or "?"
    if f.title then return f.title end
    if NICE[name] then return NICE[name] end
    local s = name:gsub("^LibDBIcon10_", ""):gsub("^[Mm]ini[Mm]ap", ""):gsub("[Bb]utton$", ""):gsub("[Ff]rame$", ""):gsub("[Ii]con$", "")
    s = s:gsub("^[Mm]ini[Mm]ap", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then s = name end
    return s
end
local function Label(f) return (DB and DB.label[Key(f)]) or DefaultLabel(f) end

-- ---- icons (pick your own, or back to the default) ----
local function FindTex(f, depth)
    if f.icon and f.icon.SetTexture then return f.icon end
    if f.Icon and f.Icon.SetTexture then return f.Icon end
    local n = f:GetName()
    if n then
        for _, suffix in ipairs({ "Icon", "Texture" }) do
            local t = _G[n .. suffix]
            if t and t.SetTexture then return t end
        end
    end
    local best
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            local t = r:GetTexture()
            if type(t) == "string" then
                local l = t:lower()
                if not (l:find("border") or l:find("highlight") or l:find("background") or l:find("overlay") or l:find("tracking")) then
                    local w = r:GetWidth() or 0
                    if w > 0 and w <= 40 and (not best or w > best:GetWidth()) then best = r end
                end
            end
        end
    end
    if best then return best end
    if (depth or 0) < 1 then
        for _, ch in ipairs({ f:GetChildren() }) do
            local t = FindTex(ch, 1)
            if t then return t end
        end
    end
end

local function ApplyIcon(f)
    local c = captured[f]
    if not c then return end
    local path = DB.icon[Key(f)]
    if c.tex == nil then
        c.tex = FindTex(f) or false
        if c.tex then c.orig = c.tex:GetTexture(); c.coords = { c.tex:GetTexCoord() } end
    end
    local t = c.tex
    if not t then return end
    if path then
        if c.shown ~= path or t:GetTexture() ~= path then
            t:SetTexture(path); t:SetTexCoord(0.07, 0.93, 0.07, 0.93); c.shown = path
        end
    elseif c.shown then   -- back to the default
        t:SetTexture(c.orig)
        if c.coords and #c.coords == 8 then t:SetTexCoord(unpack(c.coords)) else t:SetTexCoord(0, 1, 0, 1) end
        c.shown = nil
    end
end

local iconList
local function Icons()
    if iconList then return iconList end
    iconList = {}
    if GetNumMacroIcons and GetMacroIconInfo then
        for i = 1, GetNumMacroIcons() do
            local n = GetMacroIconInfo(i)
            if n then iconList[#iconList + 1] = n end
        end
    end
    if #iconList == 0 then for _, n in ipairs(FALLBACK_ICONS) do iconList[#iconList + 1] = n end end
    return iconList
end
local function IconPath(n)
    if type(n) ~= "string" or n == "" then return end
    if n:find("\\") or n:find("/") then return n end
    return "Interface\\Icons\\" .. n
end

-- ---- popups ----
StaticPopupDialogs["WOTLKMMD_INPUT"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, maxLetters = 40, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        eb:SetText(self.data and self.data.text or ""); eb:HighlightText(); eb:SetFocus()
    end,
    OnAccept = function(self)
        local d = self.data
        if d and d.fn then d.fn(_G[self:GetName() .. "EditBox"]:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local d = p.data
        if d and d.fn then d.fn(self:GetText()) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
StaticPopupDialogs["WOTLKMMD_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self) local d = self.data; if d and d.fn then d.fn() end end,
}
local function Ask(title, prefill, fn) StaticPopup_Show("WOTLKMMD_INPUT", title, nil, { text = prefill, fn = fn }) end
local function Confirm(title, fn) StaticPopup_Show("WOTLKMMD_CONFIRM", title, nil, { fn = fn }) end

-- ---- categories ----
local editing = false
local Layout   -- forward

local function CatIndex(name) for i, c in ipairs(DB.cats) do if c == name then return i end end end
local function ValidCat(name) return name and CatIndex(name) and name or DB.home end
local function CatOf(f)
    local k = Key(f)
    return ValidCat(DB.assign[k] or (f.addon and LAUNCHER_HOME))
end
local function AddCat(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    if CatIndex(name) then UIErrorsFrame:AddMessage("That category already exists.", 1, 0.2, 0.2); return end
    DB.cats[#DB.cats + 1] = name
    Layout()
end
local function RenameCat(old, new)
    new = (new or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if new == "" or new == old then return end
    if CatIndex(new) then UIErrorsFrame:AddMessage("That category already exists.", 1, 0.2, 0.2); return end
    DB.cats[CatIndex(old)] = new
    if DB.home == old then DB.home = new end
    for k, v in pairs(DB.assign) do if v == old then DB.assign[k] = new end end
    Layout()
end
local function DeleteCat(name)
    if name == DB.home then return end
    table.remove(DB.cats, CatIndex(name))
    for k, v in pairs(DB.assign) do if v == name then DB.assign[k] = nil end end   -- they fall back to the home category
    Layout()
end
local function MoveCat(name, dir)
    local i = CatIndex(name)
    local j = i + dir
    if not DB.cats[j] then return end
    DB.cats[i], DB.cats[j] = DB.cats[j], DB.cats[i]
    Layout()
end

-- ---- icon picker ----
local picker
local PCOLS, PROWS = 8, 5
local function BuildPicker()
    if picker then return picker end
    local p = CreateFrame("Frame", "WotlkMinimapIconPicker", UIParent)
    p:SetSize(PCOLS * 38 + 28, PROWS * 38 + 118); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:EnableMouse(true)
    p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    p:Hide(); tinsert(UISpecialFrames, "WotlkMinimapIconPicker")
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); p.title:SetPoint("TOP", 0, -16)
    p.page = 1
    p.cells = {}
    local function Refresh()
        local list = Icons()
        local per = PCOLS * PROWS
        local pages = math.max(1, math.ceil(#list / per))
        if p.page > pages then p.page = pages end
        if p.page < 1 then p.page = 1 end
        p.pageText:SetText(p.page .. " / " .. pages)
        for i, cell in ipairs(p.cells) do
            local n = list[(p.page - 1) * per + i]
            cell.name = n
            if n then cell.tex:SetTexture(IconPath(n)); cell:Show() else cell:Hide() end
        end
    end
    p.Refresh = Refresh
    local function Choose(path)
        if p.target then
            if path then DB.icon[p.target] = path else DB.icon[p.target] = nil end
            Layout()
        end
        p:Hide()
    end
    for i = 1, PCOLS * PROWS do
        local c = CreateFrame("Button", nil, p)
        c:SetSize(34, 34)
        c:SetPoint("TOPLEFT", 14 + ((i - 1) % PCOLS) * 38, -40 - math.floor((i - 1) / PCOLS) * 38)
        c.tex = c:CreateTexture(nil, "ARTWORK"); c.tex:SetAllPoints(); c.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        c:SetScript("OnClick", function(self) Choose(IconPath(self.name)) end)
        c:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.name or ""); GameTooltip:Show() end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.cells[i] = c
    end
    local function Btn(text, w, x, y, fn)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetText(text); b:SetPoint("BOTTOMLEFT", x, y); b:SetScript("OnClick", fn)
        return b
    end
    local bottom = 16
    Btn("<", 28, 14, bottom + 62, function() p.page = p.page - 1; Refresh() end)
    Btn(">", 28, 14 + 28 + 60, bottom + 62, function() p.page = p.page + 1; Refresh() end)
    p.pageText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.pageText:SetPoint("BOTTOMLEFT", 14 + 28 + 4, bottom + 66); p.pageText:SetWidth(56)
    local eb = CreateFrame("EditBox", "WotlkMinimapIconBox", p, "InputBoxTemplate")
    eb:SetSize(170, 20); eb:SetPoint("BOTTOMLEFT", 20 + 100, bottom + 63); eb:SetAutoFocus(false); eb:SetMaxLetters(120)
    local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lbl:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -4, 2); lbl:SetText("or type an icon name, e.g. INV_Misc_Bag_10")
    local function UseTyped() local t = eb:GetText(); if t ~= "" then Choose(IconPath(t)) end end
    eb:SetScript("OnEnterPressed", UseTyped); eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Btn("Use", 44, 20 + 100 + 176, bottom + 62, UseTyped)
    Btn("Default icon", 100, 14, bottom, function() Choose(nil) end)
    Btn("Cancel", 80, p:GetWidth() - 14 - 80 - 8, bottom, function() p:Hide() end)
    picker = p
    return p
end
local function OpenPicker(f)
    local p = BuildPicker()
    p.target = Key(f)
    p.title:SetText("Icon for " .. Label(f))
    p.Refresh()
    p:Show()
end

-- ---- right-click menu in edit mode ----
local menuFrame
local function ItemMenu(f)
    menuFrame = menuFrame or CreateFrame("Frame", "WotlkMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    local k = Key(f)
    local cur = CatOf(f)
    local list = { { text = Label(f), isTitle = true, notCheckable = true } }
    for _, c in ipairs(DB.cats) do
        list[#list + 1] = { text = "Move to: " .. c, checked = (c == cur), func = function() DB.assign[k] = c; Layout() end }
    end
    list[#list + 1] = { text = "Rename label...", notCheckable = true, func = function() Ask("Label for this icon:", Label(f), function(t)
        t = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
        DB.label[k] = (t ~= "" and t ~= DefaultLabel(f)) and t or nil; Layout() end) end }
    list[#list + 1] = { text = "Reset label", notCheckable = true, func = function() DB.label[k] = nil; Layout() end }
    list[#list + 1] = { text = "Choose icon...", notCheckable = true, func = function() OpenPicker(f) end }
    list[#list + 1] = { text = "Reset icon to default", notCheckable = true, func = function() DB.icon[k] = nil; Layout() end }
    list[#list + 1] = { text = "Close", notCheckable = true, func = function() end }
    EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end

-- ---- layout ----
local headers, overlays, headerUsed = {}, {}, 0
local footerEdit, footerAdd

local function GetHeader(i)
    local h = headers[i]
    if h then return h end
    h = CreateFrame("Frame", nil, drawer)
    h:SetSize(COLS * CELL_W, HDR)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h.text:SetPoint("LEFT", 2, 0); h.text:SetJustifyH("LEFT")
    h.line = h:CreateTexture(nil, "ARTWORK"); h.line:SetTexture(1, 1, 1, 0.15); h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT", 0, 0); h.line:SetPoint("BOTTOMRIGHT", 0, 0)
    local function B(text, w)
        local b = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
        b:SetSize(w, 18); b:SetText(text)
        return b
    end
    h.del, h.ren, h.dn, h.up = B("Delete", 50), B("Rename", 54), B("Down", 40), B("Up", 30)
    h.del:SetPoint("RIGHT", 0, 1); h.ren:SetPoint("RIGHT", h.del, "LEFT", -2, 0)
    h.dn:SetPoint("RIGHT", h.ren, "LEFT", -2, 0); h.up:SetPoint("RIGHT", h.dn, "LEFT", -2, 0)
    h.ren:SetScript("OnClick", function() Ask("New name for the category '" .. h.cat .. "':", h.cat, function(t) RenameCat(h.cat, t) end) end)
    h.del:SetScript("OnClick", function() Confirm("Delete the category '" .. h.cat .. "'? Its icons go back to '" .. DB.home .. "'.", function() DeleteCat(h.cat) end) end)
    h.up:SetScript("OnClick", function() MoveCat(h.cat, -1) end)
    h.dn:SetScript("OnClick", function() MoveCat(h.cat, 1) end)
    headers[i] = h
    return h
end

local function GetOverlay(f)
    local c = captured[f]
    if c.over then return c.over end
    local o = CreateFrame("Button", nil, drawer)
    o:SetSize(CELL_W - 4, CELL_H - 4); o:SetFrameLevel(drawer:GetFrameLevel() + 20)
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    o:SetScript("OnClick", function() ItemMenu(f) end)
    o:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Click to edit " .. Label(f)); GameTooltip:Show() end)
    o:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.over = o
    return o
end

local function BuildFooter()
    if footerEdit then return end
    footerEdit = CreateFrame("Button", nil, drawer, "UIPanelButtonTemplate")
    footerEdit:SetSize(90, 22)
    footerEdit:SetScript("OnClick", function() editing = not editing; Layout() end)
    footerAdd = CreateFrame("Button", nil, drawer, "UIPanelButtonTemplate")
    footerAdd:SetSize(100, 22); footerAdd:SetText("+ Category")
    footerAdd:SetScript("OnClick", function() Ask("Name of the new category:", "", AddCat) end)
end

Layout = function()
    BuildFooter()
    for _, h in ipairs(headers) do h:Hide() end
    for _, c in pairs(captured) do c.label:Hide(); if c.over then c.over:Hide() end end

    -- which launchers exist
    local items = {}
    for _, f in ipairs(launchers) do
        if IsAddOnLoaded(f.addon) then f:Show(); items[#items + 1] = f else f:Hide() end
    end
    for _, f in ipairs(order) do if f:IsShown() then items[#items + 1] = f end end

    local byCat = {}
    for _, f in ipairs(items) do
        local c = CatOf(f)
        byCat[c] = byCat[c] or {}
        table.insert(byCat[c], f)
        ApplyIcon(f)
    end
    for _, list in pairs(byCat) do table.sort(list, function(a, b) return Label(a):lower() < Label(b):lower() end) end

    local y, hi = PAD, 0
    for _, cat in ipairs(DB.cats) do
        local list = byCat[cat] or {}
        if #list > 0 or editing then
            hi = hi + 1
            local h = GetHeader(hi)
            h.cat = cat
            h:ClearAllPoints(); h:SetPoint("TOPLEFT", drawer, "TOPLEFT", PAD, -y)
            h.text:SetText(cat)
            if editing then
                h.ren:Show(); h.up:Show(); h.dn:Show()
                if cat == DB.home then h.del:Hide() else h.del:Show() end
            else h.ren:Hide(); h.del:Hide(); h.up:Hide(); h.dn:Hide() end
            h:Show()
            y = y + HDR + 4
            for i, f in ipairs(list) do
                local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
                local cx = PAD + col * CELL_W + CELL_W / 2
                local top = y + row * CELL_H
                local c = captured[f]
                c.clear(f); c.set(f, "CENTER", drawer, "TOPLEFT", cx, -(top + 20))
                c.label:ClearAllPoints(); c.label:SetPoint("TOP", drawer, "TOPLEFT", cx, -(top + 38))
                c.label:SetText(Label(f)); c.label:Show()
                if editing then
                    local o = GetOverlay(f)
                    o:ClearAllPoints(); o:SetPoint("TOP", drawer, "TOPLEFT", cx, -(top + 2)); o:Show()
                end
            end
            y = y + math.ceil(#list / COLS) * CELL_H + 6
            if #list == 0 then y = y + 4 end
        end
    end
    if hi == 0 then empty:Show(); y = y + 30 else empty:Hide() end

    footerEdit:SetText(editing and "Done" or "Edit")
    footerEdit:ClearAllPoints(); footerEdit:SetPoint("TOPLEFT", drawer, "TOPLEFT", PAD, -(y + 4))
    footerAdd:ClearAllPoints(); footerAdd:SetPoint("LEFT", footerEdit, "RIGHT", 6, 0)
    if editing then footerAdd:Show() else footerAdd:Hide() end
    drawer:SetSize(COLS * CELL_W + PAD * 2, y + FOOT + PAD - 4)
end

local function Scan()
    for _, parent in ipairs({ Minimap, MinimapCluster, MinimapBackdrop }) do
        if parent then
            for _, f in ipairs({ parent:GetChildren() }) do
                if Candidate(f) then Capture(f) end
            end
        end
    end
    for _, f in ipairs({ UIParent:GetChildren() }) do   -- some addons parent their icon to the screen and anchor it to the minimap
        if not captured[f] and Candidate(f, true) then Capture(f) end
    end
    for _, n in ipairs(KNOWN) do
        local f = _G[n]
        if f and not Ignored(n) and not captured[f] then Capture(f) end
    end
    -- anything the player told us to ignore comes out of the list
    for i = #order, 1, -1 do
        local f = order[i]
        local n = f:GetName()
        if n and DB.ignore[n] then
            local c = captured[f]
            f.SetPoint, f.ClearAllPoints = nil, nil
            f:SetParent(Minimap)
            c.clear(f); c.set(f, "CENTER", Minimap, "CENTER", 0, 0)
            c.label:Hide(); if c.over then c.over:Hide() end
            captured[f] = nil; table.remove(order, i)
        end
    end
end

local function Anchor()   -- open the drawer on the side of the button that has room
    local bx, by = btn:GetCenter()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local right, top = bx > sw / 2, by > sh / 2
    drawer:ClearAllPoints()
    drawer:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), btn,
        (top and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT"), 0, top and -2 or 2)
end

local function Toggle()
    if drawer:IsShown() then drawer:Hide(); return end
    Scan(); Layout(); Anchor(); drawer:Show()
end
btn:SetScript("OnClick", Toggle)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Minimap icons")
    GameTooltip:AddLine("Click to open the drawer. Drag to move this button.", 1, 1, 1, true)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
drawer:SetScript("OnHide", function() editing = false end)

-- keep it current: addons add their minimap buttons late, and icons like mail appear and disappear
local acc = 0
drawer:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    if not StaticPopup_Visible("WOTLKMMD_INPUT") then Layout() end
end)
local tick = CreateFrame("Frame")
local t2 = 0
tick:SetScript("OnUpdate", function(_, dt)
    t2 = t2 + dt
    if t2 < 2 then return end
    t2 = 0
    if DB then
        Scan()
        if HasNewMail and HasNewMail() then mail:Show() else mail:Hide() end
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, e, a)
    if e == "ADDON_LOADED" and a == ADDON then
        WotlkMinimapDB = WotlkMinimapDB or {}
        DB = WotlkMinimapDB
        DB.angle = DB.angle or 225
        DB.ignore = DB.ignore or {}
        DB.assign = DB.assign or {}   -- icon name -> category
        DB.label = DB.label or {}     -- icon name -> your own label
        DB.icon = DB.icon or {}       -- icon name -> your own picture
        if not DB.cats then DB.cats = { "Other", LAUNCHER_HOME }; DB.home = "Other" end
        DB.home = DB.home or DB.cats[1]
        Place()
    elseif e == "PLAYER_ENTERING_WORLD" and DB then
        Place(); Scan()
    end
end)

-- ---- /mmd ----
SLASH_WOTLKMMD1 = "/mmd"
SlashCmdList["WOTLKMMD"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local function say(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMinimap Drawer:|r " .. s) end
    if cmd == "" then Toggle()
    elseif cmd == "edit" then
        if not drawer:IsShown() then Toggle() end
        editing = true; Layout()
    elseif cmd == "list" then
        Scan()
        if #order == 0 then say("nothing collected yet.") end
        for _, f in ipairs(order) do say((f:GetName() or "?") .. (f:IsShown() and "" or "  (hidden)")) end
        local ig = {}
        for k in pairs(DB.ignore) do ig[#ig + 1] = k end
        if #ig > 0 then table.sort(ig); say("ignored: " .. table.concat(ig, ", ")) end
    elseif cmd == "ignore" and arg ~= "" then DB.ignore[arg] = true; Scan(); say(arg .. " stays on the minimap.")
    elseif cmd == "unignore" and arg ~= "" then DB.ignore[arg] = nil; Scan(); say(arg .. " goes into the drawer again.")
    elseif cmd == "reset" then DB.angle = 225; Place(); say("button moved back.")
    else say("/mmd  (open)   /mmd edit   /mmd list   /mmd ignore <name>   /mmd unignore <name>   /mmd reset") end
end
