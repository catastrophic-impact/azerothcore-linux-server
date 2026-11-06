-- Placement mode (client half): a small bar replaces the big window while the server shows a solid "ghost" of the item in front of you.
-- Enter = place, Esc = cancel (override bindings, only while the mode runs), buttons for turn / nearer / further. Server: garrison.lua "placement mode".
-- Safety: bindings are always cleared when the mode ends, the bar hides, you log out / zone, or the server stops answering (no "pbeat" for 6 s).
local G = WotlkGarrison
local st, ui = G.st, G.ui
local PM = { active = false }
G.PM = PM
local beat = 0

local function Clear()   -- ends the mode locally; idempotent
    if ui.pmBar then ClearOverrideBindings(ui.pmBar); ui.pmBar:Hide() end
    PM.active = false
end
function PM.End(reopen, text)
    local was = PM.active
    Clear()
    if not was then return end
    if text and text ~= "" then G.SetMsg(text, 1, 0.9, 0.5) end
    if reopen and ui.frame then G.Request(); G.Refresh(); ui.frame:Show() end
end

local function Build()
    local bar = CreateFrame("Frame", "WotlkGarrisonPlaceBar", UIParent)
    bar:SetSize(420, 96); bar:SetPoint("BOTTOM", 0, 140); bar:SetFrameStrata("DIALOG"); bar:EnableMouse(true)
    bar:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    AcoreLib.Solid(bar, 9)
    bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal"); bar.title:SetPoint("TOP", 0, -12)
    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bar.hint:SetPoint("TOP", 0, -30)
    bar.hint:SetText("Walk and turn to position it.  |cff00ff00Enter|r = place   |cffff8080Esc|r = cancel")
    bar.msg = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bar.msg:SetPoint("TOP", 0, -44)
    local function B(txt, w, x, fn, name)
        local b = CreateFrame("Button", name, bar, "UIPanelButtonTemplate"); b:SetSize(w, 24); b:SetPoint("BOTTOMLEFT", x, 12); b:SetText(txt); b:SetScript("OnClick", fn); return b
    end
    local ok = B("Place", 70, 14, function() if PM.active then AcoreLib.Send("house", "pconfirm", "") end end, "WotlkGarrisonPlaceOK")
    local cancel = B("Cancel", 70, 88, function() if PM.active then AcoreLib.Send("house", "pcancel", ""); PM.End(true, "Placement cancelled.") end end, "WotlkGarrisonPlaceCancel")
    B("Turn L", 56, 170, function() AcoreLib.Send("house", "prot", "-15") end)
    B("Turn R", 56, 230, function() AcoreLib.Send("house", "prot", "15") end)
    B("Nearer", 56, 296, function() AcoreLib.Send("house", "pdist", "-1") end)
    B("Further", 56, 356, function() AcoreLib.Send("house", "pdist", "1") end)
    bar:SetScript("OnHide", function(self) ClearOverrideBindings(self) end)
    bar:SetScript("OnUpdate", function()
        if PM.active and GetTime() - beat > 6 then PM.End(true, "Placement ended (no answer from the server).") end   -- watchdog: never stay stuck
    end)
    bar:Hide(); ui.pmBar = bar
end

function PM.Start(kind)
    if not ui.pmBar then Build() end
    local e = G.ItemByKind(kind)
    ui.pmBar.title:SetText("Placing: " .. (e and e.name or kind) .. (e and G.PriceText(e) or ""))
    ui.pmBar.msg:SetText("")
    PM.active, PM.kind, beat = true, kind, GetTime()
    if ui.frame then ui.frame:Hide() end
    ui.pmBar:Show()
    ClearOverrideBindings(ui.pmBar)
    SetOverrideBindingClick(ui.pmBar, true, "ENTER", "WotlkGarrisonPlaceOK")
    SetOverrideBindingClick(ui.pmBar, true, "NUMPADENTER", "WotlkGarrisonPlaceOK")
    SetOverrideBindingClick(ui.pmBar, true, "ESCAPE", "WotlkGarrisonPlaceCancel")
end

-- server -> client
AcoreLib.On("house", "pstart", function(kind) PM.Start(kind) end)
AcoreLib.On("house", "pbeat", function() beat = GetTime() end)
AcoreLib.On("house", "pok", function(p)
    if ui.pmBar and PM.active then ui.pmBar.msg:SetText(p == "1" and "" or "|cffff6060Outside your garrison: move back inside.|r") end
end)
AcoreLib.On("house", "pend", function(p) PM.End(true, p) end)   -- "" after a successful placement (the "dnew" message already selected the new item)
function PM.Msg(text) if ui.pmBar and PM.active then ui.pmBar.msg:SetText("|cffffd070" .. text .. "|r") end end

local ev = CreateFrame("Frame")   -- logging out / loading screens / dying: drop the mode and its key bindings
ev:RegisterEvent("PLAYER_LOGOUT"); ev:RegisterEvent("PLAYER_ENTERING_WORLD"); ev:RegisterEvent("PLAYER_DEAD")
ev:SetScript("OnEvent", function() if PM.active then AcoreLib.Send("house", "pcancel", ""); Clear() end end)
