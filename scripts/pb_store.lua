-- Pet battle STORAGE + journal server side (module "pbj"). One row per owned species per character (a duplicate recruit REPLACES it).
-- Tables (acore_characters): dc_battlepet(guid, species, level, xp, a1, a2, a3)   dc_battleteam(guid, team, slot, species)   dc_battleplayer(guid, active_team)
-- Client -> server: pbj|list  pbj|abil|<species>  pbj|setabil|<species>,<slot>,<opt>  pbj|setteam|<team>,<s1>,<s2>,<s3>  pbj|active|<team>  pbj|addteam  pbj|delteam|<team>
-- Server -> client: pbj|pet|..., pbj|nteams|n, pbj|team|..., pbj|active|n, pbj|done, pbj|abl|...
-- Needs: mod-ale (built and tested with commit 84b85cc) and the shared core scripts acore_*.lua in the same lua_scripts folder.
for _, m in ipairs({ "acore_msg", "acore_prime", "acore_bus", "acore_util", "acore_settings" }) do if not pcall(require, m) then print("[Pet Battles] DISABLED: the shared core script " .. m .. ".lua is missing from lua_scripts (copy all acore_*.lua files, see the README)"); return true end end
local Msg = require("acore_msg")
local D = require("pb_data")
local Eng = require("pb_core")

if PB_STORE then return PB_STORE end   -- the server runs every script AND require() may load it again: keep ONE instance (one cache)
local Store = {}
PB_STORE = Store
local Prime = require("acore_prime")   -- Pet Battles registers its own species for the 3D previews; the core service does the sending
Prime.Register("pets", function() local t = {}; for entry in pairs(D.species or {}) do t[#t + 1] = entry end; return t end)
Prime.SetDisplayResolver(function(player, entry) return Store.PetDisplay and Store.PetDisplay(player, entry) or 0 end)   -- a battle pet shows the skin YOU own
Prime.Enable("pbj")
require("acore_bus").On("companion_learned", function(player) Store.SyncCompanions(player) end, "pets")   -- the Shop taught a companion: straight into the journal
local Info   -- forward declaration (defined below, used by the XP code)
local TEAMS, MAX_TEAMS = 3, 30   -- every player starts with 3 teams and can add more (up to MAX_TEAMS; the addon mirrors it)
local cache = {}   -- guidLow -> { pets = { [species] = {level, xp, a = {1,1,1}} }, teams = { [n] = {s1,s2,s3} }, active = 1 }

-- synchronous on purpose: the SHOW COLUMNS check below runs right away, and on a FRESH database an async CREATE has not run yet (error 1146 aborts worldserver)
CharDBQuery("CREATE TABLE IF NOT EXISTS dc_battlepet (guid INT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, level TINYINT UNSIGNED NOT NULL DEFAULT 1, xp INT UNSIGNED NOT NULL DEFAULT 0, a1 TINYINT NOT NULL DEFAULT 1, a2 TINYINT NOT NULL DEFAULT 1, a3 TINYINT NOT NULL DEFAULT 1, quality TINYINT UNSIGNED NOT NULL DEFAULT 1, display INT UNSIGNED NOT NULL DEFAULT 0, hp INT UNSIGNED NOT NULL DEFAULT 0, hp_at INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (guid, species)) ENGINE=InnoDB")
-- older installs: add the columns that came later (hp 0 = full health)
for _, c in ipairs({ { "quality", "TINYINT UNSIGNED NOT NULL DEFAULT 1" }, { "display", "INT UNSIGNED NOT NULL DEFAULT 0" }, { "hp", "INT UNSIGNED NOT NULL DEFAULT 0" }, { "hp_at", "INT UNSIGNED NOT NULL DEFAULT 0" } }) do
    if not CharDBQuery("SHOW COLUMNS FROM dc_battlepet LIKE '" .. c[1] .. "'") then CharDBExecute("ALTER TABLE dc_battlepet ADD COLUMN " .. c[1] .. " " .. c[2]) end
end
CharDBQuery("CREATE TABLE IF NOT EXISTS dc_battleteam (guid INT UNSIGNED NOT NULL, team TINYINT UNSIGNED NOT NULL, slot TINYINT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, PRIMARY KEY (guid, team, slot)) ENGINE=InnoDB")
CharDBQuery("CREATE TABLE IF NOT EXISTS dc_battlefollower (guid INT UNSIGNED NOT NULL, species INT UNSIGNED NOT NULL, PRIMARY KEY (guid)) ENGINE=InnoDB")
CharDBQuery("CREATE TABLE IF NOT EXISTS dc_battleplayer (guid INT UNSIGNED NOT NULL, active_team TINYINT UNSIGNED NOT NULL DEFAULT 1, PRIMARY KEY (guid)) ENGINE=InnoDB")
if not CharDBQuery("SHOW COLUMNS FROM dc_battleplayer LIKE 'n_teams'") then CharDBExecute("ALTER TABLE dc_battleplayer ADD COLUMN n_teams TINYINT UNSIGNED NOT NULL DEFAULT 3") end

local function Load(guid)
    if cache[guid] then return cache[guid] end
    local c = { pets = {}, teams = {}, active = 1 }
    local q = CharDBQuery("SELECT active_team, n_teams FROM dc_battleplayer WHERE guid=" .. guid)
    local nTeams = TEAMS
    if q then c.active = q:GetUInt32(0); nTeams = math.max(TEAMS, math.min(MAX_TEAMS, q:GetUInt32(1))) end
    for n = 1, nTeams do c.teams[n] = { 0, 0, 0 } end
    if not (c.teams[c.active]) then c.active = 1 end
    q = CharDBQuery("SELECT species, level, xp, a1, a2, a3, quality, display, hp, hp_at FROM dc_battlepet WHERE guid=" .. guid)
    if q then repeat
        c.pets[q:GetUInt32(0)] = { level = q:GetUInt32(1), xp = q:GetUInt32(2), a = { q:GetUInt32(3), q:GetUInt32(4), q:GetUInt32(5) },
                                   quality = math.max(1, q:GetUInt32(6)), display = q:GetUInt32(7), hp = q:GetUInt32(8) > 0 and q:GetUInt32(8) or nil, hpAt = q:GetUInt32(9) }
    until not q:NextRow() end
    q = CharDBQuery("SELECT team, slot, species FROM dc_battleteam WHERE guid=" .. guid)
    if q then repeat
        local t, sl = q:GetUInt32(0), q:GetUInt32(1)
        if c.teams[t] and sl >= 1 and sl <= 3 then c.teams[t][sl] = q:GetUInt32(2) end
    until not q:NextRow() end
    cache[guid] = c
    return c
end

local function SavePet(guid, sp, p)
    CharDBExecute(string.format("REPLACE INTO dc_battlepet (guid, species, level, xp, a1, a2, a3, quality, display, hp, hp_at) VALUES (%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d)",
        guid, sp, p.level, p.xp, p.a[1], p.a[2], p.a[3], p.quality or 1, p.display or 0, p.hp or 0, p.hpAt or 0))
end

-- Health: stored as the value at time hpAt (nil = full); it recovers 1% of max every 10 seconds, also while offline. Computed on demand, nothing ticks.
local function MaxHp(sp, p)
    return Eng.MaxHp(sp, math.min(p.level, D.MAX_LEVEL), p.quality or 1)
end
local function CurHp(sp, p, now)
    local max = MaxHp(sp, p)
    if not p.hp then return max end
    now = now or os.time()
    local ticks = math.floor((now - (p.hpAt or 0)) / D.REGEN_SECONDS)
    local hp = p.hp + math.max(0, ticks) * math.max(1, math.floor(max * D.REGEN_PCT / 100))
    local f = p.fed   -- WELL FED: only valid for the health snapshot it was started from (any other write of hp/hpAt - a battle, a level up, a heal - cancels it)
    if f and f.from == p.hpAt then
        hp = hp + math.max(0, math.floor((math.min(now, f.to) - f.from) / D.FED_STEP)) * math.floor(max * D.FED_PCT / 100)
    end
    return math.min(max, hp)
end
function Store.PetHp(sp, p, now) return CurHp(sp, p, now), MaxHp(sp, p) end
-- after a battle: fainted pets are back with 1 HP, everyone else keeps what is left (by guid, the player may be gone)
function Store.SetHp(guid, species, hp)
    local c = Load(guid); local p = c.pets[species]
    if not p then return end
    local max = MaxHp(species, p)
    hp = math.max(1, math.floor(hp))
    p.fed = nil
    if hp >= max then p.hp, p.hpAt = nil, 0 else p.hp, p.hpAt = hp, os.time() end
    SavePet(guid, species, p)
end

-- admin: every owned pet back to full health (nil hp = full)
function Store.HealAll(player)
    local guid = player:GetGUIDLow(); local c = Load(guid); local n = 0
    for species, p in pairs(c.pets) do
        p.hp, p.hpAt, p.fed = nil, 0, nil; SavePet(guid, species, p); n = n + 1
        pcall(Msg.Send, player, "pbj", "pet", Info(species, p))   -- refresh the open journal
    end
    return n
end
RegisterPlayerEvent(42, function(_, player, command)   -- .pbheal (GM only)
    if not player or not command or not command:match("^pbheal%s*$") then return end
    if player:GetGMRank() < 2 then return end
    player:SendBroadcastMessage("Healed " .. Store.HealAll(player) .. " battle pets to full health.")
    return false
end)

-- .pbtypes (GM only): one level-1 pet of every pet TYPE the character does not own yet (to check the journal's type icons). Uses the same AddPet a capture uses.
local TYPES = { "Humanoid", "Dragonkin", "Flying", "Undead", "Critter", "Magic", "Elemental", "Mechanical", "Aquatic", "Beast" }
RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command or not command:match("^pbtypes%s*$") then return end
    if player:GetGMRank() < 2 then return end
    local c = Load(player:GetGUIDLow()); local have = {}
    for sp in pairs(c.pets) do local ok, f = pcall(Eng.Family, sp); if ok and f then have[f] = true end end
    local ids = {}; for e, sp in pairs(D.species) do if not sp.dex then ids[#ids + 1] = e end end; table.sort(ids)
    local added = {}
    for _, fam in ipairs(TYPES) do
        if not have[fam] then
            for _, e in ipairs(ids) do
                local ok, f = pcall(Eng.Family, e)
                if ok and f == fam then
                    if Store.AddPet(player, e, 1, { 1, 1, 1 }, 1, 0) then
                        added[#added + 1] = fam .. ": " .. tostring(D.species[e].name)
                        pcall(Msg.Send, player, "pbj", "pet", Info(e, Load(player:GetGUIDLow()).pets[e]))
                    end
                    break
                end
            end
        end
    end
    player:SendBroadcastMessage(#added > 0 and ("Added one pet of each missing type: " .. table.concat(added, "; ")) or "You already own every pet type.")
    return false
end)

-- Recruiting: a duplicate species REPLACES the owned one (better versions). Returns true when stored.
function Store.AddPet(player, species, level, picks, quality, display)
    if not D.species[species] then return false end
    local g = player:GetGUIDLow(); local c = Load(g)
    c.pets[species] = { level = level or 1, xp = 0, a = { (picks and picks[1]) or 1, (picks and picks[2]) or 1, (picks and picks[3]) or 1 },
                        quality = math.max(1, math.min(4, quality or 1)), display = display or 0 }
    SavePet(g, species, c.pets[species])
    if (display or 0) > 0 then Prime.SendOne(player, species, display) end   -- the journal preview shows THIS skin
    return true
end
-- CAPTURE (retail trap): the captured pet keeps its level, quality and skin. One per species: a better version (quality, then level) replaces the owned one, otherwise the capture is released.
function Store.Capture(player, pet)
    local c = Load(player:GetGUIDLow()); local owned = c.pets[pet.species]
    local q, lvl = pet.quality or 1, math.min(pet.level, D.MAX_LEVEL)
    if owned and ((owned.quality or 1) > q or ((owned.quality or 1) == q and owned.level >= lvl)) then
        return "You captured " .. pet.name .. ", but you already own a better one, so it was released.", false
    end
    Store.AddPet(player, pet.species, lvl, { math.random(1, 2), math.random(1, 2), math.random(1, 2) }, q, pet.display)
    Msg.Send(player, "pbj", "pet", Info(pet.species, Load(player:GetGUIDLow()).pets[pet.species]))
    return "You captured " .. pet.name .. "!" .. (owned and " It replaces the one you had." or ""), true, q
end
-- the skin of the pet you own (one per species): saved the first time it is seen so it never changes by chance
function Store.PetDisplay(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and p.display or 0 end
function Store.SetDisplay(player, species, display)
    local g = player:GetGUIDLow(); local p = Load(g).pets[species]
    if p and (p.display or 0) == 0 and display and display > 0 then
        p.display = display; SavePet(g, species, p)
        Prime.SendOne(player, species, display)
    end
end

-- Real companion journal -> battle pets: every companion the character knows whose creature is a defined species becomes a level 1 pet
-- (never overwrites an owned one). Spell -> creature map = world.dc_companion (tools/gen_companions.py).
local COMP = {}   -- species entry -> { spells }
do
    local q = WorldDBQuery("SELECT spell, npc FROM dc_companion")
    if q then repeat
        local npc = q:GetUInt32(1)
        if D.species[npc] then COMP[npc] = COMP[npc] or {}; table.insert(COMP[npc], q:GetUInt32(0)) end
    until not q:NextRow() end
end
Store.COMP = COMP   -- companion creature -> { spells } (tests)
-- Idempotent: a companion creature that is a species becomes a level 1 journal pet ONCE (only when the character does not own that species yet, so a leveled pet is never reset and
-- no duplicate row can appear however often this runs: login, journal open, battle start, right after a shop purchase).
function Store.SyncCompanions(player)
    local g = player:GetGUIDLow(); local c = Load(g); local added = 0
    for npc, spells in pairs(COMP) do
        if not c.pets[npc] then
            for _, sp in ipairs(spells) do
                if player:HasSpell(sp) then Store.AddPet(player, npc, 1); added = added + 1; break end
            end
        end
    end
    return added
end

-- XP: reward depends on the PET's level vs the enemy level; a pet must have acted in the battle (checked by the caller)
function Store.XPReward(petLevel, enemyLevel)
    local base = Eng.XPPerWin(enemyLevel)   -- retail table: a win is worth the XpPerWin of the enemy's level
    local diff = petLevel - enemyLevel
    if diff <= 0 then return base end
    local f = 1 - diff * D.XP_STEP   -- our rule: -20% per level the enemy is BELOW the pet, nothing at 5+ below (no power leveling)
    return f > 0.001 and math.floor(base * f + 0.5) or 0
end
-- returns gained xp, new level, levels gained (nil if the pet is not owned)
function Store.GrantXP(player, species, enemyLevel)
    local g = player:GetGUIDLow(); local c = Load(g); local p = c.pets[species]
    if not p then return nil end
    if p.level >= D.MAX_LEVEL then return 0, p.level, 0 end
    local gain, start = Store.XPReward(p.level, enemyLevel), p.level
    p.xp = p.xp + gain
    while p.xp >= Eng.XPNeeded(p.level) and p.level < D.MAX_LEVEL do p.xp = p.xp - Eng.XPNeeded(p.level); p.level = p.level + 1 end
    if p.level >= D.MAX_LEVEL then p.xp = 0 end
    if p.level > start then p.hp, p.hpAt, p.fed = nil, nil, nil end   -- a level up heals the pet fully (nil = full health)
    SavePet(g, species, p)
    Msg.Send(player, "pbj", "pet", Info(species, p))
    return gain, p.level, p.level - start
end
function Store.Pets(player) return Load(player:GetGUIDLow()).pets end   -- (tests)
function Store.OwnedQuality(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and (p.quality or 1) or 0 end
-- how a wild pet (quality q, level lvl) compares with our collection: 0 = not collected, 1 = it would be an upgrade (same rule as Capture), 2 = we own the same or better. Also returns the owned quality / level.
function Store.Compare(player, species, q, lvl)
    local o = Load(player:GetGUIDLow()).pets[species]
    if not o then return 0, 0, 0 end
    local oq = o.quality or 1
    if (q or 1) > oq or ((q or 1) == oq and math.min(lvl, D.MAX_LEVEL) > o.level) then return 1, oq, o.level end
    return 2, oq, o.level
end
function Store.PushPet(player, species) local p = Load(player:GetGUIDLow()).pets[species]; if p then Msg.Send(player, "pbj", "pet", Info(species, p)) end end
function Store.OwnedLevel(player, species) local p = Load(player:GetGUIDLow()).pets[species]; return p and p.level or 0 end

-- the active team as engine input: { {species, level, picks}, ... } (empty slots dropped)
local function SaveTeam(g, n, sl)
    CharDBExecute("DELETE FROM dc_battleteam WHERE guid=" .. g .. " AND team=" .. n)
    for i = 1, 3 do if sl[i] ~= 0 then CharDBExecute(string.format("INSERT INTO dc_battleteam (guid, team, slot, species) VALUES (%d,%d,%d,%d)", g, n, i, sl[i])) end end
end
local function SavePlayer(g, c)
    CharDBExecute(string.format("REPLACE INTO dc_battleplayer (guid, active_team, n_teams) VALUES (%d,%d,%d)", g, c.active, #c.teams))
end
local function SendTeams(player, c)
    Msg.Send(player, "pbj", "nteams", #c.teams)
    for n = 1, #c.teams do Msg.Send(player, "pbj", "team", n .. "," .. c.teams[n][1] .. "," .. c.teams[n][2] .. "," .. c.teams[n][3]) end
    Msg.Send(player, "pbj", "active", c.active)
end
function Store.ActiveTeam(player)
    local g = player:GetGUIDLow(); local c = Load(g)
    -- no team set up yet: use (and save) the three highest level pets so a battle is never a dead end
    local have = false
    for _, sp in ipairs(c.teams[c.active] or {}) do if sp ~= 0 and c.pets[sp] then have = true end end
    if not have then
        local list = {}
        for sp, p in pairs(c.pets) do list[#list + 1] = sp end
        table.sort(list, function(a, b) if c.pets[a].level ~= c.pets[b].level then return c.pets[a].level > c.pets[b].level end return a < b end)
        if #list > 0 then
            local sl = { list[1] or 0, list[2] or 0, list[3] or 0 }
            c.teams[c.active] = sl; SaveTeam(g, c.active, sl)
            Msg.Send(player, "pbj", "team", c.active .. "," .. sl[1] .. "," .. sl[2] .. "," .. sl[3])
            Msg.Send(player, "pbt", "msg", "No team was set up: using your highest level pets. Change it in /pets > Teams.")
        end
    end
    local out = {}
    for _, sp in ipairs(c.teams[c.active] or {}) do
        local p = c.pets[sp]
        if sp ~= 0 and p then out[#out + 1] = { species = sp, level = p.level, picks = { p.a[1], p.a[2], p.a[3] }, quality = p.quality or 1, display = p.display or 0, hp = CurHp(sp, p) } end
    end
    return out
end

function Info(sp, p)
    local s = D.species[sp]
    local lvl = math.min(p.level, D.MAX_LEVEL)
    local st = Eng.Stats(sp, lvl, p.quality or 1)
    local cur, max = CurHp(sp, p), MaxHp(sp, p)
    return string.format("%d,%d,%d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%s", sp, lvl, p.xp, p.a[1], p.a[2], p.a[3], Eng.Family(sp), s.icon,
        max, math.floor(st.power + 0.5), p.quality or 1, cur, Eng.XPNeeded(lvl), s.name)
end

local function SendAll(player)
    local c = Load(player:GetGUIDLow())
    for sp, p in pairs(c.pets) do if D.species[sp] then Msg.Send(player, "pbj", "pet", Info(sp, p)) end end
    SendTeams(player, c)
    Msg.Send(player, "pbj", "follow", Store.Follower and Store.Follower(player) or 0)
    Msg.Send(player, "pbj", "done", "")
end

-- ---------------------------------------------------------------- feeding (cooking): food gives the pet a WELL FED buff = +FED_PCT% of max health every FED_STEP s for FED_SECONDS s
-- food = a Food item (class 0, subclass 5, food spell category 11; drinks are category 59); its level = RequiredLevel (0 counts as 1) and must be >= the pet's level
local foodLevel = {}
local function FoodLevel(entry)
    if foodLevel[entry] == nil then
        local q = WorldDBQuery("SELECT RequiredLevel FROM item_template WHERE entry=" .. entry .. " AND class=0 AND subclass=5 AND spellcategory_1=11")
        foodLevel[entry] = q and math.max(1, q:GetUInt32(0)) or false
    end
    return foodLevel[entry] or nil
end
Store.FoodLevel = FoodLevel
-- returns ok, message
function Store.Feed(player, species, entry)
    if PB_BATTLE and PB_BATTLE.InBattle(player) then return false, "Pets cannot be fed during a battle." end
    local guid = player:GetGUIDLow(); local c = Load(guid); local p = c.pets[species]
    if not p then return false, "You do not own that pet." end
    local name = D.species[species].name
    local lv = entry and FoodLevel(entry)
    if not lv then return false, "That is not food a pet can eat." end
    if player:GetItemCount(entry) < 1 then return false, "You do not have that food." end
    local now = os.time(); local cur, max = CurHp(species, p, now), MaxHp(species, p)
    if cur >= max then return false, name .. " is already at full health." end
    if lv < p.level then return false, "That food is too weak for a level " .. p.level .. " pet: it needs a food of level " .. p.level .. " or more." end
    player:RemoveItem(entry, 1)
    p.hp, p.hpAt = cur, now; p.fed = { from = now, to = now + D.FED_SECONDS }   -- start from the health the pet has right now (a re-feed restarts the buff)
    SavePet(guid, species, p)
    local low, pguid = guid, player:GetGUID()   -- the Player OBJECT is invalid once this call returns (ALE): keep only the GUID value and find the player again in the timer
    CreateLuaEvent(function()   -- the journal shows the health climbing: one refresh per step while the buff runs
        local pl = GetPlayerByGUID and GetPlayerByGUID(pguid)
        local cp = Load(low).pets[species]
        if pl and cp then pcall(Msg.Send, pl, "pbj", "pet", Info(species, cp)) end
    end, D.FED_STEP * 1000, math.floor(D.FED_SECONDS / D.FED_STEP) + 1)
    Msg.Send(player, "pbj", "pet", Info(species, p))
    return true, name .. " is well fed and recovers health for " .. D.FED_SECONDS .. " seconds."
end
Msg.On("pbj", "feed", function(player, payload)
    local sp, entry = payload:match("^(%d+),(%d+)$"); sp, entry = tonumber(sp), tonumber(entry)
    if not sp then return end
    local ok, text = Store.Feed(player, sp, entry)
    Msg.Send(player, "pbt", "msg", text)
end)
Msg.On("pbj", "list", function(player) Store.SyncCompanions(player); SendAll(player) end)
Msg.On("pbj", "abil", function(player, payload)   -- the 6 abilities of one species (2 options per slot)
    local sp = tonumber(payload); local s = sp and D.species[sp]
    if not s then return end
    local mine = Load(player:GetGUIDLow()).pets[sp]   -- the numbers in the text are THIS pet's: its level and quality decide its power (a species you do not own yet is shown at level 1)
    local power = Eng.Stats(sp, mine and mine.level or 1, mine and mine.quality or 1).power
    for _, k in ipairs(Eng.Kit(sp)) do
        local a = k.ability
        local tip = Eng.Describe(a, power):gsub("[#|~;]", " ")
        local nm = a.name:gsub("[#|~;]", " ")
        local room = math.min(170, 240 - (#("pbj|abl|" .. sp .. ",3,2|") + #a.icon + #nm + #tostring(a.cd) + #tostring(k.unlock) + 6))   -- addon messages are limited to 240 characters: the tip gets what icon + name leave (flavored spell names are longer than retail's)
        if #tip > room then local cut = tip:sub(1, room); local dot = cut:match("^.*()%. "); tip = (dot and dot > room / 2) and cut:sub(1, dot) or (cut:sub(1, room - 3) .. "...") end
        Msg.Send(player, "pbj", "abl", sp .. "," .. k.slot .. "," .. k.opt .. "|" .. a.icon .. "#" .. nm .. "#" .. tip .. "#" .. a.cd .. "#" .. k.unlock)
    end
end)
Msg.On("pbj", "setabil", function(player, payload)
    local sp, slot, opt = payload:match("^(%d+),(%d),(%d)$"); sp, slot, opt = tonumber(sp), tonumber(slot), tonumber(opt)
    local g = player:GetGUIDLow(); local c = Load(g)
    if not (sp and c.pets[sp] and slot and slot >= 1 and slot <= 3 and (opt == 1 or opt == 2)) then return end
    c.pets[sp].a[slot] = opt; SavePet(g, sp, c.pets[sp])
    Msg.Send(player, "pbj", "pet", Info(sp, c.pets[sp]))
end)
Msg.On("pbj", "setteam", function(player, payload)
    local n, a, b, d = payload:match("^(%d+),(%d+),(%d+),(%d+)$"); n = tonumber(n)
    local g = player:GetGUIDLow(); local c = Load(g)
    if not (n and c.teams[n]) then return end
    local sl, seen = { tonumber(a), tonumber(b), tonumber(d) }, {}
    for i = 1, 3 do
        if sl[i] ~= 0 and (not c.pets[sl[i]] or seen[sl[i]]) then SendAll(player); return end   -- not owned / twice: resend the truth
        seen[sl[i]] = true
    end
    c.teams[n] = sl
    SaveTeam(g, n, sl)
    Msg.Send(player, "pbj", "team", n .. "," .. sl[1] .. "," .. sl[2] .. "," .. sl[3])
end)
Msg.On("pbj", "active", function(player, payload)
    local n = tonumber(payload); local g = player:GetGUIDLow(); local c = Load(g)
    if not (n and c.teams[n]) then return end
    c.active = n
    SavePlayer(g, c)
    Msg.Send(player, "pbj", "active", n)
end)
Msg.On("pbj", "addteam", function(player)
    local g = player:GetGUIDLow(); local c = Load(g)
    if #c.teams >= MAX_TEAMS then return end
    c.teams[#c.teams + 1] = { 0, 0, 0 }
    SavePlayer(g, c); SendTeams(player, c)
end)
Msg.On("pbj", "delteam", function(player, payload)   -- later teams move up one number; the last team can never be deleted
    local n = tonumber(payload); local g = player:GetGUIDLow(); local c = Load(g)
    if not (n and c.teams[n]) or #c.teams <= 1 then return end
    table.remove(c.teams, n)
    if c.active == n then c.active = math.min(n, #c.teams) elseif c.active > n then c.active = c.active - 1 end
    CharDBExecute("DELETE FROM dc_battleteam WHERE guid=" .. g .. " AND team>=" .. n)
    for k = n, #c.teams do SaveTeam(g, k, c.teams[k]) end
    SavePlayer(g, c); SendTeams(player, c)
end)
RegisterPlayerEvent(4, function(_, player) cache[player:GetGUIDLow()] = nil end)   -- logout

-- ---------------------------------------------------------------- size normalization (shared by battle + follower)
-- A pet is SMALL. Scaling to a fixed bounding RADIUS alone made tall thin models bigger than their normal size (a Defias Bandit, radius 0.31, came out at 1.3x; a rabbit at 1.5x),
-- so the height (combat reach) is capped as well: whichever of the two gives the smaller scale wins. Explicit D.species[..].scale still overrides.
local TARGET_RADIUS, TARGET_REACH = 0.40, 0.75
local MIN_SCALE, MAX_SCALE = 0.1, 1.5   -- (long sea creatures like the Wavethrashers need 0.1 to be pet sized)
local function ScaleFor(radius, reach)   -- radius / reach from creature_model_info; nil or ~0 = unknown
    local sc
    if radius and radius > 0.05 then sc = TARGET_RADIUS / radius end
    if reach and reach > 0.05 then local r2 = TARGET_REACH / reach; sc = sc and math.min(sc, r2) or r2 end
    if not sc then return 0.4 end
    return math.max(MIN_SCALE, math.min(MAX_SCALE, sc))
end
Store.ScaleFor = ScaleFor
local SCALE = {}
for entry, sp in pairs(D.species) do
    local q = WorldDBQuery("SELECT cmi.BoundingRadius, cmi.CombatReach FROM creature_template_model m JOIN creature_model_info cmi ON cmi.DisplayID=m.CreatureDisplayID WHERE m.CreatureID=" .. entry .. " AND m.Idx=0")
    SCALE[entry] = sp.scale or (sp.companion and 1.0) or ScaleFor(   -- companion creatures (cubs, cats, squirrels) are ALREADY pet sized: shrinking them to a normal creature's size made the Dun Morogh Cub microscopic
        q and q:GetFloat(0) or 0, q and q:GetFloat(1) or 0)
end
-- ONE PET SIZE: every pet is scaled so its TRUE visible size S is PET_SIZE yards. S = sqrt(mean of the top / side / front silhouette areas) measured from the real model mesh in the client
-- archives (pet-battle/gen_model_size.py -> gen_scale_caps.py -> scripts/pb_scale_caps.lua, third value), times the display scale: the same S looks the same size for a cube-like gorilla
-- and a leggy spider (a bounding box does not: it counts empty space). PET_SIZE = the median size of the 3.3.5 companion pets (0.53). Companions keep their natural size (never resized).
-- A species whose mesh could not be measured falls back to the old radius-based scale above.
local PET_SIZE, MIN_S, MAX_S = 0.53, 0.02, 8.0
-- SWAP-ONLY DRAWING (2026-11-23, measured): the client treats a display differently when a creature is CREATED with it (k unpredictable: some models follow, some ignore) and when it is SWAPPED on
-- with SetDisplayId over a different display (k_eff = max(k, 0.63), the same for every model). Every stand-in template is therefore INVISIBLE (display 11686, custom-sql/017) and every spawn
-- site dresses it with the pet's real display right away (Store.Dress), so the scale formula only needs the swap rule (gen_scale_caps.py EFF).
local displayCache = {}
function Store.PickDisplay(species)   -- a random model row of the species' real template (the models the stand-in used to carry)
    local list = displayCache[species]
    if not list then
        list = {}
        local q = WorldDBQuery and WorldDBQuery("SELECT CreatureDisplayID FROM creature_template_model WHERE CreatureID = " .. species .. " ORDER BY Idx")
        if q then repeat list[#list + 1] = q:GetUInt32(0) until not q:NextRow() end
        displayCache[species] = list
    end
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end
function Store.Dress(obj, species, display)   -- swap the invisible stand-in to the pet's real skin (display given, or a random one of the species); returns the display worn
    local d = (display and display > 0) and display or Store.PickDisplay(species)
    if d and d > 0 then pcall(function() obj:SetDisplayId(d) end); return d end
    return nil
end
local DIM = require("pb_scale_caps")
function Store.Scale(entry)
    local d = DIM[entry]
    local S = d and d[3] or 0
    if S <= 0.01 then return SCALE[entry] or 0.4 end
    local sp = D.species[entry]
    local sc
    if sp and sp.companion then sc = sp.scale or 1.0   -- companions are REAL creatures: always their natural size, never resized
    else sc = PET_SIZE / S end
    return math.max(MIN_S, math.min(MAX_S, sc))
end
function Store.Width(entry) local d = DIM[entry]; return d and d[3] > 0.01 and d[3] * Store.Scale(entry) or nil end   -- the true visible size S in yards
-- The scale FOLLOWS THE MODEL ON SCREEN: a species can show several models (the Crab has 4 of very different size), so the size comes from the creature DISPLAY id actually worn
-- (pb_scale_displays.lua), falling back to the species default.
local DSZ = require("pb_scale_displays")
function Store.ScaleOf(entry, display)
    local S = display and DSZ[display]
    if not S or S <= 0.01 then return Store.Scale(entry) end
    local sp = D.species[entry]
    local sc
    if sp and sp.companion then sc = sp.scale or 1.0   -- companions are REAL creatures: always their natural size, never resized
    else sc = PET_SIZE / S end
    sc = math.max(MIN_S, math.min(MAX_S, sc))
    return sc
end
function Store.SizeOf(entry, display) local S = display and DSZ[display]; if S and S > 0.01 then return S * Store.ScaleOf(entry, display) end return Store.Width(entry) end   -- true visible size in yards

-- ---------------------------------------------------------------- FOLLOWER: the summoned pet that walks behind you
-- One per player. Desired only while: alive, not mounted, not in a battle. It follows its owner through phases.
-- A single 2 s tick keeps it right (respawns it after a teleport / zone change / dismount). Not saved to the world DB.
local follow = {}        -- guidLow -> { species, obj = creature guid, map = id }
local suppressed = {}    -- guidLow -> true while a battle runs
local tickEv
local FOLLOW_LEAVE = 22  -- farther than this (or other map) = respawn next to the player

-- GMs have the "all phases" mask (0xFFFFFFFF) instead of 1: that still counts as the normal world; garrison phases are single other bits
local function NormalWorld(player) local m = player:GetPhaseMask(); return m == 1 or m < 0 or m >= 0x7FFFFFFF end
Store.NormalWorld = NormalWorld
function Store.FollowPhase(player) if NormalWorld(player) then return 1 end return player:GetPhaseMask() end   -- the phase a follower must be in to be seen with its owner

function Store.IsFollower(low) for _, f in pairs(follow) do if f.low == low then return true end end return false end   -- low = numeric low guid (GUID objects never compare equal)
function Store.SetSuppressed(player, on) suppressed[player:GetGUIDLow()] = on or nil end

local function Despawn(f)
    if f.obj then
        local map = f.map and GetMapById(f.map, 0)
        local o = map and map:GetWorldObject(f.obj)
        if o then pcall(function() o:DespawnOrUnsummon(0) end) end
    end
    f.obj, f.low, f.map = nil, nil, nil
end

-- every follower runs faster than its owner (30 % + a floor), whatever the creature template says: no pet falls behind
local function Pace(obj, pl)
    local rate = math.max(1.4, (pl:GetSpeed(1) / 7) * 1.3)
    pcall(function() obj:SetWalk(false) end)
    pcall(function() obj:SetSpeed(1, rate, true) end)
end

local function SpawnFollower(player, f)
    local x, y, z, o = player:GetX(), player:GetY(), player:GetZ(), player:GetO()
    local ph = Store.FollowPhase(player)   -- the pet lives in whatever phase its owner is in
    local px, py = x - math.cos(o) * 2 + math.cos(o + 1.57) * 1, y - math.sin(o) * 2 + math.sin(o + 1.57) * 1
    -- EVERY follower is born far underground and lifted to its spot after 3 s, with a small portal marking the spot: the client's first draw of a model is always full size, so that moment happens hidden by the terrain
    local sz, gz = z, z
    do local okh, gh = pcall(function() return player:GetMap():GetHeight(px, py, z) end); gz = math.min(z, (okh and gh and gh > -1000) and gh or z); sz = gz - 40 end
    local obj = PerformIngameSpawn(1, D.StandIn(f.species) or f.species, player:GetMapId(), 0, px, py, sz, o, false, 0, ph)
    if not obj then return end
    f.obj, f.low, f.map = obj:GetGUID(), obj:GetGUIDLow(), player:GetMapId()     -- registered immediately, configured after
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetFaction(35) end)
    local disp = Store.PetDisplay(player, f.species)
    do
        local d = (disp and disp > 0) and disp or Store.PickDisplay(f.species)
        local sc = Store.ScaleOf(f.species, d)
        Store.Dress(obj, f.species, d)
        pcall(function() obj:SetScale(sc) end)
        if not (disp and disp > 0) and d then Store.SetDisplay(player, f.species, d) end
        f.holdUntil = os.time() + 5
        local okp, portal = pcall(function() return PerformIngameSpawn(2, 142074, player:GetMapId(), 0, px, py, gz, o, false, 0, ph) end)   -- 142074 Bly's Escape Portal: the warlock portal look (display 1327), type 5 = decoration, not clickable, template size 1 (179705 was 1.5)
        local portalG = okp and portal and portal:GetGUID() or nil
        local low, fm, pg = obj:GetGUIDLow(), player:GetMapId(), f.pguid
        CreateLuaEvent(function()
            local map = GetMapById(fm, 0); local o2 = map and f.obj and map:GetWorldObject(f.obj)
            if portalG then local pm = GetMapById(fm, 0); local pg2 = pm and pm:GetWorldObject(portalG); if pg2 then pcall(function() pg2:RemoveFromWorld(false) end) end end
            local pl = GetPlayerByGUID(pg)
            if not o2 or o2:GetGUIDLow() ~= low or not pl then return end
            local x2, y2, z2, r2 = pl:GetX(), pl:GetY(), pl:GetZ(), pl:GetO()
            pcall(function() o2:NearTeleport(x2 - math.cos(r2) * 2 + math.cos(r2 + 1.57), y2 - math.sin(r2) * 2 + math.sin(r2 + 1.57), z2, r2) end)
            pcall(function() o2:CastSpell(o2, 12244, true) end)   -- Poof (instant, checked by check_fx.py)
            Pace(o2, pl)
            pcall(function() o2:MoveFollow(pl, 1.8, 2.6) end)
        end, 3000, 1)
    end
end

local function Tick()
    local any = false
    for g, f in pairs(follow) do
        any = true
        local pl = GetPlayerByGUID(f.pguid)
        if not pl then Despawn(f); follow[g] = nil
        else
            local want = pl:IsAlive() and not pl:IsMounted() and not suppressed[g]
            local obj
            if f.obj then local map = GetMapById(f.map, 0); obj = map and map:GetWorldObject(f.obj) end
            if not want then Despawn(f)
            elseif f.holdUntil and os.time() < f.holdUntil and obj then   -- still settling underground: leave it alone
            elseif not obj or pl:GetMapId() ~= f.map or pl:GetDistance(obj) > FOLLOW_LEAVE then Despawn(f); SpawnFollower(pl, f)
            else
                local ph = Store.FollowPhase(pl); local okm, cur = pcall(function() return obj:GetPhaseMask() end)
                if okm and cur ~= ph then pcall(function() obj:SetPhaseMask(ph, true) end) end   -- owner changed phase (garrison, quest phase...): the pet goes along
                Pace(obj, pl)
                if pl:GetDistance(obj) > 4 then pcall(function() obj:MoveFollow(pl, 1.8, 2.6) end) end
            end
        end
    end
    if not any and tickEv then RemoveEventById(tickEv); tickEv = nil end
end

local function SendFollow(player, species) Msg.Send(player, "pbj", "follow", species or 0) end
local function SetFollower(player, species)   -- species 0 / nil = dismiss
    local g = player:GetGUIDLow()
    if follow[g] then Despawn(follow[g]); follow[g] = nil end
    if species and species ~= 0 then
        follow[g] = { species = species, pguid = player:GetGUID() }
        if not tickEv then tickEv = CreateLuaEvent(Tick, 2000, 0) end
        CreateLuaEvent(Tick, 200, 1)   -- appear right away
        CharDBExecute(string.format("REPLACE INTO dc_battlefollower (guid, species) VALUES (%d,%d)", g, species))
    else CharDBExecute("DELETE FROM dc_battlefollower WHERE guid=" .. g) end
    SendFollow(player, species)
end
function Store.Follower(player) local f = follow[player:GetGUIDLow()]; return f and f.species or 0 end

Msg.On("pbj", "summon", function(player, payload)
    local sp = tonumber(payload); local c = Load(player:GetGUIDLow())
    if sp and c.pets[sp] then SetFollower(player, sp) end
end)
Msg.On("pbj", "dismiss", function(player) SetFollower(player, 0) end)

function Store.IsHuman(player)   -- playerbots (300 of them) never get pet features: no wild pets, no saved followers, no database lookups
    return not require("acore_util").IsBot(player)
end
local function Restore(player)   -- login / script load: bring the last summoned pet back
    if not Store.IsHuman(player) then return end
    local g = player:GetGUIDLow()
    if follow[g] then return end
    local q = CharDBQuery("SELECT species FROM dc_battlefollower WHERE guid=" .. g)
    if q and D.species[q:GetUInt32(0)] then
        local c = Load(g)
        if c.pets[q:GetUInt32(0)] then SetFollower(player, q:GetUInt32(0)) end
    end
end
RegisterPlayerEvent(3, function(_, player) pcall(Store.SyncCompanions, player); if Store.IsHuman(player) then SetFollower(player, 0) end end)   -- login: companions the character already knows are in the journal; every pet is DISMISSED (saved follower cleared) so nothing is left over from the last session. A script reload still restores it (Restore below)
RegisterPlayerEvent(4, function(_, player)   -- logout: remove the follower
    local g = player:GetGUIDLow()
    if follow[g] then Despawn(follow[g]); follow[g] = nil end
    suppressed[g] = nil
end)
pcall(function() for _, pl in ipairs(GetPlayersInWorld()) do Restore(pl) end end)   -- script reload: pets come back


return Store
