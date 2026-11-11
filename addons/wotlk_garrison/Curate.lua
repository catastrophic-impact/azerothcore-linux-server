-- Curator mode (GM level 3+): sort, rename, price and re-centre the decor catalog from inside the garrison window.
-- The server keeps the curation (scripts/garrison_curate.lua) and sends it to every client; this file holds the local copy, applies it over the
-- generated catalog, and builds the curator controls: the sort bar under the window, the Name / Price / view boxes, the category menu.
--   WotlkGarrisonDB.cur = { rev, items = {kind = {cat, name, price}}, fits = {lowercase model = {vs, vy, vz, vr}}, cats = {{name, price}} or nil }
local G = WotlkGarrison
local C, st, ui = G.C, G.st, G.ui
st.keep, st.undo, st.moved = {}, {}, 0

local function DB() WotlkGarrisonDB = WotlkGarrisonDB or {}; return WotlkGarrisonDB end
local function Cur()
    local d = DB()
    d.cur = d.cur or { rev = -1, items = {}, fits = {} }
    d.cur.items, d.cur.fits = d.cur.items or {}, d.cur.fits or {}
    return d.cur
end
local function Special(cat) return cat == "Unsorted" or cat == "Removed" end
local function Lower(s) return (s or ""):lower() end
local function Copy(t) local c = {}; for k, v in pairs(t or {}) do c[k] = v end; return c end
local function Msg(text) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffGarrison curator:|r " .. text) end

-- categories are always alphabetical (a subcategory follows its parent, also alphabetical); Unsorted, Removed last. Same rule as the server.
local function SortKey(n)
    local rank = n == "Removed" and 2 or (n == "Unsorted" and 1 or 0)
    local p, c = n:match("^(.-) > (.+)$")
    return rank, (p or n):lower(), p and c:lower() or ""
end
function G.SortCats(names)
    table.sort(names, function(a, b)
        local ra, pa, ca = SortKey(a); local rb, pb, cb = SortKey(b)
        if ra ~= rb then return ra < rb end
        if pa ~= pb then return pa < pb end
        return ca < cb
    end)
end
function G.CuratorOn() return (st.curator and DB().curatorOn) and true or false end

-- ---- apply the curation over the generated catalog (idempotent: always starts from the generated values kept in e.b) ----
function G.ApplyCur()
    local cur, tab, on = Cur(), G.TabDef("objects"), G.CuratorOn()
    if not tab then return end
    G.baseCats = G.baseCats or Copy(tab.cats)
    local names, prices = {}, {}
    if cur.cats then
        for i, c in ipairs(cur.cats) do names[i] = c.name; prices[c.name] = c.price end
    else
        for i, c in ipairs(G.baseCats) do names[i] = c; prices[c] = (C.catprice or {})[c] end
    end
    G.SortCats(names)
    tab.cats = names
    for _, e in ipairs(C.items) do
        if e.tab == "objects" then
            e.b = e.b or { cat = e.cat, name = e.name, vs = e.vs, vy = e.vy, vz = e.vz, vr = e.vr }
            local o = cur.items[e.kind]
            e.cat = (o and o.cat) or e.b.cat
            e.name = (o and o.name) or e.b.name
            e.price = (o and o.price) or e.ip or prices[e.cat] or 0
            local f = e.model ~= "" and cur.fits[Lower(e.model)]
            if f then e.vs, e.vy, e.vz, e.vr = f[1], f[2], f[3], f[4] else e.vs, e.vy, e.vz, e.vr = e.b.vs, e.b.vy, e.b.vz, e.b.vr end
            e.hidden = (Special(e.cat) and not on) or nil   -- Removed + Unsorted are hidden from players; a curator sees them
        end
    end
end

-- ---- server -> client ----
local function Split(s)
    local t, pos = {}, 1
    while true do
        local i = s:find("~", pos, true)
        if not i then t[#t + 1] = s:sub(pos); break end
        t[#t + 1] = s:sub(pos, i - 1); pos = i + 1
    end
    return t
end
local lastAsk = 0
function G.CurSync()   -- ask for the whole curation (throttled)
    if GetTime() - lastAsk < 4 then return end
    lastAsk = GetTime(); AcoreLib.Send("house", "curget", "")
end
local function SameItem(a, b) a, b = a or {}, b or {}; return a.cat == b.cat and a.name == b.name and a.price == b.price end
-- one record; returns true when it changed anything
local function ApplyRecord(cur, rec)
    local t = Split(rec)
    if t[1] == "i" then
        local o = { cat = t[3] ~= "" and t[3] or nil, name = t[4] ~= "" and t[4] or nil, price = tonumber(t[5]) }
        if not (o.cat or o.name or o.price) then o = nil end
        local same = SameItem(cur.items[t[2]], o)
        cur.items[t[2]] = o; return not same
    elseif t[1] == "f" then
        local f = { tonumber(t[3]), tonumber(t[4]), tonumber(t[5]), tonumber(t[6]) }
        local old = cur.fits[t[2]]
        local same = old and old[1] == f[1] and old[2] == f[2] and old[3] == f[3] and old[4] == f[4]
        cur.fits[t[2]] = f; return not same
    end
end
local buf = {}
AcoreLib.On("house", "curgm", function(p)
    local was = st.curator
    st.curator = p == "1"
    if st.curator ~= was then G.ApplyCur(); G.Refresh() end
end)
AcoreLib.On("house", "currev", function(p) if tonumber(p) ~= Cur().rev then G.CurSync() end end)
AcoreLib.On("house", "curbad", function() Cur().rev = -1; Msg("the server refused that change (GM level 3 needed)."); G.CurSync() end)
AcoreLib.On("house", "curd", function(p)
    local n, rec = p:match("^(%d+);(.*)$")
    n = tonumber(n)
    if not n then return end
    local cur = Cur()
    if n <= cur.rev then return end
    if n ~= cur.rev + 1 then G.CurSync(); return end
    cur.rev = n
    if ApplyRecord(cur, rec) then G.ApplyCur(); st.rv = (st.rv or 0) + 1; G.Refresh() end
end)
AcoreLib.On("house", "curfull", function(p)
    local i, n, part = p:match("^(%d+)/(%d+);(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not i then return end
    if i == 1 then buf = {} end
    buf[i] = part
    if i < n then return end
    local cur = { rev = 0, items = {}, fits = {} }
    for k = 1, n do
        for rec in ((buf[k] or "") .. ";"):gmatch("(.-);") do
            local t = Split(rec)
            if t[1] == "r" then cur.rev = tonumber(t[2]) or 0
            elseif t[1] == "k" then cur.cats = cur.cats or {}
            elseif t[1] == "c" then cur.cats = cur.cats or {}; cur.cats[#cur.cats + 1] = { name = t[2], price = tonumber(t[3]) or 0 }
            elseif rec ~= "" then ApplyRecord(cur, rec) end
        end
    end
    buf = {}
    DB().cur = cur
    G.ApplyCur(); st.rv = (st.rv or 0) + 1; G.Refresh()
end)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() G.ApplyCur() end)

-- ---- editing (every edit is applied here at once and sent to the server, which tells everybody) ----
local function Push(kind, old) st.undo[#st.undo + 1] = { kind = kind, old = Copy(old) }; if #st.undo > 60 then table.remove(st.undo, 1) end end
local function SendItem(kind)
    local o = Cur().items[kind] or {}
    AcoreLib.Send("house", "ciset", kind .. "~" .. (o.cat or "") .. "~" .. (o.name or "") .. "~" .. (o.price or ""))
end
-- fields: cat / name / price; false clears that override. Returns false when it changed nothing.
function G.CurEdit(e, fields, noUndo)
    if not e or e.tab ~= "objects" or not G.CuratorOn() then return false end
    local cur = Cur()
    local old = cur.items[e.kind]
    local o = Copy(old)
    for k, v in pairs(fields) do o[k] = (v ~= false) and v or nil end
    if o.cat == e.b.cat then o.cat = nil end
    if o.name == e.b.name then o.name = nil end
    if not (o.cat or o.name or o.price) then o = nil end
    if SameItem(old, o) then return false end
    if not noUndo then Push(e.kind, old) end
    cur.items[e.kind] = o
    G.ApplyCur(); SendItem(e.kind)
    return true
end
function G.CurMove(cat)
    local e = st.selected
    if not (G.CuratorOn() and e and e.tab == "objects") or e.cat == cat then return end
    st.keep[e.kind] = true   -- the item stays in the list being browsed (greyed, "-> Category") so the pages do not shift under you
    if G.CurEdit(e, { cat = cat }) then st.moved = st.moved + 1 end
    if DB().auto ~= false then G.AdvanceFrom(e) else G.Refresh() end
end
function G.CurUndo()
    local u = table.remove(st.undo)
    if not u then return end
    local e = G.ItemByKind(u.kind)
    if not e then return end
    Cur().items[u.kind] = (u.old.cat or u.old.name or u.old.price) and u.old or nil
    G.ApplyCur(); SendItem(u.kind)
    st.keep[u.kind] = nil; st.moved = math.max(0, st.moved - 1)
    G.GoTo(e)
end
function G.CurSaveView()
    local e = st.selected
    local s, y, z, r = G.CurrentView()
    if not (G.CuratorOn() and e and s) then return end
    local function R(v) return math.floor(v * 1000 + .5) / 1000 end
    s, y, z, r = R(s), R(y), R(z), R(r)
    Cur().fits[Lower(e.model)] = { s, y, z, r }
    AcoreLib.Send("house", "cfset", Lower(e.model) .. "~" .. s .. "~" .. y .. "~" .. z .. "~" .. r)
    G.ApplyCur(); G.Preview(e); G.InvalidateGrid(); Msg("view saved for " .. e.name)
end
function G.CurResetView()
    local e = st.selected
    if not (G.CuratorOn() and e and e.model ~= "") then return end
    Cur().fits[Lower(e.model)] = nil
    AcoreLib.Send("house", "cfclr", Lower(e.model))
    G.ApplyCur(); G.Preview(e); G.InvalidateGrid()
end

-- ---- small dialogs ----
StaticPopupDialogs["WOTLKGARRISON_PROMPT"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, maxLetters = 50, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self) self.editBox:SetText((self.data and self.data.default) or ""); self.editBox:HighlightText() end,
    OnAccept = function(self) local d = self.data; if d and d.fn then d.fn(self.editBox:GetText()) end end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.data and p.data.fn then p.data.fn(self:GetText()) end; p:Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
StaticPopupDialogs["WOTLKGARRISON_CONFIRM"] = {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self) local d = self.data; if d and d.fn then d.fn() end end,
}
function G.Prompt(text, default, fn) StaticPopup_Show("WOTLKGARRISON_PROMPT", text, nil, { fn = fn, default = default }) end
local function Trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

-- ---- category menu (right-click a category in the left column) ----
local menuFrame
local function Menu(list)
    menuFrame = menuFrame or CreateFrame("Frame", "WotlkGarrisonCurMenu", UIParent, "UIDropDownMenuTemplate")
    EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end
function G.CatMenu(name)
    if Special(name) then
        Menu({ { text = name, isTitle = true, notCheckable = true },
               { text = "New category...", notCheckable = true, func = function() G.Prompt("New category name:", "", function(t) t = Trim(t); if t ~= "" then AcoreLib.Send("house", "ccadd", t) end end) end } })
        return
    end
    local parent, child = G.SplitCat(name)
    local isChild = child ~= nil
    Menu({
        { text = name, isTitle = true, notCheckable = true },
        { text = "New category...", notCheckable = true, func = function() G.Prompt("New category name:", "", function(t) t = Trim(t); if t ~= "" then AcoreLib.Send("house", "ccadd", t) end end) end },
        { text = "New subcategory here...", notCheckable = true, disabled = isChild, func = function() G.Prompt("New subcategory of " .. name .. ":", "", function(t) t = Trim(t); if t ~= "" then AcoreLib.Send("house", "ccadd", name .. " > " .. t) end end) end },
        { text = "Rename...", notCheckable = true, func = function()
            G.Prompt("Rename " .. name .. " to:", child or name, function(t)
                t = Trim(t); if t == "" then return end
                AcoreLib.Send("house", "ccren", name .. "~" .. (isChild and (parent .. " > " .. t) or t))
            end) end },
        { text = "Set default price...", notCheckable = true, func = function()
            G.Prompt("Default price for everything in " .. name .. " (whole gold or item count; 0 = free):", "0", function(t) AcoreLib.Send("house", "ccprice", name .. "~" .. (tonumber(t) or 0)) end) end },
        { text = "|cffff6060Delete...|r", notCheckable = true, func = function()
            StaticPopup_Show("WOTLKGARRISON_CONFIRM", "Delete the category " .. name .. "?\nIts items move to Unsorted.", nil, { fn = function() AcoreLib.Send("house", "ccdel", name) end }) end },
    })
end
-- ---- the controls ----
local bar, sendRows = nil, {}
local WIDE, NARROW = 1010, 800
function G.BuildCurate(frame)
    -- header: Curator mode switch (GM level 3+ only)
    local on = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); on:SetSize(24, 24); on:SetPoint("TOPLEFT", 450, -64)
    local onl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); onl:SetPoint("LEFT", on, "RIGHT", 0, 0); onl:SetText("Curator")
    on:SetScript("OnClick", function(self) DB().curatorOn = self:GetChecked() and true or false; G.ApplyCur(); st.keep = {}; G.Refresh() end)
    ui.curOn = on; ui.curOnLabel = onl

    -- right column: name / price / view
    local anchor = ui.pvCheck
    local panel = CreateFrame("Frame", nil, frame); panel:SetSize(210, 80); panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -20, -8)   -- the check box sits 20 px in from the preview's left edge
    ui.curPanel = panel
    local function Lbl(text, y) local f = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); f:SetPoint("TOPLEFT", 0, y - 4); f:SetText(text) end
    local function Box(w, x, y)
        local b = CreateFrame("EditBox", nil, panel, "InputBoxTemplate"); b:SetSize(w, 20); b:SetPoint("TOPLEFT", x, y); b:SetAutoFocus(false); b:SetMaxLetters(60)
        b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return b
    end
    Lbl("Name", 0); Lbl("Price", -26)
    local name = Box(166, 42, 0)
    name:SetScript("OnEnterPressed", function(self)
        local e = st.selected; self:ClearFocus()
        if e then local t = Trim(self:GetText()); G.CurEdit(e, { name = t ~= "" and t or false }); G.Refresh(); G.Select(e) end
    end)
    local price = Box(50, 42, -26); price:SetMaxLetters(7)
    price:SetScript("OnEnterPressed", function(self)
        local e = st.selected; self:ClearFocus()
        if e then local t = Trim(self:GetText()); G.CurEdit(e, { price = tonumber(t) and math.floor(tonumber(t)) or false }); G.Refresh() end
    end)
    local function Btn(text, w, x, y, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn); return b
    end
    ui.curSave = Btn("Save view", 76, 96, -26, G.CurSaveView)
    ui.curReset = Btn("Reset", 36, 174, -26, G.CurResetView)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("TOPLEFT", 0, -54); hint:SetWidth(210); hint:SetJustifyH("LEFT")
    hint:SetText("Drag / wheel in the preview to re-centre, then Save view.")
    ui.curName, ui.curPrice = name, price

    -- send-to column (right of the preview; the window grows by 210 in curator mode): every category in a scrolling list, subcategories indented
    bar = CreateFrame("Frame", nil, frame); bar:SetSize(196, 520); bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 540, -62)   -- between the grid (ends at 520) and the preview (anchored to the right edge)
    ui.curBar = bar
    local lbl = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lbl:SetPoint("TOPLEFT", 0, 0); lbl:SetText("Send the selected item to:")
    local sc = CreateFrame("ScrollFrame", "WotlkGarrisonSendScroll", bar, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 0, -22); sc:SetSize(160, 388)
    local content = CreateFrame("Frame", nil, sc); content:SetSize(160, 1); sc:SetScrollChild(content)
    ui.curScroll, ui.curContent = sc, content
    local function Row3(text, w, x, y, fn)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"); b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn); return b
    end
    ui.curNew = Row3("New category...", 176, 0, -420, function() G.Prompt("New category name:", "", function(t) t = Trim(t); if t ~= "" then AcoreLib.Send("house", "ccadd", t) end end) end)
    ui.curUndo = Row3("Undo", 86, 0, -446, G.CurUndo)
    ui.curCount = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ui.curCount:SetPoint("TOPLEFT", 92, -451); ui.curCount:SetWidth(90); ui.curCount:SetJustifyH("LEFT")
    local auto = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate"); auto:SetSize(24, 24); auto:SetPoint("TOPLEFT", -2, -472)
    local al = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); al:SetPoint("LEFT", auto, "RIGHT", 0, 0); al:SetText("Auto-advance to next item")
    auto:SetScript("OnClick", function(self) DB().auto = self:GetChecked() and true or false end)
    ui.curAuto = auto
    local rc = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); rc:SetPoint("TOPLEFT", 0, -500); rc:SetWidth(190); rc:SetJustifyH("LEFT")
    rc:SetText("Right-click a category (here or on the left) to rename, move, price or delete it.")
    bar:Hide(); panel:Hide(); on:Hide(); onl:Hide()
end

-- the rows of the send-to list: { label, cat (nil = header), indent }
local function SendRows()
    local groups, order = {}, {}
    for _, name in ipairs(G.TabDef("objects").cats) do
        local p, c = G.SplitCat(name)
        local g = groups[p]
        if not g then g = { kids = {} }; groups[p] = g; order[#order + 1] = p end
        if c then g.kids[#g.kids + 1] = { label = c, cat = name, indent = true } else g.direct = name end
    end
    local rows = {}
    for _, p in ipairs(order) do
        local g = groups[p]
        rows[#rows + 1] = { label = p, cat = g.direct, header = not g.direct }
        for _, k in ipairs(g.kids) do rows[#rows + 1] = k end
    end
    return rows
end
local function SendRow(i)
    local b = sendRows[i]
    if b then return b end
    b = CreateFrame("Button", nil, ui.curContent, "UIPanelButtonTemplate")
    b:SetNormalFontObject(GameFontNormalSmall); b:SetHighlightFontObject(GameFontHighlightSmall); b:SetDisabledFontObject(GameFontDisableSmall)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn)
        if not self.cat then return end
        if btn == "RightButton" then G.CatMenu(self.cat) else G.CurMove(self.cat) end
    end)
    sendRows[i] = b; return b
end

-- called at the end of every G.Refresh()
function G.CurRefresh()
    if not ui.curBar then return end
    local frame = ui.frame
    if st.curator then ui.curOn:Show(); ui.curOnLabel:Show(); ui.curOn:SetChecked(DB().curatorOn and true or false) else ui.curOn:Hide(); ui.curOnLabel:Hide() end
    local active = G.CuratorOn() and st.tab == "objects"
    if active ~= st.curWide then   -- the window grows to the right in curator mode; keep it on screen
        st.curWide = active
        frame:SetWidth(active and WIDE or NARROW)
        if active then frame:ClearAllPoints(); frame:SetPoint("CENTER", -100, 0) end
    end
    if not active then ui.curBar:Hide(); ui.curPanel:Hide(); return end
    ui.curBar:Show(); ui.curPanel:Show()
    local e = st.selected
    local rows = SendRows()
    ui.curContent:SetHeight(math.max(#rows * 23, 1))
    for i, r in ipairs(rows) do
        local b = SendRow(i)
        b:ClearAllPoints(); b:SetSize(r.indent and 140 or 158, 21); b:SetPoint("TOPLEFT", r.indent and 18 or 0, -(i - 1) * 23)
        b.cat = r.cat; b:SetText(r.header and ("|cff909090" .. r.label .. "|r") or r.label); b:Show()
        if r.header or not e or e.cat == r.cat then b:Disable() else b:Enable() end
        if e and r.cat and e.cat == r.cat then b:LockHighlight() else b:UnlockHighlight() end
    end
    for i = #rows + 1, #sendRows do sendRows[i]:Hide() end
    ui.curAuto:SetChecked(DB().auto ~= false)
    if #st.undo > 0 then ui.curUndo:Enable(); ui.curUndo:SetText("Undo (" .. #st.undo .. ")") else ui.curUndo:Disable(); ui.curUndo:SetText("Undo") end
    ui.curCount:SetText(st.moved > 0 and (st.moved .. " moved") or "")
    local has = e and e.tab == "objects"
    if has then ui.curName:Show(); ui.curPrice:Show() else ui.curName:Hide(); ui.curPrice:Hide() end
    if has and e.model ~= "" then ui.curSave:Enable(); ui.curReset:Enable() else ui.curSave:Disable(); ui.curReset:Disable() end
    if has then
        local o = Cur().items[e.kind] or {}
        if not ui.curName:HasFocus() then ui.curName:SetText(e.name or ""); ui.curName:SetCursorPosition(0) end
        if not ui.curPrice:HasFocus() then ui.curPrice:SetText(tostring(e.price or 0)); ui.curPrice:SetCursorPosition(0) end
        if o.name then ui.curName:SetTextColor(0.4, 1, 0.4) else ui.curName:SetTextColor(1, 1, 1) end
        if o.price then ui.curPrice:SetTextColor(0.4, 1, 0.4) else ui.curPrice:SetTextColor(0.8, 0.8, 0.8) end
    end
end
