-- Jukebox: browse the game's music by group/area, play, repeat/shuffle/random, favorites.
-- Personal mode (/jukebox): plays only for you. Garrison mode (opened from the Jukebox NPC inside a garrison): your pick is sent to the
-- server, which plays it for everyone inside that garrison (server side: scripts/garrison_jukebox.lua, optional; the addon works without it). Track data: Tracks.lua (generated).
local T = WotlkJukeboxTracks
local ROW_H, ROWS = 22, 17
local title
local frame, areaScroll, areaContent, trackScroll, trackContent
local areaRows, trackRows = {}, {}
local nowText, timeText, modeText, shuffleBtn, repeatBtn, favBtn, playBtn
local mode = "personal"                -- "personal" | "garrison" (window mode)
local inGarrison, ctrl = false, false    -- server says we are inside a garrison; we are this garrison's music controller
local curArea                           -- index into T (or "fav")
local selected                          -- selected track {path,name,dur}
local queue, qi = {}, 0                 -- what Next/Prev/auto-advance walk through
local playing, elapsed, shuffle, repeatMode = nil, 0, false, "off"   -- repeatMode: off | one | all

local function DB() WotlkJukeboxDB = WotlkJukeboxDB or { favs = {} }; return WotlkJukeboxDB end
local function Fmt(s) s = math.floor(s + 0.5); return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
local function Pretty(f) return (f:gsub("%.mp3$", ""):gsub("%.MP3$", "")) end

local function TracksOf(a)
    local out = {}
    if a == "fav" then
        for _, area in ipairs(T) do for _, t in ipairs(area.tracks) do
            local p = area.dir .. "\\" .. t[1]
            if DB().favs[p] then out[#out + 1] = { path = p, name = Pretty(t[1]) .. "  |cff999999(" .. area.area .. ")|r", dur = t[2] } end
        end end
    elseif a and T[a] then
        for _, t in ipairs(T[a].tracks) do out[#out + 1] = { path = T[a].dir .. "\\" .. t[1], name = Pretty(t[1]), dur = t[2] } end
    end
    return out
end

local Refresh   -- forward

local function Stop(silent)
    playing = nil; elapsed = 0
    StopMusic()
    if nowText then nowText:SetText("Not playing"); timeText:SetText("") end
end

local function PlayLocal(tr)
    playing, elapsed = tr, 0
    PlayMusic(tr.path)
    nowText:SetText("|cff00ff00Now playing:|r " .. tr.name); timeText:SetText("0:00 / " .. Fmt(tr.dur))
end

local function PlayIndex(i)
    local tr = queue[i]; if not tr then return end
    qi = i; selected = tr
    if mode == "garrison" then AcoreLib.Send("jukebox", "play", tr.path)   -- the server echoes it back to everyone, us included
    else PlayLocal(tr) end
    Refresh()
end

local function Advance(dir)
    if #queue == 0 then return end
    if shuffle and dir > 0 then
        PlayIndex(#queue == 1 and 1 or (function() local n repeat n = math.random(#queue) until n ~= qi return n end)())
    else
        local n = qi + dir
        if n > #queue then n = 1 elseif n < 1 then n = #queue end
        PlayIndex(n)
    end
end

local function PlaySelected()
    if not selected then return end
    queue = TracksOf(curArea)
    for i, t in ipairs(queue) do if t.path == selected.path then PlayIndex(i); return end end
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    if not playing then return end
    elapsed = elapsed + dt
    if timeText then timeText:SetText(Fmt(math.min(elapsed, playing.dur)) .. " / " .. Fmt(playing.dur)) end
    if elapsed >= playing.dur + 1 then
        if inGarrison and not ctrl then Stop(); return end          -- listeners just wait for the controller's next song
        if repeatMode == "one" then (mode == "garrison" and (function() AcoreLib.Send("jukebox", "play", playing.path) end) or PlayLocal)(playing)
        elseif repeatMode == "all" or shuffle then Advance(1)
        elseif qi < #queue then Advance(1)
        elseif mode == "garrison" then AcoreLib.Send("jukebox", "stop", "")   -- end of list: stop for everyone
        else Stop() end
    end
end)

Refresh = function()
    if not frame then return end
    modeText:SetText(mode == "garrison" and "|cff66ccffGARRISON MODE|r  -  plays for everyone in this garrison" or "Personal jukebox: plays only for you")
    title:SetText(mode == "garrison" and "Jukebox - Garrison Mode" or "Jukebox")
    -- areas (left): Favorites, then area rows with group headers
    local items = { { fav = true } }
    local lastGroup
    for i, a in ipairs(T) do
        if a.group ~= lastGroup then items[#items + 1] = { header = a.group }; lastGroup = a.group end
        items[#items + 1] = { idx = i, text = a.area }
    end
    areaContent:SetHeight(#items * ROW_H)
    for i, it in ipairs(items) do
        local r = areaRows[i]
        if not r then
            r = CreateFrame("Button", nil, areaContent); r:SetSize(170, ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.text:SetPoint("LEFT", 4, 0)
            r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r:SetScript("OnClick", function(self) if self.target then curArea = self.target; Refresh() end end)
            areaRows[i] = r
        end
        r.target = it.fav and "fav" or it.idx
        if it.header then
            r.target = nil; r.text:SetText("|cffffd100" .. it.header .. "|r"); r:EnableMouse(false); r:SetHighlightTexture(nil)
        else
            r:EnableMouse(true); r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r.text:SetText(it.fav and "|cffffff00* Favorites|r" or ("   " .. it.text))
        end
        if r.target and r.target == curArea then r.sel:Show() else r.sel:Hide() end
        r:Show()
    end
    for i = #items + 1, #areaRows do areaRows[i]:Hide() end
    -- tracks (middle)
    local list = TracksOf(curArea)
    trackContent:SetHeight(math.max(#list * ROW_H, 1))
    for i, t in ipairs(list) do
        local r = trackRows[i]
        if not r then
            r = CreateFrame("Button", nil, trackContent); r:SetSize(310, ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.text:SetPoint("LEFT", 4, 0); r.text:SetWidth(240); r.text:SetJustifyH("LEFT")
            r.len = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.len:SetPoint("RIGHT", -4, 0)
            r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r:SetScript("OnClick", function(self) selected = self.tr; Refresh() end)
            r:SetScript("OnDoubleClick", function(self) selected = self.tr; PlaySelected() end)
            trackRows[i] = r
        end
        r.tr = t
        local fav = DB().favs[t.path] and "|cffffff00*|r " or ""
        local live = playing and playing.path == t.path and "|cff00ff00> |r" or ""
        r.text:SetText(live .. fav .. t.name); r.len:SetText(Fmt(t.dur))
        if selected and selected.path == t.path then r.sel:Show() else r.sel:Hide() end
        r:Show()
    end
    for i = #list + 1, #trackRows do trackRows[i]:Hide() end
    shuffleBtn:SetText("Shuffle: " .. (shuffle and "On" or "Off"))
    repeatBtn:SetText("Repeat: " .. (repeatMode == "one" and "Track" or repeatMode == "all" and "All" or "Off"))
    favBtn:SetText(selected and DB().favs[selected.path] and "Remove favorite" or "Add favorite")
    if selected then favBtn:Enable(); playBtn:Enable() else favBtn:Disable(); playBtn:Disable() end
end

local function Build()
    frame = CreateFrame("Frame", "WotlkJukeboxFrame", UIParent)
    frame:SetSize(820, 520); frame:SetPoint("CENTER"); frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(frame, 9)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WotlkJukeboxFrame")
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -18); title:SetText("Jukebox")
    modeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); modeText:SetPoint("TOP", 0, -42)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)

    areaScroll = CreateFrame("ScrollFrame", "WotlkJukeboxAreaScroll", frame, "UIPanelScrollFrameTemplate")
    areaScroll:SetPoint("TOPLEFT", 24, -66); areaScroll:SetSize(170, ROW_H * ROWS)
    areaContent = CreateFrame("Frame", nil, areaScroll); areaContent:SetSize(170, 1); areaScroll:SetScrollChild(areaContent)
    trackScroll = CreateFrame("ScrollFrame", "WotlkJukeboxTrackScroll", frame, "UIPanelScrollFrameTemplate")
    trackScroll:SetPoint("TOPLEFT", 230, -66); trackScroll:SetSize(310, ROW_H * ROWS)
    trackContent = CreateFrame("Frame", nil, trackScroll); trackContent:SetSize(310, 1); trackScroll:SetScrollChild(trackContent)

    local function Btn(text, w, x, y, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); b:SetSize(w, 26); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn); return b
    end
    nowText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nowText:SetPoint("TOPLEFT", 590, -70); nowText:SetWidth(210); nowText:SetJustifyH("LEFT"); nowText:SetText("Not playing")
    timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); timeText:SetPoint("TOPLEFT", 590, -110)
    playBtn = Btn("Play", 100, 590, -140, PlaySelected)
    Btn("Stop", 100, 700, -140, function() if mode == "garrison" then AcoreLib.Send("jukebox", "stop", "") else Stop() end end)
    Btn("< Prev", 100, 590, -172, function() Advance(-1) end)
    Btn("Next >", 100, 700, -172, function() Advance(1) end)
    Btn("Random track", 210, 590, -204, function()
        local all = {}
        for i = 1, #T do for _, t in ipairs(TracksOf(i)) do all[#all + 1] = t end end
        queue = all; PlayIndex(math.random(#all))
    end)
    Btn("Play favorites (repeat)", 210, 590, -236, function()
        curArea = "fav"; queue = TracksOf("fav")
        if #queue == 0 then nowText:SetText("|cffff6060No favorites yet: select a track and Add favorite.|r"); return end
        repeatMode, shuffle = "all", false; PlayIndex(1)
    end)
    shuffleBtn = Btn("", 210, 590, -280, function() shuffle = not shuffle; Refresh() end)
    repeatBtn = Btn("", 210, 590, -312, function() repeatMode = repeatMode == "off" and "one" or repeatMode == "one" and "all" or "off"; Refresh() end)
    favBtn = Btn("", 210, 590, -356, function() if selected then local d = DB().favs; d[selected.path] = (not d[selected.path]) or nil; Refresh() end end)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("TOPLEFT", 590, -396); note:SetWidth(210); note:SetJustifyH("LEFT")
    note:SetText("Double-click a track to play it. Next/Prev, shuffle and repeat walk the list you are viewing.")
    frame:Hide()
end

local function Open(m)
    if not frame then Build() end
    mode = m or "personal"
    if not curArea then curArea = 1 end
    Refresh(); frame:Show()
end

-- server -> client
AcoreLib.On("jukebox", "garrison", function(p)   -- "1" entered / "0" left a garrison: personal and garrison music never mix
    inGarrison = p == "1"; ctrl = false
    Stop()
    if frame and frame:IsShown() then frame:Hide() end
    mode = "personal"
end)
AcoreLib.On("jukebox", "open", function() ctrl = true; Open("garrison") end)       -- we took control at the Jukebox NPC
AcoreLib.On("jukebox", "release", function() ctrl = false; queue, qi = {}, 0; if frame then Refresh() end end)   -- someone else took control
AcoreLib.On("jukebox", "play", function(path)
    local name = path:match("([^\\]+)$") or path
    local dur = 180
    for _, a in ipairs(T) do if path:sub(1, #a.dir) == a.dir then for _, t in ipairs(a.tracks) do if t[1] == name then dur = t[2] end end end end
    PlayLocal({ path = path, name = Pretty(name), dur = dur }); if frame then Refresh() end
end)
AcoreLib.On("jukebox", "stop", function() Stop(); if frame then Refresh() end end)

SLASH_WOTLKJUKEBOX1 = "/jukebox"
SlashCmdList["WOTLKJUKEBOX"] = function()
    if inGarrison then print("|cff66ccffJukebox:|r inside a garrison the jukebox only works through the Jukebox NPC."); return end
    if frame and frame:IsShown() then frame:Hide() else Open("personal") end
end
