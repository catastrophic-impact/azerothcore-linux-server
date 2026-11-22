-- Offline check of the Jukebox addon logic (library, random, playlists, default-less personal mode, zone fix, garrison now-playing bar) with a fake WoW UI.
-- Run: luajit tools/test_jukebox.lua   (or lua5.1)
local checks, fails = 0, 0
local function check(c, w) checks = checks + 1; if not c then fails = fails + 1; print("FAIL: " .. w) end end

local frames, played, stops, sent = {}, {}, 0, {}
local Obj = {}
Obj.__index = function(t, k)
    if Obj[k] then return Obj[k] end
    return function(self, ...) return self end    -- every unknown method (SetPoint, SetSize, ...) is a no-op returning self
end
function Obj:SetText(s) rawset(self, "text", s) end
function Obj:GetText() return rawget(self, "text") end
function Obj:SetScript(n, f) local sc = rawget(self, "scripts"); if not sc then sc = {}; rawset(self, "scripts", sc) end; sc[n] = f end
function Obj:Show() self.shown = true; local sc = rawget(self, "scripts"); if sc and sc.OnShow then sc.OnShow(self) end end
function Obj:Hide() self.shown = false; local sc = rawget(self, "scripts"); if sc and sc.OnHide then sc.OnHide(self) end end
function Obj:IsShown() return rawget(self, "shown") == true end
function Obj:Enable() self.disabled = false end
function Obj:Disable() self.disabled = true end
function Obj:SetValue(v) rawset(self, "value", v) end
function Obj:CreateFontString() local o = setmetatable({}, Obj); return o end
function Obj:CreateTexture() return setmetatable({}, Obj) end
function CreateFrame(kind, name, parent) local o = setmetatable({ kind = kind, name = name }, Obj); frames[#frames + 1] = o; return o end
UIParent = setmetatable({}, Obj); UISpecialFrames = {}; tinsert = table.insert
SlashCmdList = {}
StaticPopupDialogs = {}; YES, NO = "Yes", "No"; popups = {}   -- playlist dialogs: the test records which popup the addon asked for
function StaticPopup_Show(which, text, _, data) popups[#popups + 1] = { which = which, text = text, data = data } end
function PlayMusic(p) played[#played + 1] = p end
function StopMusic() stops = stops + 1 end
local handlers = {}
AcoreLib = { Announce = function() end, Solid = function() end, On = function(m, a, f) handlers[m .. "|" .. a] = f end,
             Send = function(m, a, p) sent[#sent + 1] = m .. "|" .. a .. "|" .. tostring(p) end }
WotlkJukeboxTracks = {
    { group = "Cities", area = "A", dir = "Sound\\Music\\A", tracks = { { "a1.mp3", 10 }, { "a2.mp3", 10 }, { "a3.mp3", 10 } } },
    { group = "Cities", area = "B", dir = "Sound\\Music\\B", tracks = { { "b1.mp3", 10 }, { "b2.mp3", 10 } } },
}
dofile("addons/wotlk_jukebox/Jukebox.lua")

-- the fake UI: EasyMenu records the menu so a test can pick an entry; popups are recorded by StaticPopup_Show above
local lastMenu
function EasyMenu(menu) lastMenu = menu end
local function menuPick(text) for _, m in ipairs(lastMenu or {}) do if m.text and m.text:find(text, 1, true) then m.func(); return true end end error("no menu entry " .. text) end

-- buttons are matched by their EXACT text ("Play" must not match "Play Random Songs: Off")
local function btn(text) for _, f in ipairs(frames) do local t, sc = rawget(f, "text"), rawget(f, "scripts"); if rawget(f, "kind") == "Button" and t == text and sc and sc.OnClick then return f end end end
local function click(text) local f = btn(text); assert(f, "no button: " .. text); rawget(f, "scripts").OnClick(f) end
local function disabled(text) local f = btn(text); assert(f, "no button: " .. text); return rawget(f, "disabled") == true end
local function tick(dt) for _, f in ipairs(frames) do local sc = rawget(f, "scripts"); if rawget(f, "kind") == "Frame" and sc and sc.OnUpdate then sc.OnUpdate(f, dt) end end end
local function areaOf(p) return p:match("Music\\(%a)\\") end
local function rowFor(path) for _, f in ipairs(frames) do local tr = rawget(f, "tr"); if tr and tr.path == path and rawget(f, "shown") then return f end end end
local function selectTrack(path) local r = rowFor(path); assert(r, "row not shown: " .. path); rawget(r, "scripts").OnClick(r) end
local function dblclick(path) local r = rowFor(path); assert(r, "row not shown: " .. path); rawget(r, "scripts").OnDoubleClick(r) end
local function selectArea(i) for _, f in ipairs(frames) do if rawget(f, "target") == i and rawget(f, "shown") then rawget(f, "scripts").OnClick(f); return end end error("no area row " .. i) end
local function last() return played[#played] end
local function popup() return popups[#popups] end
local A1, A2, A3, B1, B2 = "Sound\\Music\\A\\a1.mp3", "Sound\\Music\\A\\a2.mp3", "Sound\\Music\\A\\a3.mp3", "Sound\\Music\\B\\b1.mp3", "Sound\\Music\\B\\b2.mp3"

WotlkJukeboxDB = { favs = { [B2] = true } }          -- an OLD favorites table: it must become a playlist called "Favorites" once
SlashCmdList["WOTLKJUKEBOX"]()                     -- opens the window
check(btn("Library") and btn("Playlists"), "Library and Playlists tabs exist")
check(btn("Play") and not btn("Stop"), "Play and Stop are one button: shows Play when nothing plays")
check(disabled("Play"), "Play is greyed out until a song is selected")
check(disabled("Next >"), "Next is greyed out when no random / playlist run is going")
check(btn("Play Random Songs: Off"), "random starts off")
check(disabled("Add to Playlist..."), "Add to Playlist is greyed out with nothing selected or playing")
check(WotlkJukeboxDB.favs == nil and WotlkJukeboxDB.lists[1] and WotlkJukeboxDB.lists[1].name == "Favorites" and WotlkJukeboxDB.lists[1].tracks[1] == B2, "old favorites became the playlist 'Favorites'")

-- a picked song: Play plays it ONCE, then silence
selectTrack(A1)
check(not disabled("Play") and not disabled("Add to Playlist..."), "selecting a song enables Play and Add to Playlist")
click("Play")
check(last() == A1 and btn("Stop"), "Play starts the selected song and the button becomes Stop")
played = {}; stops = 0; tick(11)
check(#played == 0 and stops >= 1 and btn("Play"), "a hand-picked song plays once: nothing follows, button back to Play")
dblclick(A2); check(last() == A2, "double-clicking a song plays it")
click("Stop"); check(btn("Play"), "Stop stops it")

-- Play Random Songs: whole catalog, Next skips, a finished song is followed by another, Stop ends it
local seen = {}
for i = 1, 60 do played = {}; click("Play Random Songs: Off"); seen[areaOf(last())] = true; click("Stop") end
check(seen.A and seen.B, "Play Random Songs picks songs from every area")
click("Play Random Songs: Off")
check(btn("Play Random Songs: On") and btn("Stop") and not disabled("Next >"), "random On shows Stop and enables Next")
local first = last(); played = {}; tick(11); check(#played == 1, "while random is on a finished song is followed by another random one")
played = {}; click("Next >"); check(#played == 1 and last() ~= nil, "Next in random plays another song")
stops = 0; click("Play Random Songs: On"); check(btn("Play Random Songs: Off") and stops >= 1 and btn("Play"), "Play Random Songs toggles off and the music stops")

-- playlists: create from the menu, add songs, play (loops), Next, remove, duplicate name, rename, delete
selectTrack(A1); click("Add to Playlist...")
menuPick("New playlist"); check(popup() and popup().which == "WOTLKJUKEBOX_NAME", "'New playlist...' asks for a name")
popup().data.fn("Mine")
check(WotlkJukeboxDB.lists[2] and WotlkJukeboxDB.lists[2].name == "Mine" and WotlkJukeboxDB.lists[2].tracks[1] == A1, "the new playlist holds the song it was created from")
selectTrack(A2); click("Add to Playlist..."); menuPick("Mine")
check(#WotlkJukeboxDB.lists[2].tracks == 2, "a song is added to an existing playlist")
selectTrack(A2); click("Add to Playlist..."); menuPick("Mine"); check(#WotlkJukeboxDB.lists[2].tracks == 2, "the same song is not added twice")
click("New Playlist"); popup().data.fn("mine"); check(#WotlkJukeboxDB.lists == 2, "a duplicate playlist name (any case) is refused")
click("New Playlist"); popup().data.fn("   "); check(#WotlkJukeboxDB.lists == 2, "an empty name is refused")
click("Playlists")
check(btn("Play Playlist") and not disabled("Play Playlist") and btn("Rename Playlist") and btn("Delete Playlist"), "Playlists tab shows the playlist buttons")
played = {}; click("Play Playlist"); check(last() == A1, "Play Playlist starts the playlist at its first song")
check(btn("Restart Playlist"), "the playing playlist's button becomes Restart Playlist")
played = {}; tick(11); check(last() == A2, "a finished song is followed by the next one of the playlist")
played = {}; tick(11); check(last() == A1, "the playlist loops back to the first song")
played = {}; click("Next >"); check(last() == A2, "Next skips to the next playlist song")
click("Stop")
selectTrack(A2); click("Remove from Playlist"); check(#WotlkJukeboxDB.lists[2].tracks == 1, "Remove from Playlist removes the selected song")
click("Rename Playlist"); check(popup().which == "WOTLKJUKEBOX_NAME", "Rename asks for a name"); popup().data.fn("Mine2")
check(WotlkJukeboxDB.lists[2].name == "Mine2", "Rename changes the playlist name")
click("Delete Playlist"); check(popup().which == "WOTLKJUKEBOX_DELETE", "Delete asks for confirmation"); popup().data()
check(#WotlkJukeboxDB.lists == 1 and WotlkJukeboxDB.lists[1].name == "Favorites", "Delete removes only that playlist")
click("Library")

-- zoning: the same song is started again from the beginning
selectArea(2); selectTrack(B1); click("Play"); played = {}
for _, f in ipairs(frames) do local sc = rawget(f, "scripts"); if sc and sc.OnEvent and rawget(f, "kind") == "Frame" then sc.OnEvent(f, "ZONE_CHANGED_NEW_AREA") end end
tick(1); check(#played == 0, "zone fix waits a moment")
tick(1.5); check(#played == 1 and last() == B1, "after zoning the same song is started again")
click("Stop")

-- a song started by the garrison jukebox is shown (even with the window closed: no error, the bar is used)
for _, f in ipairs(frames) do if rawget(f, "name") == "WotlkJukeboxFrame" then f:Hide() end end
handlers["jukebox|play"](A2)
local bar; for _, f in ipairs(frames) do if rawget(f, "name") == "WotlkJukeboxNowBar" then bar = f end end
check(bar and bar:IsShown(), "the Now playing bar shows what the garrison jukebox plays")
handlers["jukebox|stop"]()
check(not bar:IsShown(), "the bar hides when the music stops")
print(string.format("%d checks, %d failed", checks, fails)); os.exit(fails == 0 and 0 or 1)
