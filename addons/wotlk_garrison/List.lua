-- Left/middle of the window: category buttons, the scrolling item list, selection and the Place/Remove buttons.
local G = WotlkGarrison
local C, st, ui = G.C, G.st, G.ui
local rows, catBtns, list = {}, {}, {}
local shown   -- tab whose categories are on screen (the category list scrolls back to the top when it changes)

local function UpdateButtons()
    local place, remove, s = ui.placeBtn, ui.removeBtn, st.selected
    if not place then return end
    if not s then place:Hide(); remove:Hide(); return end
    if st.tab == "placed" then
        place:Hide(); remove:Show(); remove:SetText("Remove this")
        if st.inHome then remove:Enable() else remove:Disable() end
        return
    end
    place:Show()
    if s.multi == 1 then
        remove:Hide()
        local n = st.decorCount[s.kind] or 0
        place:SetText((n > 0 and ("Place another (" .. n .. " placed)") or "Place here") .. G.PriceText(s))
    else
        remove:Show(); remove:SetText("Remove")
        place:SetText(st.placed[s.kind] and "Move here" or ("Place here" .. G.PriceText(s)))
        if st.inHome and st.placed[s.kind] then remove:Enable() else remove:Disable() end
    end
    if st.inHome then place:Enable() else place:Disable() end
end
G.UpdateButtons = UpdateButtons

local function ShowInfo(e) ui.bigName:SetText(e and e.name or ""); ui.bigDetail:SetText(e and e.detail or "") end

local cells, GRID_N = {}, 9
local CW, CH, LBL = 96, 114, 16
function G.Select(e)
    st.selected = e
    st.selDid = e and e.key or nil; st.previewedDid = st.selDid
    ShowInfo(e); G.Preview(e); UpdateButtons()
    if st.tab == "placed" and e then G.Mark() else G.Unmark() end
    for _, r in ipairs(rows) do if r:IsShown() then if r.entry == e then r.sel:Show() else r.sel:Hide() end end end
    for _, c in ipairs(cells) do if c.entry and c.entry == e then c.sel:Show() else c.sel:Hide() end end
    if G.CurRefresh then G.CurRefresh() end   -- curator controls follow the selection
end

-- the list for the current tab. Placed tab = what the server says is placed (decor instances first, then single-instance kinds)
local function Copy(def, over)
    local e = { kind = def.kind, name = def.name, detail = def.detail, npc = def.npc, model = def.model, human = def.human, icon = def.icon,
                cz = def.cz, sz = def.sz, tz = def.tz, vs = def.vs, vy = def.vy, vz = def.vz, vr = def.vr, price = def.price }
    for k, v in pairs(over) do e[k] = v end
    return e
end
local function BuildList()
    list = {}
    if st.tab == "placed" then
        local count = {}
        for _, d in ipairs(st.decor) do
            local def = G.ItemByKind(d.kind)
            if def then
                count[d.kind] = (count[d.kind] or 0) + 1
                list[#list + 1] = Copy(def, { did = d.did, key = d.did, multi = 1, name = def.name .. " #" .. count[d.kind] })
            end
        end
        for _, e in ipairs(C.items) do
            if e.multi ~= 1 and st.placed[e.kind] then list[#list + 1] = Copy(e, { key = e.kind }) end
        end
    else
        local q = (st.query or ""):lower()
        local kk = st.tab .. "|" .. (st.cat or "")
        if kk ~= st.keepKey then st.keepKey = kk; st.keep = {} end   -- items moved out of the category being browsed stay listed (greyed) until you change category
        for _, e in ipairs(C.items) do
            if e.tab == st.tab and (not e.hidden or st.keep[e.kind]) then   -- hidden = Removed / Unsorted for players
                if q ~= "" then   -- a search looks through the whole tab, not only the open category
                    if st.keep[e.kind] or e.name:lower():find(q, 1, true) or (e.detail or ""):lower():find(q, 1, true) or e.cat:lower():find(q, 1, true) then list[#list + 1] = e end
                elseif e.cat == st.cat or st.keep[e.kind] then list[#list + 1] = e end
            end
        end
    end
end

local function RefreshCategories()
    for _, b in ipairs(catBtns) do b:Hide() end
    if st.tab == "placed" then ui.pad:Show(); ui.catScroll:Hide(); return end
    ui.pad:Hide(); ui.catScroll:Show()
    local names = {}
    for _, name in ipairs(G.TabDef(st.tab).cats) do   -- categories with nothing in them (e.g. an empty Unsorted) are not shown
        if G.CuratorOn() and st.tab == "objects" then names[#names + 1] = name   -- a curator sees empty categories too (to send things there)
        else
            for _, e in ipairs(C.items) do if e.tab == st.tab and e.cat == name and not e.hidden then names[#names + 1] = name; break end end
        end
    end
    -- subcategories ("Holiday > Winter Veil"): a parent is a toggle row, its children show indented while it is open
    st.open = st.open or {}
    if st.cat ~= st.lastCat then   -- the category changed (tab switch, search, first open): make sure its parent is expanded
        st.lastCat = st.cat
        local p, c = G.SplitCat(st.cat or "")
        if c then st.open[p] = true end
    end
    local rowsData = G.CategoryRows(names, st.open)
    local curParent = G.SplitCat(st.cat or "")
    for i, row in ipairs(rowsData) do
        local b = catBtns[i]
        if not b then
            b = CreateFrame("Button", nil, ui.catContent, "UIPanelButtonTemplate"); catBtns[i] = b
        end
        b:ClearAllPoints(); b:SetSize(row.indent and 126 or 142, 28); b:SetPoint("TOPLEFT", row.indent and 18 or 2, -(i - 1) * 31)
        b:SetText(row.label); b:Show()
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then   -- curator: the category menu (pin, add, rename, move, price, delete)
                if G.CuratorOn() and st.tab == "objects" then G.CatMenu(row.parent or row.cat) end
                return
            end
            if row.parent then
                st.open[row.parent] = not st.open[row.parent]
                if st.open[row.parent] then st.cat = row.cat end   -- opening a parent shows its own items, or its first child
            else st.cat = row.cat end
            G.Refresh()
        end)
        local on
        if row.parent then on = (curParent == row.parent) else on = (row.cat == st.cat) end
        if on then b:LockHighlight() else b:UnlockHighlight() end
    end
    ui.catContent:SetHeight(math.max(#rowsData * 31, 1))   -- more categories than fit: the list scrolls (wheel or the bar)
    if shown ~= st.tab then shown = st.tab; ui.catScroll:SetVerticalScroll(0) end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, ui.content)
    r:SetSize(330, G.ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * G.ROW_H)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.text:SetPoint("LEFT", 6, 0)
    r.mark = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.mark:SetPoint("RIGHT", -6, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    r:SetScript("OnClick", function(self) G.Select(self.entry) end)
    rows[i] = r; return r
end

function G.Refresh()
    if not ui.frame then return end
    ui.statusText:SetText(st.inHome and "|cff00ff00You are in your garrison: stand where you want it, then Place.|r"
                                     or (G.CuratorOn() and "|cffffd100Curator mode: sorting works anywhere; placing needs your garrison.|r" or "|cffff6060Enter your garrison through the portal to place things.|r"))
    if st.maxDecor then
        local n = #st.decor
        local col = n >= st.maxDecor and "|cffff4040" or (n >= st.maxDecor * 0.9 and "|cffffd100" or "|cffffffff")
        ui.countText:SetText("Placed " .. col .. n .. "/" .. st.maxDecor .. "|r")
    end
    for key, b in pairs(ui.tabBtns) do if key == st.tab then b:LockHighlight() else b:UnlockHighlight() end end
    RefreshCategories(); BuildList()
    if st.tab == "placed" then   -- keep the selection across rebuilds (the list is rebuilt on every server message)
        if st.wantSelect then st.selDid = st.wantSelect end
        st.selected = nil
        for _, e in ipairs(list) do if e.key == st.selDid then st.selected = e end end
        if st.selected then st.wantSelect = nil end   -- keep wanting it until the chunked list has actually arrived
        ShowInfo(st.selected)
        local key = st.selected and st.selected.key or nil
        if key ~= st.previewedDid then
            st.previewedDid = key; G.Preview(st.selected)
            if st.selected then G.Mark() else G.Unmark() end
        end
    end
    if st.tab == "placed" then   -- the plain list (placed things are nudged / removed by name, not browsed by looks)
        ui.listScroll:Show(); G.HideGrid()
        ui.content:SetHeight(math.max(#list * G.ROW_H, 1))
        for i, e in ipairs(list) do
            local r = Row(i)
            r.entry = e; r.text:SetText(e.name); r.mark:SetText("")
            if st.selected == e then r.sel:Show() else r.sel:Hide() end
            r:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
    else
        ui.listScroll:Hide(); for _, r in ipairs(rows) do r:Hide() end
        G.RenderGrid(list)
    end
    UpdateButtons()
    if G.CurRefresh then G.CurRefresh() end
end

-- ---- grid: 3 x 3 live previews per page (replaces the list on the NPCs / Objects tabs) ----
local lastBase, lastKey, page = nil, nil, 1
local function Mark(e)   -- small text in the corner: how many are placed
    if e.multi == 1 then local n = st.decorCount[e.kind] or 0; return n > 0 and ("|cff00ff00x" .. n .. "|r") or "" end
    return st.placed[e.kind] and "|cff00ff00placed|r" or ""
end
local function CellLabel(c, e)   -- an item a curator moved away stays in the list, greyed, with its new category
    local moved = st.keep[e.kind] and e.cat ~= st.cat and (st.query or "") == ""
    c.label:SetText(moved and ("|cff808080" .. e.name .. " -> " .. e.cat .. "|r") or e.name)
    c.bg:SetAlpha(moved and 0.45 or 1)
end
local function FillCell(c, e)
    c.entry = e
    CellLabel(c, e); c.mark:SetText(Mark(e))
    c.nm:Hide(); c.om:Hide(); c.icon:Hide(); c.note:SetText("")
    -- creatures and objects use SEPARATE model frames: a humanoid NPC leaves its appearance behind in a frame that is reused for an object
    if e.npc > 0 then
        if not st.primed then c.note:SetText("loading...")
        else c.nm:Show(); c.nm:ClearModel(); c.nm:SetCreature(e.npc); G.FitModel(c.nm, e) end
    elseif e.model:lower():match("%.wmo$") then   -- a whole building: the model frames cannot draw it, so show the picture rendered offline (WmoPreviews.lua / wmo/<kind>.blp)
        if G.wmoPic and G.wmoPic[e.kind] then
            c.icon:SetSize(CW - 6, CW - 6); c.icon:SetTexture(nil); c.icon:SetTexture("Interface\\AddOns\\wotlk_garrison\\wmo\\" .. e.kind); c.icon:Show()
        else c.note:SetText("building") end
    elseif e.model ~= "" then
        c.om:Show(); c.om:ClearModel()
        if pcall(c.om.SetModel, c.om, e.model) then G.FitModel(c.om, e) else c.om:Hide(); c.note:SetText("no preview") end
    elseif e.icon and e.icon ~= "" then
        c.icon:SetSize(56, 56); c.icon:SetTexture("Interface\\Icons\\" .. e.icon); c.icon:Show()
    else c.note:SetText("no preview") end
    c.bg:Show()
end
function G.HideGrid() if ui.grid then ui.grid:Hide() end; lastKey = nil end
function G.RenderGrid(items)
    local g = ui.grid; if not g then return end
    g:Show()
    local base = st.tab .. "|" .. (st.cat or "") .. "|" .. (st.query or "")
    local pages = math.max(1, math.ceil(#items / GRID_N))
    local mem = WotlkGarrisonDB and WotlkGarrisonDB.pages
    if base ~= lastBase then   -- a different tab / category / search: back to where you were in that category (the first item of the page you left), else page 1
        lastBase, page = base, 1
        local r = mem and mem[base]
        if r and (st.query or "") == "" then
            for i, x in ipairs(items) do if x.kind == r[2] then page = math.ceil(i / GRID_N); r = nil; break end end
            if r then page = math.min(r[1] or 1, pages) end
        end
    end
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    if (st.query or "") == "" and items[(page - 1) * GRID_N + 1] then
        WotlkGarrisonDB = WotlkGarrisonDB or {}; WotlkGarrisonDB.pages = WotlkGarrisonDB.pages or {}
        WotlkGarrisonDB.pages[base] = { page, items[(page - 1) * GRID_N + 1].kind }
    end
    g.pageText:SetText(string.format("Page %d / %d   (%d items)", page, pages, #items))
    local key = base .. "|" .. page .. "|" .. (st.primed and 1 or 0) .. "|" .. #items .. "|" .. (st.rv or 0)
    if key ~= lastKey then   -- models are only (re)loaded when the page content changed, not on every server message
        lastKey = key
        for i = 1, GRID_N do
            local c, e = cells[i], items[(page - 1) * GRID_N + i]
            if e then FillCell(c, e) else c.entry = nil; c.bg:Hide(); c.nm:Hide(); c.om:Hide(); c.icon:Hide(); c.note:SetText(""); c.label:SetText("") end   -- the label belongs to the grid, not the cell: clear it too
        end
    end
    for i = 1, GRID_N do   -- cheap updates every time: placed marks and the selection frame
        local c = cells[i]
        if c.entry then CellLabel(c, c.entry); c.mark:SetText(Mark(c.entry)); if st.selected == c.entry then c.sel:Show() else c.sel:Hide() end end
    end
end
function G.GridPage(d) page = math.max(1, page + d); lastKey = nil; G.Refresh() end   -- the upper limit is clamped in RenderGrid
function G.InvalidateGrid() lastKey = nil; G.Refresh() end   -- reload the models of the visible page (a view was changed)
-- show an item: select it and turn to its page
function G.GoTo(e)
    for i, x in ipairs(list) do
        if x == e then
            local np = math.ceil(i / GRID_N)
            if np ~= page then page = np; lastKey = nil end
            break
        end
    end
    G.Refresh(); G.Select(e)
end
-- curator auto-advance: select the next item after e that was not moved away (the page turns when needed)
function G.AdvanceFrom(e)
    local idx
    for i, x in ipairs(list) do if x == e then idx = i; break end end
    local nxt
    if idx then for j = idx + 1, #list do if not st.keep[list[j].kind] then nxt = j; break end end end
    if nxt then G.GoTo(list[nxt])
    else G.Refresh(); G.SetMsg("End of this list.", 1, 0.82, 0) end
end

function G.BuildGrid(frame)
    local g = CreateFrame("Frame", nil, frame); ui.grid = g
    frame:HookScript("OnShow", function() lastKey = nil; G.Refresh() end)   -- models go blank while the window is hidden (placement mode): reload them
    g:SetSize(330, 470); g:SetPoint("TOPLEFT", 190, -96)
    -- search (looks through the whole tab); Esc clears it
    local sb = CreateFrame("EditBox", nil, g, "InputBoxTemplate"); sb:SetSize(250, 20); sb:SetPoint("TOPLEFT", 6, 0); sb:SetAutoFocus(false); sb:SetMaxLetters(40)
    local ph = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ph:SetPoint("LEFT", sb, "LEFT", 4, 0); ph:SetText("search all of this tab")
    local wait
    sb:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then ph:Show() else ph:Hide() end
        wait = GetTime() + 0.35   -- debounce: models only reload once you stop typing
    end)
    sb:SetScript("OnUpdate", function(self) if wait and GetTime() > wait then wait = nil; st.query = self:GetText(); G.Refresh() end end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); st.query = ""; wait = nil; G.Refresh() end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ui.search = sb
    for i = 1, GRID_N do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local bg = CreateFrame("Frame", nil, g)
        bg:SetSize(CW, CH); bg:SetPoint("TOPLEFT", 4 + col * (CW + 8), -(28 + row * (CH + LBL + 6)))
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bg:SetBackdropColor(0.06, 0.06, 0.08, 1)
        local function Mdl()
            local f = CreateFrame("DressUpModel", nil, bg)
            f:SetPoint("TOPLEFT", 2, -2); f:SetPoint("BOTTOMRIGHT", -2, 2); f:SetFrameLevel(bg:GetFrameLevel() + 2); f:Hide()   -- 92 x 110 = the big preview's shape (210:250)
            return f
        end
        local m, nm = Mdl(), Mdl()   -- m = objects, nm = creatures
        local icon = bg:CreateTexture(nil, "ARTWORK"); icon:SetSize(56, 56); icon:SetPoint("CENTER"); icon:Hide()
        local note = bg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("CENTER")
        local sel = bg:CreateTexture(nil, "OVERLAY"); sel:SetAllPoints(); sel:SetTexture(1, 0.82, 0, 0.28); sel:Hide()
        local btn = CreateFrame("Button", nil, bg); btn:SetAllPoints(); btn:SetFrameLevel(m:GetFrameLevel() + 3)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:EnableMouseWheel(true); btn:SetScript("OnMouseWheel", function(_, d) G.GridPage(-d) end)
        local label = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -1); label:SetSize(CW, LBL - 2); label:SetJustifyH("CENTER")
        local mark = bg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); mark:SetPoint("TOPRIGHT", -4, -4)
        local c = { bg = bg, om = m, nm = nm, icon = icon, note = note, sel = sel, label = label, mark = mark }
        mark:SetParent(btn)
        btn:SetScript("OnClick", function() if c.entry then G.Select(c.entry) end end)
        btn:SetScript("OnEnter", function() if c.entry then GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:SetText(c.entry.name); GameTooltip:Show() end end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[i] = c; bg:Hide()
    end
    local function Pg(txt, x, d) local b = CreateFrame("Button", nil, g, "UIPanelButtonTemplate"); b:SetSize(40, 22); b:SetPoint("BOTTOMLEFT", x, 0); b:SetText(txt); b:SetScript("OnClick", function() G.GridPage(d) end) end
    Pg("<", 4, -1); Pg(">", 48, 1)
    g.pageText = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g.pageText:SetPoint("BOTTOMLEFT", 98, 5)
    g:Hide()
end

function G.BuildScroll(frame)
    local scroll = CreateFrame("ScrollFrame", "WotlkGarrisonScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 190, -96); scroll:SetSize(340, G.ROW_H * G.ROW_N); ui.listScroll = scroll
    ui.content = CreateFrame("Frame", nil, scroll); ui.content:SetSize(330, 1)
    scroll:SetScrollChild(ui.content)
    -- categories (left): a scroll frame of its own
    ui.catScroll = CreateFrame("ScrollFrame", "WotlkGarrisonCatScroll", frame, "UIPanelScrollFrameTemplate")
    ui.catScroll:SetPoint("TOPLEFT", 20, -96); ui.catScroll:SetSize(146, G.ROW_H * G.ROW_N)
    ui.catContent = CreateFrame("Frame", nil, ui.catScroll); ui.catContent:SetSize(146, 1)
    ui.catScroll:SetScrollChild(ui.catContent)
end

function G.BuildActions(frame, previewBg)   -- Place / Remove under the preview
    local place = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); place:SetSize(210, 30); place:SetPoint("TOP", ui.bigDetail, "BOTTOM", 0, -14)
    local remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); remove:SetSize(170, 26); remove:SetPoint("TOP", place, "BOTTOM", 0, -6); remove:SetText("Remove")
    -- "Preview before placing" (default OFF = the instant placement as before; only for decor, which can be placed many times)
    WotlkGarrisonDB = WotlkGarrisonDB or {}
    local pv = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate"); pv:SetSize(24, 24); pv:SetPoint("TOPLEFT", remove, "BOTTOMLEFT", 0, -4)
    local pvl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); pvl:SetPoint("LEFT", pv, "RIGHT", 2, 0); pvl:SetText("Preview before placing (Enter)")
    ui.pvCheck = pv
    pv:SetChecked(WotlkGarrisonDB.preview and true or false)
    pv:SetScript("OnClick", function(self) WotlkGarrisonDB.preview = self:GetChecked() and true or false end)
    place:SetScript("OnClick", function()
        local s = st.selected; if not s then return end
        if s.multi == 1 and WotlkGarrisonDB.preview and st.tab ~= "placed" then AcoreLib.Send("house", "pstart", s.kind); return end
        AcoreLib.Send("house", s.multi == 1 and "dplace" or "place", s.kind); G.Request()
    end)
    remove:SetScript("OnClick", function()
        local s = st.selected; if not s then return end
        if st.tab == "placed" and s.did then AcoreLib.Send("house", "dremove", tostring(s.did)); G.Select(nil)
        elseif st.tab == "placed" then AcoreLib.Send("house", "remove", s.kind); G.Select(nil)
        else AcoreLib.Send("house", "remove", s.kind) end
        G.Request()
    end)
    ui.placeBtn, ui.removeBtn = place, remove
end
