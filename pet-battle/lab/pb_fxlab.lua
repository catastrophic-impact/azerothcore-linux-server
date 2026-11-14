-- Presentation lab (GM only): `.pbfx` spawns two pets in front of you and tries every way of making one creature "cast" at another,
-- logging what really happens (HP change, combat state, death) to the world log AND chat. Result goes into DEVNOTES; remove when done.
--   .pbfx              run the whole series
--   .pbfx spell <id> [bp]   one cast from A to B (triggered, optional custom damage)
--   .pbfx clean        remove the lab pets
local LAB = {}   -- [playerLow] = { a=guid, b=guid, map }
local function After(ms, fn) CreateLuaEvent(function() fn() end, ms, 1) end
local function Say(pl, m) pcall(function() pl:SendBroadcastMessage(m) end); print("[pbfx] " .. m) end
local function Big(pl, m) pcall(function() pl:SendNotification(m) end) end   -- big yellow text in the middle of the screen

local function Get(l, k)
    local pl = GetPlayerByGUID(l.pl); local m = pl and pl:GetMap()   -- fresh map each time: a stored Map userdata goes stale
    return m and m:GetWorldObject(l[k])
end
local function Spawn(pl, entry, f, side)
    local x, y, z, o = pl:GetX(), pl:GetY(), pl:GetZ(), pl:GetO()
    local px = x + math.cos(o) * f - math.sin(o) * side
    local py = y + math.sin(o) * f + math.cos(o) * side
    local okh, h = pcall(function() return pl:GetMap():GetHeight(px, py, pl:GetPhaseMask()) end)
    if okh and h and h > -1000 and math.abs(h - z) < 8 then z = h + 0.1 end   -- stand on the real ground (pets fell through before)
    local obj = PerformIngameSpawn(1, entry, pl:GetMapId(), 0, px, py, z, o + 3.14, false, 0, pl:GetPhaseMask())
    if obj then
        pcall(function() obj:SetReactState(0) end)
        pcall(function() obj:SetFaction(35) end)
        pcall(function() obj:SetScale(0.6) end)
        pcall(function() obj:SetMaxHealth(1000) end)
        pcall(function() obj:SetHealth(1000) end)
    end
    return obj
end
local function Clean(pl)
    local l = LAB[pl:GetGUIDLow()]
    if l then
        for _, k in ipairs({ "a", "b" }) do local o = Get(l, k); if o then pcall(function() o:DespawnOrUnsummon(0) end) end end
        LAB[pl:GetGUIDLow()] = nil
    end
    -- also remove lab pets this script no longer tracks (after a reload): Lua-spawned wolves, which have no database row
    for _, entry in ipairs({ 299, 69 }) do
        local ok, list = pcall(function() return pl:GetCreaturesInRange(80, entry) end)
        if ok and list then
            for _, c in ipairs(list) do
                local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
                if okd and (dbg == 0 or dbg == nil) then pcall(function() c:DespawnOrUnsummon(0) end) end
            end
        end
    end
end
local function Setup(pl)
    Clean(pl)
    local a, b = Spawn(pl, 299, 5, 2.5), Spawn(pl, 69, 5, -2.5)
    if not a or not b then Say(pl, "spawn failed"); return end
    LAB[pl:GetGUIDLow()] = { a = a:GetGUID(), b = b:GetGUID(), pl = pl:GetGUID() }
    return LAB[pl:GetGUIDLow()]
end
local function State(o)
    local ok, s = pcall(function()
        return string.format("hp=%d alive=%s combat=%s victim=%s", o:GetHealth(), tostring(o:IsAlive()), tostring(o:IsInCombat()), tostring(o:GetVictim() ~= nil))
    end)
    return ok and s or "?"
end

-- each case: name, function(a, b)   (b is reset to 1000 HP before each case; the log shows b's state 2.5 s later)
local CASES = {
    { "CastSpell fireball 133, triggered", function(a, b) a:CastSpell(b, 133, true) end },
    { "CastCustomSpell fireball bp0=100", function(a, b) a:CastCustomSpell(b, 133, true, 100) end },
    { "CastCustomSpell fireball bp0=0", function(a, b) a:CastCustomSpell(b, 133, true, 0) end },
    { "DealDamage 100 flat (melee style)", function(a, b) a:DealDamage(b, 100, false) end },
    { "DealDamage 100 fire school", function(a, b) a:DealDamage(b, 100, false, 2) end },
    { "DealDamage 100 fire + spell id 133", function(a, b) a:DealDamage(b, 100, false, 2, 133) end },
    { "Claw 1082 triggered (visual hit?)", function(a, b) a:CastSpell(b, 1082, true) end },
    { "Heal visual 2050 on ally (A->A)", function(a, b) a:CastSpell(a, 2050, true) end },
    { "Lethal: b=50hp, DealDamage 100", function(a, b) b:SetHealth(50); a:DealDamage(b, 100, false) end },
}
-- hostile-for-a-moment cases: a real spell only lands on an ATTACKABLE target, so swap factions for the cast and restore them 350 ms later
local function Swap(fa, fb, f)
    return function(a, b)
        a:SetFaction(fa); b:SetFaction(fb)
        f(a, b)
        After(350, function() pcall(function() a:SetFaction(35); b:SetFaction(35) end) end)
    end
end
CASES[#CASES + 1] = { "A=14 B=35, fireball 100", Swap(14, 35, function(a, b) a:CastCustomSpell(b, 133, true, 100) end) }
CASES[#CASES + 1] = { "A=14 B=1, fireball 100", Swap(14, 1, function(a, b) a:CastCustomSpell(b, 133, true, 100) end) }
CASES[#CASES + 1] = { "A=1 B=14, fireball 100", Swap(1, 14, function(a, b) a:CastCustomSpell(b, 133, true, 100) end) }
CASES[#CASES + 1] = { "A=14 B=1, claw 1082", Swap(14, 1, function(a, b) a:CastSpell(b, 1082, true) end) }
CASES[#CASES + 1] = { "PB_CAST fireball, exact hp_after=900", function(a, b) PB_CAST.Cast(a, b, 133, { dmg = 100, hp_after = 900, ranged = true }) end }
CASES[#CASES + 1] = { "PB_CAST claw, exact hp_after=950", function(a, b) PB_CAST.Cast(a, b, 1082, { hp_after = 950 }) end }
CASES[#CASES + 1] = { "PB_CAST lethal: hp_after=-30 (must clamp to 1)", function(a, b) PB_CAST.Cast(a, b, 133, { dmg = 100, hp_after = -30, ranged = true }) end }
local FIRST_PBCAST = #CASES - 2
local FIRST_FACTION = #CASES - 6
local function Run(pl, from)
    from = from or 1
    local l = Setup(pl); if not l then return end
    Say(pl, "lab started: 2 pets in front of you, " .. #CASES .. " cases, one every 5 s. Watch floating numbers, effects, sounds.")
    for i, c in ipairs(CASES) do
      if i >= from then
        After((i - from + 1) * 5000, function()
            local a, b = Get(l, "a"), Get(l, "b")
            if not a or not b then Say(pl, "case " .. i .. ": a pet is gone (killed?) - stopping"); return end
            pcall(function() b:SetMaxHealth(1000); b:SetHealth(1000) end)
            Big(pl, "TEST " .. i .. ": " .. c[1])
            Say(pl, string.format("[%d] before: B %s", i, State(b)))
            local ok, err = pcall(c[2], a, b)
            Say(pl, string.format("[%d] %s -> %s", i, c[1], ok and "called" or ("ERROR " .. tostring(err))))
            After(1100, function()   -- 1.1 s (PB_CAST restores at 0.45 s melee / 0.8 s ranged; creatures regenerate fast afterwards): creatures regenerate quickly out of combat, 2.5 s hid the damage before
                local b2, a2 = Get(l, "b"), Get(l, "a")
                pcall(function() if a2 then a2:SetFaction(35) end; if b2 then b2:SetFaction(35) end end)   -- always back to friendly (the stale-object restore in Swap can fail)
                Say(pl, string.format("[%d] result: B %s | A %s", i, b2 and State(b2) or "GONE", a2 and State(a2) or "GONE"))
            end)
        end)
      end
    end
    After((#CASES - from + 2) * 5000, function() Say(pl, "lab done (pets stay for .pbfx spell tests; .pbfx clean removes them)") end)
end

RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command then return end
    local cmd, arg = command:match("^pbfx%s*(%a*)%s*(.-)%s*$")
    if not cmd then return end
    if player:GetGMRank() < 2 then return end
    if cmd == "clean" then Clean(player); pcall(PB_BATTLE.CleanAll, player); Say(player, "cleaned")
    elseif cmd == "spell" then
        local id, bp = arg:match("^(%d+)%s*(%-?%d*)$")
        local l = LAB[player:GetGUIDLow()] or Setup(player)
        local a, b = l and Get(l, "a"), l and Get(l, "b")
        if a and b and id then
            pcall(function() b:SetMaxHealth(1000); b:SetHealth(1000) end)
            if bp ~= "" then a:CastCustomSpell(b, tonumber(id), true, tonumber(bp)) else a:CastSpell(b, tonumber(id), true) end
            After(2500, function() local b2 = Get(l, "b"); Say(player, "result: B " .. (b2 and State(b2) or "GONE")) end)
        else Say(player, "usage: .pbfx spell <id> [damage]") end
    elseif cmd == "faction" then Run(player, FIRST_FACTION)
    elseif cmd == "cast" then Run(player, FIRST_PBCAST)
    else Run(player) end
    return false
end)

-- Remote trigger so the lab can be run (and screenshotted) without typing: write a line to release/config/pbfx.trigger
--   "run" | "faction" | "spell <id> [dmg]" | "clean"      (runs for the first GM-level player online)
local TRIG = "config/pbfx.trigger"
CreateLuaEvent(function()
    local f = io.open(TRIG, "r"); if not f then return end
    local line = f:read("*l"); f:close(); os.remove(TRIG)
    if not line then return end
    for _, pl in ipairs(GetPlayersInWorld()) do
        if pl:GetGMRank() >= 2 then
            local cmd, arg = line:match("^(%a+)%s*(.-)%s*$")
            if cmd == "clean" then Clean(pl); pcall(PB_BATTLE.CleanAll, pl) elseif cmd == "faction" then Run(pl, FIRST_FACTION)
            elseif cmd == "cast" then Run(pl, FIRST_PBCAST)
            elseif cmd == "battle" then   -- EVEN-level test battle (3 vs 3, all level 10), the lab plays the player's commands: trap when allowed, else a random ready ability. "battle <ticks>"
                local ticks = tonumber(arg) or 12
                local mine = { { species = 299, level = 10, quality = 1 }, { species = 721, level = 10, quality = 1 }, { species = 257, level = 10, quality = 1 } }
                local foes = { { species = 6, level = 10, quality = 1 }, { species = 6, level = 10, quality = 1 }, { species = 6, level = 10, quality = 1 } }
                if PB_BATTLE.Start(pl, foes, mine) then
                    local g = pl:GetGUID()
                    for i = 1, ticks * 4 do   -- every 2.5 s: if the bars wait for a move, play one (trap as soon as it is legal)
                        After(i * 2500, function()
                            local p2 = GetPlayerByGUID(g); if not p2 or not PB_BATTLE.Waiting(p2) then return end
                            if PB_BATTLE.CanTrap(p2) then PB_BATTLE.Command(p2, "T")
                            else PB_BATTLE.Command(p2, "A" .. math.random(1, 3)); PB_BATTLE.Command(p2, "A1"); PB_BATTLE.Command(p2, "S1"); PB_BATTLE.Command(p2, "S2"); PB_BATTLE.Command(p2, "S3") end
                        end)
                    end
                end
            elseif cmd == "rabbits" then   -- retail-core battle: 3 rabbits (level 10) vs 3 rabbits (level 10), the lab plays the commands: "rabbits <rounds>"
                local rounds = tonumber(arg) or 8
                local mine = { { species = 721, level = 10, quality = 3 }, { species = 721, level = 10, quality = 3 }, { species = 721, level = 10, quality = 3 } }
                if PB_BATTLE.Start(pl, { { species = 721, level = 10, quality = 2 }, { species = 721, level = 10, quality = 2 }, { species = 721, level = 10, quality = 2 } }, mine) then
                    local g = pl:GetGUID()
                    for i = 1, rounds do
                        After(i * 9000, function() local p2 = GetPlayerByGUID(g); if p2 then PB_BATTLE.Command(p2, "A" .. ((i % 3) + 1)) end end)
                    end
                end
            elseif cmd == "spell" then
                local id, bp = arg:match("^(%d+)%s*(%-?%d*)$")
                local l = LAB[pl:GetGUIDLow()] or Setup(pl); local a, b = l and Get(l, "a"), l and Get(l, "b")
                if a and b and id then pcall(function() b:SetMaxHealth(1000); b:SetHealth(1000) end)
                    if bp ~= "" then a:CastCustomSpell(b, tonumber(id), true, tonumber(bp)) else a:CastSpell(b, tonumber(id), true) end end
            else Run(pl) end
            return
        end
    end
end, 1500, 0)
print("[pbfx] loaded (.pbfx)")
return true
