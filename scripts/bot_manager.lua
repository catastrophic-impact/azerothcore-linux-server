-- ============================================================
-- Bot Manager (server side). Client addon: addons/wotlk_botmanager.  Replaces the NPC gossip botmanv2.lua.
-- Companions are summoned with  .playerbots bot addclass <class>  (pooled class bots, not permanent account bots),
-- then their spec is set by whispering "talents spec <spec>". All input is validated against the tables below.
-- Messages (module "bots"): list | add class:spec | role Tank/Healer/DPS | fill both/tank/healer/dps | remove <name> | removeall
-- ============================================================
local Msg = require("acore_msg")

local CFG = { MAX_GROUP = 5, DK_MIN_LEVEL = 55, SYNC = true, SYNC_MS = 5000 }

local SPECS = {   -- class -> allowed spec strings (as playerbots expects them)
    warrior = { "arms pve", "fury pve", "prot pve" },
    paladin = { "holy pve", "prot pve", "ret pve" },
    hunter  = { "bm pve", "mm pve", "survival pve" },
    rogue   = { "as pve", "combat pve", "subtlety pve" },
    priest  = { "disc pve", "holy pve", "shadow pve" },
    dk      = { "blood pve", "frost pve", "unholy pve" },
    shaman  = { "ele pve", "enh pve", "resto pve" },
    mage    = { "arcane pve", "fire pve", "frost pve" },
    warlock = { "affli pve", "demo pve", "destro pve" },
    druid   = { "balance pve", "bear pve", "cat pve", "resto pve" },
}
local LABEL = { warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue", priest = "Priest",
                dk = "Death Knight", shaman = "Shaman", mage = "Mage", warlock = "Warlock", druid = "Druid" }
local ROLES = {   -- random picks per role: { class, { specs } }
    Tank   = { { "warrior", { "prot pve" } }, { "paladin", { "prot pve" } }, { "dk", { "blood pve" } }, { "druid", { "bear pve" } } },
    Healer = { { "priest", { "holy pve", "disc pve" } }, { "paladin", { "holy pve" } }, { "shaman", { "resto pve" } }, { "druid", { "resto pve" } } },
    DPS    = { { "warrior", { "arms pve", "fury pve" } }, { "paladin", { "ret pve" } }, { "hunter", { "bm pve", "mm pve", "survival pve" } },
               { "rogue", { "as pve", "combat pve", "subtlety pve" } }, { "priest", { "shadow pve" } }, { "shaman", { "ele pve", "enh pve" } },
               { "mage", { "arcane pve", "fire pve", "frost pve" } }, { "warlock", { "affli pve", "demo pve", "destro pve" } },
               { "druid", { "balance pve", "cat pve" } }, { "dk", { "frost pve", "unholy pve" } } },
}
math.randomseed(os.time())

local queues = {}      -- [guidLow] = { guid = ObjectGuid, items = {...}, mode = "single"/"fill" }
local botRole = {}     -- [bot guidLow] = "Tank"/"Healer"/"DPS" (roles of bots WE added; unknown bots count as DPS)
local removing = {}    -- [bot guidLow] = os.time() deadline: bots told to leave, hidden from the list while they log out

local TANK_SPEC = { ["prot pve"] = true, ["blood pve"] = true, ["bear pve"] = true }
local HEAL_SPEC = { ["holy pve"] = true, ["disc pve"] = true, ["resto pve"] = true }
local function RoleOfSpec(class, spec)
    if TANK_SPEC[spec] then return "Tank" end
    if HEAL_SPEC[spec] and not (class == "paladin" and spec ~= "holy pve") then return "Healer" end
    return "DPS"
end

local function GroupCount(player)
    local g = player:GetGroup()
    return g and g:GetMembersCount() or 1
end

local function GroupBots(player)
    local out, g = {}, player:GetGroup()
    if g then
        for _, m in pairs(g:GetMembers()) do
            if m and m:IsBot() then out[#out + 1] = m end
        end
    end
    return out
end

local function VisibleBots(player)   -- online bots, minus the ones already asked to leave
    local out, now = {}, os.time()
    for _, b in ipairs(GroupBots(player)) do
        local d = removing[b:GetGUIDLow()]
        if not (d and now < d) then out[#out + 1] = b end
    end
    return out
end

local function SendList(player)
    local parts = {}
    for _, b in ipairs(VisibleBots(player)) do
        parts[#parts + 1] = b:GetName() .. ":" .. b:GetClass() .. ":" .. b:GetLevel() .. ":" .. (botRole[b:GetGUIDLow()] or "DPS")
    end
    Msg.Send(player, "bots", "list", table.concat(parts, "|"))
end

local function SendHumans(player)   -- real players in the group (including you), for the Fill Group dialog
    local parts, g = {}, player:GetGroup()
    if g then
        for _, m in pairs(g:GetMembers()) do
            if m and not m:IsBot() then parts[#parts + 1] = m:GetName() .. ":" .. m:GetClass() .. ":" .. m:GetLevel() end
        end
    else
        parts[1] = player:GetName() .. ":" .. player:GetClass() .. ":" .. player:GetLevel()
    end
    Msg.Send(player, "bots", "humans", table.concat(parts, "|"))
end

local function RefreshLater(player, delays)   -- bots take a moment to log in/out: re-read the list a few times
    local g = player:GetGUID()
    for _, d in ipairs(delays) do
        CreateLuaEvent(function() local p = GetPlayerByGUID(g); if p then SendList(p) end end, d)
    end
end

local function Say(player, text) Msg.Send(player, "bots", "res", text) end

local function PickRole(player, role)
    local pool = {}
    for _, e in ipairs(ROLES[role]) do
        if e[1] ~= "dk" or player:GetLevel() >= CFG.DK_MIN_LEVEL then pool[#pool + 1] = e end
    end
    local e = pool[math.random(#pool)]
    return { class = e[1], spec = e[2][math.random(#e[2])], role = role, label = LABEL[e[1]] .. " (" .. role .. ")" }
end

local function Next(low)
    local q = queues[low]
    local player = q and GetPlayerByGUID(q.guid)
    if not q or not player then queues[low] = nil; return end
    local item = table.remove(q.items, 1)
    if not item then
        queues[low] = nil
        if q.mode == "fill" then Say(player, "Group fill complete.") end
        SendList(player); return
    end
    if GroupCount(player) >= CFG.MAX_GROUP then queues[low] = nil; Say(player, "Your group is full."); SendList(player); return end

    local before = {}
    for _, b in ipairs(GroupBots(player)) do before[b:GetGUIDLow()] = true end
    player:RunCommand(".playerbots bot addclass " .. item.class)

    local attempts = 0
    local function Check()
        local p = queues[low] and GetPlayerByGUID(q.guid)
        if not p then queues[low] = nil; return end
        attempts = attempts + 1
        for _, b in ipairs(GroupBots(p)) do
            if not before[b:GetGUIDLow()] then
                botRole[b:GetGUIDLow()] = item.role or RoleOfSpec(item.class, item.spec)
                removing[b:GetGUIDLow()] = nil
                p:Whisper("talents spec " .. item.spec, 0, b)
                Say(p, "Added " .. item.label .. ".")
                SendList(p); RefreshLater(p, { 1500 })
                CreateLuaEvent(function() Next(low) end, 300)
                return
            end
        end
        if attempts < 12 then CreateLuaEvent(Check, 250)
        else queues[low] = nil; Say(p, "Could not find the new bot (is Playerbots.AddClassCommand enabled?)."); SendList(p) end
    end
    CreateLuaEvent(Check, 250)
end

local function Start(player, items, mode)
    local low = player:GetGUIDLow()
    if queues[low] then return Say(player, "A bot operation is already running.") end
    if GroupCount(player) >= CFG.MAX_GROUP then return Say(player, "Your group is already full.") end
    queues[low] = { guid = player:GetGUID(), items = items, mode = mode }
    Next(low)
end

Msg.On("bots", "list", function(player) SendList(player); SendHumans(player) end)
Msg.On("bots", "humans", function(player) SendHumans(player) end)

Msg.On("bots", "add", function(player, payload)
    local class, spec = payload:match("^(%a+):(.+)$")
    local allowed = class and SPECS[class]
    local ok = false
    if allowed then for _, s in ipairs(allowed) do if s == spec then ok = true end end end
    if not ok then return Say(player, "Unknown class or spec.") end
    if class == "dk" and player:GetLevel() < CFG.DK_MIN_LEVEL then return Say(player, "You must be level " .. CFG.DK_MIN_LEVEL .. " to bring a Death Knight.") end
    Start(player, { { class = class, spec = spec, label = LABEL[class] } }, "single")
end)

Msg.On("bots", "role", function(player, payload)
    if not ROLES[payload] then return end
    Start(player, { PickRole(player, payload) }, "single")
end)

-- fill payload: "Name=Role;Name=Role" (one entry per REAL player). Adds whatever the group still lacks: 1 tank, 1 healer, rest DPS.
Msg.On("bots", "fill", function(player, payload)
    local humans = {}
    local g = player:GetGroup()
    if g then for _, m in pairs(g:GetMembers()) do if m and not m:IsBot() then humans[m:GetName()] = true end end
    else humans[player:GetName()] = true end
    local tanks, healers = 0, 0
    for name, role in payload:gmatch("([^=;]+)=(%a+)") do
        if humans[name] then
            if role == "Tank" then tanks = tanks + 1 elseif role == "Healer" then healers = healers + 1 end
        end
    end
    for _, b in ipairs(VisibleBots(player)) do   -- bots already in the group count toward the roles
        local r = botRole[b:GetGUIDLow()]
        if r == "Tank" then tanks = tanks + 1 elseif r == "Healer" then healers = healers + 1 end
    end
    local need = CFG.MAX_GROUP - GroupCount(player)
    if need <= 0 then return Say(player, "Your group is already full.") end
    local items = {}
    local function add(role) if need > 0 then items[#items + 1] = PickRole(player, role); need = need - 1 end end
    if tanks == 0 then add("Tank") end
    if healers == 0 then add("Healer") end
    while need > 0 do add("DPS") end
    Start(player, items, "fill")
end)

Msg.On("bots", "remove", function(player, name)
    for _, b in ipairs(GroupBots(player)) do   -- only bots that are really in the caller's group
        if b:GetName() == name then
            removing[b:GetGUIDLow()] = os.time() + 20
            player:RunCommand(".playerbots bot remove " .. name)
            SendList(player); RefreshLater(player, { 1500, 4000 })
            return Say(player, "Removed " .. name .. ".")
        end
    end
    Say(player, "That bot is not in your group.")
end)

Msg.On("bots", "removeall", function(player)
    queues[player:GetGUIDLow()] = nil
    for _, b in ipairs(GroupBots(player)) do removing[b:GetGUIDLow()] = os.time() + 20 end
    player:RunCommand(".playerbots bot remove *")
    SendList(player); RefreshLater(player, { 1500, 4000 })
    Say(player, "All companions removed.")
end)

-- NOTE: group membership is never changed from Lua (playerbots logs bots in/out on worker threads); offline companions are
-- removed from the party by the ADDON via UninviteUnit, the normal game path.
-- keep companions with their player (from botmanv2): summon bots that fell behind, except in battlegrounds/arenas
local function Synchronize()
    for _, player in pairs(GetPlayersInWorld()) do
        if player and not player:IsBot() and player:GetGroup() then
            local pmap = player:GetMap()
            if pmap and not pmap:IsBattleground() and not pmap:IsArena() then
                for _, b in ipairs(GroupBots(player)) do
                    if b:GetMapId() ~= player:GetMapId() or b:GetAreaId() ~= player:GetAreaId() then
                        player:Whisper("summon", 0, b)
                    end
                end
            end
        end
    end
    CreateLuaEvent(Synchronize, CFG.SYNC_MS)
end
if CFG.SYNC then CreateLuaEvent(Synchronize, CFG.SYNC_MS) end

print("[bot_manager] loaded")
return true
