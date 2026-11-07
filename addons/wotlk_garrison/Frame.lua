-- Main window, server messages and the /garrison command.
local G = WotlkGarrison
local C, st, ui = G.C, G.st, G.ui

local function Build()
    local frame = CreateFrame("Frame", "WotlkGarrisonFrame", UIParent)
    ui.frame = frame
    frame:SetSize(800, 600); frame:SetPoint("CENTER", -120, 0); frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(frame, 9)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WotlkGarrisonFrame")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -18); title:SetText("Garrison")
    ui.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.statusText:SetPoint("TOP", 0, -42)
    ui.msgText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ui.msgText:SetPoint("BOTTOM", 0, 20)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
    local exit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); exit:SetSize(110, 24); exit:SetPoint("TOPRIGHT", -42, -14); exit:SetText("Exit Garrison")
    exit:SetScript("OnClick", function() StaticPopup_Show("WOTLKGARRISON_EXIT") end)   -- confirm first: it teleports you out

    -- "Show garrison radius": the server spawns a ring of markers on the garrison edge
    local ring = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); ring:SetSize(24, 24); ring:SetPoint("BOTTOMLEFT", 16, 14)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); label:SetPoint("LEFT", ring, "RIGHT", 2, 0)
    label:SetText("Show garrison radius (glowing ring, owner only)")
    ring:SetScript("OnClick", function(self) AcoreLib.Send("house", "ring", self:GetChecked() and "1" or "0") end)
    ui.ring = ring

    -- tabs: the catalog's (NPCs, Objects) plus the client-only "Placed" tab
    ui.tabBtns = {}
    local function AddTab(i, key, text, onclick)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); b:SetSize(100, 28)
        b:SetPoint("TOPLEFT", 22 + (i - 1) * 104, -62); b:SetText(text); b:SetScript("OnClick", onclick); ui.tabBtns[key] = b
    end
    for i, t in ipairs(C.tabs) do
        AddTab(i, t.key, t.key == "npcs" and "NPCs" or "Objects", function() st.tab, st.cat = t.key, t.cats[1]; G.Select(nil); G.Refresh() end)
    end
    AddTab(#C.tabs + 1, "placed", "Placed", function() st.tab = "placed"; G.Select(nil); G.Request(); G.Refresh() end)

    G.BuildScroll(frame)
    G.BuildGrid(frame)
    G.BuildPad(frame)
    local previewBg = G.BuildPreview(frame)
    G.BuildActions(frame, previewBg)
    frame:SetScript("OnHide", G.Unmark)
    frame:Hide()
end

-- server -> client
AcoreLib.On("house", "head", function(p)
    st.inHome = p:sub(1, 1) == "1"; st.placed, st.decor, st.decorCount = {}, {}, {}
    if not st.inHome and G.HideLeaveWarning then G.HideLeaveWarning() end
    if G.wantOpen then   -- /garrison asked the server where we are: open only inside our own garrison
        G.wantOpen = false
        if st.inHome then
            if not ui.frame then Build() end
            G.Refresh(); ui.frame:Show()
            if not st.primed then AcoreLib.Send("house", "prime", "") end   -- the server primes the client's creature-model cache for NPC previews
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGarrison:|r You can only open the garrison window inside your own garrison (use the portal at the Mage Tower).")
        end
        return
    end
    if not st.inHome and ui.frame and ui.frame:IsShown() then ui.frame:Hide() end   -- left the garrison: close the window
    G.Refresh()
end)
-- "Exit Garrison" button: ask first, it teleports you out
StaticPopupDialogs["WOTLKGARRISON_EXIT"] = {
    text = "Leave your garrison and return to the Mage Tower?", button1 = "Leave", button2 = "Stay", timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function() AcoreLib.Send("house", "exit", ""); if ui.frame then ui.frame:Hide() end end,
}
-- server: "you crossed the border": a big countdown in the middle of the screen; walking back in (or leaving) hides it. The server does the teleport.
local warn = CreateFrame("Frame", "WotlkGarrisonLeaveWarn", UIParent); warn:SetSize(700, 80); warn:SetPoint("TOP", 0, -180); warn:SetFrameStrata("FULLSCREEN_DIALOG"); warn:Hide()
warn.text = warn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); warn.text:SetPoint("CENTER")
warn.left, warn.total = 0, 0
warn:SetScript("OnUpdate", function(self, elapsed)
    self.left = self.left - elapsed
    if self.left <= 0 then self:Hide(); return end
    self.text:SetText(string.format("|cffff4040You are leaving your garrison|r\nReturning to the Mage Tower in |cffffffff%d|r - walk back inside to stay", math.ceil(self.left)))
end)
function G.HideLeaveWarning() warn:Hide() end
AcoreLib.On("house", "leaveask", function(p) warn.total = tonumber(p) or 5; warn.left = warn.total; warn:Show(); PlaySound("RaidWarning") end)
AcoreLib.On("house", "leavecancel", function() warn:Hide() end)
AcoreLib.On("house", "ringreq", function() if ui.ring and ui.ring:GetChecked() then AcoreLib.Send("house", "ring", "1") end end)
AcoreLib.On("house", "admok", function() if G.wantAdmin then G.wantAdmin = false; if WotlkGarrisonOpenAdmin then WotlkGarrisonOpenAdmin() end end end)
AcoreLib.On("house", "admno", function() if G.wantAdmin then G.wantAdmin = false; DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGarrison:|r The admin tool needs a GM account of level 3 or higher.") end end)
AcoreLib.On("house", "cur", function(p) local mode, item = p:match("^(%a+),(%d+)$"); if mode then st.currency, st.currencyItem = mode, tonumber(item) end end)
AcoreLib.On("house", "placed", function(p) for k in p:gmatch("[^,]+") do st.placed[k] = true end; G.Refresh() end)
AcoreLib.On("house", "dplaced", function(p)
    for did, kind in p:gmatch("(%d+):([^,]+)") do
        st.decor[#st.decor + 1] = { did = tonumber(did), kind = kind }
        st.decorCount[kind] = (st.decorCount[kind] or 0) + 1
    end
    G.Refresh()
end)
AcoreLib.On("house", "dnew", function(p) end)   -- stay on the current tab (the Placed list still refreshes)
AcoreLib.On("house", "res", function(p) G.SetMsg(p, 0.6, 1, 0.6); if G.PM then G.PM.Msg(p) end; G.Request() end)
AcoreLib.On("house", "primed", function() st.primed = true; if st.selected then G.Preview(st.selected) end; G.Refresh() end)

SLASH_WOTLKGARRISON1 = "/garrison"
SlashCmdList["WOTLKGARRISON"] = function(msg)
    msg = (msg or ""):lower()
    if msg:match("^admin") then   -- wotlk_garrison_admin (tools/, not shipped): the server decides (GM level 3+), anywhere in the world
        if not WotlkGarrisonOpenAdmin then return end
        G.wantAdmin = true; AcoreLib.Send("house", "adm", ""); return
    end
    if ui.frame and ui.frame:IsShown() then ui.frame:Hide(); return end
    G.wantOpen = true; G.Request()   -- the answer ("head") opens the window if we are inside our own garrison
end
