-- 3D preview (right side of the window). Mouse: wheel = zoom, left-drag = turn, right-drag = move (no on-screen text). The view of an item comes from the catalog:
--   vs/vy/vz = scale/sideways/up and vr = turn (measured or set with the admin tool); items without them get a size-based guess.
local G = WotlkGarrison
local view = { zoom = 1, rot = 0.61, panX = 0, panZ = 0, e = nil }
local DEFAULT_ROT = 0.61

-- scale, sideways, up for an object model at the current zoom/pan
local function ViewOf(e, zoom, px, pz)
    if e.vs then return e.vs * zoom, (e.vy or 0) * zoom + px, (e.vz or 0) * zoom + pz end
    local sz, cz = e.sz or 0, e.cz or 0
    local base = sz > 0 and math.max(0.05, math.min(10, 2.2 / sz)) or 1
    local sc = base * zoom
    return sc, px, 1 - cz * sc + pz
end

local function ApplyView()
    local model, e = G.ui.model, view.e
    if not model or not e then return end
    if e.npc and e.npc > 0 then
        model:SetModelScale(view.zoom); model:SetPosition(0, view.panX, view.panZ)
    elseif e.model and e.model ~= "" then
        local sc, vy, vz = ViewOf(e, view.zoom, view.panX, view.panZ)
        model:SetModelScale(sc); model:SetPosition(0, vy, vz)
    end
    model:SetRotation(view.rot)
end

local function ResetView()
    local e = view.e
    view.zoom, view.rot, view.panX, view.panZ = 1, (e and e.vr) or DEFAULT_ROT, 0, 0
end

function G.Preview(e)
    local ui = G.ui
    if not ui.model then return end
    ui.model:Hide(); ui.iconTex:Hide()
    view.e = e; ResetView()
    if not e then ui.hint:SetText("Select something to preview it"); ui.hint:Show(); return end
    ui.hint:Hide()
    if e.npc > 0 then
        if not G.st.primed then ui.hint:SetText("Loading preview..."); ui.hint:Show(); return end
        ui.model:Show(); ui.model:ClearModel(); ui.model:SetCreature(e.npc)
        ApplyView()
    elseif e.model ~= "" then
        ui.model:Show(); ui.model:ClearModel()
        if not pcall(ui.model.SetModel, ui.model, e.model) then ui.model:Hide(); ui.hint:SetText("(no preview for this object)"); ui.hint:Show() end
        ApplyView()
    elseif e.icon and e.icon ~= "" then
        ui.iconTex:SetTexture("Interface\\Icons\\" .. e.icon); ui.iconTex:Show()
    else
        ui.hint:SetText("(no preview)"); ui.hint:Show()
    end
end

-- grid cells (List.lua) use the same view as the big preview at zoom 1, so a cell must keep the big preview's 210:250 shape
function G.FitModel(model, e)
    if e.npc and e.npc > 0 then
        model:SetModelScale(1); model:SetPosition(0, 0, 0)
    elseif e.model and e.model ~= "" then
        local sc, vy, vz = ViewOf(e, 1, 0, 0)
        model:SetModelScale(sc); model:SetPosition(0, vy, vz)
    end
    model:SetRotation(e.vr or DEFAULT_ROT)
end

-- the view as drawn right now (curator "Save view"): scale, sideways, up, turn - or nil for a creature / nothing
function G.CurrentView()
    local e = view.e
    if not e or (e.npc and e.npc > 0) or not e.model or e.model == "" then return nil end
    local sc, vy, vz = ViewOf(e, view.zoom, view.panX, view.panZ)
    return sc, vy, vz, view.rot
end

local function Zoom(f) view.zoom = math.max(0.3, math.min(4, view.zoom * f)); ApplyView() end

function G.BuildPreview(frame)
    local ui = G.ui
    local bg = CreateFrame("Frame", nil, frame)
    bg:SetSize(210, 250); bg:SetPoint("TOPRIGHT", -26, -64)
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                     tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0.06, 0.06, 0.08, 1)
    -- DressUpModel (not PlayerModel) applies humanoid appearance records: a plain PlayerModel draws them white
    local model = CreateFrame("DressUpModel", nil, bg)
    model:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4); model:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -4, 4)
    model:SetFrameLevel(bg:GetFrameLevel() + 5); model:Hide()
    model:EnableMouse(true); model:EnableMouseWheel(true)
    model:SetScript("OnMouseWheel", function(_, d) Zoom(d > 0 and 1.15 or 1 / 1.15) end)
    local dragX, dragY, dragBtn
    model:SetScript("OnMouseDown", function(_, b) dragX, dragY = GetCursorPosition(); dragBtn = b end)
    model:SetScript("OnMouseUp", function() dragX, dragBtn = nil, nil end)
    model:SetScript("OnHide", function() dragX, dragBtn = nil, nil end)
    model:SetScript("OnUpdate", function()
        if not dragX then return end
        local x, y = GetCursorPosition()
        if dragBtn == "RightButton" then
            view.panX = view.panX + (x - dragX) * 0.01; view.panZ = view.panZ + (y - dragY) * 0.01; ApplyView()
        else
            view.rot = view.rot + (x - dragX) * 0.012; model:SetRotation(view.rot)
        end
        dragX, dragY = x, y
    end)
    local function Button(label, x, fn)
        local b = CreateFrame("Button", nil, bg, "UIPanelButtonTemplate"); b:SetSize(26, 20); b:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", x, 6)
        b:SetText(label); b:SetFrameLevel(model:GetFrameLevel() + 3); b:SetScript("OnClick", fn)
    end
    Button("+", -8, function() Zoom(1.25) end)
    Button("-", -36, function() Zoom(1 / 1.25) end)
    Button("R", -64, function() ResetView(); ApplyView() end)
    ui.model = model
    ui.iconTex = bg:CreateTexture(nil, "ARTWORK"); ui.iconTex:SetSize(128, 128); ui.iconTex:SetPoint("CENTER", bg, "CENTER", 0, 0); ui.iconTex:Hide()
    ui.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable"); ui.hint:SetPoint("CENTER", bg, "CENTER", 0, 0); ui.hint:SetWidth(190)
    ui.bigName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); ui.bigName:SetPoint("TOP", bg, "BOTTOM", 0, -10); ui.bigName:SetWidth(210)
    ui.bigDetail = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); ui.bigDetail:SetPoint("TOP", ui.bigName, "BOTTOM", 0, -4); ui.bigDetail:SetWidth(210)
    return bg
end
