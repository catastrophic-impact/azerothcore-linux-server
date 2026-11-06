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

    -- "Show garrison radius": the server spawns a ring of markers on the garrison edge
    local ring = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); ring:SetSize(24, 24); ring:SetPoint("BOTTOMLEFT", 16, 14)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); label:SetPoint("LEFT", ring, "RIGHT", 2, 0)
    label:SetText("Show garrison radius (glowing ring, owner only)")
    ring:SetScript("OnClick", function(self) AcoreLib.Send("house", "ring", self:GetChecked() and "1" or "0") end)

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
AcoreLib.On("house", "head", function(p) st.inHome = p:sub(1, 1) == "1"; st.placed, st.decor, st.decorCount = {}, {}, {}; G.Refresh() end)
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
    if msg:match("^admin") and WotlkGarrisonOpenAdmin then return WotlkGarrisonOpenAdmin() end   -- wotlk_garrison_admin (tools/, not shipped)
    if not ui.frame then Build() end
    if ui.frame:IsShown() then ui.frame:Hide() else
        G.Request(); G.Refresh(); ui.frame:Show()
        if not st.primed then AcoreLib.Send("house", "prime", "") end   -- the server primes the client's creature-model cache for NPC previews
    end
end
