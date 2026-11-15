-- Headless test for addons/wotlk_pets/Pets.lua (filters, search, drag and drop team building).  Run from the project root:
--   flatpak-spawn --host sh -c "cd <proj> && luajit pet-battle/test_ui_pets.lua"
-- Real Pets.lua is loaded over a strict WoW API stub: any widget method the addon calls that the stub lacks fails the test loudly,
-- any read of an undefined global is reported, and the global namespace is checked for leaks.
local asserts, fails = 0, 0
local function ok(c, m) asserts = asserts + 1; if not c then fails = fails + 1; print("FAIL " .. m) end end
local function eq(a, b, m) ok(a == b, m .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

---------------------------------------------------------------- WoW API stub
local created, handlers, sent, over, chat, mouseDown, closed = {}, {}, {}, {}, {}, true, 0
local popups = {}
local ZONEDATA   -- nil = the small fixture below, or a table { levels=, groups=, species= } (the real generated data)
local M = {}; M.__index = M
local function fire(f, ev, ...) local s = f.scripts and f.scripts[ev]; if s then return s(f, ...) end end
local function new(kind, name, parent)
    local f = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, text = "", n = #created + 1 }, M)
    created[#created + 1] = f
    if name then rawset(_G, name, f) end
    return f
end
for _, m in ipairs({ "SetSize", "SetPoint", "SetAutoFocus", "ClearFocus", "SetTextColor", "SetWidth", "SetHeight", "SetJustifyH", "SetBackdrop", "SetBackdropBorderColor",
    "SetAllPoints", "SetTexture", "SetVertexColor", "SetHighlightTexture", "RegisterForDrag", "RegisterForClicks", "SetFrameStrata", "ClearAllPoints", "SetMovable", "EnableMouse",
    "SetCreature", "HighlightText", "SetRotation", "SetDesaturated", "SetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues", "SetValue", "StartMoving", "StopMovingOrSizing", "AddLineX" }) do
    M[m] = function(self, ...) self["last_" .. m] = { ... } end
end
function M:SetScript(ev, fn) self.scripts[ev] = fn end
function M:GetScript(ev) return self.scripts[ev] end
function M:SetText(t) self.text = tostring(t == nil and "" or t); if self.kind == "EditBox" then fire(self, "OnTextChanged", true) end end
function M:GetText() return self.text end
function M:Show() if not self.shown then self.shown = true; fire(self, "OnShow") else self.shown = true end end
function M:Hide() if self.shown then self.shown = false; fire(self, "OnHide") end end
function M:IsShown() return self.shown end
function M:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
function M:LockHighlight() self.hl = true end
function M:UnlockHighlight() self.hl = false end
function M:Enable() self.enabled = true end
function M:Disable() self.enabled = false end
function M:SetOwner(o) self.owner = o end
function M:GetEffectiveScale() return 1 end
function M:GetParent() return self.parent end
function M:SetChecked(v) self.checked = v and true or false end
function M:GetChecked() return self.checked end
function M:SetScrollChild(c) self.child = c end
function M:CreateFontString(name, layer, tpl) return new("FontString", name, self) end
function M:CreateTexture(name, layer) return new("Texture", name, self) end

local function installStub()
    created, handlers, sent, over, chat, mouseDown, closed = {}, {}, {}, {}, {}, true, 0
    local zd = ZONEDATA or { levels = { ["Elwynn Forest"] = { 1, 2, 1, 10 }, Duskwood = { 5, 6, 1, 30 }, Westfall = { 1, 2, 1, 10 }, Durotar = { 1, 2, 1, 10 }, ["The Barrens"] = { 2, 3, 5, 15 } },
        groups = { { "Eastern Kingdoms", { "Elwynn Forest", "Duskwood", "Westfall" } }, { "Kalimdor", { "Durotar", "The Barrens" } } },
        species = { [3] = { "Elwynn Forest" }, [7] = { "Durotar", "Duskwood" }, [8] = { "Westfall", "Durotar", "Duskwood" },
                    [10] = { "Elwynn Forest", "Duskwood", "Westfall", "Durotar", "The Barrens" },
                    [101] = { "Duskwood" }, [102] = { "Elwynn Forest", "Duskwood", "Westfall", "Durotar", "The Barrens", "Zone Six", "Zone Seven" } } }
    rawset(_G, "WotlkPetZoneLevels", zd.levels); rawset(_G, "WotlkPetZoneGroups", zd.groups); rawset(_G, "WotlkPetSpeciesZones", zd.species); rawset(_G, "WotlkPetDex", zd.dex)
    rawset(_G, "UIDROPDOWNMENU_MENU_VALUE", "")
    rawset(_G, "ACCEPT", "Accept"); rawset(_G, "CANCEL", "Cancel"); StaticPopupDialogs = {}; popups = {}
    function StaticPopup_Show(which, text, _, data)
        local dlg = new("Frame", nil, UIParent); dlg.which, dlg.arg, dlg.data = which, text, data
        dlg.editBox = new("EditBox", nil, dlg); popups[#popups + 1] = dlg
        local d = StaticPopupDialogs[which]; if d and d.OnShow then d.OnShow(dlg) end
        return dlg
    end
    for _, k in ipairs({ "WotlkPets", "WotlkPetsFrame", "WotlkPetsSearch", "WotlkPetsScroll", "WotlkPetsFamilyDD", "WotlkPetsQualityDD", "WotlkPetsViewDD", "WotlkPetsZoneDD", "SLASH_PETS1", "SLASH_PETS2" }) do rawset(_G, k, nil) end
    UIParent = new("Frame", nil, nil)
    GameTooltip = new("Frame", nil, nil); GameTooltip.lines = {}
    function GameTooltip:SetOwner(o) self.owner = o; self.lines = {} end
    function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
    function CreateFrame(kind, name, parent, tpl) return new(kind, name, parent) end
    local cur
    function UIDropDownMenu_SetWidth(dd, w) dd.ddw = w end
    function UIDropDownMenu_SetText(dd, t) dd.ddtext = t end
    function UIDropDownMenu_Initialize(dd, fn) dd.initfn = fn end
    function UIDropDownMenu_CreateInfo() return {} end
    function UIDropDownMenu_AddButton(info, level) if cur then cur[#cur + 1] = info end end
    function CloseDropDownMenus() closed = closed + 1 end
    function OPENMENU_(dd, level, value) cur = {}; UIDROPDOWNMENU_MENU_VALUE = value or ""; dd.initfn(dd, level or 1); local r = cur; cur = nil; return r end
    function IsMouseButtonDown() return mouseDown end
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) chat[#chat + 1] = t end }
    function GetCursorPosition() return 100, 200 end
    function MouseIsOver(f) return over[f] == true end
    SlashCmdList, UISpecialFrames = {}, {}
    tinsert = table.insert
    AcoreLib = {
        On = function(m, a, f) handlers[m .. "|" .. a] = f end,
        Send = function(m, a, p) sent[#sent + 1] = { m = m, a = a, p = tostring(p) } end,
        Solid = function(f) return f end,
    }
end

local undef, seen = {}, { WotlkPetZoneLevels = true, WotlkPetZoneGroups = true, WotlkPetSpeciesZones = true, WotlkPetDex = true }   -- the zone globals may legitimately be nil (Pets.lua guards them)
setmetatable(_G, { __index = function(_, k) if not seen[k] then seen[k] = true; undef[#undef + 1] = tostring(k) end end })

local function snapshot() local s = {}; for k in pairs(_G) do s[k] = true end return s end
local function loadPets()
    installStub()
    local before = snapshot()
    local chunk, err = loadfile("addons/wotlk_pets/Pets.lua"); assert(chunk, err)
    local good, e2 = pcall(chunk); ok(good, "Pets.lua loads: " .. tostring(e2))
    local added = {}
    for k in pairs(_G) do if not before[k] then added[#added + 1] = tostring(k) end end
    return added
end

---------------------------------------------------------------- test data
local PETS = {   -- sp, name, family, quality  (pet 2 is renamed: wire name "nickname|species")
    { 1, "Young Wolf", "Beast", 1 }, { 2, "Fang|Dire Wolf", "Beast", 3 }, { 3, "Stone Turtle", "Aquatic", 2 }, { 4, "Cave Whelp", "Dragonkin", 4 },
    { 5, "Fire Imp", "Elemental", 1 }, { 6, "Frost Imp", "Magic", 2 }, { 7, "Moon Sprite", "Magic", 3 }, { 8, "Wild Sprite", "Flying", 4 },
    { 9, "Gray Wolf Pup", "Beast", 1 }, { 10, "Sea Turtle", "Aquatic", 3 }, { 11, "Ice Elemental", "Elemental", 4 }, { 12, "Healing Bloom, Greater", "Humanoid", 2 },
}
-- real wire format of scripts/pb_store.lua "pet": sp,lv,xp,a1,a2,a3,family,icon,hp,dmg,quality,cur,need,name
local function wire(p) return string.format("%d,%d,%d,1,2,1,%s,Ability_Hunter_Pet_Wolf,%d,%d,%d,%d,%d,%s", p[1], 10 + p[1], 5, p[3], 1500, 30, p[4], 1400, 200, p[2]) end
local function feed(list) for _, p in ipairs(list) do handlers["pbj|pet"](wire(p)) end end

local added = loadPets()
local W = WotlkPets
ok(W and W.S and W.PetPasses and W.StartDrag and W.EndDrag and W.CancelDrag and W.PlaceInTeam, "WotlkPets test hooks exported")
local S = W.S
ok(SlashCmdList["PETS"] and SLASH_PETS1 == "/pets" and SLASH_PETS2 == "/petjournal", "slash command registered")
for _, need in ipairs({ "pet", "team", "follow", "active", "done", "abl", "primed" }) do ok(handlers["pbj|" .. need], "handler registered at load: pbj|" .. need) end

-- (1) open the frame through the slash command
SlashCmdList["PETS"]()
local frame = WotlkPetsFrame
ok(frame and frame:IsShown(), "slash opens the frame")
ok(WotlkPetsSearch and WotlkPetsScroll, "named search box and scroll frame exist")
local function sentOf(a) local t = {}; for _, s in ipairs(sent) do if s.m == "pbj" and s.a == a then t[#t + 1] = s.p end end return t end
eq(table.concat(sentOf("list"), "|"), "", "opening asks the server for the pet list (empty payload)")
eq(#sentOf("list"), 1, "list sent once on open"); eq(#sentOf("prime"), 1, "prime sent once on open")
local tuis = 0; for _, n in ipairs(UISpecialFrames) do if n == "WotlkPetsFrame" then tuis = tuis + 1 end end
eq(tuis, 1, "frame registered in UISpecialFrames (Esc closes)")

handlers["pbj|pet"]("garbage"); handlers["pbj|pet"]("1,2,3")   -- malformed lines are ignored
feed(PETS)
local n = 0; for _ in pairs(S.pets) do n = n + 1 end
eq(n, 12, "12 pets parsed from the wire format")
eq(S.pets[12].name, "Healing Bloom, Greater", "name containing a comma survives the wire parse")
eq(S.pets[4].quality, 4, "quality parsed"); eq(S.pets[7].family, "Magic", "family parsed"); eq(S.pets[2].level, 12, "level parsed")
handlers["pbj|team"]("1,1,3,5"); handlers["pbj|team"]("2,0,0,0"); handlers["pbj|team"]("3,0,0,0"); handlers["pbj|active"]("1")
eq(S.teams[1][2], 3, "team wire parsed")

---------------------------------------------------------------- (2) PetPasses suite (shared with the mutation check)
local PD = {   -- uncollected pseudo pets, shaped like Pets.lua's PetOf() output
    [101] = { dex = true, name = "Alpha Crab", family = "Aquatic", level = 0, quality = 1 }, [102] = { dex = true, name = "Beta Cat", family = "Beast", level = 0, quality = 1 },
    [103] = { dex = true, name = "Gamma Wolf", family = "Beast", level = 0, quality = 1 }, [104] = { dex = true, name = "Delta Bot", family = "Mechanical", level = 0, quality = 1 },
    [105] = { dex = true, name = "Echo Wisp", family = "Magic", level = 0, quality = 1 } }
local U1, U2 = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 101, 102, 103, 104, 105 }
local function ids(pass, F, U) local t = {}; for _, sp in ipairs(U or U1) do if pass(S.pets[sp] or PD[sp], sp, F) then t[#t + 1] = sp end end return table.concat(t, ",") end
local function set(...) local t = {}; for _, v in ipairs({ ... }) do t[v] = true end return t end
local CASES = {
    { "no filter: all", { filter = "", family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12" },
    { "filter field absent: all", { family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12" },
    { "whitespace only search: all", { filter = "   ", family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12" },
    { "family Aquatic", { filter = "", family = set("Aquatic"), qual = {} }, "3,10" },
    { "family Beast", { filter = "", family = set("Beast"), qual = {} }, "1,2,9" },
    { "family Magic", { filter = "", family = set("Magic"), qual = {} }, "6,7" },
    { "family Aquatic+Elemental is OR within families", { filter = "", family = set("Aquatic", "Elemental"), qual = {} }, "3,5,10,11" },
    { "family with no pets (Undead) -> empty", { filter = "", family = set("Undead"), qual = {} }, "" },
    { "quality 1", { filter = "", family = {}, qual = set(1) }, "1,5,9" },
    { "quality 4", { filter = "", family = {}, qual = set(4) }, "4,8,11" },
    { "quality 2+3 is OR within qualities", { filter = "", family = {}, qual = set(2, 3) }, "2,3,6,7,10,12" },
    { "view=team (team 1 = 1,3,5)", { filter = "", family = {}, qual = {}, view = "team" }, "1,3,5" },
    { "family Aquatic AND quality 3", { filter = "", family = set("Aquatic"), qual = set(3) }, "10" },
    { "family Aquatic AND quality 2", { filter = "", family = set("Aquatic"), qual = set(2) }, "3" },
    { "family Beast AND q1 AND view=team", { filter = "", family = set("Beast"), qual = set(1), view = "team" }, "1" },
    { "family Elemental AND view=team", { filter = "", family = set("Elemental"), qual = {}, view = "team" }, "5" },
    { "search 'wolf'", { filter = "wolf", family = {}, qual = {} }, "1,2,9" },
    { "search 'WOLF' (case-insensitive)", { filter = "WOLF", family = {}, qual = {} }, "1,2,9" },
    { "search 'wOlF' (mixed case)", { filter = "wOlF", family = {}, qual = {} }, "1,2,9" },
    { "search is a substring match ('ire' hits Dire Wolf and Fire Imp)", { filter = "ire", family = {}, qual = {} }, "2,5" },
    { "search matches the FAMILY: 'magic'", { filter = "magic", family = {}, qual = {} }, "6,7" },
    { "search matches the family case-insensitively: 'BEAST'", { filter = "BEAST", family = {}, qual = {} }, "1,2,9" },
    { "search matches a family substring: 'aqua'", { filter = "aqua", family = {}, qual = {} }, "3,10" },
    { "search matches name OR family: 'elemental' (family of 5 and 11, name of 11)", { filter = "elemental", family = {}, qual = {} }, "5,11" },
    { "search family word and name word AND: 'wolf beast'", { filter = "wolf beast", family = {}, qual = {} }, "1,2,9" },
    { "search name word and family word AND: 'imp magic'", { filter = "imp magic", family = {}, qual = {} }, "6" },
    { "search words AND: 'wolf magic' -> empty", { filter = "wolf magic", family = {}, qual = {} }, "" },
    { "multi-word AND 'gray wolf'", { filter = "gray wolf", family = {}, qual = {} }, "9" },
    { "multi-word order independent 'wolf gray'", { filter = "wolf gray", family = {}, qual = {} }, "9" },
    { "multi-word AND with extra spaces", { filter = "  wolf   pup ", family = {}, qual = {} }, "9" },
    { "multi-word AND not OR: 'wolf imp' -> empty", { filter = "wolf imp", family = {}, qual = {} }, "" },
    { "search 'imp' matches both imps", { filter = "imp", family = {}, qual = {} }, "5,6" },
    { "search 'turtle'+view=team", { filter = "turtle", family = {}, qual = {}, view = "team" }, "3" },
    { "search 'wolf' AND quality 3", { filter = "wolf", family = {}, qual = set(3) }, "2" },
    { "search 'wolf' AND family Aquatic -> empty", { filter = "wolf", family = set("Aquatic"), qual = {} }, "" },
    { "all four combined", { filter = "wolf", family = set("Beast"), qual = set(1), view = "team" }, "1" },
    { "search 'sea turtle' + Aquatic + q3", { filter = "sea turtle", family = set("Aquatic"), qual = set(3) }, "10" },
    { "comma + word ', g' hits only pet 12", { filter = ", g", family = {}, qual = {} }, "12" },
    { "search 'hum' hits the Humanoid family", { filter = "hum", family = {}, qual = {} }, "12" },
    { "search is plain text, not a Lua pattern ('.' -> empty)", { filter = ".", family = {}, qual = {} }, "" },
    { "search is plain text ('%' -> empty)", { filter = "%", family = {}, qual = {} }, "" },
    { "zone Elwynn Forest", { filter = "", family = {}, qual = {}, zone = "Elwynn Forest" }, "3,10" },
    { "zone Durotar", { filter = "", family = {}, qual = {}, zone = "Durotar" }, "7,8,10" },
    { "zone Duskwood", { filter = "", family = {}, qual = {}, zone = "Duskwood" }, "7,8,10" },
    { "zone Westfall", { filter = "", family = {}, qual = {}, zone = "Westfall" }, "8,10" },
    { "zone The Barrens (one species)", { filter = "", family = {}, qual = {}, zone = "The Barrens" }, "10" },
    { "zone nobody lives in -> empty", { filter = "", family = {}, qual = {}, zone = "Nowhere" }, "" },
    { "zone Durotar AND family Magic", { filter = "", family = set("Magic"), qual = {}, zone = "Durotar" }, "7" },
    { "zone Durotar AND quality 4", { filter = "", family = {}, qual = set(4), zone = "Durotar" }, "8" },
    { "zone Elwynn AND quality 3", { filter = "", family = {}, qual = set(3), zone = "Elwynn Forest" }, "10" },
    { "zone Elwynn AND family Aquatic", { filter = "", family = set("Aquatic"), qual = {}, zone = "Elwynn Forest" }, "3,10" },
    { "zone Elwynn AND view=team (team 1 = 1,3,5)", { filter = "", family = {}, qual = {}, view = "team", zone = "Elwynn Forest" }, "3" },
    { "zone Durotar AND search 'wild'", { filter = "wild", family = {}, qual = {}, zone = "Durotar" }, "8" },
    { "zone Durotar AND search 'turtle' AND family Magic -> empty", { filter = "turtle", family = set("Magic"), qual = {}, zone = "Durotar" }, "" },
    { "search matches zone names: 'durotar'", { filter = "durotar", family = {}, qual = {} }, "7,8,10" },
    { "search matches zone names case-insensitively: 'ELWYNN'", { filter = "ELWYNN", family = {}, qual = {} }, "3,10" },
    { "search matches a zone substring: 'forest'", { filter = "forest", family = {}, qual = {} }, "3,10" },
    { "search matches a multi-word zone name: 'the barrens'", { filter = "the barrens", family = {}, qual = {} }, "10" },
    { "search zone word AND name word: 'westfall turtle'", { filter = "westfall turtle", family = {}, qual = {} }, "10" },
    { "search zone word AND name word: 'durotar sprite'", { filter = "durotar sprite", family = {}, qual = {} }, "7,8" },
    { "search zone word AND family word: 'elwynn magic' -> empty", { filter = "elwynn magic", family = {}, qual = {} }, "" },
    { "search two zone words AND: 'duskwood westfall'", { filter = "duskwood westfall", family = {}, qual = {} }, "8,10" },
    { "search by nickname: 'fang' (pet 2 is renamed Fang, a Dire Wolf)", { filter = "fang", family = {}, qual = {} }, "2" },
    { "search by species of a renamed pet: 'dire'", { filter = "dire", family = {}, qual = {} }, "2" },
    { "nickname and species words AND: 'fang wolf'", { filter = "fang wolf", family = {}, qual = {} }, "2" },
    { "nickname word AND another pet's word -> empty: 'fang gray'", { filter = "fang gray", family = {}, qual = {} }, "" },
    { "renamed pet is still found by its species: 'dire wolf'", { filter = "dire wolf", family = {}, qual = {} }, "2" },
    { "view=team + quality 4 -> empty", { filter = "", family = {}, qual = set(4), view = "team" }, "" },
}
local CASES2 = {   -- universe: 12 owned pets + 5 uncollected pseudo pets (101-105; 101 lives in Duskwood, 102 in Elwynn Forest and Duskwood)
    { "view all lists owned and uncollected", { view = "all", filter = "", family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12,101,102,103,104,105" },
    { "view absent behaves like all", { filter = "", family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12,101,102,103,104,105" },
    { "view collected hides uncollected pets", { view = "collected", filter = "", family = {}, qual = {} }, "1,2,3,4,5,6,7,8,9,10,11,12" },
    { "view missing shows only uncollected pets", { view = "missing", filter = "", family = {}, qual = {} }, "101,102,103,104,105" },
    { "view team: only team pets (1,3,5)", { view = "team", filter = "", family = {}, qual = {} }, "1,3,5" },
    { "view missing AND family Beast", { view = "missing", family = set("Beast"), filter = "", qual = {} }, "102,103" },
    { "view collected AND family Beast", { view = "collected", family = set("Beast"), filter = "", qual = {} }, "1,2,9" },
    { "view all AND family Beast covers both", { view = "all", family = set("Beast"), filter = "", qual = {} }, "1,2,9,102,103" },
    { "quality 1 excludes uncollected pets", { view = "all", qual = set(1), filter = "", family = {} }, "1,5,9" },
    { "quality 4 excludes uncollected pets", { view = "all", qual = set(4), filter = "", family = {} }, "4,8,11" },
    { "view missing AND quality -> empty (uncollected has no quality)", { view = "missing", qual = set(1), filter = "", family = {} }, "" },
    { "view missing AND zone Duskwood", { view = "missing", zone = "Duskwood", filter = "", family = {}, qual = {} }, "101,102" },
    { "view all AND zone Duskwood", { view = "all", zone = "Duskwood", filter = "", family = {}, qual = {} }, "7,8,10,101,102" },
    { "view team AND zone Elwynn Forest", { view = "team", zone = "Elwynn Forest", filter = "", family = {}, qual = {} }, "3" },
    { "view missing AND search 'wolf'", { view = "missing", filter = "wolf", family = {}, qual = {} }, "103" },
    { "view all AND search 'wolf'", { view = "all", filter = "wolf", family = {}, qual = {} }, "1,2,9,103" },
    { "search an uncollected name 'crab'", { filter = "crab", family = {}, qual = {} }, "101" },
    { "search an uncollected family 'aquatic'", { filter = "aquatic", family = {}, qual = {} }, "3,10,101" },
    { "view missing AND search zone 'elwynn'", { view = "missing", filter = "elwynn", family = {}, qual = {} }, "102" },
    { "view collected AND search an uncollected name -> empty", { view = "collected", filter = "alpha", family = {}, qual = {} }, "" },
    { "view team AND family Aquatic", { view = "team", family = set("Aquatic"), filter = "", qual = {} }, "3" },
    { "view missing AND family Aquatic AND search 'crab' AND zone Duskwood", { view = "missing", family = set("Aquatic"), filter = "crab", zone = "Duskwood", qual = {} }, "101" },
}
local ALLCASES = {}; for _, c in ipairs(CASES) do ALLCASES[#ALLCASES + 1] = { c[1], c[2], c[3], U1 } end; for _, c in ipairs(CASES2) do ALLCASES[#ALLCASES + 1] = { c[1], c[2], c[3], U2 } end
local function runSuite(pass, report)
    local bad = 0
    for _, c in ipairs(ALLCASES) do
        local got = ids(pass, c[2], c[4])
        if got ~= c[3] then bad = bad + 1; if report then ok(false, "PetPasses: " .. c[1] .. " (got [" .. got .. "], want [" .. c[3] .. "])") end
        elseif report then ok(true, "") end
    end
    -- a pet record with no quality counts as common (1)
    local q = { name = "X", family = "Beast" }
    local r1 = pass(q, 99, { filter = "", family = {}, qual = set(1) }); local r2 = pass(q, 99, { filter = "", family = {}, qual = set(2) })
    if not (r1 == true and r2 == false) then bad = bad + 1; if report then ok(false, "PetPasses: nil quality counts as 1") end elseif report then ok(true, "") end
    return bad
end
runSuite(W.PetPasses, true)
ok(#CASES >= 25 and #CASES2 >= 20, "at least 25 owned-pet PetPasses cases and 20 view/uncollected cases")

---------------------------------------------------------------- (6) mutation check: broken PetPasses variants must FAIL the same suite
local function cp(F) local G = {}; for k, v in pairs(F) do G[k] = v end return G end
local function build(o)   -- full reimplementation with switches
    return function(p, sp, F)
        local zs = WotlkPetSpeciesZones and WotlkPetSpeciesZones[sp]
        if F.zone and not o.noZone then
            local here = false; for _, z in ipairs(zs or {}) do if z == F.zone then here = true end end
            if o.zoneNilPass and not zs then here = true end
            if o.invZone then here = not here end
            if not here then return false end
        end
        local zl = (zs and not o.noZoneSearch) and table.concat(zs, " "):lower() or ""
        local full = (o.noSpecies and p.name or (o.noNick and (p.species or p.name) or (p.name .. " " .. (p.species or ""))))
        local name = o.case and full or full:lower(); local fam = o.case and p.family or p.family:lower()
        local words = {}; for w in (o.case and (F.filter or "") or (F.filter or ""):lower()):gmatch("%S+") do words[#words + 1] = w end
        if #words > 0 then
            local hit = not o.or_
            for _, w in ipairs(words) do
                local okp, r = pcall(string.find, name, w, 1, not o.pattern); local f = okp and r ~= nil
                if not f and not o.nameOnly then local ok2, r2 = pcall(string.find, fam, w, 1, not o.pattern); f = ok2 and r2 ~= nil end
                if not f and not o.nameOnly then f = zl:find(w, 1, true) ~= nil end
                if o.or_ then hit = hit or f else hit = hit and f end
            end
            if not hit then return false end
        end
        if next(F.family) and not F.family[p.family] then return false end
        if next(F.qual) and ((p.dex and not o.dexQual) or not F.qual[p.quality or (o.q2 and 2 or 1)]) then return false end
        local v = o.noView and "all" or F.view
        if v == "collected" and p.dex and not o.collectedKeepsDex then return false end
        if v == "missing" and not p.dex and not o.missingKeepsOwned then return false end
        if v == "team" then local inT = false; for t = 1, 3 do for i = 1, 3 do if S.teams[t][i] == sp then inT = true end end end
            if o.invTeam then inT = not inT end; if not inT then return false end end
        return true
    end
end
eq(runSuite(build({}), false), 0, "mutation harness sanity: faithful reimplementation passes the suite")
local MUT = {
    ["ignores the quality filter"] = function() return function(p, sp, F) local G = cp(F); G.qual = {}; return W.PetPasses(p, sp, G) end end,
    ["ignores the family filter"] = function() return function(p, sp, F) local G = cp(F); G.family = {}; return W.PetPasses(p, sp, G) end end,
    ["ignores the view filter"] = function() return function(p, sp, F) local G = cp(F); G.view = nil; return W.PetPasses(p, sp, G) end end,
    ["ignores the search text"] = function() return function(p, sp, F) local G = cp(F); G.filter = ""; return W.PetPasses(p, sp, G) end end,
    ["search words OR instead of AND"] = function() return build({ or_ = true }) end,
    ["search ignores the family (name only)"] = function() return build({ nameOnly = true }) end,
    ["ignores the zone filter"] = function() return function(p, sp, F) local G = cp(F); G.zone = nil; return W.PetPasses(p, sp, G) end end,
    ["zone filter inverted"] = function() return build({ invZone = true }) end,
    ["zone filter passes species with no zone data"] = function() return build({ zoneNilPass = true }) end,
    ["search ignores zone names"] = function() return build({ noZoneSearch = true }) end,
    ["search ignores the species of a renamed pet"] = function() return build({ noSpecies = true }) end,
    ["search ignores the nickname of a renamed pet"] = function() return build({ noNick = true }) end,
    ["case-sensitive search"] = function() return build({ case = true }) end,
    ["search uses Lua patterns"] = function() return build({ pattern = true }) end,
    ["missing quality defaults to 2"] = function() return build({ q2 = true }) end,
    ["view ignored (build switch)"] = function() return build({ noView = true }) end,
    ["collected view still shows uncollected pets"] = function() return build({ collectedKeepsDex = true }) end,
    ["missing view still shows owned pets"] = function() return build({ missingKeepsOwned = true }) end,
    ["quality filter lets uncollected pets through"] = function() return build({ dexQual = true }) end,
    ["view=team inverted"] = function() return build({ invTeam = true }) end,
    ["everything passes"] = function() return function() return true end end,
    ["nothing passes"] = function() return function() return false end end,
}
for name, mk in pairs(MUT) do ok(runSuite(mk(), false) > 0, "MUTANT SURVIVED (suite did not notice): PetPasses " .. name) end

---------------------------------------------------------------- UI helpers (rows, slots, buttons found through the stub's creation log)
local function rowFor(sp) for _, f in ipairs(created) do if f.kind == "Button" and f.parent == WotlkPetsScroll.child and f.sp == sp and f.shown then return f end end end
local function visibleRows() local t = {}; for _, f in ipairs(created) do if f.kind == "Button" and f.parent == WotlkPetsScroll.child and f.shown then t[#t + 1] = f.sp end end return table.concat(t, ",") end
local slots = {}; for _, f in ipairs(created) do if f.kind == "Button" and f.last_RegisterForClicks then slots[#slots + 1] = f end end
eq(#slots, 9, "9 team slots found")
local function slot(n, i) return slots[(n - 1) * 3 + i] end
local function btn(label) for _, f in ipairs(created) do if f.kind == "Button" and f.text:find(label, 1, true) then return f end end error("no button " .. label) end
local dragFrame   -- created lazily by the first StartDrag
local function findDrag() for _, f in ipairs(created) do if f.last_SetFrameStrata and f.last_SetFrameStrata[1] == "TOOLTIP" then dragFrame = f end end end
local function teamsStr() local t = {}; for n2 = 1, 3 do t[n2] = table.concat(S.teams[n2], ",") end return table.concat(t, " | ") end
local function setteams() local t = {}; for _, s in ipairs(sent) do if s.a == "setteam" then t[#t + 1] = s.p end end return table.concat(t, " ; ") end
local function reset(tab)
    S.family, S.qual, S.view, S.filter, S.sel, S.tab = {}, {}, "all", "", nil, tab or 2
    W.CancelDrag(); over = {}
    if not frame:IsShown() then SlashCmdList["PETS"]() end
    WotlkPetsSearch.text = ""
    handlers["pbj|team"]("1,1,3,5"); handlers["pbj|team"]("2,0,0,0"); handlers["pbj|team"]("3,0,0,0")
    handlers["pbj|done"]()
    sent = {}
end
local function drop(target) over = {}; if target == "outside" then return end; over[frame] = true; if target ~= "window" then over[target] = true end end

---------------------------------------------------------------- (4) filters through the real UI: row order, count, empty state
reset(1)
eq(visibleRows(), "4,2,5,6,9,12,11,7,10,3,8,1", "list sorted by name, all 12 shown")
eq(frame.count.text, "12 pets", "count with no filter")
eq(S.emptyTxt.text, "", "no empty-state text when pets are shown")
local fdd, qdd, vdd = WotlkPetsFamilyDD, WotlkPetsQualityDD, WotlkPetsViewDD
local function setView(i) OPENMENU_(vdd)[i].func() end
ok(fdd and qdd and vdd, "family/quality/view drop-downs exist"); ok(rawget(_G, "WotlkPetsTeamCB") == nil, "the old team check box is gone")
eq(fdd.ddtext, "All families", "family drop-down starts at 'All families'"); eq(qdd.ddtext, "All qualities", "quality drop-down starts at 'All qualities'"); eq(vdd.ddtext, "All pets", "view drop-down starts at 'All pets'"); eq(S.view, "all", "S.view starts at all")
local FAMS = { "Aquatic", "Beast", "Critter", "Dragonkin", "Elemental", "Flying", "Humanoid", "Magic", "Mechanical", "Undead" }
local fm = OPENMENU_(fdd)
eq(#fm, 11, "family menu: 'All families' + 10 families"); eq(fm[1].text, "All families", "first family entry is 'All families'")
local famOk = true; for i, f in ipairs(FAMS) do if fm[i + 1].text ~= f then famOk = false end end; ok(famOk, "family menu lists the ten real families in order")
local keepOk = true; for i, e in ipairs(fm) do if (i > 1 and not e.keepShownOnClick) or type(e.func) ~= "function" then keepOk = false end end; ok(keepOk, "every family entry (except the All entry) keeps the menu open and has a func")
ok(fm[2].isNotRadio and not fm[2].checked, "family entries are check boxes, unticked at start")
local qm = OPENMENU_(qdd)
eq(#qm, 5, "quality menu: 'All qualities' + 4"); eq(qm[1].text, "All qualities", "first quality entry is 'All qualities'"); ok(qm[4].text:find("Rare", 1, true), "quality entries carry the quality name")
local vm = OPENMENU_(vdd)
eq(#vm, 4, "view menu has 4 entries"); eq(vm[1].text .. "|" .. vm[2].text .. "|" .. vm[3].text .. "|" .. vm[4].text, "All pets|Collected|Not collected|In a team", "view menu labels")
ok(vm[1].checked == true and vm[2].checked == false, "view menu ticks the current view (All pets)")
local cb4 = closed; vm[2].func(); eq(S.view, "collected", "choosing Collected sets S.view"); eq(vdd.ddtext, "Collected", "view text 'Collected'"); eq(closed, cb4 + 1, "choosing a view closes the menus"); ok(OPENMENU_(vdd)[2].checked == true and OPENMENU_(vdd)[1].checked == false, "reopened view menu ticks Collected (single choice)")
vm[3].func(); eq(S.view, "missing", "choosing Not collected sets S.view"); eq(vdd.ddtext, "Not collected", "view text 'Not collected'"); vm[1].func(); eq(S.view, "all", "back to all")
fm[2].func()   -- Aquatic
ok(S.family.Aquatic and next(S.family) == "Aquatic", "ticking Aquatic sets S.family"); eq(fdd.ddtext, "Aquatic", "single family: the dropdown shows its name")
eq(visibleRows(), "10,3", "family Aquatic rows (Sea Turtle, Stone Turtle)"); eq(frame.count.text, "2 of 12 pets", "count 'n of N pets' after family filter")
ok(OPENMENU_(fdd)[2].checked == true, "reopened menu shows Aquatic ticked")
fm[6].func()   -- Elemental
eq(fdd.ddtext, "2 selected", "two families: 'n selected'"); eq(visibleRows(), "5,11,10,3", "Aquatic OR Elemental rows"); eq(frame.count.text, "4 of 12 pets", "count with two families")
qm[4].func()   -- Rare (3)
ok(S.qual[3], "ticking Rare sets S.qual[3]"); eq(qdd.ddtext, qm[4].text, "single quality: dropdown shows the coloured quality name"); eq(visibleRows(), "10", "families AND Rare"); eq(frame.count.text, "1 of 12 pets", "count families+quality")
qm[5].func()   -- Epic (4)
eq(qdd.ddtext, "2 selected", "two qualities: 'n selected'"); eq(visibleRows(), "11,10", "families AND (Rare or Epic)"); eq(frame.count.text, "2 of 12 pets", "count families+2 qualities")
fm[2].func()   -- untick Aquatic
ok(S.family.Aquatic == nil, "unticking removes the family"); eq(fdd.ddtext, "Elemental", "back to a single family name"); eq(visibleRows(), "11", "Elemental AND (Rare or Epic)"); eq(frame.count.text, "1 of 12 pets", "count after untick")
setView(4)
eq(S.view, "team", "choosing 'In a team' sets S.view"); eq(vdd.ddtext, "In a team", "view text shows 'In a team'"); eq(visibleRows(), "", "Elemental AND Rare/Epic AND in a team -> none"); eq(frame.count.text, "0 of 12 pets", "count 0 of 12")
eq(S.emptyTxt.text, "No pet matches the filters. Use Clear filters.", "empty-result text with menu filters")
fm[1].func(); eq(next(S.family), nil, "'All families' clears the family set"); eq(fdd.ddtext, "All families", "dropdown text back to 'All families'")
qm[1].func(); eq(next(S.qual), nil, "'All qualities' clears the quality set"); eq(qdd.ddtext, "All qualities", "quality text back")
eq(visibleRows(), "5,3,1", "only the team filter remains"); eq(frame.count.text, "3 of 12 pets", "count with the team filter alone"); eq(S.view, "team", "view still team")
setView(1); eq(S.view, "all", "choosing 'All pets' resets the view"); eq(vdd.ddtext, "All pets", "view text back to 'All pets'"); eq(frame.count.text, "12 pets", "all pets again")
-- Clear filters resets everything, including the check box and the search text
fm[3].func(); qm[2].func(); setView(4); WotlkPetsSearch:SetText("fire")
ok(next(S.family) and next(S.qual) and S.view == "team" and S.filter == "fire", "all filters set before Clear")
fire(btn("Clear filters"), "OnClick")
eq(next(S.family), nil, "Clear empties the family set"); eq(next(S.qual), nil, "Clear empties the quality set"); eq(S.view, "all", "Clear resets the view"); eq(vdd.ddtext, "All pets", "Clear resets the view text")
eq(S.filter, "", "Clear resets the search"); eq(WotlkPetsSearch.text, "", "Clear empties the search box"); eq(fdd.ddtext, "All families", "Clear resets the family text"); eq(qdd.ddtext, "All qualities", "Clear resets the quality text")
eq(frame.count.text, "12 pets", "Clear restores the count")
-- zone drop-down: single choice, two levels
local zdd = WotlkPetsZoneDD
ok(zdd, "zone drop-down exists"); eq(zdd.ddtext, "All zones", "zone drop-down starts at 'All zones'")
local z1 = OPENMENU_(zdd, 1)
eq(#z1, 3, "zone level 1: 'All zones' + 2 continents"); eq(z1[1].text, "All zones", "first zone entry is 'All zones'")
ok(z1[2].hasArrow and z1[2].value == "Eastern Kingdoms" and z1[2].text == "Eastern Kingdoms", "continent entry has an arrow and its group name as value")
ok(z1[3].hasArrow and z1[3].value == "Kalimdor" and not z1[3].func, "second continent entry; continents have no func")
local z2 = OPENMENU_(zdd, 2, "Eastern Kingdoms")
eq(#z2, 3, "zone level 2 lists the group's zones"); eq(z2[1].text .. "|" .. z2[2].text .. "|" .. z2[3].text, "Elwynn Forest|Duskwood|Westfall", "level 2 zones in group order")
ok(not z2[1].checked and not z2[2].checked, "no zone ticked at start"); eq(#OPENMENU_(zdd, 2, "Nonexistent"), 0, "unknown group value lists nothing"); eq(#OPENMENU_(zdd, 2, "Kalimdor"), 2, "Kalimdor has 2 zones")
local closedBefore = closed
z2[1].func()
eq(S.zone, "Elwynn Forest", "choosing a zone sets S.zone"); eq(zdd.ddtext, "Elwynn Forest", "zone text shows the zone"); eq(closed, closedBefore + 1, "choosing a zone closes the menus")
eq(visibleRows(), "10,3", "zone Elwynn rows (Sea Turtle, Stone Turtle)"); eq(frame.count.text, "2 of 12 pets", "count after zone filter")
z2 = OPENMENU_(zdd, 2, "Eastern Kingdoms"); ok(z2[1].checked == true and z2[2].checked == false, "reopened level 2 ticks the current zone")
OPENMENU_(zdd, 2, "Kalimdor")[1].func()
eq(S.zone, "Durotar", "single choice: a new zone replaces the old one"); eq(zdd.ddtext, "Durotar", "zone text updated"); eq(visibleRows(), "7,10,8", "zone Durotar rows"); eq(frame.count.text, "3 of 12 pets", "count zone Durotar")
fm = OPENMENU_(fdd); fm[9].func(); eq(visibleRows(), "7", "zone AND family through the UI"); eq(frame.count.text, "1 of 12 pets", "count zone+family")
fm[1].func()
local sb = WotlkPetsSearch; sb:SetText("barrens"); eq(visibleRows(), "10", "zone Durotar AND search 'barrens' -> pet 10 (lives in both)")
sb:SetText("")
z1[1].func(); eq(S.zone, nil, "'All zones' clears the zone"); eq(zdd.ddtext, "All zones", "zone text back to 'All zones'"); eq(frame.count.text, "12 pets", "all pets after 'All zones'"); ok(closed > closedBefore + 1, "'All zones' closes the menus")
OPENMENU_(zdd, 2, "Eastern Kingdoms")[3].func(); fm[3].func(); setView(4); qm[2].func()
ok(S.zone and next(S.family) and next(S.qual) and S.view == "team", "all filters incl. zone set before Clear")
fire(btn("Clear filters"), "OnClick")
eq(S.zone, nil, "Clear resets the zone"); eq(zdd.ddtext, "All zones", "Clear resets the zone text"); eq(frame.count.text, "12 pets", "Clear restores the count with zone filter")
-- tooltips: 'Found in' line
local function lines() return table.concat(GameTooltip.lines, " / ") end
fire(rowFor(10), "OnEnter"); ok(lines():find("Found in: Elwynn Forest, Duskwood, Westfall +2 more", 1, true), "row tooltip: 5 zones -> first three and '+2 more': " .. lines())
fire(rowFor(3), "OnEnter"); ok(lines():find("Found in: Elwynn Forest", 1, true) and not lines():find("more", 1, true), "row tooltip: single zone, no 'more'")
fire(rowFor(8), "OnEnter"); ok(lines():find("Found in: Westfall, Durotar, Duskwood", 1, true) and not lines():find("more", 1, true), "row tooltip: exactly 3 zones, no 'more'")
fire(rowFor(12), "OnEnter"); ok(not lines():find("Found in", 1, true), "row tooltip: species with no zone data has no 'Found in' line")
reset(2); handlers["pbj|team"]("2,7,10,0"); fire(slot(2, 1), "OnEnter"); ok(lines():find("Found in: Durotar, Duskwood", 1, true), "team slot tooltip has the 'Found in' line: " .. lines())
fire(slot(2, 2), "OnEnter"); ok(lines():find("+2 more", 1, true), "team slot tooltip: '+2 more'")
reset(1)
-- PET RENAME
eq(S.pets[2].name, "Fang", "renamed wire 'nick|species': name is the nickname"); eq(S.pets[2].species, "Dire Wolf", "renamed wire: species is the real species name")
eq(S.pets[1].name, "Young Wolf", "plain wire: name unchanged"); eq(S.pets[1].species, nil, "plain wire: species is nil")
eq(S.pets[12].name, "Healing Bloom, Greater", "plain name with a comma still parses whole"); eq(S.pets[12].species, nil, "plain name with a comma: no species")
reset(1)
eq(table.concat({ ids(W.PetPasses, { filter = "wolf", family = {}, qual = {} }) }), "1,2,9", "'wolf' finds the renamed Dire Wolf through its species")
sb = WotlkPetsSearch; sb:SetText("fang"); eq(visibleRows(), "2", "UI search by nickname"); sb:SetText("dire"); eq(visibleRows(), "2", "UI search by species of a renamed pet"); sb:SetText(""); eq(frame.count.text, "12 pets", "count restored after search")
-- tooltip species line
local function nlines() return #GameTooltip.lines end
fire(rowFor(2), "OnEnter"); local renLines = nlines(); ok(lines():find("Dire Wolf", 1, true), "renamed pet tooltip has the species line: " .. lines())
fire(rowFor(9), "OnEnter"); eq(nlines(), renLines - 1, "plain pet tooltip has one line fewer (no species line)"); ok(not lines():find("Dire", 1, true) and not lines():find("Gray Wolf", 1, true), "plain pet tooltip has no species line")
reset(2); fire(slot(1, 1), "OnEnter"); eq(nlines(), renLines - 1, "team slot, plain pet 1: no species line"); handlers["pbj|team"]("1,2,3,5"); fire(slot(1, 1), "OnEnter"); eq(nlines(), renLines, "team slot, renamed pet 2: species line"); ok(lines():find("Dire Wolf", 1, true), "team slot tooltip names the species")
-- details pane second line
reset(1); local function subOf() for _, f in ipairs(created) do if f.kind == "FontString" and f.text:find("Level 12", 1, true) and f.text:find("Rare", 1, true) then return f.text end end end
fire(rowFor(2), "OnClick"); ok((subOf() or ""):find("\n[^\n]*Dire Wolf"), "details pane: second line shows the species: " .. tostring(subOf()))
fire(rowFor(1), "OnClick"); local plainSub; for _, f in ipairs(created) do if f.kind == "FontString" and f.text:find("Level 11", 1, true) and f.text:find("Common", 1, true) then plainSub = f.text end end
ok(plainSub and not plainSub:find("\n", 1, true), "details pane: no second line for a plain pet: " .. tostring(plainSub))
-- rename button and popup
local def = StaticPopupDialogs["WOTLKPETS_RENAME"]
ok(def and def.button1 == ACCEPT and def.button2 == CANCEL and def.hasEditBox, "popup WOTLKPETS_RENAME defined with Accept/Cancel and an edit box"); eq(def.maxLetters, 12, "popup limits the name to 12 letters")
local ren = btn("Rename"); ok(ren, "Rename button exists")
reset(1); popups = {}; fire(ren, "OnClick"); eq(#popups, 0, "Rename with no selected pet opens nothing")
fire(rowFor(2), "OnClick"); fire(ren, "OnClick")
local dlg = popups[1]; ok(dlg and dlg.which == "WOTLKPETS_RENAME" and dlg.data == 2, "Rename opens the popup for the selected species id"); eq(dlg.arg, "Dire Wolf", "popup text argument is the real species name")
eq(dlg.editBox.text, "Fang", "renamed pet: edit box prefilled with the nickname")
sent = {}; dlg.editBox:SetText("Rex"); def.OnAccept(dlg); eq(#sent, 1, "accept sends once"); eq(sent[1].m .. "|" .. sent[1].a .. "|" .. sent[1].p, "pbj|rename|2,Rex", "accept sends '<id>,<text>'")
sent = {}; dlg.editBox:SetText("Rex Jr"); def.EditBoxOnEnterPressed(dlg.editBox); eq(sent[1] and sent[1].p, "2,Rex Jr", "Enter sends '<id>,<text>'"); ok(not dlg:IsShown(), "Enter closes the popup")
sent = {}; local dlg2 = StaticPopup_Show("WOTLKPETS_RENAME", "x", nil, 2); dlg2.editBox:SetText(""); def.OnAccept(dlg2); eq(sent[1] and sent[1].p, "2,", "empty text on accept clears the nickname ('<id>,')")
sent = {}; dlg2.editBox:SetText(""); def.EditBoxOnEnterPressed(dlg2.editBox); eq(sent[1] and sent[1].p, "2,", "empty text on Enter clears the nickname")
local dlg3 = StaticPopup_Show("WOTLKPETS_RENAME", "x", nil, 2); def.EditBoxOnEscapePressed(dlg3.editBox); ok(not dlg3:IsShown(), "Escape closes the popup"); eq(#sent, 1 + 0, "Escape sends nothing")
-- plain pet: popup opens with an empty box, argument is its own name
fire(rowFor(1), "OnClick"); popups = {}; fire(ren, "OnClick")
eq(popups[1].data, 1, "plain pet: popup carries its id"); eq(popups[1].arg, "Young Wolf", "plain pet: popup text argument is its name"); eq(popups[1].editBox.text, "", "plain pet: edit box is not prefilled")
sent = {}; popups[1].editBox:SetText("Rover"); def.OnAccept(popups[1]); eq(sent[1] and sent[1].p, "1,Rover", "plain pet rename string")
-- server confirms: clearing the nickname returns a plain pet
handlers["pbj|pet"](wire({ 2, "Dire Wolf", "Beast", 3 })); eq(S.pets[2].species, nil, "after a clear the pet is plain again"); eq(S.pets[2].name, "Dire Wolf", "after a clear the name is the species")
handlers["pbj|pet"](wire({ 2, "Fang|Dire Wolf", "Beast", 3 })); eq(S.pets[2].name, "Fang", "renamed again")
reset(1)
-- COLLECTED / NOT COLLECTED (pseudo pets from WotlkPetDex)
local FIXDEX = { [101] = { "Alpha Crab", "Aquatic", "INV_Misc_A" }, [102] = { "Beta Cat", "Beast", "INV_Misc_B" }, [103] = { "Gamma Wolf", "Beast", "INV_Misc_C" },
    [104] = { "Delta Bot", "Mechanical", "INV_Misc_D" }, [105] = { "Echo Wisp", "Magic", "INV_Misc_E" }, [3] = { "Flesh Eater", "Undead", "INV_Misc_F" } }   -- 3 is owned: the owned pet wins
WotlkPetDex = FIXDEX
reset(1)
eq(visibleRows(), "101,102,4,104,105,2,5,6,103,9,12,11,7,10,3,8,1", "view all: owned and uncollected pets merged, sorted by name; owned species 3 not duplicated")
eq(frame.count.text, "17 pets", "count counts owned + uncollected")
setView(3); eq(visibleRows(), "101,102,104,105,103", "view Not collected: only uncollected pets"); eq(frame.count.text, "5 of 17 pets", "count 'n of N pets' for Not collected")
setView(2); eq(visibleRows(), "4,2,5,6,9,12,11,7,10,3,8,1", "view Collected: only owned pets"); eq(frame.count.text, "12 pets", "count in Collected view excludes uncollected pets")
setView(4); eq(visibleRows(), "5,3,1", "view In a team"); eq(frame.count.text, "3 of 12 pets", "count in team view")
setView(1)
-- rows
local function rowOf(sp) return rowFor(sp) end
local r101, r1 = rowOf(101), rowOf(1)
eq(r101.name.text, "Alpha Crab", "uncollected row: name"); eq(r101.name.last_SetTextColor[1] .. "," .. r101.name.last_SetTextColor[2], "0.6,0.6", "uncollected row: grey name")
ok(r101.icon.last_SetDesaturated[1] == true, "uncollected row: desaturated icon"); eq(r101.icon.last_SetTexture[1], "Interface\\Icons\\INV_Misc_A", "uncollected row: dex icon")
ok(r101.sub.text:find("Aquatic", 1, true) and r101.sub.text:find("not collected", 1, true), "uncollected row sub: '<family> not collected': " .. r101.sub.text); eq(r101.lvl.text, "", "uncollected row: empty level")
ok(r1.icon.last_SetDesaturated[1] == false, "owned row: icon not desaturated"); ok(not r1.sub.text:find("not collected", 1, true), "owned row: no 'not collected'"); eq(r1.lvl.text, "11", "owned row: level shown")
-- filters apply to uncollected pets
fm[3].func(); eq(visibleRows(), "102,2,103,9,1", "family Beast applies to uncollected pets too"); eq(frame.count.text, "5 of 17 pets", "count with family over merged list"); fm[1].func()
qm[4].func(); eq(visibleRows(), "2,7,10", "quality filter hides uncollected pets (Rare: Fang, Moon Sprite, Sea Turtle)"); eq(frame.count.text, "3 of 17 pets", "count with quality"); qm[1].func()
setView(3); qm[2].func(); eq(visibleRows(), "", "Not collected AND quality -> nothing"); eq(S.emptyTxt.text, "No pet matches the filters. Use Clear filters.", "empty text for view+quality"); qm[1].func(); setView(1)
OPENMENU_(zdd, 2, "Eastern Kingdoms")[2].func(); eq(visibleRows(), "101,102,7,10,8", "zone Duskwood lists owned and uncollected species"); OPENMENU_(zdd, 1)[1].func()
sb:SetText("crab"); eq(visibleRows(), "101", "search finds an uncollected pet"); sb:SetText("")
setView(3); fire(btn("Clear filters"), "OnClick"); eq(S.view, "all", "Clear resets S.view"); eq(vdd.ddtext, "All pets", "Clear resets the view text"); eq(frame.count.text, "17 pets", "Clear restores the merged count")
-- details pane
local function dOf() return btn("Rename").parent end
local function kids(kind, pred) local t = {}; for _, f in ipairs(created) do if f.parent == dOf() and f.kind == kind and (not pred or pred(f)) then t[#t + 1] = f end end return t end
local function whereTxt() for _, f in ipairs(kids("FontString")) do if f.text:find("^Found in") then return f.text end end end
local function subTxt() for _, f in ipairs(kids("FontString")) do if f.text:find("Not collected  %-", 1) or f.text:find("Level ", 1, true) then return f.text end end end
local function statsTxt() for _, f in ipairs(kids("FontString")) do if f.text:find("^Family") or f.text:find("^Health") then return f.text end end end
local abBtns = kids("Button", function(f) return f.cd ~= nil end); eq(#abBtns, 6, "6 ability buttons found")
local labels = kids("FontString", function(f) return f.text == "Basic" or f.text == "Utility" or f.text == "Major" end); eq(#labels, 3, "3 ability labels found")
local sumB, xpB = btn("Summon") or btn("Dismiss"), kids("StatusBar")[1]
reset(1); sent = {}
fire(rowFor(102), "OnClick")
eq(statsTxt(), "Family   |cffffffffBeast|r", "dex details: stats show only the family"); eq(subTxt(), "Not collected  -  Beast", "dex details: sub 'Not collected - Family'")
local dn; for _, f in ipairs(kids("FontString")) do if f.text == "Beta Cat" then dn = f end end
ok(dn and dn.last_SetTextColor[1] == 0.65, "dex details: grey name")
eq(whereTxt(), "Found in: Elwynn Forest, Duskwood, Westfall, Durotar, The Barrens, Zone Six +1 more", "dex details: first 6 zones and '+1 more'")
ok(not sumB:IsShown() and not btn("Rename"):IsShown() and not xpB:IsShown(), "dex details: Summon, Rename and the xp bar are hidden")
local allHidden = true; for _, b in ipairs(abBtns) do if b:IsShown() then allHidden = false end end; ok(allHidden, "dex details: ability buttons hidden")
allHidden = true; for _, l in ipairs(labels) do if l:IsShown() then allHidden = false end end; ok(allHidden, "dex details: ability labels hidden")
eq(#sentOf("abil"), 0, "selecting an uncollected pet asks the server for no abilities")
fire(rowFor(101), "OnClick"); eq(whereTxt(), "Found in: Duskwood", "dex details: single zone")
fire(rowFor(103), "OnClick"); eq(whereTxt(), "Found in: companion pet", "dex details: species with no zones -> 'companion pet'")
fire(rowFor(10), "OnClick")
eq(whereTxt(), "Found in: Elwynn Forest, Duskwood, Westfall, Durotar, The Barrens", "owned details: where shown under the xp bar")
ok(sumB:IsShown() and btn("Rename"):IsShown() and xpB:IsShown(), "owned details: Summon, Rename and the xp bar shown again")
allHidden = true; for _, b in ipairs(abBtns) do if not b:IsShown() then allHidden = false end end; ok(allHidden, "owned details: ability buttons shown again")
allHidden = true; for _, l in ipairs(labels) do if not l:IsShown() then allHidden = false end end; ok(allHidden, "owned details: ability labels shown again")
ok((statsTxt() or ""):find("^Health"), "owned details: stats back"); ok((subTxt() or ""):find("Level 20", 1, true), "owned details: sub shows the level")
fire(rowFor(1), "OnClick"); eq(whereTxt(), "Found in: companion pet", "owned pet without zones: 'companion pet'")
-- tooltips
fire(rowFor(104), "OnEnter"); ok(lines():find("Not collected  -  Mechanical", 1, true), "dex tooltip: 'Not collected - family': " .. lines()); ok(not lines():find("Health", 1, true) and not lines():find("Level", 1, true), "dex tooltip: no health/level line")
ok(lines():find("Click: details", 1, true) and not lines():find("Drag", 1, true), "dex tooltip: 'Click: details' without drag text"); ok(not lines():find("Found in", 1, true), "dex tooltip: no zones -> no 'Found in'")
fire(rowFor(101), "OnEnter"); ok(lines():find("Found in: Duskwood", 1, true), "dex tooltip with zones has 'Found in'")
fire(rowFor(102), "OnEnter"); ok(lines():find("Found in: Elwynn Forest, Duskwood, Westfall +4 more", 1, true), "dex tooltip: 3 zones and '+4 more': " .. lines())
fire(rowFor(9), "OnEnter"); ok(lines():find("Health", 1, true) and lines():find("Drag: put in a team", 1, true), "owned tooltip keeps health and drag text")
-- dragging a dex pet does nothing
reset(1); sent = {}; fire(rowFor(104), "OnDragStart"); eq(S.drag, nil, "dragging an uncollected pet starts nothing"); eq(S.tab, 1, "dragging an uncollected pet does not open the Teams tab")
drop(slot(2, 1)); fire(rowFor(104), "OnDragStop"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "uncollected pet dropped on a slot: teams unchanged"); eq(#setteams(), 0, "nothing sent")
W.StartDrag(104); eq(S.drag, nil, "StartDrag refuses an uncollected pet")
-- picking up an owned pet becoming collected: the server sends the pet, the pseudo pet disappears
handlers["pbj|pet"](wire({ 104, "Delta Bot", "Mechanical", 2 })); S.view = "all"; handlers["pbj|done"]()
ok(rowFor(104) and rowFor(104).lvl.text == "114", "a newly collected pet is listed as owned (level shown)"); eq(frame.count.text, "17 pets", "total unchanged when an uncollected pet becomes owned")
S.pets[104] = nil; handlers["pbj|done"](); setView(1)
WotlkPetDex = nil; reset(1)
eq(visibleRows(), "4,2,5,6,9,12,11,7,10,3,8,1", "no dex data: only owned pets are listed"); eq(frame.count.text, "12 pets", "no dex data: count is the owned pets")

-- search through the real EditBox script
sb = WotlkPetsSearch; sb:SetText("wolf"); eq(S.filter, "wolf", "typing in the search box sets the filter"); eq(visibleRows(), "2,9,1", "search 'wolf' rows"); eq(frame.count.text, "3 of 12 pets", "count after search")
sb:SetText("GRAY  WOLF"); eq(visibleRows(), "9", "multi-word case-insensitive search through the UI")
sb:SetText("magic"); eq(visibleRows(), "6,7", "search matches the family through the UI (Frost Imp, Moon Sprite)")
sb:SetText("wolf imp"); eq(visibleRows(), "", "no row visible for empty result"); eq(S.emptyTxt.text, "No pet matches the filters. Use Clear filters.", "empty-result text")
eq(frame.count.text, "0 of 12 pets", "count 0 of 12 on empty result")
fire(btn("Clear filters"), "OnClick"); eq(sb.text, "", "Clear filters clears the search box"); eq(S.filter, "", "Clear filters clears S.filter"); eq(frame.count.text, "12 pets", "count restored")
setView(4); eq(visibleRows(), "5,3,1", "In a team shows team pets only"); eq(frame.count.text, "3 of 12 pets", "count with In a team")
fire(btn("Clear filters"), "OnClick")

---------------------------------------------------------------- (3) drag and drop
reset(1)
-- list -> empty slot
fire(rowFor(2), "OnDragStart"); findDrag()
eq(S.tab, 2, "dragging from the list opens the Teams tab"); ok(S.drag and S.drag.sp == 2 and S.drag.fromTeam == nil, "drag state from list")
ok(dragFrame and dragFrame.shown and dragFrame.tex.last_SetTexture[1] == "Interface\\Icons\\Ability_Hunter_Pet_Wolf", "cursor icon shown")
fire(dragFrame, "OnUpdate"); ok(dragFrame.last_SetPoint ~= nil, "cursor icon follows the mouse")
drop(slot(2, 2)); fire(rowFor(2), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,2,0 | 0,0,0", "list -> empty slot: teams"); eq(setteams(), "2,0,2,0", "list -> empty slot: exact setteam"); eq(S.drag, nil, "drag cleared after drop"); ok(not dragFrame.shown, "cursor icon hidden after drop")
eq(#sent, 1, "list -> empty slot: nothing else sent")

reset(1)   -- list -> occupied slot: the old pet is replaced
fire(rowFor(2), "OnDragStart"); drop(slot(1, 2)); fire(rowFor(2), "OnDragStop")
eq(teamsStr(), "1,2,5 | 0,0,0 | 0,0,0", "list -> occupied slot replaces"); eq(setteams(), "1,1,2,5", "list -> occupied slot: exact setteam")

reset(1)   -- list pet already in this team: positions swap
fire(rowFor(5), "OnDragStart"); drop(slot(1, 1)); fire(rowFor(5), "OnDragStop")
eq(teamsStr(), "5,3,1 | 0,0,0 | 0,0,0", "list pet already in team swaps places"); eq(setteams(), "1,5,3,1", "swap from list: exact setteam")

reset(1)   -- list pet dropped on the slot it already occupies
fire(rowFor(3), "OnDragStart"); drop(slot(1, 2)); fire(rowFor(3), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "list pet onto its own slot: unchanged")

reset(2)   -- slot -> slot swap within a team
fire(slot(1, 1), "OnDragStart"); ok(S.drag and S.drag.sp == 1 and S.drag.fromTeam == 1 and S.drag.fromSlot == 1, "drag state from slot")
drop(slot(1, 3)); fire(slot(1, 1), "OnDragStop")
eq(teamsStr(), "5,3,1 | 0,0,0 | 0,0,0", "slot -> slot swap within team"); eq(setteams(), "1,5,3,1", "swap within team: ONE exact setteam"); eq(#sent, 1, "swap within team sends once")

reset(2)   -- slot -> empty slot within a team (moves the pet)
fire(slot(2, 1), "OnDragStart"); eq(S.drag, nil, "dragging an empty slot starts nothing")
handlers["pbj|team"]("2,7,0,0"); sent = {}
fire(slot(2, 1), "OnDragStart"); drop(slot(2, 3)); fire(slot(2, 1), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,7 | 0,0,0", "slot -> empty slot moves the pet"); eq(setteams(), "2,0,0,7", "move within team: exact setteam")

reset(2)   -- across teams, swap: both teams are sent (target first, then source)
handlers["pbj|team"]("2,7,0,0"); sent = {}
fire(slot(1, 2), "OnDragStart"); drop(slot(2, 1)); fire(slot(1, 2), "OnDragStop")
eq(teamsStr(), "1,7,5 | 3,0,0 | 0,0,0", "slot -> slot across teams swaps"); eq(setteams(), "2,3,0,0 ; 1,1,7,5", "across teams: both teams sent, exact strings")

reset(2)   -- across teams into an empty slot
fire(slot(1, 3), "OnDragStart"); drop(slot(3, 2)); fire(slot(1, 3), "OnDragStop")
eq(teamsStr(), "1,3,0 | 0,0,0 | 0,5,0", "slot -> empty slot in another team"); eq(setteams(), "3,0,5,0 ; 1,1,3,0", "across teams into empty: both sent")

reset(2)   -- drop on its own slot
fire(slot(1, 2), "OnDragStart"); drop(slot(1, 2)); fire(slot(1, 2), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "slot dropped on itself: unchanged")

reset(2)   -- slot dropped outside the window: removed
fire(slot(1, 2), "OnDragStart"); drop("outside"); fire(slot(1, 2), "OnDragStop")
eq(teamsStr(), "1,0,5 | 0,0,0 | 0,0,0", "drop outside window removes from slot"); eq(setteams(), "1,1,0,5", "removal: exact setteam")

reset(2)   -- slot dropped inside the window but not on a slot: nothing
fire(slot(1, 2), "OnDragStart"); drop("window"); fire(slot(1, 2), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "drop on window background keeps the pet"); eq(#sent, 0, "drop on window background sends nothing")

reset(1)   -- list pet dropped outside: nothing changes
fire(rowFor(2), "OnDragStart"); drop("outside"); fire(rowFor(2), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "list drop outside changes nothing"); eq(#sent, 0, "list drop outside sends nothing"); eq(S.drag, nil, "list drop outside clears drag")

reset(1)   -- list pet dropped inside window, not on a slot
fire(rowFor(2), "OnDragStart"); drop("window"); fire(rowFor(2), "OnDragStop")
eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "list drop on background changes nothing"); eq(#sent, 0, "list drop on background sends nothing")

reset(2)   -- CancelDrag
fire(slot(1, 1), "OnDragStart"); ok(S.drag ~= nil and dragFrame.shown, "drag active before cancel")
W.CancelDrag(); eq(S.drag, nil, "CancelDrag clears state"); ok(not dragFrame.shown, "CancelDrag hides the cursor icon")
drop(slot(2, 1)); fire(slot(1, 1), "OnDragStop"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "OnDragStop after cancel does nothing"); eq(#sent, 0, "nothing sent after cancel")

reset(1)   -- hiding the frame cancels a drag
fire(rowFor(4), "OnDragStart"); ok(S.drag ~= nil, "drag active before hide")
SlashCmdList["PETS"](); ok(not frame:IsShown(), "slash toggles the frame closed"); eq(S.drag, nil, "hiding the frame cancels the drag"); ok(not dragFrame.shown, "cursor icon hidden with the frame")
SlashCmdList["PETS"](); ok(frame:IsShown(), "slash reopens the frame")
eq(#sentOf("list"), 1, "reopen asks for the list again"); eq(#sentOf("prime"), 1, "prime sent again while not primed")
handlers["pbj|primed"](); sent = {}; SlashCmdList["PETS"](); SlashCmdList["PETS"](); eq(#sentOf("prime"), 0, "no prime once primed")

reset(1)   -- StartDrag guards
W.StartDrag(0); eq(S.drag, nil, "StartDrag(0) ignored"); W.StartDrag(999); eq(S.drag, nil, "StartDrag(unknown pet) ignored")
fire(rowFor(1), "OnDragStart"); S.pets[1] = nil; handlers["pbj|done"](); eq(S.drag, nil, "drag of a vanished pet is cancelled by Refresh")
feed({ PETS[1] }); handlers["pbj|done"]()

reset(2)   -- removal is announced in chat
chat = {}; fire(slot(1, 2), "OnDragStart"); drop("outside"); fire(slot(1, 2), "OnDragStop")
ok(#chat == 1 and chat[1]:find("Stone Turtle removed from team 1", 1, true), "removal by dropping outside prints a chat line: " .. tostring(chat[1]))

reset(1)   -- OnUpdate poll: the source button vanished, mouse released -> drag ends as a drop
fire(rowFor(2), "OnDragStart"); drop(slot(3, 1)); mouseDown = false; fire(dragFrame, "OnUpdate"); mouseDown = true
eq(teamsStr(), "1,3,5 | 0,0,0 | 2,0,0", "OnUpdate with the button released completes the drop"); eq(S.drag, nil, "drag cleared by OnUpdate poll")
reset(1)
fire(rowFor(2), "OnDragStart"); drop(slot(3, 1)); fire(dragFrame, "OnUpdate"); ok(S.drag ~= nil, "OnUpdate while the button is held keeps dragging"); W.CancelDrag()

reset(1)   -- tooltips
fire(rowFor(4), "OnEnter"); eq(GameTooltip.owner, rowFor(4), "row hover shows the pet tooltip"); fire(rowFor(4), "OnLeave"); ok(not GameTooltip:IsShown(), "row leave hides tooltip")
S.tab = 2; handlers["pbj|done"](); fire(slot(1, 1), "OnEnter"); eq(GameTooltip.owner, slot(1, 1), "slot hover shows tooltip"); fire(slot(2, 1), "OnEnter")   -- empty slot: no error

reset(1)   -- a plain left click never places a pet (drag and drop only), selected or not, and prints nothing
chat = {}; fire(slot(1, 1), "OnClick", "LeftButton"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "left click with no selection changes nothing"); eq(#sent, 0, "left click with no selection sends nothing"); eq(#chat, 0, "left click prints no chat message")
fire(rowFor(7), "OnClick"); eq(S.sel, 7, "clicking a row selects the pet"); eq(sentOf("abil")[1], "7", "selecting asks for the abilities")
S.tab = 2; handlers["pbj|done"](); sent = {}; chat = {}
fire(slot(3, 3), "OnClick", "LeftButton"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "left click on an EMPTY slot with a selected pet changes nothing"); eq(#sent, 0, "left click on empty slot sends nothing")
fire(slot(1, 3), "OnClick", "LeftButton"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "left click on an OCCUPIED slot with a selected pet changes nothing"); eq(#sent, 0, "left click on occupied slot sends nothing")
eq(#chat, 0, "left clicks print nothing"); eq(S.sel, 7, "left click on a slot keeps the selection")
fire(slot(1, 2), "OnClick"); eq(teamsStr(), "1,3,5 | 0,0,0 | 0,0,0", "click with no button argument changes nothing"); eq(#sent, 0, "click with no button sends nothing")

reset(2)   -- right-click empties
fire(slot(1, 3), "OnClick", "RightButton"); eq(teamsStr(), "1,3,0 | 0,0,0 | 0,0,0", "right-click empties the slot"); eq(setteams(), "1,1,3,0", "right-click: exact setteam")
sent = {}; fire(slot(2, 1), "OnClick", "RightButton"); eq(teamsStr(), "1,3,0 | 0,0,0 | 0,0,0", "right-click on an empty slot keeps it empty"); eq(#sent, 0, "right-click on an empty slot sends no setteam")

reset(2)   -- team widgets
ok(slot(1, 1):IsVisible(), "slots visible on the Teams tab"); S.tab = 1; handlers["pbj|done"](); ok(not slot(1, 1):IsVisible(), "slots hidden on the Pets tab")
S.tab = 2; handlers["pbj|done"]()
local actBtn; for _, f in ipairs(created) do if f.kind == "Button" and f.text == "Make active" then actBtn = f; break end end
fire(actBtn, "OnClick"); eq(sentOf("active")[1], "2", "Make active sends the team number"); eq(S.active, 2, "active team updated")

---------------------------------------------------------------- zone globals may be nil (PetPasses guards them)
do
    local sv = { WotlkPetZoneLevels, WotlkPetZoneGroups, WotlkPetSpeciesZones }
    WotlkPetZoneLevels, WotlkPetZoneGroups, WotlkPetSpeciesZones = nil, nil, nil
    eq(ids(W.PetPasses, { filter = "wolf", family = {}, qual = {} }), "1,2,9", "no zone data: name search still works")
    eq(ids(W.PetPasses, { filter = "", family = {}, qual = {}, zone = "Elwynn Forest" }), "", "no zone data: a zone filter matches nothing (no error)")
    eq(ids(W.PetPasses, { filter = "durotar", family = {}, qual = {} }), "", "no zone data: zone search words match nothing (no error)")
    eq(#OPENMENU_(zdd, 1), 1, "no zone data: zone menu is just 'All zones'")
    fire(rowFor(10), "OnEnter"); ok(not lines():find("Found in", 1, true), "no zone data: no 'Found in' line")
    WotlkPetZoneLevels, WotlkPetZoneGroups, WotlkPetSpeciesZones = sv[1], sv[2], sv[3]
end

---------------------------------------------------------------- data test: the real generated ZoneLevels.lua
do
    local chunk, err = loadfile("addons/wotlk_pets/ZoneLevels.lua"); ok(chunk, "ZoneLevels.lua parses: " .. tostring(err))
    local env = {}; setfenv(chunk, env); local good, e = pcall(chunk); ok(good, "ZoneLevels.lua runs: " .. tostring(e))
    local L, G, SZ = env.WotlkPetZoneLevels, env.WotlkPetZoneGroups, env.WotlkPetSpeciesZones
    ok(type(L) == "table" and type(G) == "table" and type(SZ) == "table", "ZoneLevels.lua defines the three globals")
    local nz = 0; for _ in pairs(L) do nz = nz + 1 end; ok(nz > 20, "ZoneLevels has many zones (" .. nz .. ")")
    for z, v in pairs(L) do ok(type(v) == "table" and #v == 4 and type(v[1]) == "number" and type(v[4]) == "number", "zone level row shape: " .. z) end
    local inGroup, dup = {}, 0
    for _, g in ipairs(G) do
        ok(type(g[1]) == "string" and type(g[2]) == "table" and #g[2] > 0, "group shape: " .. tostring(g[1]))
        ok(#g[2] <= 32, "group '" .. tostring(g[1]) .. "' fits one drop-down level (" .. #g[2] .. " <= 32)")
        for _, z in ipairs(g[2]) do
            ok(L[z] ~= nil, "group zone exists in WotlkPetZoneLevels: " .. z)
            if inGroup[z] then dup = dup + 1 end; inGroup[z] = true
        end
    end
    eq(dup, 0, "no zone listed in two groups")
    for z in pairs(L) do ok(inGroup[z], "every WotlkPetZoneLevels zone is in a group: " .. z) end
    local ns = 0
    for sp, zs in pairs(SZ) do
        ns = ns + 1
        if type(sp) ~= "number" or type(zs) ~= "table" or #zs == 0 then ok(false, "species zone row shape: " .. tostring(sp)) end
        for _, z in ipairs(zs) do if not inGroup[z] then ok(false, "species " .. tostring(sp) .. " zone not in any group: " .. tostring(z)) end end
    end
    ok(ns > 100, "WotlkPetSpeciesZones has many species (" .. ns .. ")")
    -- the real data through the real addon: menus build, every continent submenu entry resolves
    ZONEDATA = { levels = L, groups = G, species = SZ }
    loadPets(); SlashCmdList["PETS"](); local zd2 = WotlkPetsZoneDD
    local l1 = OPENMENU_(zd2, 1); eq(#l1, #G + 1, "real data: level 1 has 'All zones' + every continent")
    for i, g in ipairs(G) do eq(#OPENMENU_(zd2, 2, g[1]), #g[2], "real data: level 2 for " .. g[1]) end
    ZONEDATA = nil
end

---------------------------------------------------------------- data test: the real generated PetDex.lua
do
    local chunk, err = loadfile("addons/wotlk_pets/PetDex.lua"); ok(chunk, "PetDex.lua parses: " .. tostring(err))
    local env = {}; setfenv(chunk, env); local good, e = pcall(chunk); ok(good, "PetDex.lua runs: " .. tostring(e))
    local DEX = env.WotlkPetDex; ok(type(DEX) == "table", "PetDex.lua defines WotlkPetDex")
    local n, badFam, badShape = 0, {}, 0
    local RF = {}; for _, f in ipairs({ "Aquatic", "Beast", "Critter", "Dragonkin", "Elemental", "Flying", "Humanoid", "Magic", "Mechanical", "Undead" }) do RF[f] = true end
    for sp, d in pairs(DEX) do
        n = n + 1
        if type(sp) ~= "number" or type(d) ~= "table" or type(d[1]) ~= "string" or d[1] == "" or type(d[2]) ~= "string" or type(d[3]) ~= "string" or d[3] == "" then badShape = badShape + 1 end
        if not RF[d[2]] then badFam[#badFam + 1] = tostring(sp) .. ":" .. tostring(d[2]) end
    end
    eq(n, 1844, "PetDex has 1844 species (1605 wild + 239 companions)"); eq(badShape, 0, "every dex entry is { name, family, icon } with a numeric key"); ok(#badFam == 0, "every dex family is one of the 10 retail families: " .. table.concat(badFam, ","))
    local zfile = loadfile("addons/wotlk_pets/ZoneLevels.lua"); local zenv = {}; setfenv(zfile, zenv); zfile()
    local missing = {}; for sp in pairs(zenv.WotlkPetSpeciesZones) do if not DEX[sp] then missing[#missing + 1] = tostring(sp) end end
    ok(#missing == 0, "every WotlkPetSpeciesZones key exists in the dex: " .. table.concat(missing, ","))
    -- the real dex through the real addon (no owned pets: everything is uncollected)
    ZONEDATA = { levels = zenv.WotlkPetZoneLevels, groups = zenv.WotlkPetZoneGroups, species = zenv.WotlkPetSpeciesZones, dex = DEX }
    loadPets(); SlashCmdList["PETS"](); local W2 = WotlkPets
    eq(WotlkPetsFrame.count.text, "1844 pets", "real dex: all 1844 species listed when nothing is owned"); eq(W2.S.emptyTxt.text, "", "real dex: no empty text")
    OPENMENU_(WotlkPetsViewDD)[2].func(); eq(WotlkPetsFrame.count.text, "0 pets", "real dex: Collected view with nothing owned lists nothing"); OPENMENU_(WotlkPetsViewDD)[1].func()
    ZONEDATA = nil
end

---------------------------------------------------------------- (4b) empty state with no pets at all (fresh load)
loadPets(); SlashCmdList["PETS"](); local f2 = WotlkPetsFrame
eq(WotlkPets.S.emptyTxt.text, "You have no battle pets yet. Capture wild pets in battle.", "no-pets empty-state text"); eq(f2.count.text, "0 pets", "count with no pets")

---------------------------------------------------------------- (5) global leak check
local bad = {}
for _, k in ipairs(added) do
    if not (k:match("^SLASH_PETS%d+$") or k == "WotlkPets" or k == "WotlkPetsFrame" or k == "WotlkPetsSearch" or k == "WotlkPetsScroll" or k == "WotlkPetsFamilyDD" or k == "WotlkPetsQualityDD" or k == "WotlkPetsViewDD" or k == "WotlkPetsZoneDD") then bad[#bad + 1] = k end
end
ok(#bad == 0, "no leaked globals: " .. table.concat(bad, ","))
ok(#undef == 0, "no reads of undefined globals (typo / missing API stub): " .. table.concat(undef, ","))

print(string.format("ui pets: %d assertions, %d failures", asserts, fails))
os.exit(fails == 0 and 0 or 1)
