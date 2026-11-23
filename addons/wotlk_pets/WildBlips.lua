-- Minimap blips for the wild pets around you. The server (pb_wild) sends "pbw|pets|<north>,<west>,<species>,<level>,<name>;..." every second while there are any:
-- offsets in YARDS from you (WoW world: +x is north, +y is west). We draw our own pet icon on the minimap, clamped to its edge when the pet is farther than it shows.
local blips, expire = {}, 0
WotlkPetsDB = WotlkPetsDB or {}   -- SavedVariables: { blips = false } when the player switched the minimap blips off in the tracking menu
local function Enabled() return WotlkPetsDB.blips ~= false end
local ICON = "Interface\\Icons\\INV_Box_PetCarrier_01"
-- radius in yards from the minimap centre to its edge, by zoom level 0 (far) .. 5 (near)
local OUTDOOR = { 233.3, 200, 166.7, 133.3, 100, 66.7 }
local INDOOR = { 150, 120, 90, 60, 40, 25 }

-- pure math: screen offset (pixels from the minimap centre, x right / y up) of a pet at (north, west) yards; facing = player facing in radians when the minimap rotates
local function Place(north, west, radiusYards, radiusPx, facing)
    local x, y = -west, north   -- east is screen right, north is screen up
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        x, y = x * c + y * s, -x * s + y * c
    end
    local d = math.sqrt(x * x + y * y)
    local k = radiusPx / radiusYards
    local edge = false
    if d > radiusYards then k = radiusPx / d; edge = true end   -- beyond the map: pinned to its rim
    return x * k, y * k, edge
end

local inside, dirty = false, true   -- recomputed only when the minimap zoom / area changes (the check below briefly changes the zoom)
local function Indoors()
    if not dirty then return inside end
    dirty = false
    local zoom = Minimap:GetZoom()
    if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1) end   -- the usual trick: a zoom step shows which table applies
    inside = (tonumber(GetCVar("minimapZoom")) or 0) == Minimap:GetZoom()
    Minimap:SetZoom(zoom)
    return inside
end

local function Blip(i)
    local b = blips[i]
    if b then return b end
    b = CreateFrame("Button", nil, Minimap); b:SetSize(16, 16); b:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    b.tex = b:CreateTexture(nil, "OVERLAY"); b.tex:SetAllPoints(); b.tex:SetTexture(ICON)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(self.name or "Wild pet", 1, 0.82, 0)
        GameTooltip:AddLine("Wild pet, level " .. (self.level or "?"), 0.8, 0.8, 0.8); GameTooltip:AddLine("Right-click it to challenge it.", 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide(); blips[i] = b
    return b
end

local data = {}   -- { north, west, species, level, name }
local shiftN, shiftW = 0, 0   -- how far YOU walked (yards north / west) since the server's last list: the offsets in the list were measured from where you stood then
local env   -- radius / blip box size, read from the minimap 10 times a second (not every frame)
local function Draw(refresh)
    if not Enabled() then for i = 1, #blips do blips[i]:Hide() end return end
    if refresh or not env then
        local zoom = Minimap:GetZoom()
        env = { radius = (Indoors() and INDOOR or OUTDOOR)[zoom + 1] or 100, px = (Minimap:GetWidth() or 140) / 2 - 6, rot = GetCVar("rotateMinimap") == "1" }
    end
    local facing = env.rot and GetPlayerFacing and GetPlayerFacing() or nil
    for i, e in ipairs(data) do
        local b = Blip(i)
        local x, y, edge = Place(e[1] - shiftN + (e[6] or 0), e[2] - shiftW + (e[7] or 0), env.radius, env.px, facing)   -- e[6], e[7]: the correction of the last list, easing out
        b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", x, y); b:SetAlpha(edge and 0.55 or 1)
        b.name, b.level = e[5], e[4]; b:Show()
    end
    for i = #data + 1, #blips do blips[i]:Hide() end
end

local driver = CreateFrame("Frame")
for _, ev in ipairs({ "MINIMAP_UPDATE_ZOOM", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }) do driver:RegisterEvent(ev) end
driver:SetScript("OnEvent", function() dirty = true; env = nil end)
driver:SetScript("OnUpdate", function(self, dt)
    if #data == 0 then return end
    local v = GetUnitSpeed and GetUnitSpeed("player") or 0   -- dead reckoning: the blips stay put in the WORLD while you run, instead of sliding with you until the next list
    if v > 0 and GetPlayerFacing then
        local f = GetPlayerFacing()
        if f then shiftN = shiftN + v * math.cos(f) * dt; shiftW = shiftW + v * math.sin(f) * dt end   -- facing 0 = north, growing towards the west
    end
    local k = math.exp(-8 * dt)   -- the jump a new list would cause is eased out over ~0.3 s
    for _, e in ipairs(data) do if e[6] then e[6], e[7] = e[6] * k, e[7] * k end end
    self.t = (self.t or 0) + dt
    if self.t >= 0.1 then   -- 10x a second: the cheap checks (stale list, minimap zoom / rotation)
        self.t = 0
        if GetTime() > expire then data = {}; Draw(true); return end   -- the server stopped talking (left the zone): no stale blips
        Draw(true)
    else
        Draw(false)   -- every other frame: smooth motion
    end
end)

AcoreLib.On("pbw", "pets", function(p)
    local prev = {}   -- where each species' blip is DRAWN right now (yards), so the new list continues from there instead of jumping
    for _, e in ipairs(data) do prev[e[3]] = { e[1] - shiftN + (e[6] or 0), e[2] - shiftW + (e[7] or 0) } end
    data = {}; shiftN, shiftW = 0, 0   -- a fresh list is measured from where you stand now
    if p ~= "none" then
        for entry in p:gmatch("[^;]+") do
            local n, w, sp, lv, name = entry:match("^(%-?[%d%.]+),(%-?[%d%.]+),(%d+),(%d+),(.+)$")
            if n then
                local e = { tonumber(n), tonumber(w), tonumber(sp), tonumber(lv), name }
                local o = prev[e[3]]
                if o then local cn, cw = o[1] - e[1], o[2] - e[2]; if math.abs(cn) < 25 and math.abs(cw) < 25 then e[6], e[7] = cn, cw end end   -- a bigger jump is a real teleport: snap
                data[#data + 1] = e
            end
        end
    end
    expire = GetTime() + 6
    Draw(true)
end)

-- the minimap TRACKING menu (the magnifier button) gets a "Wild Pets" tick box; /petblips does the same from the chat line
local function Toggle(on)
    if on == nil then on = not Enabled() end
    WotlkPetsDB.blips = on and true or false
    Draw()
end
if hooksecurefunc and MiniMapTrackingDropDown_Initialize then
    hooksecurefunc("MiniMapTrackingDropDown_Initialize", function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Wild Pets"; info.isNotRadio = true; info.keepShownOnClick = 1; info.checked = Enabled()
        info.icon = ICON; info.func = function() Toggle(); end
        UIDropDownMenu_AddButton(info)
    end)
    -- the tracking dropdown kept a reference to the ORIGINAL function when Blizzard's UI loaded: point it at the hooked one
    if MiniMapTrackingDropDown and UIDropDownMenu_Initialize then pcall(UIDropDownMenu_Initialize, MiniMapTrackingDropDown, MiniMapTrackingDropDown_Initialize, "MENU") end
end
SLASH_PETBLIPS1 = "/petblips"
SlashCmdList["PETBLIPS"] = function() Toggle(); DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[Pets]|r minimap wild pet markers " .. (Enabled() and "on" or "off") .. ".") end

WotlkBlips = { Toggle = Toggle, Enabled = Enabled, Place = Place, Data = function() return data end, Blips = function() return blips end, Draw = Draw }   -- (tests)
