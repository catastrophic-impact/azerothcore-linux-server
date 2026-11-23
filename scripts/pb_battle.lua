-- Pet battle in the open world on the REAL engine (pb_engine.lua / pb_data.lua). Started by /pbtest (debug, random foes) or by a wild pet (pb_wild.lua).
-- 1 pet out, 2 benched (swap costs the turn), enemy sends one pet at a time. Pets are shrunk real creatures next to the player.
-- Client -> server: pbt|start, pbt|cmd|A1..A3 / S2,S3, pbt|rec|<enemy idx>, pbt|skiprec, pbt|quit, pbt|fx|<spellId>
-- Server -> client: pbt|begin, st, abil, in, act, hp, tag, fnt, turn, msg, end, recruit, rmsg, done
-- Needs: mod-ale (built and tested with commit 84b85cc) and the shared core scripts acore_*.lua in the same lua_scripts folder.
for _, m in ipairs({ "acore_msg", "acore_prime", "acore_bus", "acore_util", "acore_settings" }) do if not pcall(require, m) then print("[Pet Battles] DISABLED: the shared core script " .. m .. ".lua is missing from lua_scripts (copy all acore_*.lua files, see the README)"); return true end end
local Msg = require("acore_msg")
local D = require("pb_data")
local Eng = require("pb_core")   -- the retail-based battle engine
-- one icon per pet TYPE (keep in sync with TYPE_ICON in addons/wotlk_pets/Pets.lua): the battle frames show it instead of a 3D model (tall models had their heads cut off)
local TYPE_ICON = { Humanoid = "INV_Misc_Head_Human_01", Dragonkin = "INV_Misc_Head_Dragon_01", Flying = "Ability_Druid_FlightForm", Undead = "Spell_Shadow_AnimateDead", Critter = "INV_Egg_01",
    Magic = "Spell_Arcane_Arcane01", Elemental = "Spell_Nature_EarthElemental_Totem", Mechanical = "INV_Gizmo_01", Aquatic = "Ability_Druid_AquaticForm", Beast = "Ability_Racial_BearForm" }
local Store = require("pb_store")

local LEVEL = 10
local POOL = {}; for entry in pairs(D.species) do POOL[#POOL + 1] = entry end   -- enemy species (random, abilities rolled: 1 of 2 per slot)
-- instant (no-duration) visual spells only: 46172 / 43452 / 43467 are long-lasting auras and stay on the pet
local FX_LEVELUP = 47292   -- Level Up (the character's gold burst; instant, no aura - checked by check_fx.py)
local FX_SPAWN, FX_POOF, FX_HIT, FX_DEBUFF = 52096, 12244, nil, 60958   -- Cosmetic Teleport Effect, Poof, (none), Cosmetic Fire Cast
local TRIES, MAX_RANGE = 3, 40
local battles = {}
local LEGACY = { 36871, 33194, 33200, 7562, 33198, 31575 }   -- creatures used by the first prototype

local SCALE = setmetatable({}, { __index = function(_, k) return Store.Scale(k) end })   -- shared size normalization lives in pb_store

local function After(ms, fn) CreateLuaEvent(function() fn() end, ms, 1) end
-- BATTLE TRACE (debug): a transcript of one battle in world.out, lines "[pbtrace] b<battle> t=<ms>": what the player was OFFERED, each engine event, every message sent to the
-- addon, every presentation step the server orders (emote id, real spell id, move). t = the scheduled playback time in ms since the battle began (waiting for the player is not counted).
-- On for ONE player with `/pbtest trace` (GM), or for everybody with PB_TRACE = true. Off: nothing is printed. The VIOLATION check below is always on.
local traceOn, battleNo = {}, 0
local RecentActs = {}   -- [player guidlow] = the last 6 abilities played, newest last
local function Tracing(b) return PB_TRACE or (b and b.trace) end
local function Tr(b, off, fmt, ...)
    if not Tracing(b) then return end
    local ok, line = pcall(string.format, fmt, ...)
    print(string.format("[pbtrace] b%d t=%6d %s", b.no or 0, off or b.vt or 0, ok and line or fmt))   -- off = absolute playback time (a delayed step), nil = now
end
local function GetPlayer(b) return GetPlayerByGUID(b.pguid) end
local function GetObj(b, s)
    local g = b.guid[s]
    if not g then return nil end
    local ok, pl = pcall(GetPlayer, b)
    local map = ok and pl and pl:GetMap()
    return map and map:GetWorldObject(g)
end
local function Send(b, action, payload) Tr(b, nil, "-> addon %s|%s", action, tostring(payload)); local pl = GetPlayer(b); if pl then Msg.Send(pl, "pbt", action, payload) end end
local function Emote(b, side, id, off)   -- one animation on a battle pet (traced)
    local o = GetObj(b, side)
    Tr(b, off, "emote %d on %s%s", id, side, o and "" or " (NO OBJECT)")
    if o then pcall(function() o:PerformEmote(id) end) end
end

local function Fx(obj, id, ms, b, side)   -- visual-only spell that removes itself again (b, side: only for the trace)
    if not obj or not id then return end
    if b then Tr(b, nil, "fx spell %d on %s for %d ms", id, tostring(side), ms or 1500) end
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

-- NO terrain query: the heightmap is not the floor in mines/caves/buildings (it sank the pets). Pets are spawned a yard above the player's own height and the movement system settles them
-- on the real floor (SpawnPet below reads the settled height back into b.pos). Verified live: outdoors, mine floors.
local function Ground(b, x, y, z) return z + 1.0 end
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
                   lootid = 0, pickpocketloot = 0, skinloot = 0, gossip_menu_id = 0, mingold = 0, maxgold = 0, VehicleId = 0, PetSpellDataId = 0, flags_extra = 0, ["rank"] = 0, MovementType = 0, type_flags = 0, faction = 35, family = 0 }   -- family 0: the 3.3.5 client otherwise raises a creature's size to its CREATURE FAMILY scale (CreatureFamily.dbc), which overrode the display scale k
    WorldDBExecute("UPDATE creature_template SET `type` = 1 WHERE entry >= 9000000 AND entry < 9100000 AND `type` = 12")   -- clones made before this rule
    local made = 0
    local have = {}   -- ONE bulk query instead of one SELECT per species on every script load (the species list grows into the thousands)
    do local qa = WorldDBQuery("SELECT entry FROM creature_template WHERE entry >= 9000000 AND entry < 9100000"); if qa then repeat have[qa:GetUInt32(0)] = true until not qa:NextRow() end end
    for species, sp in pairs(D.species) do
        local id = D.StandIn(species)
        if id and not have[id] then
            local sel = {}
            for _, c in ipairs(cols) do
                if c == "entry" then sel[#sel + 1] = tostring(id)
                elseif c == "AIName" or c == "ScriptName" then sel[#sel + 1] = "''"
                elseif ZERO[c] ~= nil then sel[#sel + 1] = tostring(ZERO[c])
                elseif c == "type" then sel[#sel + 1] = "IF(`type` = 12, 1, `type`)"   -- 12 = non-combat pet: spells never land on it (the cats / Spectral Tiger Cub): a plain Beast instead
                else sel[#sel + 1] = "`" .. c .. "`" end
            end
            WorldDBExecute("INSERT INTO creature_template (`" .. table.concat(cols, "`,`") .. "`) SELECT " .. table.concat(sel, ",") .. " FROM creature_template WHERE entry = " .. species)
            WorldDBExecute("INSERT IGNORE INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild) SELECT " .. id .. ", Idx, 11686, 1, Probability, VerifiedBuild FROM creature_template_model WHERE CreatureID = " .. species)   -- INVISIBLE (11686): the real skin is swapped on at spawn (Store.Dress)
            made = made + 1
        end
    end
    for species in pairs(D.species) do   -- weapons / shields (creature_equip_template is keyed by creature entry): idempotent; only needed when clones were just made (custom-sql/016 carries them otherwise)
        local id = D.StandIn(species)
        if id and made > 0 then WorldDBExecute("INSERT IGNORE INTO creature_equip_template (CreatureID, ID, ItemID1, ItemID2, ItemID3, VerifiedBuild) SELECT " .. id .. ", ID, ItemID1, ItemID2, ItemID3, VerifiedBuild FROM creature_equip_template WHERE CreatureID = " .. species) end
    end
    if made > 0 then
        print("[pb_battle] created " .. made .. " stand-in creature templates, reloading creature templates in 3 s")
        CreateLuaEvent(function() pcall(RunCommand, "reload creature_template") end, 3000, 1)
    end
end
EnsureStandIns()

local PickDisplay = Store.PickDisplay   -- random model row of the species

-- A new model is always drawn at full size for a moment: every battle pet is BORN SETTLE_DEPTH yards underground (hidden by the terrain) with a small portal on the ground where it will stand,
-- and is lifted to its spot after SETTLE_MS, when the portal closes. Everything that waits on the pet (turn offer, next event) is pushed back by SETTLE_MS.
local SETTLE_MS, SETTLE_DEPTH, PORTAL_GO = 3000, 40, 142074   -- 142074 Bly's Escape Portal: the warlock portal look, a type-5 decoration (nothing to click)
local function ClearPortal(b, s)
    local g = b.portal and b.portal[s]; if not g then return end
    b.portal[s] = nil
    local m = GetMapById(b.map, 0); local go = m and m:GetWorldObject(g)
    if go then pcall(function() go:RemoveFromWorld(false) end) end
end
local function SpawnPet(b, s, idx)
    local pet = b.eng[s][idx]; local p = b.pos[s]
    local sp = D.species[pet.species]
    local obj = PerformIngameSpawn(1, D.StandIn(pet.species) or pet.species, b.map, 0, p[1], p[2], p[3] - SETTLE_DEPTH, p[4], false, 0, b.phase)
    if not obj then return end
    b.guid[s] = obj:GetGUID(); b.low[s] = obj:GetGUIDLow()
    pcall(function() obj:SetReactState(0) end)
    pcall(function() obj:SetUnitFlags(0) end)   -- the cats (and other companion templates) carry IMMUNE_TO_PC|IMMUNE_TO_NPC (768): spells then never land on them, so no hit visual / sound / animation for EITHER side
    pcall(function() obj:SetFaction(35) end)   -- friendly to everyone: no mob, guard or player attacks it. (A PERMANENT hostile pair does not work: every pair that can hurt each other is also attacked by real mobs, e.g. a whole murloc camp joined a battle.)
    local worn = Store.Dress(obj, pet.species, pet.display)   -- the skin this pet really has (swapped on over the invisible stand-in)
    if not (pet.display and pet.display > 0) and worn then
        pet.display = worn   -- remembered: recruiting an enemy pet keeps ITS skin, and your own pet never changes skin by chance
        if s == "P" then local pl = GetPlayer(b); if pl then Store.SetDisplay(pl, pet.species, worn) end end
    end
    do local okd2, d2 = pcall(function() return obj:GetDisplayId() end); pcall(function() obj:SetScale(Store.ScaleOf(pet.species, okd2 and d2 or nil)) end) end   -- the scale of the model it WEARS (a species can wear several models)
    pcall(function() obj:SetMaxHealth(1000); obj:SetHealth(1000) end)   -- real spells hit it for presentation: a tiny creature must not die from the transient damage (pb_cast sets the exact health afterwards)
    pcall(function() obj:SetPhaseMask(b.phase, true) end)
    b.portal = b.portal or {}; ClearPortal(b, s)
    local okp, go = pcall(function() return PerformIngameSpawn(2, PORTAL_GO, b.map, 0, p[1], p[2], p[3], p[4], false, 0, b.phase) end)
    if okp and go then b.portal[s] = go:GetGUID() end
    local low = obj:GetGUIDLow()
    After(SETTLE_MS, function()   -- settled: close the portal and lift the pet to its spot
        ClearPortal(b, s)
        local o = GetObj(b, s); if not o or o:GetGUIDLow() ~= low then return end
        pcall(function() o:NearTeleport(p[1], p[2], p[3], p[4]) end)
        pcall(function() o:SetHomePosition(p[1], p[2], p[3], p[4]) end)
        pcall(function() o:MoveTo(1, p[1], p[2], p[3], true) end)   -- settle on the real floor
        pcall(function() o:RegisterEvent(function(ev, d, n, c)       -- read the settled height back so every later MoveTo / home position uses the real floor
            local z = c:GetZ(); if z and math.abs(z - p[3]) < 4 then p[3] = z; pcall(function() c:SetHomePosition(p[1], p[2], z, p[4]) end) end
        end, 800, 1) end)
        Fx(o, FX_SPAWN, 1200)
    end)
end
local function Despawn(b, s, fx)
    ClearPortal(b, s)
    local obj = GetObj(b, s)
    if obj then
        if fx then Fx(obj, FX_POOF, 600) end
        obj:DespawnOrUnsummon(fx and 400 or 0)
    end
    b.guid[s] = nil; b.low[s] = nil
end

-- ---------------------------------------------------------------- addon sync helpers
local function Cap(text, n)   -- wire-safe text (no separators) cut at a sentence end when too long (addon messages are limited to 240 characters)
    text = tostring(text or ""):gsub("[#|~;]", " ")
    if #text <= n then return text end
    local cut = text:sub(1, n); local dot = cut:match("^.*()%. ")
    return (dot and dot > n * 0.5) and cut:sub(1, dot) or (cut:sub(1, n - 3) .. "...")
end
local function SendAbilities(b)
    local pet = b.eng.P[b.eng.active.P]
    for slot = 1, 3 do Send(b, "abil", slot .. "|") end   -- clear the whole bar every time, then load the pet that is in (a pet with fewer abilities left the previous pet's, e.g. Chew Cud, on the bar)
    for slot, a in ipairs(pet.abil) do
        local nm = Cap(a.name, 30); local room = math.min(170, 240 - (#("pbt|abil|" .. slot .. "|") + #a.icon + #nm + #tostring(a.cd) + 4))   -- addon messages are limited to 240 characters: flavored spell names and icons are longer than retail's
        Send(b, "abil", slot .. "|" .. a.icon .. "#" .. nm .. "#" .. Cap(a.tip, room) .. "#" .. a.cd)
    end
end
-- what the player may know about the active pets: family matchup (both sides) and the ENEMY's abilities with their cooldowns left (retail shows these too)
local function SendInfo(b)
    for _, s in ipairs({ "P", "E" }) do
        local pet = b.eng[s][b.eng.active[s]]
        local f = b.api.FamilyInfo(pet.family)
        Send(b, "info", table.concat({ s, f.name, f.strong, f.weak, f.hurtBy, f.resists }, "|"))
    end
    local e = b.eng.E[b.eng.active.E]
    for slot = 1, 3 do Send(b, "eabil", slot .. "|") end   -- same for the enemy's abilities
    for slot = 1, 3 do
        local a = e.abil[slot]
        if a then Send(b, "eabil", slot .. "|" .. a.icon .. "#" .. Cap(a.name, 30) .. "#" .. Cap(a.tip, 150) .. "#" .. a.cd .. "#" .. (e.cd[slot] or 0)) end
    end
end
local PREVIEW_BASE = 9100000   -- preview entry = PREVIEW_BASE + display id: a client creature record with ONE model, so the 3D box shows the exact skin (male/female) the pet spawns with
local function SendPet(b, s, i)
    local p = b.eng[s][i]
    local entry = p.species
    local pl = GetPlayer(b)
    if p.display and p.display > 0 and pl then
        entry = PREVIEW_BASE + p.display
        require("acore_prime").SendAs(pl, entry, p.species, p.display)
    end
    Send(b, "st", string.format("%s,%d,%d,%d,%d,%s,%d,%d,%d,%s", s, i, p.level, p.hp, p.max, TYPE_ICON[p.family] or p.icon, p.quality or 1, entry, math.floor(Store.ScaleOf(p.species, p.display) * 100 + 0.5), p.name))   -- the scale of the model the pet really wears (same value SpawnPet sets)   -- the pet TYPE icon (no 3D model in the battle frames)
end
local function SendTags(b, s, stat)   -- stat = the snapshot an engine event carries (state at THAT moment); nil = current state. Structured: label~icon~turns~stacks~bad;...
    local str = stat and stat[s] or b.api.StatusString(b.eng[s][b.eng.active[s]])
    do   -- the status list can exceed the 240 character message limit (6 statuses): the first part replaces the list ("tag"), the rest is appended ("tag2")
        local parts, cur = {}, ""
        for item in str:gmatch("[^;]+") do
            if #cur + #item + 1 > 190 and cur ~= "" then parts[#parts + 1] = cur; cur = "" end
            cur = cur .. item .. ";"
        end
        parts[#parts + 1] = cur
        for i, part in ipairs(parts) do Send(b, i == 1 and "tag" or "tag2", s .. "|" .. part) end
    end
    b.tipSent = b.tipSent or {}
    for label in str:gmatch("([^~;]+)~[^~;]+~%d+~%d+~%d") do   -- the description of each status, once per battle (the addon keeps it by label)
        local tip = b.api.tips and b.api.tips[label]
        if tip and tip ~= "" and b.tipSent[label] ~= tip then b.tipSent[label] = tip; Send(b, "stip", Cap(label, 30) .. "#" .. Cap(tip, 190)) end
    end
end
local function FaceAll(b)   -- both pets look at each other again (a hit / fleeing / moving creature ends up facing anywhere); runs before every turn, a little later too
    for _, s in ipairs({ "P", "E" }) do
        local o = GetObj(b, s); local p = b.pos and b.pos[s]
        if o and p then pcall(function() o:SetFacing(p[4]) end) end
    end
end
local Play   -- forward declaration (defined below)
-- Legal: the command the player may give right now (nil = not offered / refused). Used by Command AND by the OFFER line of the trace, so both always agree.
local function Legal(b, cmd)
    local eng = b.eng; local pet = eng.P[eng.active.P]
    local kind, n = cmd:sub(1, 1), tonumber(cmd:sub(2))
    if kind == "A" and n and n >= 1 and n <= 3 and b.api.Ready(pet, n) and pet.hp > 0 then return cmd
    elseif kind == "S" and eng.P[n] and eng.P[n].hp > 0 and n ~= eng.active.P and not (pet.hp > 0 and b.api.Locked(pet, "swapOutLock")) then return cmd
    elseif kind == "T" and pet.hp > 0 and b.api.CanTrap(eng) then return "T" end
end
-- Honored: the INVARIANT 'a choice that is offered must be honored by the engine'. Given the command and the event list of the round it started: did the engine do what was
-- offered? false + reason otherwise (e.g. the player picked ability 2 and the engine ran slot 1, or a trap was offered and nothing was captured).
-- An ability may legitimately not happen when the enemy acted FIRST and fainted or stunned the player's pet.
local function Honored(cmd, ev)
    local kind, n = cmd:sub(1, 1), tonumber(cmd:sub(2))
    local enemyActed, forcedOut = false, false
    for _, e in ipairs(ev) do
        if kind == "S" then if e.k == "swap" and e.side == "P" and e.idx == n then return true end
        elseif kind == "T" then if e.k == "trap" then return true end
        else
            if e.k == "act" and e.side == "E" then enemyActed = true end
            if e.k == "swap" and e.side == "P" and e.forced then forcedOut = true end   -- Nether Gate / Death Grip: the choice was made for the pet that got pulled out; the new pet uses the nearest legal slot (its own cooldowns)
            if e.k == "act" and e.side == "P" then
                if e.slot == n or forcedOut then return true end
                return false, "ability " .. n .. " was offered, the engine ran slot " .. tostring(e.slot) .. " (" .. tostring(e.name) .. ")"
            end
            if enemyActed and e.side == "P" and (e.k == "stunned" or e.k == "faint") then return true end   -- the enemy went first and took the turn away
            if enemyActed and e.k == "faint" and e.side == "E" and not e.bench then return true end   -- the enemy went first and then DIED (reflect / damage over time): no target is left for the player's pet
        end
    end
    if kind == "S" then return false, "swap to " .. n .. " was offered, no swap happened" end
    if kind == "T" then return false, "capture was offered, nothing was captured" end
    return false, "ability " .. n .. " was offered, the player's pet never acted"
end
local violations = 0
local function SendTurn(b, force)
    FaceAll(b); After(500, function() if not b.over then FaceAll(b) end end)
    local pet = b.eng.P[b.eng.active.P]
    b.waiting = true; b.lastAct = os.time()
    SendInfo(b)
    local chan = pet.channel   -- an ability that runs over several rounds (Stampede, Dive, Solar Beam...): the player has NO choice until it ends, so nothing is offered
    if not force and pet.hp > 0 and (chan or b.api.CantAct(pet)) then   -- stunned / asleep / mid-ability: everything stays greyed out and the turn passes by itself
        if chan and not b.api.CantAct(pet) then Send(b, "turn", "lock;0,0,0;0;" .. Cap(chan.ab.name .. ": round " .. chan.turn .. " of " .. #chan.ab.turns, 40))
        else Send(b, "turn", "stun;0,0,0;0;" .. (Eng.LockLabel(pet) or "Stunned")) end
        b.waiting = false
        After(1500, function()
            if b.over or b.waiting then return end
            b.lastAct = os.time(); local ev, status = b.api.Round(b.eng, "A1", b.api.AI(b.eng)); Play(b, ev, 1, status)
        end)
        return
    end
    if Tracing(b) then
        local offered = {}
        for _, c in ipairs({ "A1", "A2", "A3", "S1", "S2", "S3", "T" }) do if Legal(b, c) then offered[#offered + 1] = c end end
        Tr(b, nil, "OFFER round %d (%s): %s | active %s hp %d/%d vs %s hp %d/%d | cooldowns %d,%d,%d", b.eng.round or 0, force and "forced swap" or "go", table.concat(offered, " "),
            pet.name, pet.hp, pet.max, b.eng.E[b.eng.active.E].name, b.eng.E[b.eng.active.E].hp, b.eng.E[b.eng.active.E].max, pet.cd[1], pet.cd[2], pet.cd[3])
        for slot = 1, 3 do local a = pet.abil[slot]; if a then Tr(b, nil, "OFFER   button %d = %s (icon %s, cd %d): %s", slot, a.name, tostring(a.icon), a.cd, tostring(a.tip)) end end
    end
    Send(b, "turn", (force and "force" or "go") .. ";" .. pet.cd[1] .. "," .. pet.cd[2] .. "," .. pet.cd[3] .. ";" .. ((not force and b.api.CanTrap(b.eng)) and 1 or 0))
end

local function End(b, result, forfeit)
    if b.over then return end
    b.over = true; b.endedAt = os.time()
    local plr = GetPlayer(b); if plr then Store.SetSuppressed(plr, false) end
    if b.api.Finish then b.api.Finish(b.eng) end   -- temporary effects (Perk Up max health ...) end with the battle, before health is saved
    if not b.test then   -- a FORFEIT is a defeat: every pet of the team drops to 1 HP, like a lost battle
        for _, p in ipairs(b.eng.P) do Store.SetHp(b.plow, p.species, (not forfeit and p.hp > 0) and p.hp or 1) end
        local plh = GetPlayer(b); if plh then for _, p in ipairs(b.eng.P) do pcall(Store.PushPet, plh, p.species) end end   -- an open journal shows the new health at once
    end   -- a test team (lab) never touches saved pets   -- health is NOT restored: fainted pets are back with 1 HP, the rest keep what is left
    Send(b, "end", result)
    battles[b.plow] = nil
    After(result == "win" and 600 or 1200, function()
        if result ~= "win" then Despawn(b, "P", true) end
        Despawn(b, "E", true)
        local leveled = false
        if result == "win" and not b.test then
            local pl = GetPlayer(b)
            if pl and not b.eng.captured then   -- experience (a battle ended by capturing the last pet gives none, like retail)
                for i, p in ipairs(b.eng.P) do
                    if b.acted[i] then
                        local gain, lv, ups = Store.GrantXP(pl, p.species, b.enemyLevel)
                        if gain then
                            Msg.Send(pl, "pbt", "xp", p.name .. "," .. gain .. "," .. lv .. "," .. ups)
                            if ups and ups > 0 then leveled = true end
                        end
                    end
                end
                if leveled then Fx(GetObj(b, "P"), FX_LEVELUP, 2500) end   -- the gold level-up burst on the pet that is standing there
            end
        end
        local plx = GetPlayer(b); if plx then Msg.Send(plx, "pbt", "done", "") end
        if result == "win" then After(leveled and 2600 or 500, function() Despawn(b, "P", true) end) end
    end)
end

-- ---------------------------------------------------------------- playback of the engine's event list
local CRATE_GO = 193761   -- Doodad_stormwindcrate05: a plain crate (type 5, not interactive) dropped over a pet being captured
local function Lunge(b, s, ts)
    local o, t = GetObj(b, s), GetObj(b, ts)
    Tr(b, nil, "move %s lunges at %s%s", s, ts, (o and t) and "" or " (NO OBJECT)")
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
    Tr(b, nil, "move %s goes back", s)
    local o = GetObj(b, s); local p = b.pos[s]
    local hop = b.vhop and b.vhop[s]; b.vhop = b.vhop or {}; b.vhop[s] = nil
    if o then
        if hop then pcall(function() o:MoveJump(p[1], p[2], p[3], 9.0, 2.5, 7) end)   -- Backflip: a hop back to the spot (lab-accepted)
        else pcall(function() o:MoveTo(2, p[1], p[2], p[3], false) end) end
    end
    After(hop and 900 or 450, function() local o2 = GetObj(b, s); if o2 then pcall(function() o2:SetFacing(p[4]) end) end end)
end

-- Non-attack presentation of an ability (modes from scripts/pb_vis.lua, accepted in the lab): self = a buff/heal spell on the pet itself, target = a debuff spell at the enemy,
-- aura = the spell's aura applied straight to the pet (no cast animation). Returns the ms to wait.
local function Support(b, e, vm, o)
    local side = e.side; local ts = side == "P" and "E" or "P"
    local t = GetObj(b, ts)
    Tr(b, nil, "support %s spell %d on %s", vm, e.vis, side)
    if vm == "aura" then
        pcall(function() o:AddAura(e.vis, o) end)
        local g = o:GetGUID(); local pg = b.pguid
        After(2400, function() pcall(function() local pl = GetPlayerByGUID(pg); local m = pl and pl:GetMap(); local o2 = m and m:GetWorldObject(g); if o2 then o2:RemoveAura(e.vis) end end) end)
        return 1500
    elseif vm == "target" then
        if not t then return 600 end
        PB_CAST.Cast(o, t, e.vis, { pguid = b.pguid, ranged = true, noSwap = nil, hp_after = t:GetHealth(), home = b.pos[ts] })   -- a debuff spell: the health stays where it is
        return 1300
    end
    -- self: the other pet is made hostile to the caster for the cast so an area heal / buff cannot land on it; both are held in place (they flee when made hostile) and put back
    if t then pcall(function() t:SetFaction(1691); o:SetFaction(1690) end) end
    local hold = 1700
    for ms = 150, hold, 150 do After(ms, function() pcall(function()
        local a2, t2 = GetObj(b, side), GetObj(b, ts)
        for _, x in ipairs({ { a2, side }, { t2, ts } }) do if x[1] then x[1]:MoveClear(); local p = b.pos[x[2]]; if p then x[1]:MoveTo(2, p[1], p[2], p[3], false) end end end
    end) end) end
    After(hold + 100, function() pcall(function()
        for _, x in ipairs({ GetObj(b, side), GetObj(b, ts) }) do if x then x:SetFaction(35); x:ClearInCombat(); x:RemoveAura(e.vis) end end
    end) end)
    PB_CAST.Cast(o, o, e.vis, { pguid = b.pguid, heal = true, hold = 1500, home = b.pos[side] })
    return 1500
end

function Play(b, ev, i, status)
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
    local function nxt(ms) b.vt = (b.vt or 0) + ms; After(ms, function() Play(b, ev, i + 1, status) end) end
    local eng = b.eng
    if Tracing(b) then
        local f = {}
        for k, v in pairs(e) do local t = type(v); if t == "number" or t == "string" or t == "boolean" then f[#f + 1] = k .. "=" .. tostring(v) end end
        table.sort(f); Tr(b, nil, "ev %d/%d %s", i, #ev, table.concat(f, " "))
    end

    if e.k == "act" then
        Send(b, "act", e.side .. "," .. e.idx .. "," .. e.name)
        if e.side == "P" then b.acted[e.idx] = true end   -- only pets that actually fought earn XP
        local o = GetObj(b, e.side)
        do   -- the last acts of this player's battle, for `/pbtest bad` (kept after the battle ends)
            local g = b.plow or 0; local list = RecentActs[g] or {}; RecentActs[g] = list
            list[#list + 1] = string.format("%s %s (ability %s) spell=%s mode=%s", e.side, e.name or "?", tostring(e.ab), tostring(e.vis), tostring(e.vm or (e.ranged and "ranged" or "melee")))
            while #list > 6 do table.remove(list, 1) end
        end
        local vm = e.vm or (e.ranged and "ranged" or "melee")   -- how the ability is played (scripts/pb_vis.lua): melee / ranged / self / target / aura
        local hitSpell = (vm == "melee" or vm == "ranged") and e.vis or nil
        b.vis = hitSpell   -- a real spell (visual + sound) cast on the hit event
        local ranged = (vm == "ranged"); b.ranged = ranged
        b.vdmg = e.vdmg; b.vhop = b.vhop or {}; b.vhop[e.side] = e.vhop
        local support = e.vis and PB_CAST and (vm == "self" or vm == "target" or vm == "aura")
        local attack = e.dmg or hitSpell ~= nil   -- a damaging ability that missed / was dodged still ATTACKS (no utility glow)
        if e.vpre and PB_CAST and o then pcall(function() PB_CAST.Cast(o, o, e.vpre, { pguid = b.pguid, heal = true, hold = 1300, home = b.pos[e.side] }) end) end   -- a caster-side spell first (Adrenaline Rush: Berserking, then the hit)
        if support and o then
            nxt(Support(b, e, vm, o) + (e.dmg and 300 or 0))   -- an ability that also deals damage (Roar) goes on to its hit event
        elseif attack and b.vis and ranged and PB_CAST then nxt(500)   -- spell casters stay put; the spell is cast on the hit event (melee abilities with a spell still lunge)
        elseif attack then
            local ts = e.side == "P" and "E" or "P"
            Lunge(b, e.side, ts); b.lunged[e.side] = true
            local emote = (Eng.Family(b.eng[e.side][e.idx].species) == "Humanoid") and 26 or 35   -- humanoids swing a weapon (1H attack); beasts use the claw/bite animation
            local at = (b.vt or 0) + 650   -- when it fires, in playback time (b.vt moves on with the event below)
            After(650, function() Emote(b, e.side, emote, at) end)
            nxt(1000)
        else
            Fx(o, 60957, 1500, b, e.side)   -- utility ability: nature-cast glow on the user
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
                local msg, kept, kq = Store.Capture(pl, pet)
                Msg.Send(pl, "pbt", "msg", msg)
                if kept then Msg.Send(pl, "pbt", "got", (kq or 1) .. "," .. pet.name) end   -- the big centered "You have collected ..."
            elseif pl then Msg.Send(pl, "pbt", "msg", "You captured " .. pet.name .. "! (test battle: not saved)") end
            Send(b, "fnt", "E," .. e.idx)
        end)
        nxt(2800)
    elseif e.k == "dmg" and (e.recoil or e.reflect) then   -- the user hurt itself (Body Slam) / a reflect hit (Lightning Shield): a wound emote and the new health, no lunge / spell
        Emote(b, e.tside, 33)
        Send(b, "hp", e.tside .. "," .. e.tidx .. "," .. e.hp .. "," .. e.max .. ",-" .. e.dmg)
        nxt(700)
    elseif e.k == "dmg" and e.bench then   -- splash on a benched pet: just its health number
        Send(b, "hp", e.tside .. "," .. e.tidx .. "," .. e.hp .. "," .. e.max .. ",-" .. e.dmg)
        nxt(250)
    elseif e.k == "faint" and e.bench then
        Send(b, "fnt", e.side .. "," .. e.idx)
        nxt(500)
    elseif e.k == "dmg" then
        local t = GetObj(b, e.tside)
        if not t and PB_DEBUG then print(string.format('[pb_battle] DIAG no target object: side=%s guid=%s vis=%s', tostring(e.tside), tostring(b.low[e.tside]), tostring(b.vis))) end
        if b.vis and PB_CAST and t then
            local att = GetObj(b, e.side)
            Emote(b, e.tside, 33)   -- wound animation as before; the spell adds its own hit visual and sound
            if not att and PB_DEBUG then print(string.format('[pb_battle] DIAG no attacker object: side=%s guid=%s', tostring(e.side), tostring(b.low[e.side]))) end
            Tr(b, nil, "cast real spell %d %s -> %s (%s) hp_after=%d", b.vis, e.side, e.tside, b.ranged and "ranged" or "melee", math.floor(e.hp / math.max(1, e.max) * 1000 + 0.5))
            if att then PB_CAST.Cast(att, t, b.vis, { pguid = b.pguid, ranged = b.ranged, retry = b.vdmg and 2 or nil, hp_after = math.floor(e.hp / math.max(1, e.max) * 1000 + 0.5), home = b.pos[e.tside] }) end
        elseif t then Emote(b, e.tside, 33); Fx(t, FX_HIT, 900, b, e.tside)
        else Tr(b, nil, "NO TARGET OBJECT for the hit on %s", e.tside) end
        Send(b, "hp", e.tside .. "," .. e.tidx .. "," .. e.hp .. "," .. e.max .. "," .. (e.crit and "-" .. e.dmg .. "!" or "-" .. e.dmg))
        if not e.more then After(600, function() Back(b, e.side) end) end   -- a multi-hit attacker stays put until its last hit
        nxt(e.more and (b.vis and 1000 or 650) or 1000)   -- a real spell needs ~1 s between hits to be seen (lab)
    elseif e.k == "dodge" then
        if e.text ~= "Burrowed!" then Emote(b, e.side, 4) end   -- little hop out of the way
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. "," .. (e.text or "Dodge!"))   -- hp as it was at THIS moment, not the end of the round
        if not e.more then After(500, function() Back(b, e.from) end) end
        nxt(e.more and 650 or 1000)
    elseif e.k == "buff" or e.k == "debuff" then
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        -- (no glow on the debuffed pet: it looked like that pet casting a buff that does nothing; the status icon is the feedback)
        nxt(700)
    elseif e.k == "heal" then
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. ",+" .. e.amt)
        nxt(e.quick and 450 or 1000)
    elseif e.k == "stunned" then
        Send(b, "msg", eng[e.side][e.idx].name .. Eng.LockText(e))
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        nxt(1300)
    elseif e.k == "dot" then
        Emote(b, e.side, 33)
        Send(b, "hp", e.side .. "," .. e.idx .. "," .. e.hp .. "," .. e.max .. ",-" .. e.dmg)
        SendTags(b, "P", e.stat); SendTags(b, "E", e.stat)
        nxt(1000)
    elseif e.k == "faint" then
        Emote(b, e.side, 34)
        Back(b, e.side == "P" and "E" or "P")
        After(1000, function() Despawn(b, e.side, true); Send(b, "fnt", e.side .. "," .. e.idx) end)
        nxt(1700)
    elseif e.k == "swap" then   -- a swap by the player, or a FORCED swap of either side (Nether Gate)
        local sd = e.side or "P"
        Send(b, "msg", (sd == "P" and not e.forced) and ("Go, " .. eng.P[e.idx].name .. "!") or (eng[sd][e.idx].name .. " is forced into battle!"))
        Despawn(b, sd, true)
        After(700, function() SpawnPet(b, sd, e.idx); Send(b, "in", sd .. "," .. e.idx); if sd == "P" then SendAbilities(b) end; SendTags(b, sd) end)
        nxt(1600 + SETTLE_MS)
    elseif e.k == "weather" then
        Send(b, "weather", e.id .. "|" .. e.turns .. "|" .. (e.name or ""))
        nxt(e.id ~= 0 and 500 or 100)
    elseif e.k == "spawn" then
        SpawnPet(b, e.side, e.idx); Send(b, "in", e.side .. "," .. e.idx); SendTags(b, e.side)
        nxt(1400 + SETTLE_MS)
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
    battleNo = battleNo + 1; b.no = battleNo; b.vt = 0; b.trace = traceOn[g]
    Tr(b, nil, "BEGIN player=%d enemy level %d, team %d vs %d pets%s", g, lvl, #P, #Ei, b.test and " (test team)" or "")
    for _, s in ipairs({ "P", "E" }) do   -- every pet gets its skin NOW (random model row of the species), so the preview and the spawn agree
        for _, pet in ipairs(b.eng[s]) do
            if not (pet.display and pet.display > 0) then
                local d = PickDisplay(pet.species)
                if d then pet.display = d; if s == "P" then Store.SetDisplay(player, pet.species, d) end end
            end
        end
    end
    b.cx, b.cy, b.cz = player:GetX(), player:GetY(), player:GetZ()
    Layout(b, player)
    Store.SetSuppressed(player, true)   -- the follower steps aside during the battle
    battles[g] = b
    Send(b, "begin", "")
    for _, s in ipairs({ "P", "E" }) do for i = 1, #b.eng[s] do SendPet(b, s, i) end end
    if not b.test then for i, ep in ipairs(b.eng.E) do local st, oq, ol = Store.Compare(player, ep.species, ep.quality, ep.level); Send(b, "own", i .. "," .. st .. "," .. oq .. "," .. ol) end end
    SendAbilities(b)
    After(300, function() SpawnPet(b, "P", 1); Send(b, "in", "P,1") end)
    After(1300, function() SpawnPet(b, "E", 1); Send(b, "in", "E,1") end)
    After(2600 + SETTLE_MS, function() SendTags(b, "P"); SendTags(b, "E"); SendTurn(b, false) end)   -- both pets are up (the second lifts at 1300 + SETTLE_MS)
    return true
end
-- Watchdog: no battle may live forever. Ends battles whose player left / died / changed map / walked away, and battles that wait for a move for
-- IDLE_TIMEOUT seconds (e.g. the window never opened); forgets a recruit picker left open that long.
local IDLE_TIMEOUT = 300   -- 5 minutes (user: at least 3)
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
PB_BATTLE = { Watchdog = Watchdog, Sweep = Sweep, Start = Start, InBattle = function(player) return battles[player:GetGUIDLow()] ~= nil end,
    Honored = Honored, Violations = function() return violations end }

-- /pbtest            3 random enemy species;   /pbtest 1124 474 30   those species (level 5) as the enemy team;   /pbtest 1196@20 3118@25   with a level each (1-25)
Msg.On("pbt", "start", function(player, payload)   -- debug start: GM only (players meet wild pets instead)
    if player:GetGMRank() < 2 then return end
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
    local cmd = Legal(b, payload)
    if not cmd then Tr(b, nil, "COMMAND %s refused (not offered)", tostring(payload)); return end
    b.waiting = false
    Tr(b, nil, "COMMAND %s (the player's choice)", cmd)
    local ev, status = b.api.Round(eng, cmd, b.api.AI(eng))
    local honored, why = Honored(cmd, ev)
    if not honored then   -- always on: an offered choice the engine ignored (the Stampede class of bug)
        violations = violations + 1
        local kinds = {}; for _, x in ipairs(ev) do kinds[#kinds + 1] = x.k .. ((x.side or "") ~= "" and ":" .. x.side or "") .. (x.name and ("(" .. x.name .. ")") or "") end
        print(string.format("[pbtrace] VIOLATION b%d round %d: %s (command %s) events: %s", b.no or 0, eng.round or 0, why, cmd, table.concat(kinds, " ")))
    end
    Play(b, ev, 1, status)
end
Msg.On("pbt", "cmd", Command)
PB_BATTLE.Command = Command
PB_BATTLE.CanTrap = function(player) local b = battles[player:GetGUIDLow()]; return b ~= nil and b.waiting and not b.over and b.api.CanTrap(b.eng) or false end
PB_BATTLE.Waiting = function(player) local b = battles[player:GetGUIDLow()]; return b ~= nil and b.waiting and not b.over end
PB_BATTLE.CleanAll = function(player) Msg.Send(player, "pbt", "end", "interrupted"); local b = battles[player:GetGUIDLow()]; if b then b.over = true; Despawn(b, "P", false); Despawn(b, "E", false); battles[player:GetGUIDLow()] = nil end; return Sweep(player, 200) end
Msg.On("pbt", "quit", function(player)
    local b = battles[player:GetGUIDLow()]
    if b and not b.over then Send(b, "msg", "You forfeited the battle: your pets are knocked out."); End(b, "loss", true) end
end)
Msg.On("pbt", "trace", function(player)   -- GM only: switch the battle trace on / off for yourself (applies from the NEXT battle; a running one too)
    if player:GetGMRank() < 2 then return end
    local g = player:GetGUIDLow(); traceOn[g] = not traceOn[g] or nil
    local b = battles[g]; if b then b.trace = traceOn[g] end
    Msg.Send(player, "pbt", "msg", "Battle trace " .. (traceOn[g] and "ON: transcript goes to world.out ([pbtrace])" or "OFF"))
end)
PB_BATTLE.Bad = function(player, comment)   -- `/pbtest bad [comment]` (GM): the ability that just looked wrong; the last acts + spells + modes go to logs/pb_bad.tsv and world.out
    local g = player:GetGUIDLow(); local list = RecentActs[g] or {}
    local line = string.format("%s\t%s\t%s", os.date("%Y-%m-%d %H:%M:%S"), table.concat(list, " | "), comment or "")
    print("[pb_bad] " .. line)
    local f = io.open("logs/pb_bad.tsv", "a"); if f then f:write(line, "\n"); f:close() end
    Msg.Send(player, "pbt", "msg", #list > 0 and ("Flagged: " .. list[#list]) or "Flagged (no ability played yet)")
    return #list
end
Msg.On("pbt", "bad", function(player, payload)
    if player:GetGMRank() < 2 then return end
    PB_BATTLE.Bad(player, payload)
end)
Msg.On("pbt", "fx", function(player, payload)   -- animation lab (GM only): /pbtest fx <spellId>
    if player:GetGMRank() < 2 then return end
    local b = battles[player:GetGUIDLow()]; local o = b and GetObj(b, "P")
    local id = tonumber(payload)
    if o and id then Fx(o, id, 4000) end
end)
RegisterPlayerEvent(4, function(_, player)
    local b = battles[player:GetGUIDLow()]
    if b then b.over = true; Despawn(b, "P", false); Despawn(b, "E", false); battles[player:GetGUIDLow()] = nil end
end)
-- after a script reload: clean up around everyone online right now
pcall(function() for _, pl in ipairs(GetPlayersInWorld()) do if Store.IsHuman(pl) then Sweep(pl, 200) end end end)   -- bots never get pets: skipping them avoids ~100k range queries per reload
print("[pb_battle] loaded")
return true
