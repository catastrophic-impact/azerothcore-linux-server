-- Bot Manager v0.2: add companions by class/spec or role, smart Fill Group (asks each real player's role), remove bots.
-- Offline companions are removed from the party here with UninviteUnit (normal game path; the server never edits groups). /bots
local CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "dk", "shaman", "mage", "warlock", "druid" }
local NAMES = { warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue", priest = "Priest", dk = "Death Knight",
                shaman = "Shaman", mage = "Mage", warlock = "Warlock", druid = "Druid" }
local TOKEN_OF = { warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST", dk = "DEATHKNIGHT",
                   shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID" }
local TOKEN_BY_ID = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }
local ROLE_COLOR = { Tank = "|cff5aa9ff", Healer = "|cff5aff7a", DPS = "|cffff6a5a" }
local SPECS = {   -- { spec string for the server, label, role }
    warrior = { { "prot pve", "Protection", "Tank" }, { "fury pve", "Fury", "DPS" }, { "arms pve", "Arms", "DPS" } },
    paladin = { { "prot pve", "Protection", "Tank" }, { "holy pve", "Holy", "Healer" }, { "ret pve", "Retribution", "DPS" } },
    hunter  = { { "bm pve", "Beast Mastery", "DPS" }, { "mm pve", "Marksmanship", "DPS" }, { "survival pve", "Survival", "DPS" } },
    rogue   = { { "as pve", "Assassination", "DPS" }, { "combat pve", "Combat", "DPS" }, { "subtlety pve", "Subtlety", "DPS" } },
    priest  = { { "holy pve", "Holy", "Healer" }, { "disc pve", "Discipline", "Healer" }, { "shadow pve", "Shadow", "DPS" } },
    dk      = { { "blood pve", "Blood", "Tank" }, { "frost pve", "Frost", "DPS" }, { "unholy pve", "Unholy", "DPS" } },
    shaman  = { { "resto pve", "Restoration", "Healer" }, { "ele pve", "Elemental", "DPS" }, { "enh pve", "Enhancement", "DPS" } },
    mage    = { { "arcane pve", "Arcane", "DPS" }, { "fire pve", "Fire", "DPS" }, { "frost pve", "Frost", "DPS" } },
    warlock = { { "affli pve", "Affliction", "DPS" }, { "demo pve", "Demonology", "DPS" }, { "destro pve", "Destruction", "DPS" } },
    druid   = { { "bear pve", "Bear Tank", "Tank" }, { "cat pve", "Cat DPS", "DPS" }, { "resto pve", "Restoration", "Healer" }, { "balance pve", "Balance", "DPS" } },
}
local PANEL = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local frame, fill, statusText
local classBtns, specBtns, rows, humanRows = {}, {}, {}, {}
local selectedClass
local humans, roleChoice = {}, {}

local function Color(token) return (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]) or { r = 1, g = 1, b = 1 } end
local function SetStatus(t, r, g, b) if statusText then statusText:SetText(t or ""); statusText:SetTextColor(r or 0.9, g or 0.9, b or 0.9) end end
local function Icon(parent, token, size)
    local t = parent:CreateTexture(nil, "ARTWORK"); t:SetSize(size, size); t:SetTexture(ICONS)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if c then t:SetTexCoord(c[1], c[2], c[3], c[4]) end
    return t
end
local function Panel(parent, w, h, x, y, title)
    local p = CreateFrame("Frame", nil, parent); p:SetSize(w, h); p:SetPoint("TOPLEFT", x, y)
    p:SetBackdrop(PANEL); p:SetBackdropColor(0.06, 0.06, 0.08, 1)
    local f = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f:SetPoint("TOPLEFT", 12, -10); f:SetText(title)
    return p
end
local function Btn(parent, w, h, text, x, y, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn)
    return b
end

-- ---- persistent set of companion names (so offline ones can be cleaned out of the party later) ----
local function Known() WotlkBotsDB = WotlkBotsDB or {}; WotlkBotsDB.names = WotlkBotsDB.names or {}; return WotlkBotsDB.names end

-- ---- class -> spec buttons ----
local function ShowSpecs(class)
    selectedClass = class
    if frame and frame.hint then frame.hint:Hide() end
    for i, b in ipairs(specBtns) do
        local s = SPECS[class][i]
        if s then b:SetText(("%s  %s(%s)|r"):format(s[2], ROLE_COLOR[s[3]], s[3])); b.spec = s[1]; b:Show() else b:Hide() end
    end
    for c, b in pairs(classBtns) do if c == class then b:LockHighlight() else b:UnlockHighlight() end end
end

-- ---- companion list ----
local function RefreshList(payload)
    for i = 1, #rows do rows[i]:Hide() end
    local n, known = 0, Known()
    for entry in (payload or ""):gmatch("[^|]+") do
        local name, cls, lvl, role = entry:match("^([^:]+):(%d+):(%d+):?(%a*)$")
        if name then
            n = n + 1; known[name] = true
            local r = rows[n]
            if not r then
                r = CreateFrame("Frame", nil, frame.right); r:SetSize(298, 30); r:SetPoint("TOPLEFT", 14, -34 - (n - 1) * 34)
                r.icon = Icon(r, "WARRIOR", 24); r.icon:SetPoint("LEFT", 0, 0)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 5)
                r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.sub:SetPoint("LEFT", r.icon, "RIGHT", 6, -8)
                r.rm = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.rm:SetSize(70, 22); r.rm:SetPoint("RIGHT", 0, 0); r.rm:SetText("Remove")
                r.rm:SetScript("OnClick", function(self)
                    local row = self:GetParent(); row:Hide()      -- disappear immediately; the server confirms
                    AcoreLib.Send("bots", "remove", row.botName)
                end)
                rows[n] = r
            end
            local token = TOKEN_BY_ID[tonumber(cls)] or "WARRIOR"
            local c = Color(token)
            local c2 = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
            if c2 then r.icon:SetTexCoord(c2[1], c2[2], c2[3], c2[4]) end
            r.text:SetText(name); r.text:SetTextColor(c.r, c.g, c.b)
            role = (role ~= "" and role) or "DPS"
            r.sub:SetText(("Level %s   %s%s|r"):format(lvl, ROLE_COLOR[role] or "", role))
            r.botName = name; r:Show()
        end
    end
    if n == 0 then frame.empty:Show() else frame.empty:Hide() end
end

-- ---- offline companions leave the party (leader only; never touches server groups) ----
local ticker, acc = CreateFrame("Frame"), 0
ticker:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 3 then return end
    acc = 0
    if not IsPartyLeader() then return end
    local known = Known()
    for i = 1, GetNumPartyMembers() do
        local unit = "party" .. i
        local name = UnitName(unit)
        if name and known[name] and not UnitIsConnected(unit) then UninviteUnit(name) end
    end
end)

-- ---- Fill Group dialog: ask each real player's role ----
local function BuildFill()
    fill = CreateFrame("Frame", "WotlkBotFillFrame", frame)
    fill:SetSize(420, 250); fill:SetPoint("CENTER", frame, "CENTER", 0, 10)
    fill:SetFrameStrata("DIALOG"); fill:SetFrameLevel(frame:GetFrameLevel() + 40)
    fill:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                       tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(fill, 9)
    fill:EnableMouse(true); fill:Hide()
    local t = fill:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOP", 0, -20); t:SetText("Who is playing?")
    local d = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); d:SetPoint("TOP", 0, -46); d:SetWidth(370)
    d:SetText("Pick each player's role. Companions fill whatever the group still needs: one tank, one healer, the rest DPS.")
    fill.go = Btn(fill, 130, 26, "Fill group", 60, -208, function()
        local parts = {}
        for _, h in ipairs(humans) do parts[#parts + 1] = h.name .. "=" .. (roleChoice[h.name] or "DPS") end
        AcoreLib.Send("bots", "fill", table.concat(parts, ";")); fill:Hide(); SetStatus("Filling your group...", 1, 1, 0.5)
    end)
    Btn(fill, 130, 26, "Cancel", 230, -208, function() fill:Hide() end)
end

local function BuildHumanRows()
    if not fill then return end
    for _, r in ipairs(humanRows) do r:Hide() end
    for i, h in ipairs(humans) do
        local r = humanRows[i]
        if not r then
            r = CreateFrame("Frame", nil, fill); r:SetSize(380, 30); r:SetPoint("TOPLEFT", 20, -82 - (i - 1) * 24)
            r.icon = Icon(r, "WARRIOR", 20); r.icon:SetPoint("LEFT", 0, 0)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.btn = {}
            for k, role in ipairs({ "Tank", "Healer", "DPS" }) do
                local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); b:SetSize(64, 20); b:SetPoint("RIGHT", -(3 - k) * 68, 0)
                b:SetText(ROLE_COLOR[role] .. role .. "|r")
                b:SetScript("OnClick", function(self) roleChoice[self:GetParent().pname] = role; BuildHumanRows() end)
                r.btn[role] = b
            end
            humanRows[i] = r
        end
        local c = Color(TOKEN_BY_ID[h.cls] or "WARRIOR"); local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[TOKEN_BY_ID[h.cls] or "WARRIOR"]
        if tc then r.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        r.name:SetText(h.name); r.name:SetTextColor(c.r, c.g, c.b); r.pname = h.name
        local pick = roleChoice[h.name] or "DPS"
        for role, b in pairs(r.btn) do if role == pick then b:LockHighlight() else b:UnlockHighlight() end end
        r:Show()
    end
    fill:SetHeight(150 + #humans * 24 + 36)
    fill.go:ClearAllPoints(); fill.go:SetPoint("BOTTOMLEFT", 60, 22)
end

local function OpenFill()
    if not fill then BuildFill() end
    AcoreLib.Send("bots", "humans", "")
    BuildHumanRows(); fill:Show(); fill:Raise()
end

-- ---- main window ----
local function Build()
    frame = CreateFrame("Frame", "WotlkBotManagerFrame", UIParent)
    frame:SetSize(694, 470); frame:SetPoint("CENTER"); frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(frame, 9)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WotlkBotManagerFrame")
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); t:SetPoint("TOP", 0, -18); t:SetText("Bot Manager")
    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sub:SetPoint("TOP", 0, -40); sub:SetText("Companions join your group while you play. Nothing permanent.")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); statusText:SetPoint("BOTTOM", 0, 20); statusText:SetWidth(640)

    -- left: class + spec
    local left = Panel(frame, 326, 380, 18, -62, "ADD A COMPANION")
    for i, c in ipairs(CLASSES) do
        local b = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
        b:SetSize(148, 28); b:SetPoint("TOPLEFT", 12 + ((i - 1) % 2) * 153, -34 - math.floor((i - 1) / 2) * 32)
        b:SetText(NAMES[c]); local fs = b:GetFontString(); local col = Color(TOKEN_OF[c]); fs:SetTextColor(col.r, col.g, col.b); fs:ClearAllPoints(); fs:SetPoint("CENTER", 10, 0)
        local ic = Icon(b, TOKEN_OF[c], 20); ic:SetPoint("LEFT", 8, 0)
        b:SetScript("OnClick", function() ShowSpecs(c) end)
        classBtns[c] = b
    end
    local sh = left:CreateFontString(nil, "OVERLAY", "GameFontNormal"); sh:SetPoint("TOPLEFT", 12, -204); sh:SetText("Specialization")
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
        b:SetSize(302, 28); b:SetPoint("TOPLEFT", 12, -226 - (i - 1) * 32)
        b:SetScript("OnClick", function(self)
            if selectedClass and self.spec then AcoreLib.Send("bots", "add", selectedClass .. ":" .. self.spec); SetStatus("Summoning...", 1, 1, 0.5) end
        end)
        b:Hide(); specBtns[i] = b
    end
    local hint = left:CreateFontString(nil, "OVERLAY", "GameFontDisable"); hint:SetPoint("TOPLEFT", 12, -230); hint:SetText("Choose a class first.")
    left.hint = hint
    frame.hint = hint

    -- right: companions, quick add, fill, remove all
    local right = Panel(frame, 326, 380, 350, -62, "YOUR COMPANIONS")
    frame.right = right
    frame.empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable"); frame.empty:SetPoint("TOPLEFT", 14, -40); frame.empty:SetText("No companions yet.")
    local qa = right:CreateFontString(nil, "OVERLAY", "GameFontNormal"); qa:SetPoint("TOPLEFT", 12, -186); qa:SetText("Quick add (random class)")
    for i, role in ipairs({ "Tank", "Healer", "DPS" }) do
        Btn(right, 98, 26, ROLE_COLOR[role] .. "Random " .. role .. "|r", 12 + (i - 1) * 102, -208, function() AcoreLib.Send("bots", "role", role); SetStatus("Summoning...", 1, 1, 0.5) end)
    end
    local fg = right:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fg:SetPoint("TOPLEFT", 12, -252); fg:SetText("Fill my group")
    Btn(right, 302, 28, "Fill Group  (asks each player's role)", 12, -274, OpenFill)
    local ra = Btn(right, 302, 28, "|cffff8080Remove All Companions|r", 12, -334, function()
        for i = 1, #rows do rows[i]:Hide() end; frame.empty:Show()      -- clear the list right away
        AcoreLib.Send("bots", "removeall", "")
    end)
    frame:SetScript("OnHide", function() if fill then fill:Hide() end end)
    frame:Hide()
end

AcoreLib.On("bots", "list", function(p) RefreshList(p) end)
AcoreLib.On("bots", "humans", function(p)
    humans = {}
    for entry in (p or ""):gmatch("[^|]+") do
        local n, c = entry:match("^([^:]+):(%d+):")
        if n then humans[#humans + 1] = { name = n, cls = tonumber(c) } end
    end
    BuildHumanRows()
end)
AcoreLib.On("bots", "res", function(p) SetStatus(p, 0.8, 1, 0.8) end)

SLASH_WOTLKBOTS1 = "/bots"
SLASH_WOTLKBOTS2 = "/botmanager"
SlashCmdList["WOTLKBOTS"] = function()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); AcoreLib.Send("bots", "list", "") end
end
