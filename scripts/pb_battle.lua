-- Pet battle in the open world on the REAL engine (pb_engine.lua / pb_data.lua). Started by /pbtest (debug, random foes) or by a wild pet (pb_wild.lua).
-- 1 pet out, 2 benched (swap costs the turn), enemy sends one pet at a time. Pets are shrunk real creatures next to the player.
-- Client -> server: pbt|start, pbt|cmd|A1..A3 / S2,S3, pbt|rec|<enemy idx>, pbt|skiprec, pbt|quit, pbt|fx|<spellId>
-- Server -> client: pbt|begin, st, abil, in, act, hp, tag, fnt, turn, msg, end, recruit, rmsg, done
local Msg = require("acore_msg")
local D = require("pb_data")
local Eng = require("pb_core")   -- the retail-based battle engine
local Store = require("pb_store")

local LEVEL = 10
local POOL = {}; for entry in pairs(D.species) do POOL[#POOL + 1] = entry end   -- enemy species (random, abilities rolled: 1 of 2 per slot)
-- instant (no-duration) visual spells only: 46172 / 43452 / 43467 are long-lasting auras and stay on the pet
local FX_SPAWN, FX_POOF, FX_HIT, FX_DEBUFF = 52096, 12244, nil, 60958   -- Cosmetic Teleport Effect, Poof, (none), Cosmetic Fire Cast
local TRIES, MAX_RANGE = 3, 40
local battles = {}
local LEGACY = { 36871, 33194, 33200, 7562, 33198, 31575 }   -- creatures used by the first prototype

local SCALE = setmetatable({}, { __index = function(_, k) return Store.Scale(k) end })   -- shared size normalization lives in pb_store

local function After(ms, fn) CreateLuaEvent(function() fn() end, ms, 1) end
local function GetPlayer(b) return GetPlayerByGUID(b.pguid) end
local function GetObj(b, s)
    local g = b.guid[s]
    if not g then return nil end
    local ok, pl = pcall(GetPlayer, b)
    local map = ok and pl and pl:GetMap()
    return map and map:GetWorldObject(g)
end
local function Send(b, action, payload) local pl = GetPlayer(b); if pl then Msg.Send(pl, "pbt", action, payload) end end

local function Fx(obj, id, ms)   -- visual-only spell that removes itself again
    if not obj or not id then return end
    pcall(function() obj:CastSpell(obj, id, true) end)
    local guid = obj:GetGUID()
    local okp, np = pcall(function() return obj:GetNearestPlayer(150) end)
    local pguid = okp and np and np:GetGUID()
    CreateLuaEvent(function()   -- a stored Map userdata is invalid by now: look the map up again through a player
        pcall(function()   -- the visual spells are instant (check_fx.py), so a failed lookup only means nothing is left to remove
            local pl = pguid and GetPlayerByGUID(pguid); local map = pl and pl:GetMap()
            local o = map and map:GetWorldObject(guid)
            if o then o:RemoveAura(id) end
        end)
    end, ms or 1500, 1)
end


-- Sweep: removes leftover battle pets (script reload / crash lose the battle table). A battle pet = one of our species entries with faction 35
-- (friendly to all, which no wild wolf/kobold has) that no live battle owns.
local function Sweep(player, range)
    local keep = {}
    for _, b in pairs(battles) do for _, low in pairs(b.low or {}) do keep[low] = true end end   -- numeric low guids: a GUID object is never equal to another as a table key
    local n = 0
    local entries = {}
    for entry in pairs(D.species) do entries[#entries + 1] = entry; if D.StandIn(entry) then entries[#entries + 1] = D.StandIn(entry) end end
    for _, entry in ipairs(entries) do
        local ok, list = pcall(function() return player:GetCreaturesInRange(range or 120, entry) end)
        if ok and list then
            for _, c in ipairs(list) do
                local okf, fac = pcall(function() return c:GetFaction() end)
                local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
                local stray = fac == 35 or (okd and (dbg == 0 or dbg == nil) and (fac == 14 or fac == 1 or fac == 1690 or fac == 1691 or fac == 1907 or fac == 1908))   -- 14/1 = a pet caught mid-cast (pb_cast hostile swap) when a script reload happened
                if okf and stray and not keep[c:GetGUIDLow()] and not Store.IsFollower(c:GetGUIDLow()) and not (PB_WILD and PB_WILD.IsWild(c:GetGUIDLow())) then pcall(function() c:DespawnOrUnsummon(0) end); n = n + 1 end
            end
        end
    end
    -- leftovers of the FIRST prototype: shop-companion creatures spawned by script (no database row, no owner) in the normal world phase.
    -- Never touches wild creatures (they have a DB row), a player's vanity pet (it has an owner) or garrison pets (other phase).
    if Store.NormalWorld(player) then
        for _, entry in ipairs(LEGACY) do
            local ok, list = pcall(function() return player:GetCreaturesInRange(range or 120, entry) end)
            if ok and list then
                for _, c in ipairs(list) do
                    local okd, dbg = pcall(function() return c:GetDBTableGUIDLow() end)
                    local oko, owner = pcall(function() return c:GetOwner() end)
                    if okd and dbg == 0 and not (oko and owner) and not keep[c:GetGUIDLow()] then pcall(function() c:DespawnOrUnsummon(0) end); n = n + 1 end
                end
            end
        end
    end
    return n
end

local function Ground(b, x, y, z)
    local pl = GetPlayer(b)
    local ok, h = pcall(function() return pl:GetMap():GetHeight(x, y, b.phase) end)
    if ok and h and h > -1000 and math.abs(h - z) < 8 then return h + 0.1 end
    return z
end
local function Layout(b, pl)
    local x, y, z, o = pl:GetX(), pl:GetY(), pl:GetZ(), pl:GetO()
    local fx, fy, lx, ly = math.cos(o), math.sin(o), -math.sin(o), math.cos(o)
    local function pt(f, l) local px, py = x + fx * f + lx * l, y + fy * f + ly * l; return { px, py, Ground(b, px, py, z) } end
    b.pos = { P = pt(4.5, 2.2), E = pt(4.5, -2.2) }
    for _, s in ipairs({ "P", "E" }) do
        local me, ot = b.pos[s], b.pos[s == "P" and "E" or "P"]
        me[4] = math.atan2(ot[2] - me[2], ot[1] - me[1]); if me[4] < 0 then me[4] = me[4] + 6.2832 end
    end
end

-- STAND-IN templates: for every species flagged standin = true a clone of its creature_template (+ model rows) is created once, entry 9000000 + species:
-- same name and model, but no AIName / ScriptName / flags / loot / gossip, faction 35. Idempotent (skipped when the row exists). The server must reload creature templates once after creation.
local function EnsureStandIns()
    if not (WorldDBQuery and WorldDBExecute) then return end
    local cols = {}
    local q = WorldDBQuery("SELECT COLUMN_NAME FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'creature_template' ORDER BY ORDINAL_POSITION")
    if not q then return end
    repeat cols[#cols + 1] = q:GetString(0) until not q:NextRow()
    local ZERO = { difficulty_entry_1 = 0, difficulty_entry_2 = 0, difficulty_entry_3 = 0, KillCredit1 = 0, KillCredit2 = 0, npcflag = 0, unit_flags = 0, unit_flags2 = 0, dynamicflags = 0,
                   lootid = 0, pickpocketloot = 0, skinloot = 0, gossip_menu_id = 0, mingold = 0, maxgold = 0, VehicleId = 0, PetSpellDataId = 0, flags_extra = 0, ["rank"] = 0, MovementType = 0, type_flags = 0, faction = 35 }
    WorldDBExecute("UPDATE creature_template SET `type` = 1 WHERE entry >= 9000000 AND entry < 9100000 AND `type` = 12")   -- clones made before this rule
    local made = 0
    for species, sp in pairs(D.species) do
        local id = D.StandIn(species)
        if id and not WorldDBQuery("SELECT entry FROM creature_template WHERE entry = " .. id) then
            local sel = {}
            for _, c in ipairs(cols) do
                if c == "entry" then sel[#sel + 1] = tostring(id)
                elseif c == "AIName" or c == "ScriptName" then sel[#sel + 1] = "''"
                elseif ZERO[c] ~= nil then sel[#sel + 1] = tostring(ZERO[c])
                elseif c == "type" then sel[#sel + 1] = "IF(`type` = 12, 1, `type`)"   -- 12 = non-combat pet: spells never land on it (the cats / Spectral Tiger Cub): a plain Beast instead
                else sel[#sel + 1] = "`" .. c .. "`" end
            end
            WorldDBExecute("INSERT INTO creature_template (`" .. table.concat(cols, "`,`") .. "`) SELECT " .. table.concat(sel, ",") .. " FROM creature_template WHERE entry = " .. species)
            WorldDBExecute("INSERT IGNORE INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild) SELECT " .. id .. ", Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = " .. species)
            made = made + 1
        end
    end
    if made > 0 then
        print("[pb_battle] created " .. made .. " stand-in creature templates, reloading creature templates in 3 s")
        CreateLuaEvent(function() pcall(RunCommand, "reload creature_template") end, 3000, 1)
    end
end
EnsureStandIns()

local function SpawnPet(b, s, idx)
    local pet = b.eng[s][idx]; local p = b.pos[s]
    local sp = D.species[pet.species]
    local obj = PerformIngameSpawn(1, D.StandIn(pet.species) or pet.species, b.map, 0, p[1], p[2], p[3], p[4], false, 0, b.phase)
    if not obj then return end
    b.guid[s] = obj:GetGUID(); b.low[s] = obj:GetGUIDLow()
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetUnitFlags(0) end)   -- the cats (and other companion templates) carry IMMUNE_TO_PC|IMMUNE_TO_NPC (768): spells then never land on them, so no hit visual / sound / animation for EITHER side
    pcall(function() obj:SetFaction(35) end)   -- friendly to everyone: no mob, guard or player attacks it. (A PERMANENT hostile pair does not work: every pair that can hurt each other is also attacked by real mobs, e.g. a whole murloc camp joined a battle.)
    if pet.display and pet.display > 0 then pcall(function() obj:SetDisplayId(pet.display) end)   -- the skin this pet really has
    else
        local okd, d = pcall(function() return obj:GetDisplayId() end)
        if okd and d and d > 0 then
            pet.display = d   -- remembered: recruiting an enemy pet keeps ITS skin, and your own pet never changes skin by chance
            if s == "P" then local pl = GetPlayer(b); if pl then Store.SetDisplay(pl, pet.species, d) end end
        end
    end
    pcall(function() obj:SetScale(SCALE[pet.species] or 0.4) end)
    pcall(function() obj:SetMaxHealth(1000); obj:SetHealth(1000) end)   -- real spells hit it for presentation: a tiny creature must not die from the transient damage (pb_cast sets the exact health afterwards)
    pcall(function() obj:SetPhaseMask(b.phase, true) end)
    pcall(function() obj:SetHomePosition(p[1], p[2], p[3], p[4]) end)
    Fx(obj, FX_SPAWN, 1200)
end
local function Despawn(b, s, fx)
    local obj = GetObj(b, s)
    if obj then
        if fx then Fx(obj, FX_POOF, 600) end
        obj:DespawnOrUnsummon(fx and 400 or 0)
    end
    b.guid[s] = nil; b.low[s] = nil
end

-- ---------------------------------------------------------------- addon sync helpers
local function SendAbilities(b)
    local pet = b.eng.P[b.eng.active.P]
    for slot, a in ipairs(pet.abil) do Send(b, "abil", slot .. "|" .. a.icon .. "#" .. a.name .. "#" .. a.tip .. "#" .. a.cd) end
end
local function SendPet(b, s, i)
    local p = b.eng[s][i]
    Send(b, "st", string.format("%s,%d,%d,%d,%d,%s,%d,%d,%d,%s", s, i, p.level, p.hp, p.max, p.icon, p.quality or 1, p.species, math.floor(SCALE[p.species] * 100 + 0.5), p.name))
end
local function SendTags(b, s, stat)   -- stat = the snapshot an engine event carries (state at THAT moment); nil = current state. Structured: label~icon~turns~stacks~bad;...
    Send(b, "tag", s .. "|" .. (stat and stat[s] or b.api.StatusString(b.eng[s][b.eng.active[s]])))
end
local function FaceAll(b)   -- both pets look at each other again (a hit / fleeing / moving creature ends up facing anywhere); runs before every turn, a little later too
    for _, s in ipairs({ "P", "E" }) do
        local o = GetObj(b, s); local p = b.pos and b.pos[s]
        if o and p then pcall(function() o:SetFacing(p[4]) end) end
    end
end
local function SendTurn(b, force)
    FaceAll(b); After(500, function() if not b.over then FaceAll(b) end end)
    local pet = b.eng.P[b.eng.active.P]
    b.waiting = true; b.lastAct = os.time()
    Send(b, "turn", (force and "force" or "go") .. ";" .. pet.cd[1] .. "," .. pet.cd[2] .. "," .. pet.cd[3] .. ";" .. ((not force and b.api.CanTrap(b.eng)) and 1 or 0))
end

local function End(b, result)
    if b.over then return end
    b.over = true; b.endedAt = os.time()
    local plr = GetPlayer(b); if plr then Store.SetSuppressed(plr, false) end
    if not b.test then for _, p in ipairs(b.eng.P) do Store.SetHp(b.plow, p.species, p.hp > 0 and p.hp or 1) end end   -- a test team (lab) never touches saved pets   -- health is NOT restored: fainted pets are back with 1 HP, the rest keep what is left
    Send(b, "end", result)
    battles[b.plow] = nil
    After(result == "win" and 600 or 1200, function()
        if result ~= "win" then Despawn(b, "P", true) end
        Despawn(b, "E", true)
        if result == "win" and not b.test then
            local pl = GetPlayer(b)
            if pl and not b.eng.captured then   -- experience (a battle ended by capturing the last pet gives none, like retail)
                for i, p in ipairs(b.eng.P) do
                    if b.acted[i] then
                        local gain, lv, ups = Store.GrantXP(pl, p.species, b.enemyLevel)
                        if gain then Msg.Send(pl, "pbt", "xp", p.name .. "," .. gain .. "," .. lv .. "," .. ups) end
                    end
                end
            end
        end
        local plx = GetPlayer(b); if plx then Msg.Send(plx, "pbt", "done", "") end
        if result == "win" then After(500, function() Despawn(b, "P", true) end) end
    end)
end

-- ---------------------------------------------------------------- playback of the engine's event list
local CRATE_GO = 193761   -- Doodad_stormwindcrate05: a plain crate (type 5, not interactive) dropped over a pet being captured
local function Lunge(b, s, ts)
    local o, t = GetObj(b, s), GetObj(b, ts)
    if not (o and t) then return end
    local ox, oy, tx, ty = o:GetX(), o:GetY(), t:GetX(), t:GetY()
    local d = math.sqrt((tx - ox) ^ 2 + (ty - oy) ^ 2); if d < 0.1 then return end
    local k = math.max(0, d - 1.1) / d
    pcall(function() o:SetWalk(false) end)
    pcall(function() o:MoveTo(1, ox + (tx - ox) * k, oy + (ty - oy) * k, t:GetZ(), false) end)
end
local function Back(b, s)
    if not b.lunged[s] then return end
    b.lunged[s] = nil
    local o = GetObj(b, s); local p = b.pos[s]
    if o then pcall(function() o:MoveTo(2, p[1], p[2], p[3], false) end) end
    After(450, function() local o2 = GetObj(b, s); if o2 then pcall(function() o2:SetFacing(p[4]) end) end end)
end

local function Play(b, ev, i, status)
    if b.over then return end
    local pl = GetPlayer(b)
    if not pl or not pl:IsAlive() or pl:GetMapId() ~= b.map or pl:GetDistance(b.cx, b.cy, b.cz) > MAX_RANGE then
        Send(b, "msg", "The battle ended due to interruption."); return End(b, "interrupted")
    end
    local e = ev[i]
    if not e then
        SendTags(b, "P"); SendTags(b, "E")   -- durations changed at the end of the round: refresh the status icons
        if status == "force" then SendTurn(b, true) elseif status == "turn" then SendTurn(b, false) end
        return
    end
    local function nxt(ms) After(ms, function() Play(b, ev, i + 1, status) end) end
    local eng = b.eng

    if e.k == "act" then
        Send(b, "act", e.side .. "," .. e.idx .. "," .. e.name)
        if e.side == "P" then b.acted[e.idx] = true end   -- only pets that actually fought earn XP
        local o = GetObj(b, e.side)
        b.vis = e.vis   -- a real spell (visual + sound) for this ability, if it has one
        local ranged = e.ranged; b.ranged = ranged
        if e.dmg and b.vis and ranged and PB_CAST then nxt(500)   -- spell casters stay put; the spell is cast on the hit event (melee abilities with a spell still lunge)
        elseif e.dmg then
            local ts = e.side == "P" and "E" or "P"
            Lunge(b, e.side, ts); b.lunged[e.side] = true
            After(650, function() local a = GetObj(b, e.side); if a then pcall(function() a:Emote(35) end) end end)
            nxt(1000)
        else
            Fx(o, 60957, 1500)   -- utility ability: nature-cast glow on the user
            nxt(900)
        end
    elseif e.k == "trap" then   -- CAPTURE: a crate drops over the enemy pet, it is taken away, the capture is saved
        local t = GetObj(b, "E")
        Send(b, "msg", eng.E[e.idx].name .. " is being captured...")
        local crate
        if t then
            local okc, go = pcall(function() return PerformIngameSpawn(2, CRATE_GO, b.map, 0, t:GetX(), t:GetY(), t:GetZ(), t:GetO(), false, 0, b.phase) end)
            if okc and go then crate = go:GetGUID(); pcall(function() go:SetScale(3.6) end) end
            if t then Fx(t, FX_HIT, 1500) end
        end
        After(2200, function()
            local pl = GetPlayer(b)
            if crate then
                local mapx = pl and pl:GetMap(); local go = mapx and mapx:GetWorldObject(crate)
                if go then pcall(function() go:RemoveFromWorld(false) end) end
            end
            local t2 = GetObj(b, "E"); if t2 then Fx(t2, FX_POOF, 600); t2:DespawnOrUnsummon(300) end
            b.guid.E = nil; b.low.E = nil
            local pet = eng.E[e.idx]
            if pl and not b.test then
                local msg = Store.Capture(pl, pet)
                Msg.Send(pl, "pbt", "msg", msg)
            elseif pl then Msg.Send(pl, "pbt", "msg", "You captured " .. pet.name .. "! (test battle: not saved)") end
            Send(b, "fnt", "E," .. e.idx)
        end)
        nxt(2800)
    elseif e.k == "dmg" and e.bench then   -- splash on a benched pet: just its health number
        Send(b, "hp", e.tside .. "," .. e.tidx .. "," .. e.hp .. "," .. e.max .. ",-" .. e.dmg)
        nxt(250)
    elseif e.k == "faint" and e.bench then
        Send(b, "fnt", e.side .. "," .. e.idx)
        nxt(500)
    elseif e.k == "dmg" then
        local t = GetObj(b, e.tside)
        if not t then print(string.format('[pb_battle] DIAG no target object: side=%s guid=%s vis=%s', tostring(e.tside), tostring(b.low[e.tside]), tostring(b.vis))) end
        if b.vis and PB_CAST and t then
            local att = GetObj(b, e.side)
            pcall(function() t:Emote(33) end)   -- wound animation as before; the spell adds its own hit visual and sound
            if not att then print(string.format('[pb_battle] DIAG no attacker object: side=%s guid=%s', tostring(e.side), tostring(b.low[e.side]))) end
            if att then PB_CAST.Cast(att, t, b.vis, { pguid = b.pguid, ranged = b.ranged, hp_after = math.floor(e.hp / math.max(1, e.max) * 1000 + 0.5), home = b.pos[e.tside] }) end
        elseif t then pcall(function() t:Emote(33) end); Fx(t, FX_HIT, 900) end
        Send(b, "hp", e.tside .. "," .. e.tidx .. "," .. e.hp .. "," .. e.max .. "," .. (e.crit and "-" .. e.dmg .. "!" or "-" .. e.dmg))
        if not e.more then After(600, function() Back(b, e.side) end) end   -- a multi-hit attacker stays put until its last hit
        nxt(e.more and 650 or 1000)
    elseif e.k == "dodge" then
        local t = GetObj(b, e.side)
        if t and e.text ~= "Burrowed!" then pcall(function() t:Emote(4) end) end   -- little hop out of the way
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. "," .. (e.text or "Dodge!"))   -- hp as it was at THIS moment, not the end of the round
        if not e.more then After(500, function() Back(b, e.from) end) end
        nxt(e.more and 650 or 1000)
    elseif e.k == "buff" or e.k == "debuff" then
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        if e.k == "debuff" then Fx(GetObj(b, e.side), FX_DEBUFF, 1200) end
        nxt(700)
    elseif e.k == "heal" then
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. ",+" .. e.amt)
        nxt(e.quick and 450 or 1000)
    elseif e.k == "stunned" then
        Send(b, "msg", eng[e.side][e.idx].name .. (e.self and " is hibernating and cannot act!" or (e.label == "Polymorphed" and " is a sheep and cannot act!" or " is stunned and loses its turn!")))
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        nxt(1300)
    elseif e.k == "dot" then
        local o = GetObj(b, e.side)
        if o then pcall(function() o:Emote(33) end) end
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. ",-" .. e.dmg)
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        nxt(1000)
    elseif e.k == "faint" then
        local o = GetObj(b, e.side)
        if o then pcall(function() o:Emote(34) end) end
        Back(b, e.side == "P" and "E" or "P")
        After(1000, function() Despawn(b, e.side, true); Send(b, "fnt", e.side .. "," .. e.idx) end)
        nxt(1700)
    elseif e.k == "swap" then
        Send(b, "msg", "Go, " .. eng.P[e.idx].name .. "!")
        Despawn(b, "P", true)
        After(700, function() SpawnPet(b, "P", e.idx); Send(b, "in", "P," .. e.idx); SendAbilities(b); SendTags(b, "P") end)
        nxt(1600)
    elseif e.k == "weather" then
        Send(b, "weather", e.id .. "|" .. e.turns .. "|" .. (e.name or ""))
        nxt(e.id ~= 0 and 500 or 100)
    elseif e.k == "spawn" then
        SpawnPet(b, e.side, e.idx); Send(b, "in", e.side .. "," .. e.idx); SendTags(b, e.side)
        nxt(1400)
    elseif e.k == "end" then
        End(b, e.result)
    else nxt(0) end
end

-- ---------------------------------------------------------------- start / commands
-- enemies = nil: debug fight against 3 random species at your average level; otherwise { {species=, level=}, ... } (a wild encounter)
local function Start(player, enemies, teamOverride)
    local g = player:GetGUIDLow()
    local old = battles[g]
    if old then old.over = true; Despawn(old, "P", true); Despawn(old, "E", true); battles[g] = nil end
    Sweep(player)
    if player:IsInCombat() or not player:IsAlive() then Msg.Send(player, "pbt", "msg", "You cannot battle right now."); return false end
    Store.SyncCompanions(player)
    local mine = teamOverride or Store.ActiveTeam(player)
    if #mine == 0 then Msg.Send(player, "pbt", "msg", "You have no pets yet. Open /pets."); return false end
    local P, Ei, sum = {}, {}, 0
    for i, m in ipairs(mine) do P[i] = Eng.NewPet(m.species, m.level, m.picks, nil, { quality = m.quality, hp = m.hp }); P[i].display = m.display; sum = sum + m.level end
    local lvl = math.max(1, math.floor(sum / #mine + 0.5))
    if enemies then
        lvl = enemies[1].level
        for i, e in ipairs(enemies) do Ei[i] = Eng.NewPet(e.species, e.level, nil, nil, { quality = e.quality or Eng.RollQuality() }); Ei[i].display = e.display end
    else
        for i = 1, 3 do Ei[i] = Eng.NewPet(POOL[math.random(1, #POOL)], lvl, nil, nil, { quality = Eng.RollQuality() }) end
    end
    local b = { acted = {}, enemyLevel = lvl, pguid = player:GetGUID(), plow = player:GetGUIDLow(), map = player:GetMapId(), phase = Store.NormalWorld(player) and 1 or player:GetPhaseMask(), guid = {}, low = {}, lunged = {}, eng = Eng.NewBattle(P, Ei), api = Eng, test = teamOverride ~= nil }
    b.cx, b.cy, b.cz = player:GetX(), player:GetY(), player:GetZ()
    Layout(b, player)
    Store.SetSuppressed(player, true)   -- the follower steps aside during the battle
    battles[g] = b
    Send(b, "begin", "")
    for _, s in ipairs({ "P", "E" }) do for i = 1, #b.eng[s] do SendPet(b, s, i) end end
    SendAbilities(b)
    After(300, function() SpawnPet(b, "P", 1); Send(b, "in", "P,1") end)
    After(1300, function() SpawnPet(b, "E", 1); Send(b, "in", "E,1") end)
    After(2600, function() SendTags(b, "P"); SendTags(b, "E"); SendTurn(b, false) end)
    return true
end
-- Watchdog: no battle may live forever. Ends battles whose player left / died / changed map / walked away, and battles that wait for a move for
-- IDLE_TIMEOUT seconds (e.g. the window never opened); forgets a recruit picker left open that long.
local IDLE_TIMEOUT = 120
local function Watchdog()
    local now = os.time()
    for low, b in pairs(battles) do
        if b.over then
            if b.endedAt and now - b.endedAt > IDLE_TIMEOUT then battles[low] = nil end
        else
            local pl = GetPlayer(b)
            local gone = not pl or not pl:IsAlive() or pl:GetMapId() ~= b.map or pl:GetDistance(b.cx, b.cy, b.cz) > MAX_RANGE
            if gone then Send(b, "msg", "The battle ended due to interruption."); End(b, "interrupted")
            elseif b.waiting and b.lastAct and now - b.lastAct > IDLE_TIMEOUT then Send(b, "msg", "The battle timed out."); End(b, "interrupted") end
        end
    end
end
CreateLuaEvent(Watchdog, 5000, 0)

-- FREEZE: while a battle runs, every ordinary creature around it is stunned (Freeze, spell 9454: aura 12 MOD_STUN, no cast time). Why: pet casts swap the pets to hostile factions for
-- ~0.8 s (pb_cast), and mobs (murlocs in Elwynn) join in and attack them. Self-healing: the aura gets a 4 s duration and is refreshed every second, so a reload / crash / end of the
-- battle releases every mob within 4 s and nothing has to be remembered or restored.
local FREEZE_SPELL, FREEZE_RANGE, FREEZE_MS = 9454, 50, 4000
local function FreezeTick()
    for low, b in pairs(battles) do
        if not b.over or (b.endedAt and os.time() - b.endedAt <= 3) then
            local pl = GetPlayer(b)
            if pl then
                local ok, list = pcall(function() return pl:GetCreaturesInRange(FREEZE_RANGE) end)
                if ok and list then
                    for _, c in ipairs(list) do pcall(function()
                        if not c:IsAlive() or D.species[c:GetEntry()] or D.IsStandIn(c:GetEntry()) or c:GetFaction() == 35 then return end   -- battle pets / wild pets / peaceful NPCs: untouched
                        local own = c:GetOwnerGUID(); if own and own ~= 0 then return end                     -- someone's pet or guardian
                        local a = c:GetAura(FREEZE_SPELL) or c:AddAura(FREEZE_SPELL, c)
                        if a then a:SetDuration(FREEZE_MS) end
                        if c:IsInCombat() then c:AttackStop(); c:ClearThreatList() end
                    end) end
                end
            end
        end
    end
end
CreateLuaEvent(FreezeTick, 1000, 0)
PB_BATTLE = { Watchdog = Watchdog, Sweep = Sweep, Start = Start, InBattle = function(player) return battles[player:GetGUIDLow()] ~= nil end }

-- /pbtest            3 random enemy species;   /pbtest 1124 474 30   those species (level 5) as the enemy team;   /pbtest 1196@20 3118@25   with a level each (1-25)
Msg.On("pbt", "start", function(player, payload)
    local list = {}
    for id, lv in tostring(payload or ""):gmatch("(%d+)@?(%d*)") do
        local n = tonumber(id)
        if D.species[n] and #list < 3 then list[#list + 1] = { species = n, level = math.max(1, math.min(D.MAX_LEVEL, tonumber(lv) or 5)), quality = Eng.RollQuality() } end
    end
    Start(player, #list > 0 and list or nil)
end)
Msg.On("pbt", "clean", function(player)
    local low = player:GetGUIDLow()
    local b = battles[low]
    if b then   -- your own (stuck) battle: end it right now and remove its pets
        b.over = true; Despawn(b, "P", true); Despawn(b, "E", true); battles[low] = nil
    end
    Msg.Send(player, "pbt", "end", "interrupted")   -- always close the battle bars (a script reload forgets the battle but not the addon window)
    Msg.Send(player, "pbt", "msg", "Removed " .. Sweep(player, 200) .. " leftover pets nearby.")
end)
local function Command(player, payload)
    local b = battles[player:GetGUIDLow()]
    if not b or b.over or not b.waiting then return end
    local eng = b.eng
    local kind, n = payload:sub(1, 1), tonumber(payload:sub(2))
    local cmd
    if kind == "A" and n and n >= 1 and n <= 3 and b.api.Ready(eng.P[eng.active.P], n) and eng.P[eng.active.P].hp > 0 then cmd = payload
    elseif kind == "S" and eng.P[n] and eng.P[n].hp > 0 and n ~= eng.active.P and not (eng.P[eng.active.P].hp > 0 and b.api.Locked(eng.P[eng.active.P], "swapOutLock")) then cmd = payload
    elseif kind == "T" and eng.P[eng.active.P].hp > 0 and b.api.CanTrap(eng) then cmd = "T" end
    if not cmd then return end
    b.waiting = false
    local ev, status = b.api.Round(eng, cmd, b.api.AI(eng))
    Play(b, ev, 1, status)
end
Msg.On("pbt", "cmd", Command)
PB_BATTLE.Command = Command
PB_BATTLE.CanTrap = function(player) local b = battles[player:GetGUIDLow()]; return b ~= nil and b.waiting and not b.over and b.api.CanTrap(b.eng) or false end
PB_BATTLE.Waiting = function(player) local b = battles[player:GetGUIDLow()]; return b ~= nil and b.waiting and not b.over end
PB_BATTLE.CleanAll = function(player) Msg.Send(player, "pbt", "end", "interrupted"); local b = battles[player:GetGUIDLow()]; if b then b.over = true; Despawn(b, "P", false); Despawn(b, "E", false); battles[player:GetGUIDLow()] = nil end; return Sweep(player, 200) end
Msg.On("pbt", "quit", function(player)
    local b = battles[player:GetGUIDLow()]
    if b and not b.over then Send(b, "msg", "You forfeited the battle."); End(b, "loss") end
end)
Msg.On("pbt", "fx", function(player, payload)   -- animation lab: /pbtest fx <spellId>
    local b = battles[player:GetGUIDLow()]; local o = b and GetObj(b, "P")
    local id = tonumber(payload)
    if o and id then Fx(o, id, 4000) end
end)
RegisterPlayerEvent(4, function(_, player)
    local b = battles[player:GetGUIDLow()]
    if b then b.over = true; Despawn(b, "P", false); Despawn(b, "E", false); battles[player:GetGUIDLow()] = nil end
end)
-- after a script reload: clean up around everyone online right now
pcall(function() for _, pl in ipairs(GetPlayersInWorld()) do Sweep(pl, 200) end end)
print("[pb_battle] loaded")
return true
