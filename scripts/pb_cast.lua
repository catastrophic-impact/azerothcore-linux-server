-- Pet battle presentation: one creature casts a REAL spell at another (animation, projectile, sound, hit visual) and the HP ends up EXACTLY where the engine says.
-- Why the tricks (found with .pbfx / pet-battle/watch_lab.sh, see DEVNOTES): a real spell only lands on an ATTACKABLE target, our pets are friendly (faction 35),
-- so for ~1.3 s (the projectile lands after the cast time) the caster/target get hostile factions, then everything is restored: factions, combat flag, the spell's own aura (Fireball leaves a DoT) and the HP.
-- The client draws NO floating numbers for creature vs creature damage, those come from the addon.
PB_CAST = PB_CAST or {}
local C = PB_CAST
C.DEBUG = false
-- 1690 vs 1691 (pet-battle/find_factions.py): hostile to each other, friendly to both sides' players, no guard faction hostile to them. Pets stay faction 35 (safe from mobs) and only swap for the 0.8 s of a cast.
C.FACTION_FRIENDLY, C.FACTION_ATT, C.FACTION_TGT, C.HOLD_MS = 35, 1690, 1691, 800

local gen = {}   -- per creature: only the LATEST cast may restore it (a restore from an older cast must not clobber a newer one)
local function After(ms, fn) CreateLuaEvent(function() fn() end, ms, 1) end
-- a stored Map userdata is INVALID by the time a timer fires: always get a fresh map through a player (found with the debug lines)
local function Fresh(pguid, guid)
    local pl = pguid and GetPlayerByGUID(pguid); local map = pl and pl:GetMap()
    return map and guid and map:GetWorldObject(guid) or nil
end

-- att/tgt: creature objects. spell: spell id (visual + sound). o.hp_after: exact health the target must have afterwards (clamped to >= 1; nil = leave the spell's damage).
-- o.heal = true: self/ally cast, no faction swap. o.dmg: basepoint damage for the spell (only changes the transient hit; the final HP is o.hp_after).
function C.Cast(att, tgt, spell, o)
    o = o or {}
    if not att or not tgt or not spell then return false end
    local ag, tg = att:GetGUID(), tgt:GetGUID()
    local al, tl = att:GetGUIDLow(), tgt:GetGUIDLow()
    gen[al] = (gen[al] or 0) + 1; gen[tl] = (gen[tl] or 0) + 1
    local ga, gt = gen[al], gen[tl]
    local pguid = o.pguid; if not pguid then local np = att:GetNearestPlayer(200); pguid = np and np:GetGUID() end
    local hostile = (not o.heal) and (not o.noSwap) and ag ~= tg   -- noSwap: the two pets are permanently hostile to each other already (battle pets), nothing to swap
    if hostile then pcall(function() att:SetFaction(C.FACTION_ATT); tgt:SetFaction(C.FACTION_TGT) end) end   -- the configuration verified with .pbfx + screenshots
    local ok = pcall(function()
        if o.dmg then att:CastCustomSpell(tgt, spell, true, o.dmg) else att:CastSpell(tgt, spell, true) end
    end)
    if not ok then print('[pb_cast] DIAG CastSpell failed spell=' .. tostring(spell)) end
    -- a hit creature starts fleeing (its own AI): stop it every 150 ms while the hit lands and put it back on its spot, instead of waiting for the window to end
    local hold = o.hold or C.HOLD_MS
    for ms = 150, hold - 100, 150 do
        After(ms, function()
            pcall(function()
                local t0 = Fresh(pguid, tg)
                if t0 then t0:MoveClear(); if o.home then t0:MoveTo(2, o.home[1], o.home[2], o.home[3], false); if o.home[4] then t0:SetFacing(o.home[4]) end end end
            end)
        end)
    end
    After(hold, function()
        local newer = gen[al] ~= ga or gen[tl] ~= gt   -- a later cast owns these creatures now: it restores them
        if newer then if o.done then pcall(o.done) end return end
        local oka, a = pcall(Fresh, pguid, ag); local okt, t = pcall(Fresh, pguid, tg)
        if C.DEBUG then print("[pb_cast] restore: att", oka, a ~= nil, "tgt", okt, t ~= nil, (not okt) and tostring(t) or "") end
        if not oka then a = nil end; if not okt then t = nil end
        local okr, err = pcall(function()
            if a then if hostile then a:SetFaction(C.FACTION_FRIENDLY) end; a:ClearInCombat(); a:MoveClear() end
            if t then
                if hostile then t:SetFaction(C.FACTION_FRIENDLY) end; t:ClearInCombat(); t:RemoveAura(spell)
                if o.hp_after then t:SetHealth(math.max(1, o.hp_after)) end
                t:MoveClear()   -- a hit critter runs away (its own AI): stop it and put it back on its spot
                if o.home then t:MoveTo(2, o.home[1], o.home[2], o.home[3], false) end
            end
        end)
        if C.DEBUG and not okr then print("[pb_cast] restore error: " .. tostring(err)) end
        if o.done then pcall(o.done, a, t) end
    end)
    return ok
end
print("[pb_cast] loaded")
return true
