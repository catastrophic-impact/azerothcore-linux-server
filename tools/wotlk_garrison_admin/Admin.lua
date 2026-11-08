-- Garrison admin tool (NOT part of the player addon). /garrison admin
-- Page of previews at the real preview size. Per preview: wheel/+/- zoom (about the frame centre), left-drag or < > = turn, right-drag = move,
-- R = undo, X = move to the Removed shelf, category button = change category. Top bar: search, filter, Categories editor, Done.
-- Saved to WotlkGarrisonAdmin = { fit = {model = {scale, sideways, up, rot}}, removed = {kind=true}, categories = {kind=cat}, cats = {object categories} }
-- (written on /reload or logout) -> claude_tools/admin_import.py -> garrison-fit.json + garrison-admin.json -> tools/gen_garrison_catalog.py
local C = WotlkGarrisonCatalog
local DB
local fx, catPanel, cells, page, selected = nil, {}, {}, 1, nil
local mode, query, catFilter = 1, "", nil   -- catFilter = one object category, or nil for all    -- mode 1 = flagged, 2 = all, 3 = on the Removed shelf
local MODES = { "Flagged", "All", "Removed" }
local showRemoved, showUnsorted = false, false   -- the two checkboxes in the top bar; both off every time the window opens
local function Hidden(cat) return (cat == "Removed" and not showRemoved) or (cat == "Unsorted" and not showUnsorted) end
local PW, PH, GAP = 210, 250, 8
local list = {}
local DEFROT = 0.61

-- preview position model (measured in claude_tools/preview_audit.py): screen offset of the model origin from the frame centre
local OX, OY0 = -2, 98
local function fz(z) return -91.5 * z - 22.5 * z * z end
local function gy(y) return 84.5 * y + 22.5 * y * y end
local function inv(a, b, want)
    local d = a * a + 4 * b * want
    if d < 0 then return want / a end
    local r1, r2 = (-a + math.sqrt(d)) / (2 * b), (-a - math.sqrt(d)) / (2 * b)
    return math.abs(r1) < math.abs(r2) and r1 or r2
end

local function Norm(p) return (p or ""):lower() end
local function Init()
    WotlkGarrisonAdmin = WotlkGarrisonAdmin or {}
    DB = WotlkGarrisonAdmin
    -- one-time repair of fits damaged by a wrong depth conversion (negative scale = upside down): undo the bad factor (7-16)/7, apply the right one 23/7
    for _, f in pairs(DB.fit or {}) do
        if f[1] and f[1] < 0 then local k = (7 - 16) / 7 / (23 / 7); f[1], f[2], f[3] = f[1] * k, f[2] * k, f[3] * k end
        f[5] = nil   -- depth is gone: any depth value saved with a fit is dropped
    end
    DB.fit = DB.fit or {}; DB.removed = DB.removed or {}; DB.categories = DB.categories or {}; DB.names = DB.names or {}; DB.prices = DB.prices or {}; DB.prices.cats = DB.prices.cats or {}; DB.prices.items = DB.prices.items or {}
    if not DB.cats then DB.cats = {}; for _, t in ipairs(C.tabs) do if t.key == "objects" then for _, c in ipairs(t.cats) do DB.cats[#DB.cats + 1] = c end end end end
    for i = #DB.cats, 1, -1 do if DB.cats[i] == "Unsorted" or DB.cats[i] == "Removed" then table.remove(DB.cats, i) end end
    DB.cats[#DB.cats + 1] = "Unsorted"; DB.cats[#DB.cats + 1] = "Removed"   -- pinned, always last
end
local function Apply()   -- push the admin's decisions into the live catalog, so the normal /garrison window shows them (fits, categories, removals)
    for _, t in ipairs(C.tabs) do
        if t.key == "objects" and DB.cats then t.cats = {}; for i, c in ipairs(DB.cats) do t.cats[i] = c end end
    end
    for _, e in ipairs(C.items) do
        e.defname = e.defname or e.name   -- the name the catalog was generated with
        e.name = DB.names[e.kind] or e.defname
        e.defcat = e.defcat or e.cat   -- the category the catalog was generated with
        e.cat = DB.categories[e.kind] or e.defcat
        e.hidden = ((e.cat == "Removed" and not showRemoved) or (e.cat == "Unsorted" and not showUnsorted)) or nil   -- the two admin checkboxes decide whether this character sees Removed / Unsorted in /garrison too (the server lets only GM accounts place them)
        e.baseprice = e.baseprice or e.price or 0   -- the price the catalog was generated with
        e.price = DB.prices.items[e.kind] or DB.prices.cats[e.cat] or e.baseprice   -- category Removed = the review shelf: players never see it
        local f = e.model and e.model ~= "" and DB.fit[Norm(e.model)]
        if f then e.vs, e.vy, e.vz, e.vr = f[1], f[2], f[3], f[4] end
    end
    if WotlkGarrison and WotlkGarrison.Refresh then pcall(WotlkGarrison.Refresh) end   -- redraw an open /garrison window
end
local ev = CreateFrame("Frame"); ev:RegisterEvent("PLAYER_LOGIN"); ev:SetScript("OnEvent", function() Init(); Apply() end)

local function View(e)
    if e.vs then return e.vs, e.vy or 0, e.vz or 0, e.vr or DEFROT end
    local af = WotlkAdminAutoFit and WotlkAdminAutoFit[Norm(e.model)]   -- AutoFit.lua: found by the blank probe
    if af then return af[1], af[2], af[3], DEFROT end
    local sz, cz = e.sz or 0, e.cz or 0
    local ca = DB.categories[e.kind] or e.defcat or e.cat; local lo = (ca == "Unsorted" or ca == "Removed") and 0.5 or 0.05   -- unfitted Unsorted items: never below 0.5 (the client culls big models drawn smaller, leaving a blank cell); a part of a huge model beats nothing
    local base = sz > 0 and math.max(lo, math.min(10, 2.2 / sz)) or 1
    return base, 0, 1 - cz * base, DEFROT
end
local function CatList(e)
    if e.tab == "objects" then return DB.cats end
    for _, t in ipairs(C.tabs) do if t.key == e.tab then return t.cats end end
    return {}
end
local function CatOf(e) return DB.categories[e.kind] or e.defcat or e.cat end
local function SetCat(e, cat) DB.categories[e.kind] = (cat ~= (e.defcat or e.cat)) and cat or nil end   -- no entry when it equals the default

local function Build_List()
    list = {}
    if catFilter then local known; for _, c in ipairs(DB.cats) do if c == catFilter then known = true end end; if not known then catFilter = nil end end   -- renamed/deleted
    local flag = {}
    if WotlkGarrisonFixList then for i, m in ipairs(WotlkGarrisonFixList) do flag[m] = i end end
    local q = query:lower()
    for _, e in ipairs(C.items) do
        if e.model and e.model ~= "" then
            local k = Norm(e.model)
            local ok
            if q ~= "" then ok = e.name:lower():find(q, 1, true) ~= nil or (e.defname or ""):lower():find(q, 1, true) ~= nil or CatOf(e):lower():find(q, 1, true) ~= nil
            elseif mode == 1 then ok = flag[k] ~= nil
            elseif mode == 3 then ok = CatOf(e) == "Removed"
            else ok = true end
            if ok and (Hidden(CatOf(e)) or (catFilter and CatOf(e) ~= catFilter)) then ok = false end
            if ok then list[#list + 1] = { e = e, model = k, rank = flag[k] or 99999 } end
        end
    end
    if mode == 1 and q == "" then table.sort(list, function(a, b) return a.rank < b.rank end) end
end

local function Draw(c)
    local x = c.x
    if not x then c.m:Hide(); return end
    c.m:Show(); c.m:ClearModel(); pcall(c.m.SetModel, c.m, x.e.model)
    c.m:SetModelScale(x.s); c.m:SetPosition(0, x.y, x.z); c.m:SetRotation(x.r)
end
local function Mark(c)
    local x = c.x
    if not x then c.nameBox:SetText(""); c.nameBox:Hide(); c.defBtn:Hide(); c.priceBox:Hide(); c.catBtn:Hide(); return end
    c.nameBox:Show(); c.defBtn:Show(); c.priceBox:Show()
    local edited = DB.fit[x.model] ~= nil
    local rem = CatOf(x.e) == "Removed"
    c.bg:SetBackdropBorderColor(rem and 1 or (c == selected and 1 or (edited and 0.2 or 1)), rem and 0.1 or (c == selected and 0.8 or 1), rem and 0.1 or (c == selected and 0 or (edited and 0.2 or 1)))
    if not c.nameBox:HasFocus() then c.nameBox:SetText(x.e.name); c.nameBox:SetCursorPosition(0) end
    if DB.names[x.e.kind] then c.nameBox:SetTextColor(0.4, 1, 0.4) else c.nameBox:SetTextColor(1, 0.82, 0) end   -- green = renamed
    if DB.names[x.e.kind] then c.defBtn:Show() else c.defBtn:Hide() end
    if not c.priceBox:HasFocus() then c.priceBox:SetText(tostring(x.e.price or 0)); c.priceBox:SetCursorPosition(0) end
    if DB.prices.items[x.e.kind] then c.priceBox:SetTextColor(0.4, 1, 0.4) else c.priceBox:SetTextColor(0.7, 0.7, 0.7) end
    c.catBtn:Show(); c.catBtn:SetText(CatOf(x.e))
    c.xBtn:SetText(rem and "undo" or "X")
end
local function Save(c)   -- store the view of a cell
    local x = c.x
    if x and x.edited then
        local function r(v) return math.floor(v * 1000 + .5) / 1000 end
        DB.fit[x.model] = { r(x.s), r(x.y), r(x.z), r(x.r) }
    end
end
local function Pages() return math.max(1, math.ceil(#list / #cells)) end
local function Show(p)
    for _, c in ipairs(cells) do Save(c) end
    page = math.max(1, math.min(Pages(), p)); selected = nil
    for i, c in ipairs(cells) do
        local it = list[(page - 1) * #cells + i]
        if it then
            local s, y, z, r = View(it.e)
            local sv = DB.fit[it.model]
            if sv then s, y, z, r = sv[1], sv[2], sv[3], sv[4] or DEFROT end
            c.x = { e = it.e, model = it.model, s = s, y = y, z = z, r = r, s0 = s, y0 = y, z0 = z, r0 = r, edited = false }
        else c.x = nil end
        Draw(c); Mark(c)
    end
    fx.pageText:SetText(string.format("%d/%d  (%d)", page, Pages(), #list))
end
local function Edit(c, f, dy, dz, dr)
    local x = c.x; if not x then return end
    if f then   -- zoom about the frame centre: the model origin's offset from the centre scales with the zoom
        local ox, oy = OX + gy(x.y), OY0 + fz(x.z)
        x.s = x.s * f
        x.y, x.z = inv(84.5, 22.5, ox * f - OX), inv(-91.5, -22.5, oy * f - OY0)
    end
    x.y, x.z = x.y + (dy or 0), x.z + (dz or 0); x.r = x.r + (dr or 0); x.edited = true
    c.m:SetModelScale(x.s); c.m:SetPosition(0, x.y, x.z); c.m:SetRotation(x.r); Save(c); Mark(c)
end

local function Refresh() Build_List(); Show(1); if fx.catText then fx.catText() end end

-- ---- categories editor ----
-- "Unsorted" is permanent and always last: deleting a category sends its items there.
local UNSORTED = "Unsorted"
local function ItemsIn(name) local n = 0; for _, e in ipairs(C.items) do if e.tab == "objects" and CatOf(e) == name then n = n + 1 end end; return n end
local function MoveItems(from, to) for _, e in ipairs(C.items) do if e.tab == "objects" and CatOf(e) == from then SetCat(e, to) end end; Apply() end
local REMOVED = "Removed"
local function EnsureEnds()   -- Unsorted, Removed: always the last two
    for i = #DB.cats, 1, -1 do if DB.cats[i] == UNSORTED or DB.cats[i] == REMOVED then table.remove(DB.cats, i) end end
    DB.cats[#DB.cats + 1] = UNSORTED; DB.cats[#DB.cats + 1] = REMOVED
end
local function Trim(v) return (v:gsub("^%s+", ""):gsub("%s+$", "")) end

-- click-open list: PickList(anchorButton, {labels}, currentLabel, function(label, index) ... end); wheel scrolls, click outside closes
local pick
local function PickList(anchor, labels, current, onPick)
    local VIS, RH, PW2 = 14, 22, 220
    if not pick then
        pick = CreateFrame("Frame", nil, UIParent); pick:SetAllPoints(UIParent); pick:SetFrameStrata("TOOLTIP"); pick:EnableMouse(true); pick:Hide()   -- above the Categories panel (FULLSCREEN_DIALOG), otherwise its list opens underneath it
        pick:SetScript("OnMouseDown", function(self) self:Hide() end)   -- click outside = close
        local box = CreateFrame("Frame", nil, pick); pick.box = box; box:EnableMouse(true); box:EnableMouseWheel(true)
        box:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        AcoreLib.Solid(box, 9)
        pick.rows = {}; pick.off = 0
        for i = 1, VIS do
            local b = CreateFrame("Button", nil, box); b:SetSize(PW2 - 16 - 16, RH); b:SetPoint("TOPLEFT", 14, -10 - (i - 1) * RH)
            b:SetNormalFontObject("GameFontHighlight"); b:SetText(" "); b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:GetFontString():SetPoint("LEFT", 4, 0); b:GetFontString():SetJustifyH("LEFT")
            b:SetScript("OnClick", function() local f = pick.fn; local k = pick.off + i; pick:Hide(); if f then f(pick.labels[k], k) end end)
            pick.rows[i] = b
        end
        function pick.Render()
            local n = #pick.labels; local maxOff = math.max(0, n - VIS)
            if pick.off > maxOff then pick.off = maxOff end; if pick.off < 0 then pick.off = 0 end
            for i = 1, VIS do
                local b, l = pick.rows[i], pick.labels[pick.off + i]
                if l then b:SetText((l == pick.cur and "|cff40ff40" or "") .. l); b:GetFontString():SetPoint("LEFT", 4, 0); b:Show() else b:Hide() end
            end
            pick.more:SetText(n > VIS and ("wheel: " .. (pick.off + 1) .. "-" .. math.min(n, pick.off + VIS) .. " of " .. n) or "")
        end
        box:SetScript("OnMouseWheel", function(_, d) pick.off = pick.off - d * 3; pick.Render() end)
        pick.more = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); pick.more:SetPoint("BOTTOM", 0, 8)
    end
    pick.labels, pick.cur, pick.fn, pick.off = labels, current, onPick, 0
    for i, l in ipairs(labels) do if l == current then pick.off = math.max(0, math.min(i - 1, #labels - VIS)) end end
    local box = pick.box; box:SetSize(PW2, 20 + math.min(#labels, VIS) * RH + (#labels > VIS and 14 or 0))
    box:ClearAllPoints(); box:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    if anchor:GetTop() and anchor:GetTop() + box:GetHeight() > UIParent:GetHeight() then box:ClearAllPoints(); box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    pick.Render(); pick:Show()
end

-- "Holiday>Winter Veil" / "holiday  >  Winter Veil" -> "Holiday > Winter Veil": a category with a parent shows as a subcategory in the players' window (one level)
local function NormCat(v)
    v = (v or ""):gsub("%s*>%s*", " > ")
    local a, b = v:match("^(.-) > (.*)$")
    if a then
        b = b:gsub(" > ", " ")   -- only one level
        if a == "" or b == "" then return a .. b end
        return a .. " > " .. b
    end
    return v
end

local function SplitCat(name)   -- "Holiday > Winter Veil" -> "Holiday", "Winter Veil"; a plain name -> name, nil
    local a, b = name:match("^(.-) > (.+)$")
    if a and a ~= "" then return a, b end
    return name, nil
end

local function BuildCatPanel()
    local W, MAXROWS = 420, 12   -- MAXROWS = visible rows; the list scrolls
    local p = CreateFrame("Frame", nil, fx)
    p:SetSize(W, 46 + MAXROWS * 27 + 110); p:SetPoint("TOP", fx, "TOP", 0, -50); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:EnableMouse(true)
    p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    AcoreLib.Solid(p, 9)
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -16); title:SetText("Object categories")
    p.rows = {}
    local Render
    local offset = 0
    local sb
    local function Row(i)
        local r = CreateFrame("Frame", nil, p); r:SetSize(W - 40, 24); r:SetPoint("TOPLEFT", 22, -46 - (i - 1) * 27)
        r.eb = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.eb:SetSize(150, 20); r.eb:SetPoint("LEFT", 8, 0); r.eb:SetAutoFocus(false)
        local function B(txt, x, fn) local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); b:SetSize(30, 22); b:SetPoint("LEFT", x, 0); b:SetText(txt); b:SetScript("OnClick", fn); return b end
        r.pb = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.pb:SetSize(44, 20); r.pb:SetPoint("LEFT", r.eb, "RIGHT", 12, 0); r.pb:SetAutoFocus(false); r.pb:SetMaxLetters(6)
        r.pb:SetScript("OnEnterPressed", function(self)   -- default price of everything in this category (an item's own price wins)
            local name = DB.cats[r.idx]; local n = tonumber(self:GetText())
            DB.prices.cats[name] = (n and n > 0) and math.floor(n) or nil
            self:ClearFocus(); Apply(); Render()
        end)
        r.pb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Render() end)
        r.up = B("^", 232, function() local k = r.idx; if k > 1 then DB.cats[k], DB.cats[k - 1] = DB.cats[k - 1], DB.cats[k]; Render() end end)
        r.dn = B("v", 266, function() local k = r.idx; if k < #DB.cats - 2 then DB.cats[k], DB.cats[k + 1] = DB.cats[k + 1], DB.cats[k]; Render() end end)
        r.del = B("x", 300, function() local k = r.idx; DB.prices.cats[DB.cats[k]] = nil; MoveItems(DB.cats[k], UNSORTED); table.remove(DB.cats, k); Render() end)
        r.n = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.n:SetPoint("LEFT", 338, 0)
        r.eb:SetScript("OnEnterPressed", function(self)
            local new, old = NormCat(Trim(self:GetText())), DB.cats[r.idx]
            local dup = false; for _, c in ipairs(DB.cats) do if c:lower() == new:lower() and c ~= old then dup = true end end
            if new ~= "" and new ~= old and not dup then MoveItems(old, new); DB.cats[r.idx] = new; DB.prices.cats[new] = DB.prices.cats[old]; DB.prices.cats[old] = nil; Apply() end
            self:ClearFocus(); Render()
        end)
        r.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Render() end)
        return r
    end
    function Render()
        EnsureEnds()
        local maxOff = math.max(0, #DB.cats - MAXROWS)
        if offset > maxOff then offset = maxOff end
        if sb then sb:SetMinMaxValues(0, maxOff); if math.floor(sb:GetValue() + 0.5) ~= offset then sb:SetValue(offset) end; if maxOff == 0 then sb:Hide() else sb:Show() end end
        for i = 1, MAXROWS do
            local r = p.rows[i]; if not r then r = Row(i); p.rows[i] = r end
            local name = DB.cats[offset + i]
            if name then
                local fixed = name == UNSORTED or name == REMOVED
                r.idx = offset + i; r.eb:SetText(name); r.eb:SetCursorPosition(0)
                local child = not fixed and select(2, SplitCat(name)) ~= nil   -- subcategories are drawn indented under their parent
                r.eb:ClearAllPoints(); r.eb:SetPoint("LEFT", child and 26 or 8, 0); r.eb:SetWidth(child and 132 or 150)
                if fixed then r.eb:ClearFocus(); r.eb:EnableMouse(false); r.eb:SetTextColor(0.6, 0.6, 0.6) else r.eb:EnableMouse(true); r.eb:SetTextColor(1, 1, 1) end
                for _, b in ipairs({ r.up, r.dn, r.del }) do if fixed then b:Hide() else b:Show() end end
                if r.idx == 1 then r.up:Disable() else r.up:Enable() end
                if r.idx == #DB.cats - 2 then r.dn:Disable() else r.dn:Enable() end
                if name == REMOVED then r.pb:Hide() else r.pb:Show(); if not r.pb:HasFocus() then r.pb:SetText(tostring(DB.prices.cats[name] or 0)); r.pb:SetCursorPosition(0) end end
                local cnt = ItemsIn(name); r.n:SetText(cnt == 0 and "|cffff8080empty|r" or cnt); r:Show()
            else r:Hide() end
        end
    end
    p.Render = Render
    sb = CreateFrame("Slider", nil, p, "UIPanelScrollBarTemplate"); sb:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -62); sb:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 96)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(self, v) v = math.floor(v + 0.5); if v ~= offset then offset = v; Render() end end)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(self, d) sb:SetValue(math.max(0, math.min(#DB.cats - MAXROWS, offset - d))) end)
    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOM", 0, 76); hint:SetWidth(W - 40); hint:SetJustifyH("CENTER")
    hint:SetText("Rename: edit the name, Enter.  Box after the name = default price of its items.  Deleting moves items to Unsorted.\nPlayers only see a category once it holds items (\"empty\" ones stay hidden).")
    -- add a category or a subcategory: choose where it goes, type the name, Add
    local parent   -- nil = top level; else the name of the parent the new category goes under
    local pbtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); pbtn:SetSize(260, 22); pbtn:SetPoint("BOTTOMLEFT", 30, 50)
    local function ParentText() pbtn:SetText("Add under: " .. (parent or "(top level)")) end
    ParentText()
    pbtn:SetScript("OnClick", function(self)
        local L, seen = { "(top level)" }, {}
        for _, c in ipairs(DB.cats) do
            if c ~= UNSORTED and c ~= REMOVED then local pp = SplitCat(c); if not seen[pp] then seen[pp] = true; L[#L + 1] = pp end end
        end
        PickList(self, L, parent or "(top level)", function(name) parent = (name ~= "(top level)") and name or nil; ParentText() end)
    end)
    local add = CreateFrame("EditBox", nil, p, "InputBoxTemplate"); add:SetSize(200, 20); add:SetPoint("BOTTOMLEFT", 36, 24); add:SetAutoFocus(false)
    local function DoAdd()
        local v = Trim(add:GetText())
        if v == "" then return end
        local full
        if parent then full = parent .. " > " .. (v:gsub("%s*>%s*", " ")) else full = NormCat(v) end
        for _, c in ipairs(DB.cats) do if c:lower() == full:lower() then return end end   -- already exists
        local at = #DB.cats - 1                                  -- before the pinned Unsorted / Removed
        if parent then                                           -- right after the parent's last entry, so the family stays together
            for k, c in ipairs(DB.cats) do if c ~= UNSORTED and c ~= REMOVED and SplitCat(c) == parent then at = k end end
            if at ~= #DB.cats - 1 then at = at + 1 end
        end
        table.insert(DB.cats, at, full)
        add:SetText(""); add:ClearFocus(); offset = math.max(0, math.min(at - 1, #DB.cats - MAXROWS)); Apply(); Render()
    end
    add:SetScript("OnEnterPressed", DoAdd)
    local ab = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); ab:SetSize(70, 22); ab:SetPoint("LEFT", add, "RIGHT", 12, 0); ab:SetText("Add"); ab:SetScript("OnClick", DoAdd)
    local cb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate"); cb:SetSize(70, 22); cb:SetPoint("BOTTOMRIGHT", -24, 24); cb:SetText("Close"); cb:SetScript("OnClick", function() p:Hide(); Refresh() end)
    p:Hide(); return p
end

local function Build()
    fx = CreateFrame("Frame", "WotlkGarrisonAdminFrame", UIParent)
    fx:SetAllPoints(UIParent); fx:SetFrameStrata("DIALOG"); fx:EnableMouse(true); fx:Hide()
    fx:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" }); fx:SetBackdropColor(0.05, 0.05, 0.08, 1)
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local cols = math.max(1, math.floor((W - 20) / (PW + GAP))); local rows = math.max(1, math.floor((H - 60) / (PH + GAP + 16)))
    local x0 = (W - cols * (PW + GAP) + GAP) / 2
    for r = 0, rows - 1 do for cI = 0, cols - 1 do
        local bg = CreateFrame("Frame", nil, fx)
        bg:SetSize(PW, PH); bg:SetPoint("TOPLEFT", fx, "TOPLEFT", x0 + cI * (PW + GAP), -(44 + r * (PH + GAP + 16)))
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bg:SetBackdropColor(0.06, 0.06, 0.08, 1)
        local m = CreateFrame("DressUpModel", nil, bg)
        m:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4); m:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4); m:SetFrameLevel(bg:GetFrameLevel() + 2); m:Hide()
        local v = bg:CreateTexture(nil, "OVERLAY"); v:SetSize(1, PH - 8); v:SetPoint("CENTER"); v:SetTexture(1, 1, 1, 0.12)
        local h = bg:CreateTexture(nil, "OVERLAY"); h:SetSize(PW - 8, 1); h:SetPoint("CENTER"); h:SetTexture(1, 1, 1, 0.12)
        local c = { bg = bg, m = m }
        -- name under the preview: edit + Enter renames (shown in /garrison and the server messages after the next generate); "def" restores the default
        c.nameBox = CreateFrame("EditBox", nil, fx, "InputBoxTemplate"); c.nameBox:SetSize(110, 16); c.nameBox:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 6, -1)
        c.nameBox:SetAutoFocus(false); c.nameBox:SetFontObject("GameFontNormalSmall"); c.nameBox:SetMaxLetters(60)
        c.nameBox:SetScript("OnEnterPressed", function(self)
            local x = c.x; if not x then return end
            local new = (self:GetText():gsub("^%s+", ""):gsub("%s+$", ""))
            if new == "" or new == x.e.defname then DB.names[x.e.kind] = nil; x.e.name = x.e.defname else DB.names[x.e.kind] = new; x.e.name = new end
            self:ClearFocus(); Mark(c)
        end)
        c.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Mark(c) end)
        c.defBtn = CreateFrame("Button", nil, fx, "UIPanelButtonTemplate"); c.defBtn:SetSize(30, 16); c.defBtn:SetPoint("LEFT", c.nameBox, "RIGHT", 6, 0); c.defBtn:SetText("def")
        -- price of placing this item: grey = the category default, green = this item's own override. Enter with an empty box removes the override
        c.priceBox = CreateFrame("EditBox", nil, fx, "InputBoxTemplate"); c.priceBox:SetSize(40, 16); c.priceBox:SetPoint("LEFT", c.defBtn, "RIGHT", 8, 0)
        c.priceBox:SetAutoFocus(false); c.priceBox:SetFontObject("GameFontNormalSmall"); c.priceBox:SetMaxLetters(6)
        c.priceBox:SetScript("OnEnterPressed", function(self)
            local x = c.x; if not x then return end
            local n = tonumber(self:GetText())
            DB.prices.items[x.e.kind] = n and math.max(0, math.floor(n)) or nil
            self:ClearFocus(); Apply(); Mark(c)
        end)
        c.priceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Mark(c) end)
        c.defBtn:SetScript("OnClick", function() local x = c.x; if x then DB.names[x.e.kind] = nil; x.e.name = x.e.defname; c.nameBox:ClearFocus(); Mark(c) end end)
        cells[#cells + 1] = c
        local lvl = m:GetFrameLevel() + 3
        local function Btn(txt, w, point, ox, oy, fn)
            local b = CreateFrame("Button", nil, bg, "UIPanelButtonTemplate"); b:SetSize(w, 18); b:SetPoint(point, bg, point, ox, oy); b:SetFrameLevel(lvl); b:SetText(txt); b:SetScript("OnClick", fn); return b
        end
        Btn("+", 22, "TOPRIGHT", -4, -4, function() Edit(c, 1.1) end)
        Btn("-", 22, "TOPRIGHT", -28, -4, function() Edit(c, 1 / 1.1) end)
        Btn("R", 22, "TOPRIGHT", -52, -4, function()
            local x = c.x; if x then x.s, x.y, x.z, x.r, x.edited = x.s0, x.y0, x.z0, x.r0, false; DB.fit[x.model] = nil; Draw(c); Mark(c) end
        end)
        Btn("<", 22, "TOPLEFT", 4, -4, function() Edit(c, nil, 0, 0, -0.2618) end)
        Btn(">", 22, "TOPLEFT", 28, -4, function() Edit(c, nil, 0, 0, 0.2618) end)
        c.xBtn = Btn("X", 36, "BOTTOMRIGHT", -4, 4, function()
            local x = c.x; if not x then return end   -- X = send to the Removed shelf; on the shelf it brings the item back (to its old category, or Unsorted)
            if CatOf(x.e) == REMOVED then SetCat(x.e, (x.e.defcat ~= REMOVED) and x.e.defcat or UNSORTED) else SetCat(x.e, REMOVED) end
            Apply(); Mark(c)
        end)
        c.catBtn = Btn("", 150, "BOTTOMLEFT", 4, 4, nil)
        c.catBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c.catBtn:SetScript("OnClick", function(self)
            local x = c.x; if not x then return end
            local L = CatList(x.e); if #L == 0 then return end
            PickList(self, L, CatOf(x.e), function(name) if c.x == x then SetCat(x.e, name); Apply(); Mark(c) end end)
        end)
        m:EnableMouse(true); m:EnableMouseWheel(true)
        m:SetScript("OnMouseWheel", function(_, d) selected = c; Edit(c, d > 0 and 1.1 or 1 / 1.1) end)
        local dx, dy, db
        m:SetScript("OnMouseDown", function(_, b) selected = c; dx, dy = GetCursorPosition(); db = b end)
        m:SetScript("OnMouseUp", function() dx = nil end)
        m:SetScript("OnHide", function() dx = nil end)
        m:SetScript("OnUpdate", function()
            if dx then
                local mx, my = GetCursorPosition()
                if db == "RightButton" then Edit(c, nil, (mx - dx) * 0.0118, (my - dy) * 0.0118) else Edit(c, nil, 0, 0, (mx - dx) * 0.012) end   -- left = turn, right = move
                dx, dy = mx, my
            end
        end)
    end end
    local function TopBtn(txt, w, xo, fn)
        local b = CreateFrame("Button", nil, fx, "UIPanelButtonTemplate"); b:SetSize(w, 26); b:SetPoint("TOPLEFT", fx, "TOPLEFT", xo, -8); b:SetText(txt); b:SetScript("OnClick", fn); return b
    end
    TopBtn("<", 36, 10, function() Show(page - 1) end)
    TopBtn(">", 36, 50, function() Show(page + 1) end)
    fx.pageText = fx:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fx.pageText:SetPoint("LEFT", fx, "TOPLEFT", 94, -21)
    local sb = CreateFrame("EditBox", nil, fx, "InputBoxTemplate"); sb:SetSize(150, 20); sb:SetPoint("TOPLEFT", fx, "TOPLEFT", 200, -11); sb:SetAutoFocus(false)
    sb:SetScript("OnEnterPressed", function(self) query = self:GetText(); self:ClearFocus(); Refresh() end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); query = ""; self:ClearFocus(); Refresh() end)
    local sl = fx:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); sl:SetPoint("BOTTOMLEFT", sb, "TOPLEFT", -4, 0); sl:SetText("search name/category + Enter")
    local mb = TopBtn("Flagged", 90, 366, function() end)
    mb:SetScript("OnClick", function() mode = mode % 3 + 1; if mode == 3 and not showRemoved then mode = 1 end; mb:SetText(MODES[mode]); Refresh() end)
    fx.modeBtn = mb
    local cf = TopBtn("Cat: All", 170, 558, function() end)
    cf:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function CatText() local n = 0; if catFilter then for _, e in ipairs(C.items) do if e.model and e.model ~= "" and CatOf(e) == catFilter then n = n + 1 end end end
        cf:SetText(catFilter and (catFilter .. " (" .. n .. ")") or "Cat: All") end
    cf:SetScript("OnClick", function(self)   -- click opens a list; picking a category switches the list to All so every item in it shows
        local L = { "All categories" }; for _, c in ipairs(DB.cats) do if not Hidden(c) then L[#L + 1] = c end end
        PickList(self, L, catFilter or "All categories", function(name, k)
            catFilter = (k > 1) and name or nil
            if catFilter then mode = 2; mb:SetText(MODES[mode]) end
            query = ""; sb:SetText(""); Refresh(); CatText()
        end)
    end)
    fx.catText = CatText; CatText()
    local function Check(txt, xo, get, set)
        local c = CreateFrame("CheckButton", nil, fx, "UICheckButtonTemplate"); c:SetSize(26, 26); c:SetPoint("TOPLEFT", fx, "TOPLEFT", xo, -8)
        local l = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); l:SetPoint("LEFT", c, "RIGHT", 0, 1); l:SetText(txt)
        c:SetChecked(get()); c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end); return c
    end
    local function Toggled()   -- a hidden category/mode can no longer be selected
        Apply()
        if catFilter and Hidden(catFilter) then catFilter = nil end
        if mode == 3 and not showRemoved then mode = 1 end
        mb:SetText(MODES[mode]); Refresh(); CatText()
    end
    fx.chkRemoved = Check("Show Removed", 740, function() return showRemoved end, function(v) showRemoved = v; Toggled() end)
    fx.chkUnsorted = Check("Show Unsorted", 860, function() return showUnsorted end, function(v) showUnsorted = v; Toggled() end)
    TopBtn("Categories", 90, 462, function()
        catPanel = catPanel.Render and catPanel or BuildCatPanel(); catPanel.Render(); catPanel:Show()
    end)
    TopBtn("Done", 70, W - 80, function()
        for _, c in ipairs(cells) do Save(c) end
        Apply(); fx:Hide()
        local f, r, k = 0, 0, 0
        for _ in pairs(DB.fit) do f = f + 1 end; for kind, cat in pairs(DB.categories) do if cat == REMOVED then r = r + 1 end end; for _ in pairs(DB.categories) do k = k + 1 end
        local nn = 0; for _ in pairs(DB.names) do nn = nn + 1 end
        print(string.format("|cff66ccffGarrison admin:|r %d fits, %d marked for removal, %d recategorised, %d renamed. Type /reload to write to disk, then tell Claude.", f, r, k, nn))
    end)
    local help = fx:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); help:SetPoint("RIGHT", fx, "TOPRIGHT", -90, -21)
    help:SetText("wheel zoom  L-drag turn  R-drag move")
end

function WotlkGarrisonOpenAdmin()
    if not DB then Init() end
    if not fx then Build() end
    showRemoved, showUnsorted = false, false; fx.chkRemoved:SetChecked(false); fx.chkUnsorted:SetChecked(false); Apply()   -- off every time
    if mode == 3 then mode = 1; fx.modeBtn:SetText(MODES[mode]) end
    if catFilter and Hidden(catFilter) then catFilter = nil end
    Refresh(); fx:Show()
end
