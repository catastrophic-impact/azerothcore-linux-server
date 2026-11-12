-- Pet Journal: owned battle pets (Pets tab) and team setup (Teams tab). Server module "pbj" (scripts/pb_store.lua).  /pets
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
                   tile = true, tileSize = 32, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
local TESTING = true   -- shows the "Grant test pets" button (remove once pets come from real sources)
local ARCH = { Tank = { 0.45, 0.65, 1 }, Melee = { 1, 0.45, 0.35 }, Caster = { 0.75, 0.5, 1 }, Support = { 0.4, 0.9, 0.5 } }
local SLOTNAME = { "Basic", "Utility", "Major" }
local GOLD = { 1, 0.82, 0 }
local QCOL = { { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } }   -- common / uncommon / rare / epic: white, green, blue, purple
local QHEX = { "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee" }
local QNAME = { "Common", "Uncommon", "Rare", "Epic" }


local S = { pets = {}, abil = {}, teams = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }, active = 1, follow = 0, sel = nil, tab = 1, primed = false, filter = "", asked = {} }
local frame, rowsHolder, rows, scroll, search, tabs, paneP, paneT, model, modelFor
local function ShowIf(f, c) if c then f:Show() else f:Hide() end end
local function Num(x) return tonumber(x) or 0 end
local function Color(fs, a) local c = ARCH[a] or { 1, 1, 1 }; fs:SetTextColor(c[1], c[2], c[3]) end

local function Sorted()
    local t = {}
    local f = S.filter:lower()
    for sp, p in pairs(S.pets) do if f == "" or p.name:lower():find(f, 1, true) then t[#t + 1] = sp end end
    table.sort(t, function(a, b) return S.pets[a].name < S.pets[b].name end)
    return t
end

local function Icon(p) return "Interface\\Icons\\" .. p.icon end
local Refresh

---------------------------------------------------------------- left list
local function BuildList()
    search = CreateFrame("EditBox", "WotlkPetsSearch", frame, "InputBoxTemplate")
    search:SetSize(200, 20); search:SetPoint("TOPLEFT", 30, -62); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self) S.filter = self:GetText() or ""; Refresh() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("LEFT", search, "RIGHT", 6, 0); hint:SetText("Search")

    local holder = CreateFrame("Frame", nil, frame); holder:SetPoint("TOPLEFT", 20, -90); holder:SetSize(262, 410)
    holder:SetBackdrop(BACKDROP)
    scroll = CreateFrame("ScrollFrame", "WotlkPetsScroll", holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    rowsHolder = CreateFrame("Frame", nil, scroll); rowsHolder:SetSize(226, 10); scroll:SetScrollChild(rowsHolder)
    rows = {}
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, rowsHolder)
    r:SetSize(226, 40); r:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetTexture(0.15, 0.12, 0.05, 0.6)
    r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(32, 32); r.icon:SetPoint("LEFT", 4, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2); r.name:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
    r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.lvl:SetPoint("RIGHT", -8, 0)
    r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    r:SetScript("OnClick", function(self) S.sel = self.sp; S.asked[self.sp] = nil; Refresh() end)
    rows[i] = r
    return r
end

---------------------------------------------------------------- Pets tab (details)
local function BuildPets()
    paneP = CreateFrame("Frame", nil, frame); paneP:SetPoint("TOPLEFT", 296, -62); paneP:SetPoint("BOTTOMRIGHT", -20, 16)
    paneP.empty = paneP:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); paneP.empty:SetPoint("CENTER"); paneP.empty:SetText("Select a pet on the left.")
    local d = CreateFrame("Frame", nil, paneP); d:SetAllPoints(); paneP.d = d
    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); d.name:SetPoint("TOPLEFT", 4, -2)
    d.sub = d:CreateFontString(nil, "OVERLAY", "GameFontNormal"); d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    local mf = CreateFrame("Frame", nil, d); mf:SetSize(250, 250); mf:SetPoint("TOPLEFT", 0, -50); mf:SetBackdrop(BACKDROP)
    model = CreateFrame("PlayerModel", nil, mf); model:SetPoint("TOPLEFT", 6, -6); model:SetPoint("BOTTOMRIGHT", -6, 6)
    d.loading = mf:CreateFontString(nil, "OVERLAY", "GameFontDisable"); d.loading:SetPoint("CENTER"); d.loading:SetText("Loading preview...")
    d.stats = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); d.stats:SetPoint("TOPLEFT", mf, "TOPRIGHT", 16, -4); d.stats:SetJustifyH("LEFT")
    d.sum = CreateFrame("Button", nil, d, "UIPanelButtonTemplate"); d.sum:SetSize(130, 24); d.sum:SetPoint("TOPLEFT", d.stats, "BOTTOMLEFT", 0, -22)
    d.sum:SetScript("OnClick", function()
        if not S.sel then return end
        if S.follow == S.sel then AcoreLib.Send("pbj", "dismiss", "") else AcoreLib.Send("pbj", "summon", S.sel) end
    end)
    d.xp = CreateFrame("StatusBar", nil, d); d.xp:SetSize(196, 12); d.xp:SetPoint("TOPLEFT", d.stats, "BOTTOMLEFT", 0, -100)
    d.xp:SetStatusBarTexture(WHITE); d.xp:SetStatusBarColor(0.6, 0.3, 0.9); d.xp:SetMinMaxValues(0, 100)
    d.xp.bg = d.xp:CreateTexture(nil, "BACKGROUND"); d.xp.bg:SetAllPoints(); d.xp.bg:SetTexture(0, 0, 0, 0.6)
    d.xp.t = d.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); d.xp.t:SetPoint("CENTER")

    d.ab = {}
    for slot = 1, 3 do
        local lab = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); lab:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 2, -12 - (slot - 1) * 50); lab:SetText(SLOTNAME[slot])
        for opt = 1, 2 do
            local b = CreateFrame("Button", nil, d); b:SetSize(208, 38)
            b:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 56 + (opt - 1) * 216, -2 - (slot - 1) * 50)   -- 2 x 208 + gap = fits the 484 wide pane
            b:SetBackdrop(BACKDROP)
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(28, 28); b.icon:SetPoint("LEFT", 6, 0)
            b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
            b.cd = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.cd:SetPoint("RIGHT", -28, 0)
            b.check = b:CreateTexture(nil, "OVERLAY"); b.check:SetSize(22, 22); b.check:SetPoint("RIGHT", -4, 0); b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            b:SetScript("OnEnter", function(self)
                local a = self.a; if not a then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(a.name, 1, 0.82, 0); GameTooltip:AddLine(a.tip, 1, 1, 1, 1)
                if a.cd > 0 then GameTooltip:AddLine("Cooldown: " .. a.cd .. " rounds", 0.7, 0.7, 0.7) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function()
                local p = S.sel and S.pets[S.sel]; if not p then return end
                p.a[slot] = opt; AcoreLib.Send("pbj", "setabil", S.sel .. "," .. slot .. "," .. opt); Refresh()
            end)
            d.ab[slot .. "," .. opt] = b
        end
    end
end

local function RefreshPets()
    local p = S.sel and S.pets[S.sel]
    ShowIf(paneP.empty, not p); ShowIf(paneP.d, p ~= nil)
    if not p then return end
    local d = paneP.d
    d.name:SetText(p.name); d.name:SetTextColor(unpack(QCOL[p.quality or 1])); d.sub:SetText(QNAME[p.quality or 1] .. " " .. p.arch .. "  -  Level " .. p.level); Color(d.sub, p.arch)
    d.stats:SetText("Health   |cffffffff" .. (p.cur or p.hp) .. " / " .. p.hp .. "|r\nAttack   |cffffffff" .. p.dmg .. "|r\nArchetype   |cffffffff" .. p.arch .. "|r\nQuality   " .. QHEX[p.quality or 1] .. QNAME[p.quality or 1] .. "|r")
    d.sum:SetText(S.follow == S.sel and "Dismiss" or "Summon Pet")
    d.xp:SetValue(math.min(100, p.xp)); d.xp.t:SetText("Experience " .. p.xp .. " / 100")
    if modelFor ~= S.sel then
        modelFor = S.sel
        if S.primed then model:SetCreature(S.sel); model:SetRotation(0.61); d.loading:Hide() else d.loading:Show() end
    end
    if not S.abil[S.sel] and not S.asked[S.sel] then S.asked[S.sel] = true; AcoreLib.Send("pbj", "abil", S.sel) end
    for slot = 1, 3 do for opt = 1, 2 do
        local b = d.ab[slot .. "," .. opt]
        local a = S.abil[S.sel] and S.abil[S.sel][slot .. "," .. opt]
        b.a = a
        if a then
            b.icon:SetTexture("Interface\\Icons\\" .. a.icon); b.name:SetText(a.name); b.cd:SetText(p.level < (a.unlock or 1) and ("Lv " .. a.unlock) or (a.cd > 0 and ("CD " .. a.cd) or ""))
            local on = p.a[slot] == opt and p.level >= (a.unlock or 1)
            ShowIf(b.check, on)
            if on then b:SetBackdropBorderColor(1, 0.82, 0) else b:SetBackdropBorderColor(0.5, 0.5, 0.5) end
            b.icon:SetDesaturated(not on)
        else b.name:SetText("..."); b.icon:SetTexture(nil); b.cd:SetText(""); b.check:Hide() end
    end end
end

---------------------------------------------------------------- Teams tab
local function SendTeam(n) local t = S.teams[n]; AcoreLib.Send("pbj", "setteam", n .. "," .. t[1] .. "," .. t[2] .. "," .. t[3]) end

local function BuildTeams()
    paneT = CreateFrame("Frame", nil, frame); paneT:SetPoint("TOPLEFT", 296, -62); paneT:SetPoint("BOTTOMRIGHT", -20, 16)
    paneT.hint = paneT:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); paneT.hint:SetPoint("TOPLEFT", 4, 0); paneT.hint:SetWidth(470); paneT.hint:SetJustifyH("LEFT")
    paneT.hint:SetText("Select a pet on the left, then click a slot to put it there. Right-click a slot to empty it. The ACTIVE team is the one you fight with.")
    paneT.box = {}
    for n = 1, 3 do
        local box = CreateFrame("Frame", nil, paneT); box:SetSize(474, 108); box:SetPoint("TOPLEFT", 0, -34 - (n - 1) * 116); box:SetBackdrop(BACKDROP)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); box.title:SetPoint("TOPLEFT", 14, -10); box.title:SetText("Team " .. n)
        box.act = CreateFrame("Button", nil, box, "UIPanelButtonTemplate"); box.act:SetSize(110, 22); box.act:SetPoint("TOPRIGHT", -12, -8)
        box.act:SetScript("OnClick", function() S.active = n; AcoreLib.Send("pbj", "active", n); Refresh() end)
        box.slot = {}
        for i = 1, 3 do
            local b = CreateFrame("Button", nil, box); b:SetSize(140, 52); b:SetPoint("TOPLEFT", 14 + (i - 1) * 150, -42); b:SetBackdrop(BACKDROP)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(36, 36); b.icon:SetPoint("LEFT", 8, 0)
            b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -1); b.name:SetWidth(86); b.name:SetJustifyH("LEFT")
            b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 1)
            b.empty = b:CreateFontString(nil, "OVERLAY", "GameFontDisable"); b.empty:SetPoint("CENTER"); b.empty:SetText("Empty")
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
            b:SetScript("OnClick", function(_, button)
                local t = S.teams[n]
                if button == "RightButton" then t[i] = 0
                elseif S.sel and S.pets[S.sel] then
                    local old = t[i]
                    for k = 1, 3 do if t[k] == S.sel then t[k] = old end end   -- already in this team: swap places
                    t[i] = S.sel
                end
                SendTeam(n); Refresh()
            end)
            box.slot[i] = b
        end
        paneT.box[n] = box
    end
end

local function RefreshTeams()
    for n = 1, 3 do
        local box = paneT.box[n]
        box.act:SetText(S.active == n and "ACTIVE" or "Make active")
        if S.active == n then box.act:Disable(); box.title:SetTextColor(0.4, 1, 0.4) else box.act:Enable(); box.title:SetTextColor(1, 0.82, 0) end
        for i = 1, 3 do
            local b, sp = box.slot[i], S.teams[n][i]
            local p = sp ~= 0 and S.pets[sp]
            ShowIf(b.icon, p ~= false and p ~= nil and p ~= 0); ShowIf(b.name, p and true or false); ShowIf(b.sub, p and true or false); ShowIf(b.empty, not p)
            if p then
                b.icon:SetTexture(Icon(p)); b.name:SetText(p.name); b.name:SetTextColor(unpack(QCOL[p.quality or 1])); b.sub:SetText("Lv " .. p.level .. " " .. p.arch); Color(b.sub, p.arch)
                b:SetBackdropBorderColor(0.9, 0.75, 0.2)
            else b:SetBackdropBorderColor(0.4, 0.4, 0.4) end
        end
    end
end

---------------------------------------------------------------- shell
function Refresh()
    if not frame or not frame:IsShown() then return end
    local list = Sorted()
    for i, sp in ipairs(list) do
        local r, p = Row(i), S.pets[sp]
        r.sp = sp; r:Show(); r.icon:SetTexture(Icon(p)); r.name:SetText(p.name); r.name:SetTextColor(unpack(QCOL[p.quality or 1])); r.lvl:SetText(p.level)
        r.sub:SetText(p.arch .. (S.follow == sp and "  |cff66ff66(following)|r" or "")); Color(r.sub, p.arch); ShowIf(r.sel, S.sel == sp)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    rowsHolder:SetHeight(math.max(10, #list * 42))
    frame.count:SetText(#list .. " pets")
    ShowIf(paneP, S.tab == 1); ShowIf(paneT, S.tab == 2)
    for i, t in ipairs(tabs) do if i == S.tab then t:LockHighlight() else t:UnlockHighlight() end end
    if S.tab == 1 then RefreshPets() else RefreshTeams() end
end

local function Build()
    frame = CreateFrame("Frame", "WotlkPetsFrame", UIParent)
    frame:SetSize(800, 560); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:SetBackdrop(BACKDROP)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    AcoreLib.Solid(frame, 4, 0.07, 0.06, 0.05)
    frame:Hide(); tinsert(UISpecialFrames, "WotlkPetsFrame")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 22, -18); title:SetText("Pet Journal")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); frame.count:SetPoint("BOTTOMLEFT", 26, 20)
    tabs = {}
    for i, name in ipairs({ "Pets", "Teams" }) do
        local t = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); t:SetSize(100, 24); t:SetPoint("TOPRIGHT", -40 - (2 - i) * 106, -16); t:SetText(name)
        t:SetScript("OnClick", function() S.tab = i; Refresh() end); tabs[i] = t
    end
    BuildList(); BuildPets(); BuildTeams()
    if TESTING then
        local g = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); g:SetSize(120, 22); g:SetPoint("BOTTOMLEFT", 110, 16); g:SetText("Grant test pets")
        g:SetScript("OnClick", function() AcoreLib.Send("pbj", "grant", "") end)
    end
end

AcoreLib.On("pbj", "pet", function(p)
    local sp, lv, xp, a1, a2, a3, arch, icon, hp, dmg, q, cur, name = p:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%a+),([^,]+),(%d+),(%d+),(%d+),(%d+),(.+)$")
    if not sp then return end
    S.pets[Num(sp)] = { level = Num(lv), xp = Num(xp), a = { Num(a1), Num(a2), Num(a3) }, arch = arch, icon = icon, hp = Num(hp), dmg = Num(dmg), quality = Num(q), cur = Num(cur), name = name }
    Refresh()
end)
AcoreLib.On("pbj", "team", function(p) local n, a, b, c = p:match("^(%d),(%d+),(%d+),(%d+)$"); if n then S.teams[Num(n)] = { Num(a), Num(b), Num(c) }; Refresh() end end)
AcoreLib.On("pbj", "follow", function(p) S.follow = Num(p); Refresh() end)
AcoreLib.On("pbj", "active", function(p) S.active = Num(p); Refresh() end)
AcoreLib.On("pbj", "done", function() Refresh() end)
AcoreLib.On("pbj", "abl", function(p)
    local sp, slot, opt, icon, name, tip, cd, unlock = p:match("^(%d+),(%d),(%d)|([^#]*)#([^#]*)#([^#]*)#(%d+)#(%d+)$")
    if not sp then return end
    sp = Num(sp); S.abil[sp] = S.abil[sp] or {}
    S.abil[sp][slot .. "," .. opt] = { icon = icon, name = name, tip = tip, cd = Num(cd), unlock = Num(unlock) }
    Refresh()
end)
AcoreLib.On("pbj", "primed", function() S.primed = true; modelFor = nil; Refresh() end)

SLASH_PETS1 = "/pets"; SLASH_PETS2 = "/petjournal"
SlashCmdList["PETS"] = function()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() return end
    frame:Show(); Refresh()
    AcoreLib.Send("pbj", "list", "")
    if not S.primed then AcoreLib.Send("pbj", "prime", "") end
end
