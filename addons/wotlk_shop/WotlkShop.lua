-- Shop: category list, paged card grid, detail pane with 3D preview, confirmation popup,
-- server-validated purchases (see scripts/shop_server.lua). Open with /shop
local C = WotlkShopCatalog
local COLS, ROWS = 3, 4
local PER_PAGE = COLS * ROWS
local balance, current, page, selected = 0, "pets", 1, nil
local frame, cards, catButtons = nil, {}, {}
local primed = false
local cfg = { mode = "item", item = 19182, gold = { pet = 100, mount = 500, toy = 100, service = 0 }, svc = 0 }
local KIND = { pets = "pet", mounts = "mount", toys = "toy", services = "service" }
local function Money(c)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t = {}
    if g > 0 then t[#t + 1] = ("|cffffd100%d|rg"):format(g) end
    if s > 0 then t[#t + 1] = ("|cffc0c0c0%d|rs"):format(s) end
    if k > 0 or #t == 0 then t[#t + 1] = ("|cffeda55f%d|rc"):format(k) end
    return table.concat(t, " ")
end
local function CurName()
    local n = GetItemInfo(cfg.item)
    if n then return n end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE"); GameTooltip:SetHyperlink("item:" .. cfg.item); GameTooltip:Hide()   -- ask the client to cache it
    return cfg.item == 19182 and "Darkmoon Faire Prize Ticket" or "items"
end
local function Price(e)   -- copper (gold mode) or item count
    if cfg.mode == "gold" then return (cfg.gold[KIND[current]] or 0) * 10000 end
    if current == "services" then return cfg.svc end
    return e.cost
end
local function Fmt(n, long)
    if n == 0 then return "|cff00ff00Free|r" end
    if cfg.mode == "gold" then return Money(n) end
    return long and ("|cffffd100%d|r %s"):format(n, CurName()) or ("|cffffd100%d|r"):format(n)
end
local balText, msgText, pageText, prevBtn, nextBtn, bigIcon, model, dName, dCost, buyBtn, dHint

local function SetMsg(t, r, g, b) if msgText then msgText:SetText(t or ""); msgText:SetTextColor(r or 1, g or 1, b or 1) end end
local function Icon(e) return "Interface\\Icons\\" .. (e.icon ~= "" and e.icon or "INV_Misc_QuestionMark") end

local confirm, ShowConfirm

local function BuildConfirm()
    confirm = CreateFrame("Frame", "WotlkShopConfirm", frame)
    confirm:SetSize(400, 160); confirm:SetPoint("CENTER", frame, "CENTER", 0, 20)
    confirm:SetFrameStrata("DIALOG"); confirm:SetFrameLevel(frame:GetFrameLevel() + 50)
    confirm:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                          edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
                          insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(confirm, 9)
    confirm:EnableMouse(true); confirm:Hide()
    confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    confirm.text:SetPoint("TOP", 0, -28); confirm.text:SetWidth(340)
    local yes = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); yes:SetSize(120, 28); yes:SetPoint("BOTTOMLEFT", 60, 22); yes:SetText("Buy")
    local no = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); no:SetSize(120, 28); no:SetPoint("BOTTOMRIGHT", -60, 22); no:SetText("Cancel")
    yes:SetScript("OnClick", function()
        local e = confirm.entry; confirm:Hide()
        if e then SetMsg("Buying " .. e.name .. "...", 1, 1, 0); AcoreLib.Send("shop", "buy", e.id) end
    end)
    no:SetScript("OnClick", function() confirm:Hide() end)
end

ShowConfirm = function(e)
    if not confirm then BuildConfirm() end
    confirm.entry = e
    local pr = Price(e)
    if pr == 0 then
        confirm.text:SetText(("Get |cffffd100%s|r?\n\nThis is free."):format(e.name))
    else
        confirm.text:SetText(("Buy |cffffd100%s|r for %s?\n\nYou will have %s left."):format(e.name, Fmt(pr, true), cfg.mode == "gold" and Money(balance - pr) or tostring(balance - pr)))
    end
    confirm:Show(); confirm:Raise()
end

local function Report(tag)
    WotlkShopDB = WotlkShopDB or {}
    local d = WotlkShopDB
    d.build = (GetBuildInfo())
    d.shopStrata = frame and frame:GetFrameStrata()
    d.confirmStrata = confirm and confirm:GetFrameStrata()
    d.confirmLevel = confirm and confirm:GetFrameLevel()
    d.shopLevel = frame and frame:GetFrameLevel()
    d.selected = selected and selected.name or nil
    d.cards = {}
    for i = 1, PER_PAGE do if cards[i] and cards[i]:IsShown() then d.cards[#d.cards + 1] = cards[i].entry.name end end
    d.lastEvent = tag
end

local function ShowDetail(e)
    selected = e
    if not e then
        dName:SetText(""); dCost:SetText(""); buyBtn:Hide(); bigIcon:Hide(); model:Hide(); dHint:SetText("Select an item to preview it"); dHint:Show(); return
    end
    dHint:Hide(); dName:SetText(e.name)
    local pr = Price(e)
    dCost:SetText(Fmt(pr, true))
    buyBtn:SetText(pr == 0 and "Get" or "Buy")
    buyBtn:Show()
    if balance >= pr then buyBtn:Enable() else buyBtn:Disable() end
    if e.npc and e.npc > 0 then
        bigIcon:Hide()
        if primed then
            model:Show(); model:ClearModel(); model:SetCreature(e.npc)
            if model.SetRotation then model:SetRotation(0.61) end
            dHint:Hide()
        else
            model:Hide(); dHint:SetText("Loading preview..."); dHint:Show()
        end
    else
        model:Hide(); bigIcon:SetTexture(Icon(e)); bigIcon:Show(); dHint:Hide()
    end
    Report("select")
end

local function Refresh()
    if not frame then return end
    balText:SetText(cfg.mode == "gold" and ("Gold: " .. Money(balance)) or ("%s: |cffffd100%d|r"):format(CurName(), balance))
    local list = C.items[current] or {}
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    if page > pages then page = pages end
    pageText:SetText(("Page %d / %d"):format(page, pages))
    if page > 1 then prevBtn:Enable() else prevBtn:Disable() end
    if page < pages then nextBtn:Enable() else nextBtn:Disable() end
    for i = 1, PER_PAGE do
        local c, e = cards[i], list[(page - 1) * PER_PAGE + i]
        c.entry = e
        if e then
            c.icon:SetTexture(Icon(e)); c.name:SetText(e.name)
            c.cost:SetText(Fmt(Price(e)))
            if selected and selected.id == e.id then c.sel:Show() else c.sel:Hide() end
            c:Show()
        else
            c:Hide()
        end
    end
    for tab, b in pairs(catButtons) do
        if tab == current then b:LockHighlight() else b:UnlockHighlight() end
    end
    if selected then ShowDetail(selected) end
end

local function Build()
    frame = CreateFrame("Frame", "WotlkShopFrame", UIParent)
    frame:SetSize(960, 540); frame:SetPoint("CENTER"); frame:SetFrameStrata("MEDIUM")   -- below StaticPopup (DIALOG) so the confirm popup is not hidden
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
                        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(frame, 9)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WotlkShopFrame")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -18); title:SetText("Shop")
    balText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); balText:SetPoint("TOPRIGHT", -44, -22)
    msgText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); msgText:SetPoint("BOTTOM", 0, 20)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)

    -- categories (left)
    for i, tab in ipairs(C.tabs) do
        local b = CreateFrame("Button", "WotlkShopCat" .. i, frame, "UIPanelButtonTemplate")
        b:SetSize(150, 34); b:SetPoint("TOPLEFT", 22, -60 - (i - 1) * 40); b:SetText(C.titles[tab])
        b:SetScript("OnClick", function() current, page = tab, 1; ShowDetail(nil); SetMsg(""); Refresh() end)
        catButtons[tab] = b
    end

    -- card grid (middle)
    for i = 1, PER_PAGE do
        local c = CreateFrame("Button", "WotlkShopCard" .. i, frame)
        c:SetSize(160, 96)
        c:SetPoint("TOPLEFT", 190 + ((i - 1) % COLS) * 166, -60 - math.floor((i - 1) / COLS) * 102)
        c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        c:SetBackdropColor(0.06, 0.06, 0.08, 1)
        c.sel = c:CreateTexture(nil, "BACKGROUND"); c.sel:SetAllPoints(); c.sel:SetTexture(1, 0.82, 0, 0.25); c.sel:Hide()
        c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(44, 44); c.icon:SetPoint("TOP", 0, -8)
        c.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.name:SetPoint("TOP", c.icon, "BOTTOM", 0, -3); c.name:SetWidth(150); c.name:SetHeight(26)
        c.cost = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.cost:SetPoint("BOTTOM", 0, 6)
        c:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        c:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); if self.entry.item and self.entry.item > 0 then GameTooltip:SetHyperlink("item:" .. self.entry.item); GameTooltip:Show() end end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c:SetScript("OnClick", function(self) ShowDetail(self.entry); Refresh() end)
        cards[i] = c
    end
    prevBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); prevBtn:SetSize(70, 24); prevBtn:SetPoint("BOTTOMLEFT", 270, 52); prevBtn:SetText("< Prev")
    nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); nextBtn:SetSize(70, 24); nextBtn:SetPoint("BOTTOMLEFT", 450, 52); nextBtn:SetText("Next >")
    pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); pageText:SetPoint("BOTTOMLEFT", 360, 56)
    prevBtn:SetScript("OnClick", function() page = page - 1; Refresh() end)
    nextBtn:SetScript("OnClick", function() page = page + 1; Refresh() end)

    -- detail pane (right)
    local mbg = CreateFrame("Frame", nil, frame)
    mbg:SetSize(220, 250); mbg:SetPoint("TOPRIGHT", -26, -60)
    mbg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    mbg:SetBackdropColor(0.06, 0.06, 0.08, 1)
    bigIcon = mbg:CreateTexture(nil, "ARTWORK"); bigIcon:SetSize(128, 128); bigIcon:SetPoint("CENTER", 0, 0); bigIcon:Hide()
    model = CreateFrame("PlayerModel", nil, mbg)   -- child of the pane, like the proven test layout
    model:SetPoint("TOPLEFT", mbg, "TOPLEFT", 4, -4); model:SetPoint("BOTTOMRIGHT", mbg, "BOTTOMRIGHT", -4, 4)
    model:SetFrameLevel(mbg:GetFrameLevel() + 5); model:Hide()
    dHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable"); dHint:SetPoint("TOPRIGHT", -40, -170); dHint:SetWidth(190); dHint:SetText("Select an item to preview it")
    dName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); dName:SetPoint("TOPRIGHT", -26, -324); dName:SetWidth(220)
    dCost = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); dCost:SetPoint("TOP", dName, "BOTTOM", 0, -8)
    buyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); buyBtn:SetSize(160, 32); buyBtn:SetPoint("TOP", dCost, "BOTTOM", 0, -14); buyBtn:SetText("Buy"); buyBtn:Hide()
    buyBtn:SetScript("OnClick", function()
        if not selected then return end
        if balance < Price(selected) then
            SetMsg(("Not enough funds: %s costs %s."):format(selected.name, Fmt(Price(selected), true)), 1, 0.3, 0.3); return
        end
        ShowConfirm(selected)
    end)
    frame:SetScript("OnHide", function() if confirm then confirm:Hide() end end)
    frame:Hide()
end

AcoreLib.On("shop", "primed", function() primed = true; if selected then ShowDetail(selected) end end)
AcoreLib.On("shop", "cfg", function(p)   -- mode;item;goldPet;goldMount;goldToy;goldService;serviceItemCost
    local m, it, gp, gm, gt, gs, sv = p:match("^(%a+);(%d+);(%d+);(%d+);(%d+);(%d+);(%d+)$")
    if not m then return end
    cfg.mode, cfg.item, cfg.svc = m, tonumber(it), tonumber(sv)
    cfg.gold = { pet = tonumber(gp), mount = tonumber(gm), toy = tonumber(gt), service = tonumber(gs) }
    Refresh()
end)
AcoreLib.On("shop", "bal", function(p) balance = tonumber(p) or 0; Refresh() end)
AcoreLib.On("shop", "res", function(p)
    local id, text = p:match("^(%d+);(.*)$")
    if text == "OK" then SetMsg("Purchased!", 0, 1, 0)
    elseif text and text:sub(1, 3) == "OK:" then SetMsg(text:sub(4), 0, 1, 0)
    else SetMsg(text or "Error", 1, 0.3, 0.3) end
end)

SLASH_WOTLKSHOP1 = "/shop"
SLASH_WOTLKSHOP2 = "/wotlkshop"
SlashCmdList["WOTLKSHOP"] = function()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else
        AcoreLib.Send("shop", "cfg", ""); AcoreLib.Send("shop", "bal", ""); Refresh(); frame:Show(); Report("open")
        if not primed then AcoreLib.Send("shop", "prime", "") end   -- ask the server to push the creature records once per session
    end
end
