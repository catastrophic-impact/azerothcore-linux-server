-- Jukebox: browse the game's music by group/area, play, shuffle / random songs, Repeat-Autoplay-Off, favorites (own tab).
-- Personal mode (/jukebox): plays only for you. Garrison mode (opened from the Jukebox NPC inside a garrison): your pick is sent to the
-- server, which plays it for everyone inside that garrison (server side: scripts/garrison_jukebox.lua, optional; the addon works without it). Track data: Tracks.lua (generated).
-- A small "Now playing" bar shows whatever the jukebox is playing for you (also when someone else controls the garrison jukebox) while the window is closed.
-- Note: the 3.3.5 client has no call that reports the game's own zone music, so only music started through the jukebox can be shown.
AcoreLib.Announce("jukebox")   -- tells the server this client has the addon (the garrison Jukebox NPC needs it)
local T = WotlkJukeboxTracks
local ROW_H, ROWS = 22, 15
local LIB_W, FAV_W = 310, 516            -- track list width in the Library tab / the Favorites tab
local title
local frame, areaScroll, areaContent, trackScroll, trackContent
local areaRows, trackRows = {}, {}
local nowText, srcText, timeText, bar, modeText, shuffleBtn, pmBtn, rndBtn, favBtn, playBtn, prevBtn, nextBtn, tabLib, tabFav, hintText, emptyText
local nowBar, nowBarText
local mode = "personal"                -- "personal" | "garrison" (window mode)
local inGarrison, ctrl = false, false    -- server says we are inside a garrison; we are this garrison's music controller
local tab = "lib"                       -- "lib" | "fav"
local curArea                           -- index into T (Library tab)
local selected                          -- selected track {path,name,dur}
local queue, qi = {}, 0                 -- what Next/Prev/auto-advance walk through
local playing, elapsed = nil, 0
local rnd, rndList = false, nil     -- random songs on: Shuffle (rndList = the list key it runs on) or Play Random Songs (rndList = "all")
local hist = {}                      -- songs played while random is on (Prev walks back through them)
local zoneFix = 0                    -- seconds until the song is restarted after a zone change (0 = idle)
local playSource = "personal"           -- "personal" | "garrison" (who started what is playing)

local function DB()
    WotlkJukeboxDB = WotlkJukeboxDB or {}
    WotlkJukeboxDB.favs = WotlkJukeboxDB.favs or {}
    if WotlkJukeboxDB.pmode == nil then WotlkJukeboxDB.pmode = "autoplay" end   -- what happens when a song ends: autoplay (next song) | repeat | off. Autoplay by default
    return WotlkJukeboxDB
end
local function Fmt(s) s = math.floor(s + 0.5); return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
local function Pretty(f) return (f:gsub("%.mp3$", ""):gsub("%.MP3$", "")) end

-- the list that Next/Prev/Shuffle/double-click work on: the favorites in the Favorites tab, else the area being viewed
local function ListKey() return tab == "fav" and "fav" or curArea end

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

local function AllTracks()
    local all = {}
    for i = 1, #T do for _, t in ipairs(TracksOf(i)) do all[#all + 1] = t end end
    return all
end

local Refresh, UpdateButtons   -- forward

-- ---- "now playing" display (window + the small bar) ----
local function UpdateNow()
    if nowText then
        if playing then
            nowText:SetText(playing.name)
            srcText:SetText(playSource == "garrison" and "|cff66ccffGarrison jukebox|r  (plays for everyone inside)" or "|cff00ff00Your jukebox|r  (plays only for you)")
            bar:SetMinMaxValues(0, math.max(playing.dur, 1)); bar:SetValue(math.min(elapsed, playing.dur))
            timeText:SetText(Fmt(math.min(elapsed, playing.dur)) .. " / " .. Fmt(playing.dur))
        else
            nowText:SetText("|cff999999Nothing playing|r"); srcText:SetText(""); bar:SetMinMaxValues(0, 1); bar:SetValue(0); timeText:SetText("")
        end
    end
    if UpdateButtons then UpdateButtons() end
    if nowBar then
        if playing and not (frame and frame:IsShown()) then
            nowBarText:SetText("|cff00ff00Now playing:|r " .. playing.name .. "  " .. Fmt(math.min(elapsed, playing.dur)) .. " / " .. Fmt(playing.dur))
            nowBar:Show()
        else nowBar:Hide() end
    end
end

local function Stop()
    playing = nil; elapsed = 0
    StopMusic()
    UpdateNow()
end

local function PlayLocal(tr, source)
    playing, elapsed, playSource = tr, 0, source or "personal"
    PlayMusic(tr.path)
    UpdateNow()
end

local function SendOrPlay(tr)
    if mode == "garrison" then AcoreLib.Send("jukebox", "play", tr.path)   -- the server echoes it back to everyone, us included
    else PlayLocal(tr, "personal") end
end

local function PlayIndex(i)
    local tr = queue[i]; if not tr then return end
    if rnd and playing then hist[#hist + 1] = playing; if #hist > 100 then table.remove(hist, 1) end end
    qi = i; selected = tr
    SendOrPlay(tr)
    if Refresh then Refresh() end
end

local function RandomIndex(n)
    if n <= 1 then return 1 end
    local k repeat k = math.random(n) until k ~= qi
    return k
end

local function PM() return DB().pmode end   -- "autoplay" | "repeat" | "off"

-- Next / Prev (and what happens when a song ends in Autoplay):
--   random on:  Next = another random song, Prev = the song played before.
--   Repeat:     Next/Prev just start the song over.
--   Autoplay / Off: the next / previous song in the list (wraps around).
local function Step(dir)
    if rnd then
        if #queue == 0 then return end
        if dir > 0 then PlayIndex(RandomIndex(#queue)); return end
        local prev = table.remove(hist)
        if prev then
            for i, t in ipairs(queue) do if t.path == prev.path then qi = i; selected = t; break end end
            SendOrPlay(prev); if Refresh then Refresh() end
        elseif playing then SendOrPlay(playing) end
        return
    end
    if PM() == "repeat" and playing then SendOrPlay(playing); return end
    if #queue == 0 then queue = TracksOf(ListKey()); qi = 0 end
    if #queue == 0 then return end
    local n = qi + dir
    if n > #queue then n = 1 elseif n < 1 then n = #queue end
    PlayIndex(n)
end

-- a specific song was picked (Play / double-click): that ends random mode
local function PlaySelected()
    if not selected then return end
    rnd, rndList, hist = false, nil, {}
    queue = TracksOf(ListKey())
    for i, t in ipairs(queue) do if t.path == selected.path then PlayIndex(i); return end end
end

-- Stop: stops the music for good (for everyone in garrison mode) and switches random off.
local function StopAll()
    rnd, rndList, hist, zoneFix = false, nil, {}, 0
    if mode == "garrison" then AcoreLib.Send("jukebox", "stop", "") else Stop() end
    if Refresh then Refresh() end
end

-- Shuffle: start a random song from the list you are looking at (an area, or your favorites) and keep picking random ones from it.
local function StartShuffle()
    queue = TracksOf(ListKey()); qi = 0
    if #queue == 0 then
        if nowText then nowText:SetText(tab == "fav" and "|cffff6060No favorites yet: select a track and add it.|r" or "|cffff6060This list is empty.|r") end
        return
    end
    rnd, rndList, hist = true, ListKey(), {}; PlayIndex(math.random(#queue))
end

-- Play Random Songs: random songs from the whole catalog.
local function StartRandomAll()
    queue = AllTracks(); qi = 0; rnd, rndList, hist = true, "all", {}; PlayIndex(math.random(#queue))
end

local barClock = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    if not playing then return end
    elapsed = elapsed + dt
    if zoneFix > 0 then   -- the game's zone music cut the song: start it again from the beginning (the client cannot resume mid-song)
        zoneFix = zoneFix - dt
        if zoneFix <= 0 then zoneFix = 0; elapsed = 0; PlayMusic(playing.path) end
    end
    if bar then bar:SetValue(math.min(elapsed, playing.dur)) end
    if timeText then timeText:SetText(Fmt(math.min(elapsed, playing.dur)) .. " / " .. Fmt(playing.dur)) end
    barClock = barClock + dt
    if barClock > 0.5 then barClock = 0; if nowBar and nowBar:IsShown() then UpdateNow() end end
    if elapsed >= playing.dur + 1 then
        if inGarrison and not ctrl then Stop(); return end          -- listeners just wait for the controller's next song
        if rnd then Step(1)
        elseif PM() == "repeat" then SendOrPlay(playing)
        elseif PM() == "autoplay" then Step(1)
        else StopAll() end                                           -- off: nothing else plays
    end
end)

-- zoning / entering a new area makes the game start its own music: bring the jukebox song back
local zev = CreateFrame("Frame")
zev:RegisterEvent("PLAYER_ENTERING_WORLD"); zev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zev:SetScript("OnEvent", function() if playing then zoneFix = 2 end end)

local function RowButton(parent, w, i, fontObj)
    local r = CreateFrame("Button", nil, parent); r:SetSize(w, ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY", fontObj); r.text:SetPoint("LEFT", 4, 0); r.text:SetJustifyH("LEFT")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    return r
end

local function FavTarget() return selected or playing end

-- which buttons are usable right now
UpdateButtons = function()
    if not playBtn then return end
    playBtn:SetText(playing and "Stop" or "Play")
    if playing or selected then playBtn:Enable() else playBtn:Disable() end
    shuffleBtn:SetText("Shuffle: " .. ((rnd and rndList == ListKey()) and "On" or "Off"))
    rndBtn:SetText("Play Random Songs: " .. ((rnd and rndList == "all") and "On" or "Off"))
    pmBtn:SetText("Mode: " .. (PM() == "repeat" and "Repeat" or PM() == "autoplay" and "Autoplay" or "Off"))
    if rnd then pmBtn:Disable() else pmBtn:Enable() end              -- random songs decide what plays next
    local tg = FavTarget()
    local isFav = tg and DB().favs[tg.path]
    if tab == "fav" then
        favBtn:SetText("Remove Favorite")
        if isFav then favBtn:Enable() else favBtn:Disable() end
    else
        favBtn:SetText("Add to Favorites")
        if tg and not isFav then favBtn:Enable() else favBtn:Disable() end
    end
end

Refresh = function()
    if not frame then return end
    modeText:SetText(mode == "garrison" and "|cff66ccffGARRISON MODE|r  -  plays for everyone in this garrison" or "Personal jukebox: plays only for you")
    title:SetText(mode == "garrison" and "Jukebox - Garrison Mode" or "Jukebox")
    -- tabs
    if tab == "lib" then tabLib:Disable(); tabFav:Enable() else tabLib:Enable(); tabFav:Disable() end
    -- layout: the Favorites tab has no area list, so its track list is wider
    local w = tab == "fav" and FAV_W or LIB_W
    trackScroll:ClearAllPoints()
    if tab == "fav" then areaScroll:Hide(); trackScroll:SetPoint("TOPLEFT", 24, -96) else areaScroll:Show(); trackScroll:SetPoint("TOPLEFT", 230, -96) end
    trackScroll:SetSize(w, ROW_H * ROWS); trackContent:SetWidth(w)

    -- areas (left, Library tab only), with group headers
    if tab == "lib" then
        local items = {}
        local lastGroup
        for i, a in ipairs(T) do
            if a.group ~= lastGroup then items[#items + 1] = { header = a.group }; lastGroup = a.group end
            items[#items + 1] = { idx = i, text = a.area }
        end
        areaContent:SetHeight(#items * ROW_H)
        for i, it in ipairs(items) do
            local r = areaRows[i]
            if not r then
                r = RowButton(areaContent, 170, i, "GameFontNormal")
                r:SetScript("OnClick", function(self) if self.target then curArea = self.target; Refresh() end end)
                areaRows[i] = r
            end
            r.target = it.idx
            if it.header then
                r.target = nil; r.text:SetText("|cffffd100" .. it.header .. "|r"); r:EnableMouse(false); r:SetHighlightTexture(nil)
            else
                r:EnableMouse(true); r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                r.text:SetText("   " .. it.text)
            end
            if r.target and r.target == curArea then r.sel:Show() else r.sel:Hide() end
            r:Show()
        end
        for i = #items + 1, #areaRows do areaRows[i]:Hide() end
    end

    -- tracks
    local list = TracksOf(ListKey())
    trackContent:SetHeight(math.max(#list * ROW_H, 1))
    for i, t in ipairs(list) do
        local r = trackRows[i]
        if not r then
            r = RowButton(trackContent, w, i, "GameFontHighlight")
            r.len = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.len:SetPoint("RIGHT", -4, 0)
            r:SetScript("OnClick", function(self) selected = self.tr; Refresh() end)
            r:SetScript("OnDoubleClick", function(self) selected = self.tr; PlaySelected() end)
            trackRows[i] = r
        end
        r:SetWidth(w); r.text:SetWidth(w - 70)
        r.tr = t
        local fav = (tab == "lib" and DB().favs[t.path]) and "|cffffff00*|r " or ""
        local live = playing and playing.path == t.path and "|cff00ff00> |r" or ""
        r.text:SetText(live .. fav .. t.name); r.len:SetText(Fmt(t.dur))
        if selected and selected.path == t.path then r.sel:Show() else r.sel:Hide() end
        r:Show()
    end
    for i = #list + 1, #trackRows do trackRows[i]:Hide() end
    if #list == 0 and tab == "fav" then emptyText:SetText("No favorites yet.\nSelect a track in the Library and press \"Add favorite\".") else emptyText:SetText("") end

    UpdateButtons()
    hintText:SetText(rnd and "Random is on: Next picks another random song, Prev goes back. Stop turns it off." or (tab == "fav" and "Shuffle plays your favorites in random order." or ("Shuffle plays random songs from " .. (T[curArea] and T[curArea].area or "this list") .. ".")))
    UpdateNow()
end

local function Build()
    frame = CreateFrame("Frame", "WotlkJukeboxFrame", UIParent)
    frame:SetSize(820, 520); frame:SetPoint("CENTER"); frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    AcoreLib.Solid(frame, 9)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function() UpdateNow() end); frame:SetScript("OnHide", function() UpdateNow() end)
    tinsert(UISpecialFrames, "WotlkJukeboxFrame")
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -18); title:SetText("Jukebox")
    modeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); modeText:SetPoint("TOP", 0, -42)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)

    local function Btn(text, w, x, y, fn)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"); b:SetSize(w, 26); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", fn); return b
    end
    tabLib = Btn("Library", 100, 24, -62, function() tab = "lib"; Refresh() end)
    tabFav = Btn("Favorites", 100, 128, -62, function() tab = "fav"; Refresh() end)

    areaScroll = CreateFrame("ScrollFrame", "WotlkJukeboxAreaScroll", frame, "UIPanelScrollFrameTemplate")
    areaScroll:SetPoint("TOPLEFT", 24, -96); areaScroll:SetSize(170, ROW_H * ROWS)
    areaContent = CreateFrame("Frame", nil, areaScroll); areaContent:SetSize(170, 1); areaScroll:SetScrollChild(areaContent)
    trackScroll = CreateFrame("ScrollFrame", "WotlkJukeboxTrackScroll", frame, "UIPanelScrollFrameTemplate")
    trackScroll:SetPoint("TOPLEFT", 230, -96); trackScroll:SetSize(LIB_W, ROW_H * ROWS)
    trackContent = CreateFrame("Frame", nil, trackScroll); trackContent:SetSize(LIB_W, 1); trackScroll:SetScrollChild(trackContent)
    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable"); emptyText:SetPoint("TOPLEFT", 40, -140); emptyText:SetWidth(440); emptyText:SetJustifyH("LEFT")

    -- right panel: now playing
    local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); head:SetPoint("TOPLEFT", 590, -66); head:SetText("NOW PLAYING")
    nowText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); nowText:SetPoint("TOPLEFT", 590, -84); nowText:SetWidth(210); nowText:SetHeight(50)
    nowText:SetJustifyH("LEFT"); nowText:SetJustifyV("TOP")
    srcText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); srcText:SetPoint("TOPLEFT", 590, -138); srcText:SetWidth(210); srcText:SetJustifyH("LEFT")
    bar = CreateFrame("StatusBar", nil, frame); bar:SetSize(210, 8); bar:SetPoint("TOPLEFT", 590, -158)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); bar:SetStatusBarColor(0.1, 0.8, 0.2); bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(); barBg:SetTexture(0, 0, 0, 0.5)
    timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); timeText:SetPoint("TOPLEFT", 590, -170)

    prevBtn = Btn("< Prev", 68, 590, -194, function() Step(-1) end)
    playBtn = Btn("Play", 68, 662, -194, function() if playing then StopAll() else PlaySelected() end end)
    nextBtn = Btn("Next >", 68, 734, -194, function() Step(1) end)
    shuffleBtn = Btn("", 210, 590, -228, function()
        if rnd and rndList == ListKey() then rnd, rndList, hist = false, nil, {}; Refresh() else StartShuffle() end   -- pressing it on another list starts shuffle there
    end)
    pmBtn = Btn("", 210, 590, -258, function()
        local d = DB(); d.pmode = d.pmode == "autoplay" and "repeat" or d.pmode == "repeat" and "off" or "autoplay"; Refresh()
    end)
    rndBtn = Btn("", 210, 590, -352, function()
        if rnd and rndList == "all" then rnd, rndList, hist = false, nil, {}; Refresh() else StartRandomAll() end
    end)
    favBtn = Btn("", 210, 590, -384, function()
        local tg = FavTarget(); if not tg then return end
        local d = DB().favs
        d[tg.path] = (tab ~= "fav") and true or nil      -- Library tab adds, Favorites tab removes
        Refresh()
    end)
    hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hintText:SetPoint("TOPLEFT", 590, -420); hintText:SetWidth(210); hintText:SetJustifyH("LEFT")
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("BOTTOMLEFT", 26, 20); note:SetWidth(540); note:SetJustifyH("LEFT")
    note:SetText("Double-click a track to play it.  Mode: Autoplay plays the next song in the list when one ends, Repeat plays the same song again, Off stops after the song.")
    frame:Hide()
end

-- the small bar: shows what is playing while the window is closed (click it to open the jukebox)
local function BuildBar()
    nowBar = CreateFrame("Button", "WotlkJukeboxNowBar", UIParent)
    nowBar:SetSize(330, 24); nowBar:SetPoint("TOP", 0, -90); nowBar:SetFrameStrata("MEDIUM")
    nowBar:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                         insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    nowBar:SetMovable(true); nowBar:EnableMouse(true); nowBar:RegisterForDrag("LeftButton")
    nowBar:SetScript("OnDragStart", nowBar.StartMoving); nowBar:SetScript("OnDragStop", nowBar.StopMovingOrSizing)
    nowBarText = nowBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); nowBarText:SetPoint("LEFT", 8, 0); nowBarText:SetWidth(314); nowBarText:SetJustifyH("LEFT")
    nowBar:SetScript("OnClick", function()
        if inGarrison then print("|cff66ccffJukebox:|r inside a garrison the jukebox only works through the Jukebox NPC."); return end
        if not frame then Build() end
        mode = "personal"; if not curArea then curArea = 1 end
        Refresh(); frame:Show()
    end)
    nowBar:Hide()
end
BuildBar()

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
    PlayLocal({ path = path, name = Pretty(name), dur = dur }, "garrison"); if frame then Refresh() end
end)
AcoreLib.On("jukebox", "stop", function() Stop(); if frame then Refresh() end end)

SLASH_WOTLKJUKEBOX1 = "/jukebox"
SlashCmdList["WOTLKJUKEBOX"] = function()
    if inGarrison then
        print("|cff66ccffJukebox:|r " .. (playing and ("now playing: " .. playing.name) or "nothing is playing") .. ". Inside a garrison the jukebox is controlled at the Jukebox NPC.")
        return
    end
    if frame and frame:IsShown() then frame:Hide() else Open("personal") end
end
