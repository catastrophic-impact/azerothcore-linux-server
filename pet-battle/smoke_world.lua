math.randomseed(tonumber(os.getenv("SEED")) or 1)
package.path = "scripts/?.lua;" .. package.path
-- the battle TRACE is on for the whole run; its lines are collected (TRACE=1 also shows them) and checked at the end
PB_TRACE = true
-- PBCAST=1: a recording PB_CAST stands in for the real-spell module, so the presentation MODES (melee/ranged hit casts, self/target/aura support casts) run and can be checked
CASTS = {}
if os.getenv("PBCAST") then PB_CAST = { Cast = function(att, tgt, spell, o) CASTS[#CASTS + 1] = { spell = spell, heal = o and o.heal, retry = o and o.retry }; return true end } end
local TL, realprint = {}, print
print = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; local l = table.concat(t, " ")
  if l:find("^%[pbtrace%]") then TL[#TL + 1] = l; if os.getenv("TRACE") then realprint(l) end else realprint(l) end end
local sent, events = {}, {}
local obj = setmetatable({}, { __index = function(t, k) return function(self, ...) if k == "GetGUID" then return setmetatable({ id = 1 }, {}) elseif k == "GetGUIDLow" then return 1 elseif k=="GetX" or k=="GetY" or k=="GetZ" then return 0 elseif k=="GetDisplayId" then return 4000 elseif k=="GetMap" then return {GetWorldObject=function() return t end} end return t end end })
local player = setmetatable({}, { __index = function(t, k)
  if k=="GetGUID" then return function() return setmetatable({ id = 7 }, {}) end elseif k=="GetGUIDLow" then return function() return 7 end
  elseif k=="GetMap" then return function() return {GetWorldObject=function() return obj end, GetHeight=function() return 0 end} end
  elseif k=="IsAlive" then return function() return true end elseif k=="IsInCombat" then return function() return false end
  elseif k=="GetDistance" then return function() return 1 end elseif k=="GetPhaseMask" then return function() return 1 end
  elseif k=="GetGMRank" then return function() return _G.RANK or 3 end elseif k=="GetMapId" then return function() return 0 end elseif k=="GetO" then return function() return 0 end
  elseif k=="GetX" or k=="GetY" or k=="GetZ" then return function() return 0 end end
  return function() end end })
local timers = {}
function CreateLuaEvent(f, ms) timers[#timers+1] = { f = f, t = ms } end
function WorldDBQuery() return nil end
function GetPlayerByGUID() return player end
function PerformIngameSpawn() return obj end
function RegisterPlayerEvent() end
package.loaded["acore_msg"] = { On = function(m, a, f) events[m.."|"..a] = f end, Send = function(p, m, a, pl) sent[#sent+1] = a .. "|" .. tostring(pl) end }
-- REAL pb_store with stubbed DB (nothing persists): dofile order mirrors the server (scripts first, then require)
function CharDBExecute() end
function CharDBQuery() return nil end
function GetMapById() return { GetWorldObject = function() return obj end } end
function RemoveEventById() end
function GetPlayersInWorld() return {} end
package.loaded["acore_msg"].Send = function(p, m, a, pl) sent[#sent+1] = a .. "|" .. tostring(pl) end
dofile("scripts/pb_battle.lua")
for sp in pairs(require("pb_data").species) do PB_STORE.AddPet(player, sp, 10) end; events["pbj|list"](player)
local sd = tonumber(os.getenv("SEED")) or 1
if sd % 4 == 3 then events["pbj|setteam"](player, "1,721,69,299"); events["pbj|active"](player, "1")   -- a team with the rabbit (Support kit)
elseif sd % 2 == 1 then events["pbj|setteam"](player, "1,299,69,257"); events["pbj|active"](player, "1") end   -- even seeds: no team = automatic fallback
events["pbj|summon"](player, "299"); events["pbj|dismiss"](player, "")
events["pbt|start"](player)
local turns, guard, seen, recruited = 0, 0, 0, false
while guard < 40000 do
  guard = guard + 1
  table.sort(timers, function(a, b) return a.t < b.t end)
  local tm = table.remove(timers, 1)
  if not tm then break end
  for _, x in ipairs(timers) do x.t = x.t - tm.t end
  tm.f()
  while seen < #sent do
    seen = seen + 1
    local m = sent[seen]
    if m:match("^turn|") then
      turns = turns + 1
      local pick
      if m:match("^turn|force") then for i = 1, 3 do events["pbt|cmd"](player, "S" .. i) end   -- first living pet is accepted, the rest rejected
      else
        local c1, c2, c3 = m:match(";(%d+),(%d+),(%d+)")
        pick = (c3 == "0") and "A3" or (c2 == "0" and turns % 2 == 0) and "A2" or "A1"
        if m:match(";1$") then pick = "T" end   -- the enemy is weak enough: capture it (retail trap)
      end
      if pick then events["pbt|cmd"](player, pick) end
    end
  end
end
local lastMsg = sent[#sent]
do   -- health is kept after the battle: at least one of my pets that fought is below full, none is at 0
    local hurt, zero = 0, 0
    for sp, p in pairs(PB_STORE.Pets(player)) do local cur, max = PB_STORE.PetHp(sp, p); if cur < max then hurt = hurt + 1 end; if cur < 1 then zero = zero + 1 end end
    assert(zero == 0, "a pet was left at 0 HP"); assert(hurt >= 1, "no pet kept damage after the battle (health must NOT be restored)")
end   -- how the first (played-out) battle ended; the extra scenarios below add more messages
assert(PB_BATTLE.InBattle(player) == false, "a finished battle must not stay registered (InBattle still true)")
-- the debug start is GM only: a normal player gets nothing
RANK = 0; events["pbt|start"](player)
for _ = 1, 400 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f() end
assert(PB_BATTLE.InBattle(player) == false, "pbt|start must be refused for a non-GM"); RANK = nil
-- stuck battle 1: the window never answers -> the watchdog ends it after the idle timeout
events["pbt|start"](player)
for _ = 1, 400 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f() end
assert(PB_BATTLE.InBattle(player) == true, "battle running and waiting for a move")
local realTime = os.time; os.time = function() return realTime() + 500 end
PB_BATTLE.Watchdog()
assert(PB_BATTLE.InBattle(player) == false, "watchdog must end a battle that waits for a move forever")
os.time = realTime
-- stuck battle 2: /pbtest clean ends your own battle at once
events["pbt|start"](player)
for _ = 1, 400 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f() end
assert(PB_BATTLE.InBattle(player) == true, "second battle running")
events["pbt|clean"](player, "")
assert(PB_BATTLE.InBattle(player) == false, "/pbtest clean must end your own stuck battle")
-- RETAIL CORE battle through the real battle script: 3 rabbits vs 3 rabbits (test team, nothing saved) played to the end
do
    local before = #sent
    local rab = { { species = 721, level = 10, quality = 3 }, { species = 721, level = 10, quality = 3 }, { species = 721, level = 10, quality = 3 } }
    local foe = { { species = 721, level = 10, quality = 2 }, { species = 721, level = 10, quality = 2 }, { species = 721, level = 10, quality = 2 } }
    assert(PB_BATTLE.Start(player, foe, rab), "retail test battle must start")
    local seen2, ended, turns2 = before, false, 0
    for _ = 1, 40000 do
        table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end
        for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f()
        while seen2 < #sent do
            seen2 = seen2 + 1; local m = sent[seen2]
            if m:match("^turn|") then
                turns2 = turns2 + 1
                if m:match("^turn|force") then for i = 1, 3 do PB_BATTLE.Command(player, "S" .. i) end
                else PB_BATTLE.Command(player, "A" .. (turns2 % 3 + 1)); PB_BATTLE.Command(player, "A1"); if m:match(";1$") then PB_BATTLE.Command(player, "T") end end   -- an unready ability is ignored, the basic always works
            elseif m:match("^end|") then ended = true end
        end
        if ended and not PB_BATTLE.InBattle(player) then break end
    end
    assert(ended, "retail battle did not finish"); assert(turns2 > 3, "retail battle too short")
    local abil = 0; for i = before + 1, #sent do if sent[i]:match("^abil|") then abil = abil + 1 end end
    assert(abil >= 1, "retail battle sent its abilities to the addon")
    print("retail core battle played to the end, turns:", turns2)
end
-- MULTI-ROUND ABILITY (Stampede): after the first round the player is offered NO choice: the turn message is 'lock' with the round count, and it passes by itself
do
    PB_STORE.HealAll(player)
    events["pbj|setteam"](player, "1,2442,0,0"); events["pbj|active"](player, "1")
    local foe = { { species = 721, level = 10, quality = 2 } }
    assert(PB_BATTLE.Start(player, foe), "battle for the stampede test must start")
    local function pump(untilFn) for _ = 1, 400 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f(); if untilFn and untilFn() then return true end end end
    local function lastTurn() for i = #sent, 1, -1 do if sent[i]:match("^turn|") then return sent[i], i end end end
    pump(function() return PB_BATTLE.Waiting(player) end)
    local base = #sent; PB_BATTLE.Command(player, "A1")   -- slot 1 = Stampede for the Cow
    local locked
    pump(function() for i = base + 1, #sent do if sent[i]:match("^turn|lock;") then locked = sent[i]; return true end end end)
    assert(locked, "after Stampede's first round the turn message must be 'lock' (the player has no choice), got: " .. tostring(lastTurn()))
    assert(locked:find("round 2 of 3", 1, true), "the lock message names the round: " .. locked)
    -- the turn passes by itself: a third round follows without any command
    local n0 = #sent
    pump(function() for i = n0 + 1, #sent do if sent[i]:match("^turn|lock;.*round 3 of 3") then return true end end end)
    local l, idx = lastTurn(); assert(l:find("round 3 of 3", 1, true), "round 3 follows by itself: " .. tostring(l))
    pump(function() local t = lastTurn(); return t and t:match("^turn|go;") end)
    assert((lastTurn()):match("^turn|go;"), "after the third round the player gets the buttons back")
    print("stampede: locked for rounds 2 and 3, buttons back afterwards")
    events["pbt|quit"](player); pump()
end
-- FORFEIT: a forfeited battle is a defeat, every pet of the team ends at 1 HP (and an open journal is told)
do
    PB_STORE.HealAll(player)   -- earlier battles of this seed left pets hurt
    events["pbj|setteam"](player, "1,721,69,299"); events["pbj|active"](player, "1")
    local foe = { { species = 721, level = 10, quality = 2 } }
    assert(PB_BATTLE.Start(player, foe), "battle for the forfeit test must start")
    for _ = 1, 60 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f(); if PB_BATTLE.Waiting(player) then break end end
    assert(PB_BATTLE.Waiting(player), "the forfeit test battle waits for a command")
    local before = #sent
    for _, sp in ipairs({ 721, 69, 299 }) do local _, max = PB_STORE.PetHp(sp, PB_STORE.Pets(player)[sp]); local cur = PB_STORE.PetHp(sp, PB_STORE.Pets(player)[sp]); assert(cur == max, "pet " .. sp .. " starts at full health") end
    events["pbt|quit"](player)
    for _ = 1, 400 do table.sort(timers, function(a, b) return a.t < b.t end); local tm = table.remove(timers, 1); if not tm then break end; for _, x in ipairs(timers) do x.t = x.t - tm.t end; tm.f() end
    for _, sp in ipairs({ 721, 69, 299 }) do local cur = PB_STORE.PetHp(sp, PB_STORE.Pets(player)[sp]); assert(cur == 1, "forfeit: pet " .. sp .. " ends at 1 HP, got " .. cur) end
    local pushed = 0; for i = before + 1, #sent do if sent[i]:match("^pet|") then pushed = pushed + 1 end end
    assert(pushed >= 3, "forfeit: the journal was sent the new health of the team (" .. pushed .. " pet messages)")
    print("forfeit: team knocked out, journal updated")
end
do   -- /pbtest bad: remembers the abilities of the battle just played (also after it ended)
    local n = PB_BATTLE.Bad(player, "smoke test")
    assert(n and n >= 1, "/pbtest bad found no recent ability after a full battle")
end
-- BATTLE TRACE checks: the transcript has what the player was offered, the engine events and the presentation steps; no offered choice was ignored by the engine
do
    local n = { offer = 0, ev = 0, cmd = 0, emote = 0, send = 0, viol = 0 }
    for _, l in ipairs(TL) do
        if l:find(" OFFER round ", 1, true) then n.offer = n.offer + 1 end
        if l:find(" ev %d+/%d+ ") then n.ev = n.ev + 1 end
        if l:find(" COMMAND ", 1, true) then n.cmd = n.cmd + 1 end
        if l:find(" emote ", 1, true) then n.emote = n.emote + 1 end
        if l:find(" -> addon ", 1, true) then n.send = n.send + 1 end
        if l:find("VIOLATION", 1, true) then n.viol = n.viol + 1; realprint(l) end
    end
    assert(n.offer > 0 and n.ev > 0 and n.cmd > 0 and n.emote > 0 and n.send > 0, string.format("trace is incomplete: offer=%d ev=%d command=%d emote=%d addon=%d", n.offer, n.ev, n.cmd, n.emote, n.send))
    assert(n.viol == 0 and PB_BATTLE.Violations() == 0, n.viol .. " offered choice(s) were ignored by the engine (see VIOLATION lines)")
    -- the checker itself must catch the Stampede class of bug (mutation check): ability 2 offered but slot 1 ran / nothing ran / no capture / no swap
    local H = PB_BATTLE.Honored
    assert(H("A2", { { k = "act", side = "P", slot = 2 } }) == true)
    assert(H("A2", { { k = "act", side = "P", slot = 1, name = "Bite" } }) == false, "checker must flag a different slot")
    assert(H("A2", { { k = "act", side = "E", slot = 1 }, { k = "stunned", side = "P" } }) == true, "enemy first and stunned my pet: fine")
    assert(H("A2", { { k = "act", side = "E", slot = 1 }, { k = "dmg", side = "P" }, { k = "faint", side = "E" } }) == true, "the enemy acted first and died from a reflect: nothing left to attack")
    assert(H("A2", { { k = "faint", side = "E" } }) == false, "an enemy faint with no enemy action first is not an excuse")
    assert(H("A2", { { k = "stunned", side = "P" } }) == false, "stunned with no enemy action first: the choice was offered, so it is a violation")
    assert(H("A2", { { k = "act", side = "E", slot = 1 }, { k = "swap", side = "P", forced = true }, { k = "act", side = "P", slot = 1 } }) == true, "forced swap: the new pet may use another slot (cooldowns)")
    assert(H("A2", { { k = "act", side = "E", slot = 1 }, { k = "swap", side = "P" }, { k = "act", side = "P", slot = 1 } }) == false, "a non-forced swap is no excuse")
    assert(H("A2", {}) == false and H("T", {}) == false and H("S2", { { k = "swap", side = "P", idx = 3 } }) == false)
    assert(H("S2", { { k = "swap", side = "P", idx = 2 } }) == true and H("T", { { k = "trap" } }) == true)
    realprint(string.format("trace: %d lines, %d offers, %d commands, %d events, %d emotes, 0 violations", #TL, n.offer, n.cmd, n.ev, n.emote))
end
if os.getenv("PBCAST") then   -- every act the engine ordered with a support mode produced exactly that support cast (same spell, same order); every hit cast belongs to an act with that spell
    local want, got, hitspells, hitcasts = {}, {}, {}, 0
    for _, l in ipairs(TL) do
        if l:find(" ev %d+/%d+ ") and l:find(" k=act ", 1, true) then
            local vis, vm = l:match(" vis=(%d+)"), l:match(" vm=(%a+)")
            if vis and (vm == "self" or vm == "target" or vm == "aura") then want[#want + 1] = vm .. " " .. vis end
            if vis and (vm == "melee" or vm == "ranged" or not vm) then hitspells[vis] = true end
        end
        local m, sp = l:match(" support (%a+) spell (%d+) on ")
        if m then got[#got + 1] = m .. " " .. sp end
        local cs = l:match(" cast real spell (%d+) ")
        if cs then hitcasts = hitcasts + 1; assert(hitspells[cs], "a hit cast of spell " .. cs .. " belongs to no act with that visual") end
    end
    assert(#want == #got, string.format("support casts: the engine ordered %d, the battle played %d", #want, #got))
    for i = 1, #want do assert(want[i] == got[i], "support cast " .. i .. ": ordered '" .. want[i] .. "', played '" .. got[i] .. "'") end
    realprint(string.format("presentation modes: %d support casts, %d hit casts, %d PB_CAST calls", #want, hitcasts, #CASTS))
end
local counts = {}
for _, m in ipairs(sent) do local a = m:match("^(%a+)"); counts[a] = (counts[a] or 0) + 1 end
for k, v in pairs(counts) do io.write(k, "=", v, " ") end print()
print("last:", lastMsg, "turns:", turns)
