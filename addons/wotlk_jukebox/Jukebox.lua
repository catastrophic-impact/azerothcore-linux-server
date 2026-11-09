-- Jukebox: browse the game's music by group/area, play, Play Random Songs on/off, playlists (own tab: named lists you fill yourself). A song picked by hand plays once.
-- Garrison OWNER only: a Default (song or playlist, saved here) that plays by itself in your own garrison whenever nothing else is playing.
-- Personal mode (/jukebox): plays only for you. Garrison mode (opened from the Jukebox NPC inside a garrison): your pick is sent to the
-- server, which plays it for everyone inside that garrison (server side: scripts/garrison_jukebox.lua, optional; the addon works without it). Track data: Tracks.lua (generated).
-- A small "Now playing" bar shows whatever the jukebox is playing for you (also when someone else controls the garrison jukebox) while the window is closed.
-- Note: the 3.3.5 client has no call that reports the game's own zone music, so only music started through the jukebox can be shown.
AcoreLib.Announce("jukebox")   -- tells the server this client has the addon (the garrison Jukebox NPC needs it)
local T = WotlkJukeboxTracks
local ROW_H, ROWS = 22, 15
local LIB_W = 310                    -- track list width
local title
local frame, areaScroll, areaContent, trackScroll, trackContent
local areaRows, trackRows = {}, {}
local nowText, srcText, timeText, bar, modeText, rndBtn, favBtn, playBtn, nextBtn, tabLib, tabPl, plBtn, newBtn, renBtn, delBtn, defSongBtn, defListBtn, defModeBtn, defText, hintText, emptyText
local nowBar, nowBarText
local mode = "personal"                -- "personal" | "garrison" (window mode)
local inGarrison, ctrl = false, false    -- server says we are inside a garrison; we are this garrison's music controller
local isOwner = false                  -- ...and it is our own garrison
local defRun = false                   -- we are playing our default (plist.src == "default")
local defSuppressed = false            -- a guest pressed Stop: the default stays quiet for this visit
local tab = "lib"                       -- "lib" | "pl" (playlists)
local curArea                           -- index into T (Library tab)
local curList                           -- index into DB().lists (Playlists tab)
local plist                             -- playlist being played through: { tracks = {...}, i = index }; it loops until something else is picked
local selected                          -- selected track {path,name,dur}
local playing, elapsed = nil, 0
local rnd = false                    -- Play Random Songs is on: a new random song starts whenever one ends
local advanceWait = 0                -- seconds to wait for the server's answer after asking for the next song (stops repeated requests)
local zoneFix = 0                    -- seconds until the song is restarted after a zone change (0 = idle)
local playSource = "personal"           -- "personal" | "garrison" (who started what is playing)

local dbg = false   -- /jukebox debug: prints every play / stop decision with a timestamp
local function D(...) if dbg then print(string.format("|cff888888[jb %.2f]|r", GetTime()), ...) end end

local function DB()
    WotlkJukeboxDB = WotlkJukeboxDB or {}
    if WotlkJukeboxDB.defMode == nil then WotlkJukeboxDB.defMode = "off" end   -- default music: "song" | "list" | "off" (defSong = path, defRef = { k = "pl", name = ... } or { k = "area", dir = ... })
    WotlkJukeboxDB.lists = WotlkJukeboxDB.lists or {}   -- playlists: { name = "...", tracks = { path, ... } }
    if WotlkJukeboxDB.favs then                          -- old favorites become a playlist called "Favorites" (once)
        local paths = {}
        for _, area in ipairs(T) do for _, t in ipairs(area.tracks) do
            local pth = area.dir .. "\\" .. t[1]
            if WotlkJukeboxDB.favs[pth] then paths[#paths + 1] = pth end
        end end
        if #paths > 0 then table.insert(WotlkJukeboxDB.lists, 1, { name = "Favorites", tracks = paths }) end
        WotlkJukeboxDB.favs = nil
    end
    return WotlkJukeboxDB
end
local function Fmt(s) s = math.floor(s + 0.5); return ("%d:%02d"):format(math.floor(s / 60), s % 60) end
local function Pretty(f) return (f:gsub("%.mp3$", ""):gsub("%.MP3$", "")) end

-- the list being viewed: the playlist in the Playlists tab, else the area being viewed
local function ListKey() return tab == "pl" and "pl" or curArea end

local byPath
local function ByPath()   -- every catalog song by its path
    if byPath then return byPath end
    byPath = {}
    for _, area in ipairs(T) do for _, t in ipairs(area.tracks) do
        local pth = area.dir .. "\\" .. t[1]
        byPath[pth] = { path = pth, name = Pretty(t[1]), dur = t[2], area = area.area }
    end end
    return byPath
end

local function TracksOf(a)
    local out = {}
    if a == "pl" then
        local L = DB().lists[curList or 0]
        if L then for _, pth in ipairs(L.tracks) do
            local t = ByPath()[pth]
            if t then out[#out + 1] = { path = t.path, name = t.name .. "  |cff999999(" .. t.area .. ")|r", dur = t.dur } end
        end end
    elseif a and T[a] then
        for _, t in ipairs(T[a].tracks) do out[#out + 1] = { path = T[a].dir .. "\\" .. t[1], name = Pretty(t[1]), dur = t[2] } end
    end
    return out
end

local allCache
local function AllTracks()
    if allCache then return allCache end
    local all = {}
    for i = 1, #T do for _, t in ipairs(TracksOf(i)) do all[#all + 1] = t end end
    allCache = all
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
    playing = nil; elapsed = 0; advanceWait = 0
    StopMusic()
    UpdateNow()
end

local function PlayLocal(tr, source)
    playing, elapsed, playSource, advanceWait = tr, 0, source or "personal", 0
    D("PlayMusic", tr.name, source or "personal")
    pcall(PlayMusic, tr.path)   -- a missing client file is silent in 3.3.5, but never let a bad path raise an error
    UpdateNow()
end

local function Net() return mode == "garrison" or defRun end   -- the server plays it for everyone (we run the music for the garrison)

local function SendOrPlay(tr)
    D("send play", tr.name, "net=" .. tostring(Net()))
    if Net() then AcoreLib.Send("jukebox", "play", tr.path)   -- the server echoes it back to everyone, us included
    else PlayLocal(tr, "personal") end
end

-- stop the music for good (for everyone in garrison mode). why: "end" = it ran out / random was switched off (the default may take over), "" = Stop pressed
local function Silence(why)
    if Net() then AcoreLib.Send("jukebox", "stop", why or "") else Stop() end
end

-- a song picked by hand (Play / double-click): ends random mode, plays once
local function PlaySelected()
    if not selected then return end
    rnd, plist = false, nil
    SendOrPlay(selected)
    if Refresh then Refresh() end
end

-- Stop: ends random mode and stops the music
local function StopAll()
    rnd, plist = false, nil
    Silence("")
    if inGarrison and isOwner then DB().defMode = "off"; defRun = false end   -- the owner's Stop switches the default off
    if Refresh then Refresh() end
end

local function RandomTrack()
    local all = AllTracks()
    if #all == 0 then return end
    local k = math.random(#all)
    if #all > 1 and playing and all[k].path == playing.path then k = k % #all + 1 end
    return all[k]
end

-- another random song from the whole catalog
local function NextRandom()
    local tr = RandomTrack(); if not tr then return end
    advanceWait = 4
    selected = tr
    SendOrPlay(tr)
    if Refresh then Refresh() end
end

-- play a playlist through (and round again) until something else is picked
local function PlayPlaylist(tracks, start, src)
    if #tracks == 0 then return end
    rnd = false
    plist = { tracks = tracks, i = start or 1, src = src }   -- src = the playlist (DB().lists entry) being played
    advanceWait = 4
    SendOrPlay(tracks[plist.i])
    if Refresh then Refresh() end
end

local function NextInPlaylist()
    if not plist or #plist.tracks == 0 then Silence("end"); return end
    plist.i = plist.i % #plist.tracks + 1
    advanceWait = 4
    SendOrPlay(plist.tracks[plist.i])
    if Refresh then Refresh() end
end

local function NextSong() if rnd then NextRandom() elseif plist then NextInPlaylist() end end

local function RandomOn() plist = nil; rnd = true; NextRandom() end
local function RandomOff() rnd = false; Silence("end"); if Refresh then Refresh() end end   -- the song stops (the game fades it out)

local barClock = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
    if not playing then return end
    elapsed = elapsed + dt
    if advanceWait > 0 then advanceWait = advanceWait - dt end
    if zoneFix > 0 then   -- the game's zone music cut the song: start it again from the beginning (the client cannot resume mid-song)
        zoneFix = zoneFix - dt
        if zoneFix <= 0 then zoneFix = 0; elapsed = 0; D("zoneFix replay", playing.name); pcall(PlayMusic, playing.path) end
    end
    if bar then bar:SetValue(math.min(elapsed, playing.dur)) end
    if timeText then timeText:SetText(Fmt(math.min(elapsed, playing.dur)) .. " / " .. Fmt(playing.dur)) end
    barClock = barClock + dt
    if barClock > 0.5 then barClock = 0; if nowBar and nowBar:IsShown() then UpdateNow() end end
    if elapsed >= playing.dur and advanceWait <= 0 then   -- the client loops a finished file on its own, so act right at the end (a 1 s grace replayed the song's start)
        if inGarrison and not (ctrl or defRun) then Stop(); return end   -- listeners just wait for the controller's next song
        D("song end:", playing.name, rnd and "random" or plist and "playlist" or "silence", "elapsed=" .. math.floor(elapsed), "dur=" .. playing.dur)
        advanceWait = 4                                              -- ask once, then wait for the server's answer (asking every frame skipped songs)
        if rnd then NextRandom() elseif plist then NextInPlaylist() else Silence("end") end   -- random / playlist: the next song; picked by hand: it was played once, done
    end
end)

-- ---- the owner's default music ----
local function DefaultTracks()
    local d = DB()
    if d.defMode == "song" then
        local t = d.defSong and ByPath()[d.defSong]
        return t and { t } or {}
    elseif d.defMode == "list" and d.defRef then
        if d.defRef.k == "pl" then
            for _, L in ipairs(d.lists) do
                if L.name == d.defRef.name then
                    local out = {}
                    for _, pth in ipairs(L.tracks) do local t = ByPath()[pth]; if t then out[#out + 1] = t end end
                    return out
                end
            end
        else
            for _, a in ipairs(T) do
                if a.dir == d.defRef.dir then
                    local out = {}
                    for _, t in ipairs(a.tracks) do out[#out + 1] = ByPath()[a.dir .. "\\" .. t[1]] end
                    return out
                end
            end
        end
    end
    return {}
end

local function StartDefault()
    if not (inGarrison and isOwner) or defSuppressed or playing or DB().defMode == "off" then return end
    local tracks = DefaultTracks()
    if #tracks == 0 then return end
    D("StartDefault", #tracks, "tracks")
    defRun, rnd = true, false
    plist = { tracks = tracks, i = 1, src = "default" }              -- a default song is a playlist of one: it loops
    advanceWait = 4
    AcoreLib.Send("jukebox", "default", tracks[1].path)             -- claims the garrison jukebox if nothing else is playing
end

-- the default stops being ours (somebody else took over, or it was switched off)
local function DropDefault()
    defRun = false
    if plist and plist.src == "default" then plist = nil end
end

-- the owner changed the default: a default that is playing right now is stopped, the idle check then starts the new one
local function ReapplyDefault()
    defSuppressed = false
    if defRun then Silence("end"); DropDefault() end
end

local idleFor, dTick = 0, 0
local dflt = CreateFrame("Frame")
dflt:SetScript("OnUpdate", function(_, dt)
    if not (inGarrison and isOwner) then return end
    dTick = dTick + dt; if dTick < 1 then return end
    dTick = 0
    if playing or defSuppressed or DB().defMode == "off" then idleFor = 0; return end
    idleFor = idleFor + 1
    if idleFor >= 3 then idleFor = 0; StartDefault() end             -- nothing has played for 3 s: the default takes over
end)

-- zoning / entering a new area makes the game start its own music: bring the jukebox song back
local zev = CreateFrame("Frame")
zev:RegisterEvent("PLAYER_ENTERING_WORLD"); zev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
local askIn = 0
local askFrame = CreateFrame("Frame")
askFrame:SetScript("OnUpdate", function(_, dt)
    if askIn <= 0 then return end
    askIn = askIn - dt
    if askIn <= 0 then AcoreLib.Send("jukebox", "state", "") end     -- after a /reload or loading screen: ask the server whether we are inside a garrison
end)
zev:SetScript("OnEvent", function(_, ev)
    D("zone event", ev, playing and playing.name or "-")
    if ev == "PLAYER_ENTERING_WORLD" then askIn = 3 end
    if not playing then return end
    if rnd and not inGarrison then NextRandom() else zoneFix = 2 end   -- random (personal): a new area gets a new random song; else bring the same song back
end)

local function RowButton(parent, w, i, fontObj)
    local r = CreateFrame("Button", nil, parent); r:SetSize(w, ROW_H - 2); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetTexture(1, 0.82, 0, 0.25); r.sel:Hide()
    r.text = r:CreateFontString(nil, "OVERLAY", fontObj); r.text:SetPoint("LEFT", 4, 0); r.text:SetJustifyH("LEFT")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    return r
end


-- which buttons are usable right now
UpdateButtons = function()
    if not playBtn then return end
    playBtn:SetText(playing and "Stop" or "Play")
    if playing or selected then playBtn:Enable() else playBtn:Disable() end
    rndBtn:SetText("Play Random Songs: " .. (rnd and "On" or "Off"))
    if rnd or plist then nextBtn:Enable() else nextBtn:Disable() end   -- Next = the next song of the random / playlist run
    local L = DB().lists[curList or 0]
    if tab == "lib" then
        favBtn:Show(); plBtn:Hide(); newBtn:Hide(); renBtn:Hide(); delBtn:Hide()
        favBtn:SetText("Add to Playlist...")
        if selected or playing then favBtn:Enable() else favBtn:Disable() end
    else
        favBtn:Show(); plBtn:Show(); newBtn:Show(); renBtn:Show(); delBtn:Show()
        favBtn:SetText("Remove from Playlist")
        local inList = false
        if L and selected then for _, pth in ipairs(L.tracks) do if pth == selected.path then inList = true end end end
        if inList then favBtn:Enable() else favBtn:Disable() end
        plBtn:SetText((plist and L and plist.src == L) and "Restart Playlist" or "Play Playlist")   -- Restart only for the playlist that is playing
        if L and #L.tracks > 0 then plBtn:Enable() else plBtn:Disable() end
        if L then renBtn:Enable(); delBtn:Enable() else renBtn:Disable(); delBtn:Disable() end
    end
    -- default music: only the owner, in their own garrison
    if mode == "garrison" and inGarrison and isOwner then
        local d = DB()
        defSongBtn:Show(); defListBtn:Show(); defModeBtn:Show(); defText:Show()
        if selected then defSongBtn:Enable() else defSongBtn:Disable() end
        if (tab == "pl" and L and #L.tracks > 0) or (tab == "lib" and curArea) then defListBtn:Enable() else defListBtn:Disable() end
        defModeBtn:SetText("Default: " .. (d.defMode == "song" and "Song" or d.defMode == "list" and "Playlist" or "Off"))
        local song = d.defSong and ByPath()[d.defSong]
        local lname = d.defRef and (d.defRef.k == "pl" and d.defRef.name or (function() for _, a in ipairs(T) do if a.dir == d.defRef.dir then return a.area end end end)())
        defText:SetText("|cff999999Song: |r" .. (song and song.name or "none") .. "   |cff999999Playlist: |r" .. (lname or "none") .. (defSuppressed and "   |cffff8040(quiet this visit)|r" or ""))
    else
        defSongBtn:Hide(); defListBtn:Hide(); defModeBtn:Hide(); defText:Hide()
    end
end

Refresh = function()
    if not frame then return end
    modeText:SetText(mode == "garrison" and "|cff66ccffGARRISON MODE|r  -  plays for everyone in this garrison" or "Personal jukebox: plays only for you")
    title:SetText(mode == "garrison" and "Jukebox - Garrison Mode" or "Jukebox")
    -- tabs
    if tab == "lib" then tabLib:Disable(); tabPl:Enable() else tabLib:Enable(); tabPl:Disable() end
    if tab == "pl" then
        local n = #DB().lists
        if n == 0 then curList = nil elseif not curList or curList > n then curList = 1 end
    end
    trackScroll:ClearAllPoints(); areaScroll:Show(); trackScroll:SetPoint("TOPLEFT", 230, -96)
    local w = LIB_W
    trackScroll:SetSize(w, ROW_H * ROWS); trackContent:SetWidth(w)

    -- left list: the areas (Library tab, with group headers) or your playlists (Playlists tab)
    local items = {}
    if tab == "lib" then
        local lastGroup
        for i, a in ipairs(T) do
            if a.group ~= lastGroup then items[#items + 1] = { header = a.group }; lastGroup = a.group end
            items[#items + 1] = { idx = i, text = a.area }
        end
    else
        for i, L in ipairs(DB().lists) do items[#items + 1] = { idx = i, text = L.name .. " |cff999999(" .. #L.tracks .. ")|r" } end
    end
    areaContent:SetHeight(math.max(#items * ROW_H, 1))
    local cur = tab == "lib" and curArea or curList
    for i, it in ipairs(items) do
        local r = areaRows[i]
        if not r then
            r = RowButton(areaContent, 170, i, "GameFontNormal")
            r:SetScript("OnClick", function(self)
                if not self.target then return end
                if tab == "lib" then curArea = self.target else curList = self.target end
                selected = nil; Refresh()
            end)
            areaRows[i] = r
        end
        r.target = it.idx
        if it.header then
            r.target = nil; r.text:SetText("|cffffd100" .. it.header .. "|r"); r:EnableMouse(false); r:SetHighlightTexture(nil)
        else
            r:EnableMouse(true); r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r.text:SetText("   " .. it.text)
        end
        if r.target and r.target == cur then r.sel:Show() else r.sel:Hide() end
        r:Show()
    end
    for i = #items + 1, #areaRows do areaRows[i]:Hide() end

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
        local live = playing and playing.path == t.path and "|cff00ff00> |r" or ""
        r.text:SetText(live .. t.name); r.len:SetText(Fmt(t.dur))
        if selected and selected.path == t.path then r.sel:Show() else r.sel:Hide() end
        r:Show()
    end
    for i = #list + 1, #trackRows do trackRows[i]:Hide() end
    if tab == "pl" and #DB().lists == 0 then emptyText:SetText("No playlists yet.\nPress \"New Playlist\", then add songs from the Library tab.")
    elseif tab == "pl" and #list == 0 then emptyText:SetText("This playlist is empty.\nSelect a song in the Library tab and press \"Add to Playlist...\".")
    else emptyText:SetText("") end

    UpdateButtons()
    hintText:SetText(rnd and "Random is on: a new random song starts when one ends. Next skips to another. Picking a song or Stop turns it off." or (plist and "A playlist is playing: it loops until you pick something else. Next skips ahead." or "A song you pick plays once."))
    UpdateNow()
end

-- ---- playlists ----
StaticPopupDialogs["WOTLKJUKEBOX_NAME"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL, hasEditBox = 1, maxLetters = 30, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self)
        local eb = getglobal(self:GetName() .. "EditBox")
        eb:SetText(self.data and self.data.default or ""); eb:HighlightText(); eb:SetFocus()
    end,
    OnAccept = function(self)
        local name = getglobal(self:GetName() .. "EditBox"):GetText()
        if self.data and self.data.fn then self.data.fn(name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local dlg = self:GetParent()
        local name = self:GetText()
        dlg:Hide()
        if dlg.data and dlg.data.fn then dlg.data.fn(name) end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
StaticPopupDialogs["WOTLKJUKEBOX_DELETE"] = {
    text = "Delete the playlist \"%s\"?", button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self) if self.data then self.data() end end,
}

local function CleanName(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    for _, L in ipairs(DB().lists) do
        if L.name:lower() == name:lower() then print("|cff66ccffJukebox:|r you already have a playlist called \"" .. L.name .. "\"."); return nil end
    end
    return name
end

local function NewPlaylist(name, firstPath)
    name = CleanName(name); if not name then return end
    local L = { name = name, tracks = {} }
    if firstPath then L.tracks[1] = firstPath end
    table.insert(DB().lists, L)
    curList = #DB().lists
    if Refresh then Refresh() end
end

local function AddToPlaylist(i, path)
    local L = DB().lists[i]; if not L or not path then return end
    for _, pth in ipairs(L.tracks) do if pth == path then print("|cff66ccffJukebox:|r that song is already in \"" .. L.name .. "\"."); return end end
    L.tracks[#L.tracks + 1] = path
    if Refresh then Refresh() end
end

local menuFrame
local function AddMenu(anchor)
    local tg = selected or playing; if not tg then return end
    menuFrame = menuFrame or CreateFrame("Frame", "WotlkJukeboxMenu", UIParent, "UIDropDownMenuTemplate")
    local menu = { { text = "Add to playlist:", isTitle = true, notCheckable = 1 } }
    for i, L in ipairs(DB().lists) do
        menu[#menu + 1] = { text = L.name, notCheckable = 1, func = function() AddToPlaylist(i, tg.path) end }
    end
    menu[#menu + 1] = { text = "|cff00ff00New playlist...|r", notCheckable = 1, func = function()
        StaticPopup_Show("WOTLKJUKEBOX_NAME", "Name of the new playlist:", nil, { default = "", fn = function(name) NewPlaylist(name, tg.path) end })
    end }
    EasyMenu(menu, menuFrame, anchor or "cursor", 0, 0, "MENU")
end

local function RemoveFromPlaylist()
    local L = DB().lists[curList or 0]; if not L or not selected then return end
    for i, pth in ipairs(L.tracks) do if pth == selected.path then table.remove(L.tracks, i); break end end
    selected = nil
    if Refresh then Refresh() end
end

local function PlayCurrentPlaylist()
    local list = TracksOf("pl"); if #list == 0 then return end
    local start = 1
    if selected then for i, t in ipairs(list) do if t.path == selected.path then start = i end end end
    PlayPlaylist(list, start, DB().lists[curList or 0])
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
    tabPl = Btn("Playlists", 100, 128, -62, function() tab = "pl"; selected = nil; Refresh() end)

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

    playBtn = Btn("Play", 102, 590, -194, function() if playing then StopAll() else PlaySelected() end end)
    nextBtn = Btn("Next >", 102, 698, -194, function() NextSong() end)
    rndBtn = Btn("", 210, 590, -228, function() if rnd then RandomOff() else RandomOn() end end)
    favBtn = Btn("", 210, 590, -262, function() if tab == "lib" then AddMenu() else RemoveFromPlaylist() end end)
    plBtn = Btn("", 210, 590, -296, PlayCurrentPlaylist)
    newBtn = Btn("New Playlist", 210, 590, -330, function()
        StaticPopup_Show("WOTLKJUKEBOX_NAME", "Name of the new playlist:", nil, { default = "", fn = function(name) NewPlaylist(name) end })
    end)
    renBtn = Btn("Rename Playlist", 210, 590, -364, function()
        local L = DB().lists[curList or 0]; if not L then return end
        StaticPopup_Show("WOTLKJUKEBOX_NAME", "New name for \"" .. L.name .. "\":", nil, { default = L.name, fn = function(name)
            name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" and name:lower() ~= L.name:lower() then name = CleanName(name); if name then L.name = name end elseif name ~= "" then L.name = name end
            Refresh()
        end })
    end)
    delBtn = Btn("Delete Playlist", 210, 590, -398, function()
        local L = DB().lists[curList or 0]; if not L then return end
        StaticPopup_Show("WOTLKJUKEBOX_DELETE", L.name, nil, function()
            for i, X in ipairs(DB().lists) do if X == L then table.remove(DB().lists, i); break end end
            selected = nil; Refresh()
        end)
    end)
    defSongBtn = Btn("Set Default Song", 150, 230, -432, function()
        if not selected then return end
        local d = DB(); d.defSong = selected.path; d.defMode = "song"; ReapplyDefault(); Refresh()
    end)
    defListBtn = Btn("Set Default Playlist", 160, 386, -432, function()
        local d, L = DB(), DB().lists[curList or 0]
        if tab == "pl" and L then d.defRef = { k = "pl", name = L.name }
        elseif tab == "lib" and curArea and T[curArea] then d.defRef = { k = "area", dir = T[curArea].dir }
        else return end
        d.defMode = "list"; ReapplyDefault(); Refresh()
    end)
    defModeBtn = Btn("", 150, 590, -432, function()
        local d = DB(); d.defMode = d.defMode == "song" and "list" or d.defMode == "list" and "off" or "song"
        if d.defMode == "off" then ReapplyDefault(); defSuppressed = false else ReapplyDefault() end
        Refresh()
    end)
    defText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); defText:SetPoint("TOPLEFT", 230, -462); defText:SetWidth(560); defText:SetJustifyH("LEFT")
    hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hintText:SetPoint("TOPLEFT", 590, -468); hintText:SetWidth(210); hintText:SetJustifyH("LEFT")
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); note:SetPoint("BOTTOMLEFT", 26, 20); note:SetWidth(540); note:SetJustifyH("LEFT")
    note:SetText("Double-click a track to play it once.  Play Playlist loops a playlist.  Play Random Songs keeps picking random songs.  Owner: Default plays by itself when nothing else does.")
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
AcoreLib.On("jukebox", "garrison", function(p)   -- "1" entered / "o" entered your own / "0" left a garrison: personal and garrison music never mix
    if (p == "1" or p == "o") == inGarrison and (p == "o") == isOwner then return end   -- nothing changed (e.g. the answer to our own state request)
    inGarrison = p == "1" or p == "o"; isOwner = p == "o"; ctrl = false; rnd, plist = false, nil
    defRun, defSuppressed, idleFor = false, false, -2                -- a fresh visit: the default starts a few seconds after arriving
    Stop()
    if frame and frame:IsShown() then frame:Hide() end
    mode = "personal"
end)
AcoreLib.On("jukebox", "open", function() ctrl = true; Open("garrison") end)       -- we took control at the Jukebox NPC
AcoreLib.On("jukebox", "release", function() ctrl = false; rnd, plist = false, nil; defRun = false; if frame then Refresh() end end)   -- someone else took control
AcoreLib.On("jukebox", "play", function(path)
    D("recv play", path:match("([^\\]+)$") or path)
    local name = path:match("([^\\]+)$") or path
    local dur = 180
    for _, a in ipairs(T) do if path:sub(1, #a.dir) == a.dir then for _, t in ipairs(a.tracks) do if t[1] == name then dur = t[2] end end end end
    PlayLocal({ path = path, name = Pretty(name), dur = dur }, "garrison"); if frame then Refresh() end
end)
AcoreLib.On("jukebox", "stop", function(why)
    D("recv stop", "why=" .. tostring(why))
    Stop()
    if isOwner then
        if why == "owner" then DB().defMode = "off" elseif why == "" then defSuppressed = true end   -- Stop: the owner's switches the default off, a guest's keeps it quiet this visit
    end
    if defRun or (plist and plist.src == "default") then DropDefault() end
    if frame then Refresh() end
end)

SLASH_WOTLKJUKEBOX1 = "/jukebox"
SlashCmdList["WOTLKJUKEBOX"] = function(msg)
    if msg == "debug" then dbg = not dbg; print("|cff66ccffJukebox:|r debug " .. (dbg and "on" or "off")); return end
    if inGarrison then
        print("|cff66ccffJukebox:|r " .. (playing and ("now playing: " .. playing.name) or "nothing is playing") .. ". Inside a garrison the jukebox is controlled at the Jukebox NPC.")
        return
    end
    if frame and frame:IsShown() then frame:Hide() else Open("personal") end
end
