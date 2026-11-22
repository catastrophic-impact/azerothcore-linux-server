-- PRESENTATION SIMULATION: plays a full battle through the REAL pb_battle.lua for EVERY species (as the enemy, against random pets) with stubs that record what the game objects and
-- the addon receive, then checks invariants that only show up on screen:
--   * the skin on the spawned creature == the skin of the preview the addon shows (the male/female mismatch)  * spawns are stand-ins  * scale == the scale sent to the addon
--   * every method called on a game object exists in the live API manifest (pcall hides typos: Emote vs PerformEmote)  * every addon message fits the 240 character limit
--   * no leftover creatures after the battle  * ability / status / enemy-ability texts are clean (no formulas, "nil", "?")
-- luajit pet-battle/sim_presentation.lua [seed] [species entry]
math.randomseed(tonumber(arg and arg[1]) or 1)
package.path = "scripts/?.lua;" .. package.path
local only = tonumber(arg and arg[2])
local manifest = {}
for l in io.lines("pet-battle/api_manifest.txt") do local n = l:match("^(%w+)="); if n then manifest[n] = true end end
local PURE = { GetGUID = true, GetGUIDLow = true }   -- handled by the stub itself (still must be in the manifest)

local objects, nextId, badCalls, problems = {}, 100, {}, {}
local cosmetic, utilityActs = {}, 0   -- cosmetic spell id -> casts this battle; abilities that are PURE utility (no damage, no attack spell) this battle
local function problem(msg) problems[#problems + 1] = msg end
local function newObj(entry, kind)
    nextId = nextId + 1
    local o = { id = nextId, entry = entry, kind = kind or "creature", despawned = false, scale = nil, display = nil, faction = nil, flagsCleared = false, emotes = 0 }
    if kind ~= "go" then local sp = entry - 9000000; o.display = (sp > 0 and sp < 100000) and (sp * 100 + math.random(1, 2)) or nil end   -- the core picks a random model row at spawn
    o.guidTable = setmetatable({ id = nextId }, {})
    local api = {}
    local mt = { __index = function(_, name)
        if not manifest[name] then badCalls[name] = (badCalls[name] or 0) + 1 end
        if name == "GetGUID" then return function() return setmetatable({ id = o.id }, {}) end
        elseif name == "GetGUIDLow" then return function() return o.id end
        elseif name == "GetDisplayId" then return function() return o.display or 0 end
        elseif name == "SetDisplayId" then return function(_, d) o.display = d end
        elseif name == "SetScale" then return function(_, s) o.scale = s end
        elseif name == "SetFaction" then return function(_, f) o.faction = f end
        elseif name == "SetUnitFlags" then return function(_, f) if f == 0 then o.flagsCleared = true end end
        elseif name == "CastSpell" then return function(_, _, spell) cosmetic[spell] = (cosmetic[spell] or 0) + 1 end   -- every visual-only spell the playback casts (Fx)
        elseif name == "PerformEmote" then return function() o.emotes = o.emotes + 1 end
        elseif name == "DespawnOrUnsummon" or name == "RemoveFromWorld" then return function() o.despawned = true end
        elseif name == "IsAlive" then return function() return not o.despawned end
        elseif name == "GetEntry" then return function() return o.entry end
        elseif name == "GetX" or name == "GetY" or name == "GetZ" or name == "GetO" or name == "GetDistance" then return function() return 1 end
        elseif name == "GetFaction" then return function() return o.faction or 35 end
        elseif name == "GetMap" then return function() return { GetWorldObject = function(_, g) local r = objects[type(g) == "table" and g.id or g]; return r and r.api end, GetHeight = function() return 0 end } end end
        return function() end
    end }
    setmetatable(api, mt); o.api = api; objects[o.id] = o
    return o
end

local sent = {}
local player = newObj(0, "player"); player.despawned = false
local playerMt = getmetatable(player.api); local baseIdx = playerMt.__index
playerMt.__index = function(t, k)
    if k == "GetGUID" then return function() return setmetatable({ id = 7 }, {}) end
    elseif k == "GetGUIDLow" then return function() return 7 end
    elseif k == "GetMapId" then return function() return 0 end
    elseif k == "GetPhaseMask" then return function() return 1 end
    elseif k == "GetZoneId" then return function() return 12 end
    elseif k == "IsInCombat" or k == "IsMounted" then return function() return false end
    elseif k == "GetCreaturesInRange" then return function() return {} end
    end
    return baseIdx(t, k)
end
local P = player.api
local timers = {}
function CreateLuaEvent(f, ms) timers[#timers + 1] = { f = f, t = ms } end
function GetPlayerByGUID() return P end
function GetPlayersInWorld() return {} end
function RemoveEventById() end
function RegisterPlayerEvent() end
function RegisterCreatureGossipEvent() end
function CharDBExecute() end
function CharDBQuery() return nil end
function GetMapById() return { GetWorldObject = function(_, g) local r = objects[type(g) == "table" and g.id or g]; return r and r.api end } end
function PerformIngameSpawn(kind, entry) local o = newObj(entry, kind == 2 and "go" or "creature"); return o.api end
-- creature_template_model rows: every species has TWO skins (a male and a female twin), like the real humanoids
function WorldDBQuery(sql)
    local sp = sql:match("FROM creature_template_model WHERE CreatureID = (%d+)")
    if sp then
        sp = tonumber(sp); local rows, i = { sp * 100 + 1, sp * 100 + 2 }, 1
        return { GetUInt32 = function() return rows[i] end, NextRow = function() i = i + 1; return i <= #rows end }
    end
    return nil
end
function WorldDBExecute() end
package.loaded["acore_msg"] = { On = function() end, Send = function(_, module, action, payload)
    local text = module .. "|" .. action .. "|" .. tostring(payload or "")
    if #text > 240 then problem("addon message too long (" .. #text .. " > 240, dropped by Msg.Send): " .. text:sub(1, 90)) end
    sent[#sent + 1] = { action = action, payload = tostring(payload or ""), module = module }
end }
package.loaded["acore_prime"] = { Register = function() end, SetDisplayResolver = function() end, Enable = function() end, SendAs = function() end, SendOne = function() end }
dofile("scripts/pb_battle.lua")
do   -- watch the engine events the playback receives: which acts are pure utility (the only ones that may play the utility glow)
    local Eng = require("pb_core"); local origRound = Eng.Round
    Eng.Round = function(b, ...)
        local ev, st = origRound(b, ...)
        for _, x in ipairs(ev) do if x.k == "act" and not (x.dmg or (x.vis ~= nil and (x.vm == nil or x.vm == "melee" or x.vm == "ranged"))) then utilityActs = utilityActs + 1 end end   -- (no PB_CAST here: a self/target/aura support spell falls back to the glow)
        return ev, st
    end
end
local D = require("pb_data")
local PREVIEW_BASE = 9100000

local function drain(max)
    local n = 0
    while n < max do
        n = n + 1
        table.sort(timers, function(a, b) return a.t < b.t end)
        local tm = table.remove(timers, 1); if not tm then return true end
        for _, x in ipairs(timers) do x.t = x.t - tm.t end
        tm.f()
        -- answer every turn the addon is asked for
        while (sent.seen or 0) < #sent do
            sent.seen = (sent.seen or 0) + 1; local m = sent[sent.seen]
            if m.action == "turn" then
                if m.payload:match("^force") then for i = 1, 3 do PB_BATTLE.Command(P, "S" .. i) end
                else PB_BATTLE.Command(P, "A" .. math.random(1, 3)); PB_BATTLE.Command(P, "A1"); if m.payload:match(";1$") and math.random() < 0.5 then PB_BATTLE.Command(P, "T") end end
            end
        end
    end
    return false
end

local ids = {}
for entry in pairs(D.species) do if not only or entry == only then ids[#ids + 1] = entry end end
table.sort(ids)
local pool = {}; for _, e in ipairs(ids) do pool[#pool + 1] = e end
local tested, skipped = 0, 0
for _, enemy in ipairs(ids) do
    -- fresh slate per battle
    for k in pairs(objects) do if objects[k].kind ~= "player" then objects[k] = nil end end
    sent = {}; timers = {}; cosmetic = {}; utilityActs = 0
    local lvl = math.random(1, 6)
    local foes = { { species = enemy, level = lvl, quality = math.random(1, 4) } }
    if lvl > 2 then for _ = 1, 2 do foes[#foes + 1] = { species = pool[math.random(#pool)], level = lvl, quality = math.random(1, 4) } end end
    local mine = {}; for i = 1, 3 do mine[i] = { species = pool[math.random(#pool)], level = lvl, quality = math.random(1, 4) } end
    local ok = PB_BATTLE.Start(P, foes, mine)
    if not ok then skipped = skipped + 1; problem("battle did not start for species " .. enemy .. " " .. D.species[enemy].name)
    else
        tested = tested + 1
        local finished = drain(60000)
        if not finished then problem("battle with " .. D.species[enemy].name .. " never finished (timers still running)") end
        if PB_BATTLE.InBattle(P) and PB_BATTLE.CleanAll then PB_BATTLE.CleanAll(P) end
        drain(2000)
        local name = D.species[enemy].name .. " (" .. enemy .. ")"
        -- the cosmetic glows must match the events: 60957 (nature glow) only for pure utility abilities, never for an attack that missed; 60958 (fire glow) was the debuff glow that looked like a buff cast
        if (cosmetic[60957] or 0) ~= utilityActs then problem(name .. ": utility glow cast " .. (cosmetic[60957] or 0) .. " times but only " .. utilityActs .. " abilities were pure utility (a missed attack or another event plays the glow)") end
        if (cosmetic[60958] or 0) > 0 then problem(name .. ": the debuff glow (60958) was cast " .. cosmetic[60958] .. " times: a pet that merely received a debuff must not look like it casts") end
        -- previews the addon was told to show: species -> set of displays
        local previewDisplays, scales = {}, {}
        for _, m in ipairs(sent) do
            if m.action == "st" then
                local s, i, lv, hp, max, icon, q, entry, sc, nm = m.payload:match("^(%a),(%d+),(%d+),(%d+),(%d+),([^,]+),(%d+),(%d+),(%d+),(.+)$")
                if entry then
                    entry = tonumber(entry)
                    if entry >= PREVIEW_BASE then
                        -- the preview record is created with SendAs(player, entry, species, display): the display is entry - PREVIEW_BASE; the species is found by the pet name
                        local disp = entry - PREVIEW_BASE
                        for spId, spd in pairs(D.species) do if spd.name == nm then previewDisplays[spId] = previewDisplays[spId] or {}; previewDisplays[spId][disp] = true; scales[spId] = tonumber(sc) / 100 end end
                    end
                end
            end
        end
        -- invariants per spawned creature
        for _, o in pairs(objects) do
            if o.kind == "creature" then
                local sp = o.entry - 9000000
                if o.entry < 9000000 then problem(name .. ": spawned a real creature template " .. o.entry .. " instead of a stand-in")
                elseif D.species[sp] then
                    local shown = previewDisplays[sp]
                    if shown and o.display and not shown[o.display] then
                        local list = {}; for d in pairs(shown) do list[#list + 1] = d end
                        problem(name .. ": spawned " .. D.species[sp].name .. " wears skin " .. o.display .. " but the addon preview shows " .. table.concat(list, "/"))
                    end
                    if scales[sp] and o.scale and math.abs(o.scale - scales[sp]) > 0.011 then problem(name .. ": " .. D.species[sp].name .. " scale " .. o.scale .. " but the addon was told " .. scales[sp]) end
                    if o.faction ~= 35 then problem(name .. ": " .. D.species[sp].name .. " spawned with faction " .. tostring(o.faction)) end
                    if not o.flagsCleared then problem(name .. ": " .. D.species[sp].name .. " unit flags were not cleared") end
                end
            end
            if o.kind ~= "player" and not o.despawned then problem(name .. ": a " .. o.kind .. " (entry " .. o.entry .. ") is still in the world after the battle") end
        end
        -- status durations the player sees must be real round counts: "until used" effects (stored as 99 internally) show no number (user report: Rake showed 99 turns)
        for _, m in ipairs(sent) do
            if m.action == "tag" or m.action == "tag2" then
                for label, turns in m.payload:gmatch("([^~;|]+)~[^~;]+~(%d+)~%d+~%d") do
                    if tonumber(turns) > 12 then problem(name .. ": status '" .. label .. "' shows " .. turns .. " turns") end
                end
            end
        end
        -- text hygiene
        for _, m in ipairs(sent) do
            if m.action == "abil" or m.action == "eabil" or m.action == "stip" then
                local tip = (m.action == "stip") and m.payload:match("^[^#]*#(.*)$") or m.payload:match("^[^|]*|[^#]*#[^#]*#([^#]*)")
                if not tip or tip == "" then problem(name .. ": empty description in " .. m.action .. ": " .. m.payload:sub(1, 80))
                elseif tip:find("%[") or tip:find("nil") or tip:find("%?") or tip:find("|4") then problem(name .. ": bad text in " .. m.action .. ": " .. tip:sub(1, 100)) end
            end
        end
    end
end
for name, n in pairs(badCalls) do problem("a game object method that is NOT in the live API manifest was called: " .. name .. " (x" .. n .. ")") end
print(string.format("presentation sim: %d battles played (%d species), %d problems", tested, #ids, #problems))
local shown, seen = 0, {}
for _, p in ipairs(problems) do if not seen[p] and shown < 25 then seen[p] = true; shown = shown + 1; print("PROBLEM " .. p) end end
os.exit(#problems == 0 and 0 or 1)
