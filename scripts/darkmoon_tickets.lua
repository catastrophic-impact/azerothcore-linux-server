-- ============================================================
-- Darkmoon Faire Prize Ticket rewards (replaces timewalking_rewards.lua)
-- * Bosses are AUTO-DETECTED from world.instance_encounters (+ heroic difficulty entries). No hand list.
-- * Every real player in the killer's group on the same instance map gets tickets. Playerbots never do.
-- * Final bosses (instance_encounters.lastEncounterDungeon > 0) also give, outside Dungeon Finder:
--     25% of current level's XP, level-scaled gold, level-scaled satchel (same as the old script).
-- * Leaving a dungeon/raid resets Hearthstone cooldown (old behaviour; switch below).
-- ============================================================
local Msg = require("acore_msg")
local Settings = require("acore_settings")
local RW = Settings.rewards or {}
local REWARD_ITEM = (RW.item and RW.item ~= 0) and RW.item or nil   -- nil = no extra item reward

local CFG = {
    DEBUG            = false,
    TICKET_ITEM      = REWARD_ITEM,   -- from acore_settings.lua (nil = off)
    TICKETS_BOSS     = 2,
    TICKETS_FINAL    = 5,
    XP_PERCENT       = 0.25,
    RESET_HEARTHSTONE = RW.resetHearthstoneOnDungeonExit ~= false,
    HEARTHSTONE_SPELL = 8690,
}

local GOLD = {
    { 15, 25, 10 }, { 26, 35, 20 }, { 36, 45, 30 }, { 46, 55, 40 },
    { 56, 60, 50 }, { 61, 64, 60 }, { 65, 70, 70 }, { 71, 80, 80 },
}
local SATCHELS = {   -- stock "Satchel of Helpful Goods" items; none for WotLK range (as before)
    { 15, 25, 51999 }, { 26, 35, 52000 }, { 36, 45, 52001 }, { 46, 55, 52002 },
    { 56, 60, 52003 }, { 61, 64, 52004 }, { 65, 70, 52005 },
}

local function dbg(...) if CFG.DEBUG then print("[tickets] " .. table.concat({...}, " ")) end end

-- ---- boss table (entry -> isFinal) ----
local BOSSES = {}
local function LoadBosses()
    local n = 0
    local q = WorldDBQuery("SELECT e.creditEntry, e.lastEncounterDungeon > 0, c.difficulty_entry_1, c.difficulty_entry_2, c.difficulty_entry_3 " ..
                           "FROM instance_encounters e LEFT JOIN creature_template c ON c.entry = e.creditEntry WHERE e.creditType = 0")
    if not q then print("[tickets] no instance_encounters rows!"); return end
    repeat
        local final = q:GetUInt32(1) == 1
        for _, col in ipairs({ 0, 2, 3, 4 }) do
            local e = q:GetUInt32(col)
            if e and e > 0 then
                if BOSSES[e] == nil then n = n + 1 end
                BOSSES[e] = BOSSES[e] or final   -- keep "final" if any row says so
            end
        end
    until not q:NextRow()
    print("[tickets] " .. n .. " boss entries loaded")
end
LoadBosses()

-- ---- helpers ----
local function Lookup(tbl, level)
    for _, r in ipairs(tbl) do if level >= r[1] and level <= r[2] then return r[3] end end
end

local xpCache = {}
local function LevelXP(level)
    if xpCache[level] == nil then
        local q = WorldDBQuery("SELECT Experience FROM player_xp_for_level WHERE Level = " .. level)
        xpCache[level] = q and q:GetUInt32(0) or 0
    end
    return xpCache[level]
end

local function SendBalance(player)   -- same value the shop shows (copper in gold mode, else shop item count)
    local sh = Settings.shop
    Msg.Send(player, "shop", "bal", sh.currency == "gold" and player:GetCoinage() or player:GetItemCount(sh.item))
end

local function Reward(player, isFinal, lfg)
    local count = isFinal and CFG.TICKETS_FINAL or CFG.TICKETS_BOSS
    local lines = {}
    if CFG.TICKET_ITEM then
        player:AddItem(CFG.TICKET_ITEM, count)
        local nm = GetItemTemplate and GetItemTemplate(CFG.TICKET_ITEM)
        lines[1] = count .. " " .. ((nm and nm:GetName()) or "reward item") .. (count > 1 and "s" or "")
    end
    if isFinal and not lfg then
        local lvl = player:GetLevel()
        if not player:IsMaxLevel() then
            local xp = math.floor(LevelXP(lvl) * CFG.XP_PERCENT)
            if xp > 0 then player:GiveXP(xp); lines[#lines + 1] = xp .. " XP" end
        end
        local gold = Lookup(GOLD, lvl)
        if gold then player:ModifyMoney(gold * 10000); lines[#lines + 1] = gold .. "g" end
        local sat = Lookup(SATCHELS, lvl)
        if sat then player:AddItem(sat, 1); lines[#lines + 1] = "a satchel" end
    end
    if #lines > 0 then player:SendBroadcastMessage("|cffffd100Dungeon reward:|r " .. table.concat(lines, ", ")) end
    SendBalance(player)
end

local rewarded = {}   -- "<creatureGuid>:<instanceId>" -> true (no double awards)

local function OnKill(event, killer, creature)
    if not killer or not creature then return end
    local isFinal = BOSSES[creature:GetEntry()]
    if isFinal == nil then return end
    local map = killer:GetMap()
    if not map or not (map:IsDungeon() or map:IsRaid()) then return end
    local key = creature:GetGUIDLow() .. ":" .. map:GetInstanceId()
    if rewarded[key] then return end
    rewarded[key] = true

    local group = killer:GetGroup()
    local lfg = group and group:IsLFGGroup() or false
    local members = group and group:GetMembers() or { killer }
    for _, m in pairs(members) do
        if m and not m:IsBot() and m:IsInWorld() and m:GetMapId() == killer:GetMapId() and m:GetInstanceId() == killer:GetInstanceId() then
            Reward(m, isFinal, lfg)
        else
            dbg("skipped", m and m:GetName() or "?")
        end
    end
end
RegisterPlayerEvent(7, OnKill)   -- PLAYER_EVENT_ON_KILL_CREATURE

-- ---- hearthstone reset when leaving an instance ----
local inInstance = {}
local function OnMapChange(event, player)
    if player:IsBot() then return end
    local g = player:GetGUIDLow()
    local map = player:GetMap()
    local nowIn = map and (map:IsDungeon() or map:IsRaid()) or false
    if inInstance[g] and not nowIn and CFG.RESET_HEARTHSTONE then
        player:ResetSpellCooldown(CFG.HEARTHSTONE_SPELL, true)
    end
    inInstance[g] = nowIn or nil
end
RegisterPlayerEvent(28, OnMapChange)   -- PLAYER_EVENT_ON_MAP_CHANGE
RegisterPlayerEvent(4, function(event, player) inInstance[player:GetGUIDLow()] = nil end)   -- logout

Msg.On("tickets", "bal", function(player) SendBalance(player) end)
return true
