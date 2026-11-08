-- Offline check of the Jukebox addon logic with a fake WoW UI. Run in the build box: lua5.1 tools/test_jukebox.lua
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

local function btn(text) for _, f in ipairs(frames) do local t, sc = rawget(f, "text"), rawget(f, "scripts"); if rawget(f, "kind") == "Button" and type(t) == "string" and t:find(text, 1, true) and sc and sc.OnClick then return f end end end
local function click(text) local f = btn(text); assert(f, "no button: " .. text); rawget(f, "scripts").OnClick(f) end
local function disabled(text) local f = btn(text); assert(f, "no button: " .. text); return rawget(f, "disabled") == true end
local function tick(dt) for _, f in ipairs(frames) do local sc = rawget(f, "scripts"); if rawget(f, "kind") == "Frame" and sc and sc.OnUpdate then sc.OnUpdate(f, dt) end end end
local function areaOf(p) return p:match("Music\\(%a)\\") end
local function rowFor(path) for _, f in ipairs(frames) do local tr = rawget(f, "tr"); if tr and tr.path == path and rawget(f, "shown") then return f end end end
local function selectTrack(path) local r = rowFor(path); assert(r, "row not shown: " .. path); rawget(r, "scripts").OnClick(r) end
local function last() return played[#played] end
local function selectArea(i) for _, f in ipairs(frames) do if rawget(f, "target") == i and rawget(f, "shown") then rawget(f, "scripts").OnClick(f); return end end error("no area row " .. i) end

SlashCmdList["WOTLKJUKEBOX"]()                     -- opens the window
check(btn("Mode: Autoplay"), "Autoplay is the default mode")
check(btn("Library") and btn("Favorites"), "Library and Favorites tabs exist")
check(btn("Play") and not btn("Stop"), "Play and Stop are one button: shows Play when nothing plays")
check(disabled("Play"), "Play is greyed out until a song is selected")
check(disabled("Add to Favorites"), "Add to Favorites is greyed out with nothing selected or playing")

-- selecting a song enables Play and Add to Favorites; Play turns into Stop
selectTrack("Sound\\Music\\A\\a1.mp3")
check(not disabled("Play") and not disabled("Add to Favorites"), "selecting a song enables Play and Add to Favorites")
click("Play")
check(last() == "Sound\\Music\\A\\a1.mp3" and btn("Stop"), "Play starts the selected song and the button becomes Stop")

-- Next / Prev per mode
click("Next >"); check(last() == "Sound\\Music\\A\\a2.mp3", "Autoplay: Next goes to the next song in the list")
click("< Prev"); check(last() == "Sound\\Music\\A\\a1.mp3", "Autoplay: Prev goes to the previous song")
click("< Prev"); check(last() == "Sound\\Music\\A\\a3.mp3", "Prev on the first song wraps to the last")
click("Next >"); check(last() == "Sound\\Music\\A\\a1.mp3", "Next on the last song wraps to the first")
click("Mode:"); check(btn("Mode: Repeat"), "the mode button cycles to Repeat")
played = {}; click("Next >"); check(#played == 1 and last() == "Sound\\Music\\A\\a1.mp3", "Repeat: Next just starts the song over")
played = {}; click("< Prev"); check(#played == 1 and last() == "Sound\\Music\\A\\a1.mp3", "Repeat: Prev just starts the song over")
played = {}; tick(11.5); check(#played == 1 and last() == "Sound\\Music\\A\\a1.mp3", "Repeat: a finished song plays again")
click("Mode:"); check(btn("Mode: Off"), "the mode button cycles to Off")
played = {}; click("Next >"); check(last() == "Sound\\Music\\A\\a2.mp3", "Off: Next still goes to the next song in the list")
played = {}; stops = 0; tick(11.5)
check(#played == 0 and stops >= 1 and btn("Play"), "Off: nothing else plays after the song, button back to Play")
click("Mode:"); check(btn("Mode: Autoplay"), "the mode button cycles back to Autoplay")

-- autoplay: a finished song is followed by the next one in the list, and the list loops
selectTrack("Sound\\Music\\A\\a3.mp3"); click("Play"); played = {}; tick(11.5)
check(last() == "Sound\\Music\\A\\a1.mp3", "Autoplay: after the last song the list loops back to the first")

-- Shuffle: random songs from the selected area only, mode button greyed, Stop turns it off
for i = 1, 15 do
    played = {}; click("Shuffle:")
    check(#played == 1 and areaOf(played[1]) == "A", "Shuffle starts a random song from the selected area")
    check(disabled("Mode:"), "the mode button is greyed out while Shuffle is on")
    click("Stop")
    check(not disabled("Mode:") and btn("Shuffle: Off"), "Stop turns Shuffle off and the mode button works again")
end
-- Play Random Songs: whole catalog
local seen = {}
for i = 1, 60 do played = {}; click("Play Random Songs"); seen[areaOf(last())] = true; click("Stop") end
check(seen.A and seen.B, "Play Random Songs picks songs from every area")
click("Play Random Songs")
check(btn("Play Random Songs: On") and disabled("Mode:") and btn("Stop"), "Play Random Songs On greys the mode button and shows Stop")
played = {}; tick(11.5); check(#played == 1, "while random is on a finished song is followed by another random one")
local first = last(); click("Next >"); local second = last(); played = {}; click("< Prev")
check(last() == first, "random: Prev goes back to the song played before")
click("Play Random Songs"); check(btn("Play Random Songs: Off") and not disabled("Mode:"), "Play Random Songs toggles off")
click("Stop")

-- zoning: the song is started again from the beginning
selectArea(2); selectTrack("Sound\\Music\\B\\b1.mp3"); click("Play"); played = {}
for _, f in ipairs(frames) do local sc = rawget(f, "scripts"); if sc and sc.OnEvent and rawget(f, "kind") == "Frame" then sc.OnEvent(f, "ZONE_CHANGED_NEW_AREA") end end
tick(1); check(#played == 0, "zone fix waits a moment")
tick(1.5); check(#played == 1 and last() == "Sound\\Music\\B\\b1.mp3", "after zoning the same song is started again")
click("Stop")

-- favorites: add (Library) is greyed once it is a favorite, remove (Favorites tab)
selectTrack("Sound\\Music\\B\\b2.mp3")
click("Add to Favorites"); check(WotlkJukeboxDB.favs["Sound\\Music\\B\\b2.mp3"], "Add to Favorites saves the favorite")
check(disabled("Add to Favorites"), "Add to Favorites is greyed out for a song that is already a favorite")
click("Favorites")
check(btn("Remove Favorite") and not disabled("Remove Favorite"), "Favorites tab: Remove Favorite is available for a favorite")
for i = 1, 10 do played = {}; click("Shuffle:"); check(last() == "Sound\\Music\\B\\b2.mp3", "Shuffle in the Favorites tab plays favorites only"); click("Stop") end
click("Remove Favorite"); check(WotlkJukeboxDB.favs["Sound\\Music\\B\\b2.mp3"] == nil, "Remove Favorite removes it")

-- a song started by the garrison jukebox is shown (even with the window closed: no error, the bar is used)
click("Library")
for _, f in ipairs(frames) do if rawget(f, "name") == "WotlkJukeboxFrame" then f:Hide() end end
handlers["jukebox|play"]("Sound\\Music\\A\\a2.mp3")
local bar; for _, f in ipairs(frames) do if rawget(f, "name") == "WotlkJukeboxNowBar" then bar = f end end
check(bar and bar:IsShown(), "the Now playing bar shows what the garrison jukebox plays")
handlers["jukebox|stop"]()
check(not bar:IsShown(), "the bar hides when the music stops")
print(string.format("%d checks, %d failed", checks, fails)); os.exit(fails == 0 and 0 or 1)
