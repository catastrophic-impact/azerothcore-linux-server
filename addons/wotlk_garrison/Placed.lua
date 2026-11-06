-- "Placed" tab: the nudge pad (move / turn the selected placed item) and the pick marker (a mark floats above the selected item).
-- Moves are relative to the way the PLAYER faces; the server moves the real object.
local G = WotlkGarrison
local STEPS = { { 0.1, 2 }, { 0.5, 5 }, { 2, 15 }, { 5, 45 } }   -- { move yards, rotate degrees }
local stepIdx = 2
local marked = false

function G.Mark()
    local s = G.st.selected
    if G.st.tab == "placed" and G.st.inHome and s and s.key then
        AcoreLib.Send("house", "mark", s.key .. "," .. string.format("%.1f", s.tz or 2.5)); marked = true
    end
end
function G.Unmark() if marked then AcoreLib.Send("house", "unmark", ""); marked = false end end

local function Send(act, amount)
    local s = G.st.selected
    if not (s and s.key) then return end
    AcoreLib.Send("house", "dmove", s.key .. "," .. act .. "," .. amount); G.Mark()
end
local function Nudge(act, turning) local st = STEPS[stepIdx]; Send(act, turning and st[2] or st[1]) end

function G.BuildPad(frame)
    local pad = CreateFrame("Frame", nil, frame); pad:SetSize(156, 380); pad:SetPoint("TOPLEFT", 20, -96); pad:Hide()
    local function Button(label, x, y, w, fn)
        local b = CreateFrame("Button", nil, pad, "UIPanelButtonTemplate"); b:SetSize(w or 50, 28); b:SetPoint("TOPLEFT", x, y)
        b:SetText(label); b:SetScript("OnClick", fn); return b
    end
    local note = pad:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); note:SetPoint("TOPLEFT", 2, 0); note:SetWidth(152); note:SetJustifyH("LEFT")
    note:SetText("Moves are relative to the way YOU face. Stand back and look at the object.")
    local step
    local function StepText() step:SetText("Step: " .. STEPS[stepIdx][1] .. " yd / " .. STEPS[stepIdx][2] .. " deg") end
    step = Button("", 0, -54, 152, function() stepIdx = stepIdx % #STEPS + 1; StepText() end); StepText()
    local grid = {   -- label, column, row, action, uses the rotate step
        { "Turn L", 0, 0, "rl", true }, { "Away", 1, 0, "f" }, { "Turn R", 2, 0, "rr", true },
        { "Left", 0, 1, "l" }, { "Closer", 1, 1, "b" }, { "Right", 2, 1, "r" },
        { "Down", 0, 2, "d" }, { "To me", 1, 2, "me" }, { "Up", 2, 2, "u" },
    }
    for _, g in ipairs(grid) do Button(g[1], g[2] * 51, -90 - g[3] * 30, 50, function() Nudge(g[4], g[5]) end) end
    for i, deg in ipairs({ 45, 90, 180 }) do   -- fixed turns
        Button("L " .. deg, (i - 1) * 51, -186, 50, function() Send("rl", deg) end)
        Button("R " .. deg, (i - 1) * 51, -216, 50, function() Send("rr", deg) end)
    end
    Button("Snap to ground", 0, -252, 152, function() Nudge("snap") end)
    StaticPopupDialogs["WOTLKGARRISON_CLEAR_DECOR"] = {
        text = "Remove ALL decor from this garrison?\n\nEverything you placed is removed and refunded where it was paid for. This cannot be undone.",
        button1 = "Remove all", button2 = "Cancel", timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
        OnAccept = function() AcoreLib.Send("house", "dclear", ""); G.Request() end,
    }
    G.ui.clearBtn = Button("Remove all decor", 0, -306, 152, function() StaticPopup_Show("WOTLKGARRISON_CLEAR_DECOR") end)
    G.ui.pad = pad
end
