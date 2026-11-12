math.randomseed(tonumber(os.getenv("SEED")) or 1)
package.path = "scripts/?.lua;" .. package.path
local sent, events = {}, {}
local obj = setmetatable({}, { __index = function(t, k) return function(self, ...) if k == "GetGUID" then return setmetatable({ id = 1 }, {}) elseif k == "GetGUIDLow" then return 1 elseif k=="GetX" or k=="GetY" or k=="GetZ" then return 0 elseif k=="GetDisplayId" then return 4000 elseif k=="GetMap" then return {GetWorldObject=function() return t end} end return t end end })
local player = setmetatable({}, { __index = function(t, k)
  if k=="GetGUID" then return function() return setmetatable({ id = 7 }, {}) end elseif k=="GetGUIDLow" then return function() return 7 end
  elseif k=="GetMap" then return function() return {GetWorldObject=function() return obj end, GetHeight=function() return 0 end} end
  elseif k=="IsAlive" then return function() return true end elseif k=="IsInCombat" then return function() return false end
  elseif k=="GetDistance" then return function() return 1 end elseif k=="GetPhaseMask" then return function() return 1 end
  elseif k=="GetMapId" then return function() return 0 end elseif k=="GetO" then return function() return 0 end
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
events["pbj|grant"](player)
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
local counts = {}
for _, m in ipairs(sent) do local a = m:match("^(%a+)"); counts[a] = (counts[a] or 0) + 1 end
for k, v in pairs(counts) do io.write(k, "=", v, " ") end print()
print("last:", lastMsg, "turns:", turns)
