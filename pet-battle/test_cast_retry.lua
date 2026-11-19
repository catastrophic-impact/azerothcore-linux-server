-- pb_cast: a real spell can MISS and then shows no effect on the target. A damaging spell (o.retry) must be cast again until it takes health; a spell that deals no damage must not.
local timers, now = {}, 0
function CreateLuaEvent(f, ms) timers[#timers + 1] = { f = f, t = now + ms } end
local function run(ms) local stop = now + ms; while true do table.sort(timers, function(a, b) return a.t < b.t end); local nx = timers[1]; if not nx or nx.t > stop then break end; table.remove(timers, 1); now = nx.t; nx.f() end; now = stop end
local world = {}
local function Unit(guid, name)
  local u = { guid = guid, hp = 1000, casts = 0, missFirst = 0, name = name }
  function u:GetGUID() return self.guid end
  function u:GetGUIDLow() return self.guid end
  function u:GetHealth() return self.hp end
  function u:SetHealth(h) self.hp = h end
  function u:GetLevel() return 80 end
  function u:SetFaction() end function u:ClearInCombat() end function u:MoveClear() end function u:MoveTo() end function u:SetFacing() end function u:RemoveAura() end
  function u:CastSpell(t, spell) self.casts = self.casts + 1; self.last = spell
    if (self.misses or 0) > 0 then self.misses = self.misses - 1 elseif self.deals then t.hp = t.hp - 30 end end
  world[guid] = u; return u
end
local player = { GetMap = function() return { GetWorldObject = function(_, g) return world[g] end } end }
function GetPlayerByGUID() return player end
dofile("scripts/pb_cast.lua")
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL: " .. m) end end
local function fresh() world = {}; timers = {}; return Unit(1, "att"), Unit(2, "tgt") end
-- 1. a damaging spell misses twice, then lands: cast 3 times, the target ends at the engine's hp
local a, t = fresh(); a.deals = true; a.misses = 2
PB_CAST.Cast(a, t, 100, { pguid = 9, hp_after = 800, retry = 2 }); run(4000)
check(a.casts == 3, "a spell that missed twice is cast again until it lands (casts=" .. a.casts .. ")")
check(t.hp == 800, "the exact hp is applied at the end (" .. t.hp .. ")")
-- 2. it lands the first time: exactly one cast
a, t = fresh(); a.deals = true
PB_CAST.Cast(a, t, 100, { pguid = 9, hp_after = 800, retry = 2 }); run(4000)
check(a.casts == 1, "a spell that landed is not repeated (casts=" .. a.casts .. ")")
-- 3. a spell that deals no damage (Kick) without retry: never repeated
a, t = fresh()
PB_CAST.Cast(a, t, 1766, { pguid = 9, hp_after = 1000 }); run(4000)
check(a.casts == 1, "a no-damage spell without retry is cast once (casts=" .. a.casts .. ")")
-- 4. retry is capped
a, t = fresh(); a.deals = true; a.misses = 99
PB_CAST.Cast(a, t, 100, { pguid = 9, hp_after = 800, retry = 2 }); run(6000)
check(a.casts == 3, "at most 1 + retry casts (casts=" .. a.casts .. ")")
-- 5. a heal / self cast never retries
a, t = fresh(); a.deals = true; a.misses = 5
PB_CAST.Cast(a, a, 100, { pguid = 9, heal = true, retry = 2 }); run(4000)
check(a.casts == 1, "a self cast is never retried (casts=" .. a.casts .. ")")
-- 6. ranged: the check waits for the projectile (750 ms), so a spell that has not landed YET is not repeated before that
a, t = fresh(); a.deals = true
PB_CAST.Cast(a, t, 100, { pguid = 9, hp_after = 800, retry = 1, ranged = true }); run(300)
check(a.casts == 1, "no repeat before the check time")
if fails > 0 then print(fails .. " FAILURES"); os.exit(1) end
print("pb_cast retry: OK")
