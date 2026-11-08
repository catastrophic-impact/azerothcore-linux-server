-- Minimap Drawer: one movable button on the minimap; clicking it opens a drawer that holds every other minimap icon
-- (addon buttons and Blizzard's tracking / mail / battleground / LFG icons), except zoom in/out and the calendar.
-- Client-only. /mmd = open, /mmd list | ignore <name> | unignore <name> | reset
local ADDON = "wotlk_minimap"
local DB
local COLS, CELL, PAD = 5, 36, 10

-- never collected: zoom, calendar, and things on the minimap that are not icons (zone text, clock, our own button)
local SKIP = {
    MinimapZoomIn = true, MinimapZoomOut = true, GameTimeFrame = true,
    MinimapZoneTextButton = true, TimeManagerClockButton = true, MinimapBackdrop = true, MinimapCluster = true,
    Minimap = true, MiniMapPing = true, WotlkMinimapDrawerButton = true, WotlkMinimapDrawer = true,
}
-- Blizzard icons that are plain frames, not buttons
local KNOWN = { "MiniMapTracking", "MiniMapMailFrame", "MiniMapBattlefieldFrame", "MiniMapLFGFrame", "MiniMapWorldMapButton", "MiniMapInstanceDifficulty", "MiniMapVoiceChatFrame" }

local function noop() end

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
    else x, y = math.max(-w, math.min(w, x * w * 1.42)) , math.max(-h, math.min(h, y * h * 1.42)) end
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
local captured, order = {}, {}
local function Ignored(name) return SKIP[name] or (DB and DB.ignore[name]) end

local function Capture(f)
    if captured[f] then return end
    local meta = getmetatable(f)
    local idx = meta and meta.__index
    if not idx or not idx.SetPoint then return end
    captured[f] = { set = idx.SetPoint, clear = idx.ClearAllPoints }
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
            captured[f] = nil; table.remove(order, i)
        end
    end
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
    f.addon = addon
    launchers[#launchers + 1] = f
    return f
end
Launcher("Garrison", "wotlk_garrison", "Interface\\Icons\\Spell_Arcane_PortalStormWind", "Garrison", "WOTLKGARRISON")
Launcher("Jukebox", "wotlk_jukebox", "Interface\\Icons\\INV_Misc_Note_01", "Jukebox", "WOTLKJUKEBOX")
Launcher("Bots", "wotlk_botmanager", "Interface\\Icons\\Ability_Hunter_BeastCall", "Bot Manager", "WOTLKBOTS")
Launcher("Shop", "wotlk_shop", "Interface\\Icons\\INV_Misc_Coin_01", "Shop", "WOTLKSHOP")

local function Layout()
    local shown = {}
    for _, f in ipairs(launchers) do
        if IsAddOnLoaded(f.addon) then
            f:Show(); shown[#shown + 1] = f
            if not captured[f] then
                local idx = getmetatable(f).__index
                captured[f] = { set = idx.SetPoint, clear = idx.ClearAllPoints }
            end
        else f:Hide() end
    end
    for _, f in ipairs(order) do if f:IsShown() then shown[#shown + 1] = f end end
    local n = #shown
    local cols = math.max(1, math.min(COLS, n))
    local rows = math.max(1, math.ceil(n / COLS))
    drawer:SetSize(cols * CELL + PAD * 2, rows * CELL + PAD * 2)
    for i, f in ipairs(shown) do
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local d = captured[f]
        d.clear(f)
        d.set(f, "CENTER", drawer, "TOPLEFT", PAD + c * CELL + CELL / 2, -(PAD + r * CELL + CELL / 2))
    end
    if n == 0 then empty:Show() else empty:Hide() end
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

-- keep it current: addons add their minimap buttons late, and icons like mail appear and disappear
local acc = 0
drawer:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    Layout()
end)
local tick = CreateFrame("Frame")
local t2 = 0
tick:SetScript("OnUpdate", function(_, dt)
    t2 = t2 + dt
    if t2 < 2 then return end
    t2 = 0
    if DB then Scan(); if HasNewMail and HasNewMail() then mail:Show() else mail:Hide() end end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, e, a)
    if e == "ADDON_LOADED" and a == ADDON then
        WotlkMinimapDB = WotlkMinimapDB or {}
        DB = WotlkMinimapDB
        DB.angle = DB.angle or 225
        DB.ignore = DB.ignore or {}
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
    else say("/mmd  (open)   /mmd list   /mmd ignore <name>   /mmd unignore <name>   /mmd reset") end
end
