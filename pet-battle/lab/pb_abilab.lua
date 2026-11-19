-- ABILITY LAB (GM only, remove before release): plays ONE ability effect at a time between two battle pets and waits for YOUR answer in chat.
--   .pblab              plays the NEXT 10 abilities that are not settled yet (retests first, then unseen ones). That is the only command you need:
--                       an ability with a 'y' is done; a candidate with an 'n' is never shown again; new candidates of a rejected ability come back automatically.
--   .pblab stop         end the session (results so far stay in the file)   .pblab status
-- Chat answers (typed in any chat channel; the lab SWALLOWS them so playerbots never see them):
--   y             looks right -> next ability
--   n             not right   -> the next candidate spell of the same ability, or the next ability when none is left
--   n: comment    same as n, and your comment is saved with it (also  y: comment)
--   r             replay what you just saw
-- An answer is accepted ONLY while the lab is waiting for it (after the effect has finished). Anything typed while an effect is still playing is
-- ignored and the lab says so - it is never counted for the next ability. Every answer is acknowledged by name, so you always see what it was counted for.
-- Results are appended to logs/pb_abilab.tsv: time, ability id, ability, candidate spell, answer, comment.
local LAB = {}
PB_ABILAB = LAB
local DATA = require("pb_abilab_data")
local D = require("pb_data")
local Store = require("pb_store")
local BATCH = 10
local RESULTS = "logs/pb_abilab.tsv"
local RESULTS_R = "logs/pb_review.tsv"   -- the full review (.pbreview): time, id, ability, spell, answer, comment (the LAST row of an ability is its verdict)
local okR, REVIEW = pcall(require, "pb_review_data"); if not okR then REVIEW = {} end

local function After(ms, fn) CreateLuaEvent(function() fn() end, ms, 1) end
local SESS = {}   -- [player guidlow] = session

-- ------------------------------------------------------------ the part that talks to the game (the test replaces these)
function LAB.Say(pl, text) pcall(function() pl:SendBroadcastMessage(text) end); print("[pblab] " .. text) end
function LAB.Big(pl, text) pcall(function() pl:SendNotification(text) end) end
function LAB.Append(line, file) local f = io.open(file or RESULTS, "a"); if f then f:write(line, "\n"); f:close() end end
function LAB.Now() return os.date("%Y-%m-%d %H:%M:%S") end
function LAB.ReadResults(file)   -- rows of the results file: time, id, ability, "label=spell", answer, comment
    local rows = {}; local f = io.open(file or RESULTS, "r")
    if f then for l in f:lines() do local c = {}; for x in (l .. "\t"):gmatch("([^\t]*)\t") do c[#c + 1] = x end; rows[#rows + 1] = c end; f:close() end
    return rows
end
local function Obj(S, k)   -- a stored Map userdata goes stale: always look the creature up again through the player
    if not S[k] then return nil end
    local pl = GetPlayerByGUID(S.pguid); local map = pl and pl:GetMap()
    return map and map:GetWorldObject(S[k]) or nil
end
local function Despawn(S)
    for _, k in ipairs({ "a", "b" }) do local o = Obj(S, k); if o then pcall(function() o:DespawnOrUnsummon(0) end) end; S[k] = nil end
end
local function Spawn(pl, species, f, side, faceTo)
    local x, y, z, o = pl:GetX(), pl:GetY(), pl:GetZ(), pl:GetO()
    local px, py = x + math.cos(o) * f - math.sin(o) * side, y + math.sin(o) * f + math.cos(o) * side
    local okh, h = pcall(function() return pl:GetMap():GetHeight(px, py, pl:GetPhaseMask()) end)
    if okh and h and h > -1000 and math.abs(h - z) < 8 then z = h + 0.1 end
    local obj = PerformIngameSpawn(1, D.StandIn(species) or species, pl:GetMapId(), 0, px, py, z, faceTo or (o + 3.14), false, 0, pl:GetPhaseMask())
    if obj then
        pcall(function() obj:SetReactState(0) end); pcall(function() obj:SetUnitFlags(0) end); pcall(function() obj:SetFaction(35) end)
        pcall(function() obj:SetScale(Store.Scale(species)) end)
        pcall(function() obj:SetMaxHealth(1000); obj:SetHealth(1000) end)
        pcall(function() obj:SetPhaseMask(pl:GetPhaseMask(), true) end)
        pcall(function() obj:SetHomePosition(px, py, z, faceTo or (o + 3.14)) end)
    end
    return obj, { px, py, z, faceTo or (o + 3.14) }
end
-- two pets facing each other 6 yards in front of the player
function LAB.SpawnPair(S, item)
    local pl = GetPlayerByGUID(S.pguid); if not pl then return false end
    Despawn(S)
    local o = pl:GetO()
    local sp, tsp = item.species or 299, (item.species == 299) and 69 or 299
    local a, pa = Spawn(pl, sp, 6, 3)
    local b, pb = Spawn(pl, tsp, 6, -3)
    if not a or not b then return false end
    S.a, S.b, S.pa, S.pb = a:GetGUID(), b:GetGUID(), pa, pb
    -- face each other
    pa[4] = a:GetAngle(b); pb[4] = b:GetAngle(a)   -- the exact angle, not GetO() (SetFacing is not applied yet at this point: the pet used to return facing the wrong way)
    pcall(function() a:SetFacing(pa[4]); b:SetFacing(pb[4]) end)
    return true
end
local function Hold(S, ms)   -- a pet that turned hostile starts fleeing (its own AI: the rabbit ran away): stop it every 150 ms and put it back, like pb_cast does
    for t = 150, ms, 150 do
        After(t, function()
            for _, k in ipairs({ "a", "b" }) do
                local o = Obj(S, k); local home = (k == "a") and S.pa or S.pb
                if o and home then pcall(function() o:MoveClear(); o:MoveTo(2, home[1], home[2], home[3], false); o:SetFacing(home[4]) end) end
            end
        end)
    end
end
local function Cleanup(S, spell)   -- a channel or a long aura must not stay on the pets: cut it after the visual has been seen
    for _, k in ipairs({ "a", "b" }) do
        local o = Obj(S, k)
        if o then
            pcall(function() if spell then o:RemoveAura(spell) end end)
            pcall(function() o:InterruptSpell(0) end); pcall(function() o:InterruptSpell(1) end); pcall(function() o:InterruptSpell(2) end)
            pcall(function() o:SetFaction(35) end); pcall(function() o:ClearInCombat() end)
        end
    end
end
-- plays one candidate; returns the milliseconds until the effect is over
function LAB.Play(S, item, cand)
    local a, b = Obj(S, "a"), Obj(S, "b")
    if not a or not b then LAB.Say(GetPlayerByGUID(S.pguid), "(pets are gone - try r)"); return 500 end
    pcall(function() b:SetMaxHealth(1000); b:SetHealth(1000) end)
    local pguid = S.pguid
    local pl = GetPlayerByGUID(pguid)
    local tok = S.token
    local function alive() return S.token == tok and SESS[S.low] == S end
    local mode = cand.mode or item.mode
    local spell = cand.spell
    local function cast(att, tgt, o)
        o = o or {}; o.pguid = pguid; o.hold = o.hold or 1300
        if cand.dmg and not o.heal then o.retry = 2 end   -- a damaging spell that MISSED shows nothing: cast it again (see pb_cast)
        local ok = pcall(function() return PB_CAST.Cast(att, tgt, spell, o) end)
        print(string.format("[pblab] cast spell %s %s -> %s mode=%s ok=%s", tostring(spell), att:GetName(), tgt:GetName(), mode, tostring(ok)))
    end
    if cand.kind == "lift" then   -- Lift-Off: raise the pet, hold it, put it back. Measured, not assumed: the height actually reached is reported.
        local z0 = a:GetZ()
        After(300, function() if not alive() then return end
            local o = Obj(S, "a"); if not o then return end
            local okg = pcall(function() o:SetDisableGravity(true) end)
            local okm = pcall(function() o:MoveTo(1, S.pa[1], S.pa[2], S.pa[3] + 3, false) end)
            LAB.Say(pl, string.format("[lift] SetDisableGravity ok=%s MoveTo ok=%s", tostring(okg), tostring(okm)))
        end)
        After(1500, function() if not alive() then return end
            local o = Obj(S, "a"); if not o then return end
            local rise = o:GetZ() - z0
            if rise < 1 then pcall(function() o:NearTeleport(S.pa[1], S.pa[2], S.pa[3] + 3, S.pa[4]) end) end   -- smooth move did nothing: try a jump
            LAB.Say(pl, string.format("[lift] height gained after 1.2 s: %.1f yards%s", rise, rise < 1 and " (smooth move failed, jump tried)" or ""))
        end)
        After(3000, function() local o = Obj(S, "a"); if o then pcall(function() o:MoveTo(2, S.pa[1], S.pa[2], S.pa[3], false) end); pcall(function() o:NearTeleport(S.pa[1], S.pa[2], S.pa[3], S.pa[4]) end); pcall(function() o:SetDisableGravity(false) end) end end)
        return 3800
    elseif cand.kind == "emote" then
        After(300, function() local o = Obj(S, "a"); if o and alive() then pcall(function() o:PerformEmote(cand.emote) end) end end)
        return 2500
    end
    if mode == "melee" then
        After(300, function() if not alive() then return end
            local o, t = Obj(S, "a"), Obj(S, "b"); if not (o and t) then return end
            local ox, oy, tx, ty = o:GetX(), o:GetY(), t:GetX(), t:GetY()
            local d = math.sqrt((tx - ox) ^ 2 + (ty - oy) ^ 2); local k = math.max(0, d - 1.1) / d
            if cand.pre then pcall(function() PB_CAST.Cast(o, o, cand.pre, { pguid = pguid, heal = true, hold = 1300 }) end) end   -- combo: the buff on the attacker first (Adrenaline Rush = Berserking, then the attack)
            pcall(function() o:SetWalk(false) end); pcall(function() o:MoveTo(1, ox + (tx - ox) * k, oy + (ty - oy) * k, t:GetZ(), false) end)
        end)
        for h = 1, item.hits or 1 do
            After(1000 + (h - 1) * 1000, function() if not alive() then return end
                local o, t = Obj(S, "a"), Obj(S, "b"); if not (o and t) then return end
                pcall(function() o:PerformEmote(35) end); pcall(function() t:PerformEmote(33) end)
                cast(o, t, { hp_after = 1000 - 200 * h, home = S.pb })
            end)
        end
        local last = 1000 + ((item.hits or 1) - 1) * 1000
        After(last + 900, function() if not alive() then return end
            local o = Obj(S, "a")
            if o then
                if item.hop then pcall(function() o:MoveJump(S.pa[1], S.pa[2], S.pa[3], 9.0, 2.5, 7) end)   -- Backflip: a hop back to the spot
                else pcall(function() o:MoveTo(2, S.pa[1], S.pa[2], S.pa[3], false) end) end
                After(item.hop and 900 or 450, function() local o2 = Obj(S, "a"); if o2 then pcall(function() o2:SetFacing(S.pa[4]) end) end end)
            end
        end)
        After(last + 1500, function() Cleanup(S, spell) end)
        return last + 2200
    elseif mode == "aura" then   -- the pet gets the spell's AURA directly (Unit:AddAura): its state visual (zzz, the hawk above the head) without any cast animation or cast glow, no target rules
        After(400, function() if not alive() then return end
            local o = Obj(S, "a"); if not o then return end
            local ok = pcall(function() o:AddAura(spell, o) end)
            print(string.format("[pblab] AddAura spell %s on %s ok=%s", tostring(spell), o:GetName(), tostring(ok)))
        end)
        After(2600, function() Cleanup(S, spell) end)
        return 3200
    elseif mode == "byother" then   -- the OTHER pet casts it onto this one, for a visual that only exists on an enemy target (Hibernate = zzz above the head)
        After(400, function() if not alive() then return end
            local o, t = Obj(S, "a"), Obj(S, "b"); if o and t then cast(t, o, { hold = 1500 }) end
        end)
        After(2600, function() Cleanup(S, spell) end)
        return 3200
    elseif mode == "ranged" or mode == "target" or mode == "friendly" then   -- friendly: a HEAL spell used as an attack visual (Chain Heal): no faction swap, it lands on a friendly target
        After(400, function() if not alive() then return end
            local o, t = Obj(S, "a"), Obj(S, "b"); if not (o and t) then return end
            local off = 0
            if cand.pre then off = 700; pcall(function() PB_CAST.Cast(o, o, cand.pre, { pguid = pguid, heal = true, hold = 1300 }) end) end   -- combo: a caster-side spell first (Squawk = Screech, then the hit)
            for h = 1, item.hits or 1 do After(off + (h - 1) * 1000, function() local o2, t2 = Obj(S, "a"), Obj(S, "b"); if o2 and t2 and alive() then pcall(function() t2:PerformEmote(33) end); cast(o2, t2, { ranged = true, heal = (mode == "friendly") or nil, hp_after = 1000 - 200 * h, home = S.pb }) end end) end
        end)
        After(2600, function() Cleanup(S, spell) end)
        return 3200 + ((item.hits or 1) - 1) * 1000
    else   -- self / ally: a buff, heal or ward on the pet itself
        After(400, function() if not alive() then return end
            local o = Obj(S, "a"); if o then
                local t = Obj(S, "b"); if t then pcall(function() t:SetFaction(1691); o:SetFaction(1690) end); Hold(S, 1800) end   -- an area heal / buff must not land on the OTHER pet: it is hostile to the caster for the cast (Cleanup puts it back)
                cast(o, o, { heal = true, hold = 1500 })
            end
        end)
        After(2400, function() Cleanup(S, spell) end)
        return 3000
    end
end

-- ------------------------------------------------------------ the session logic (pure: tested without the game)
function LAB.Parse(raw)   -- returns answer ("y"|"n"|"r") and an optional comment, or nil when the text is not an answer
    raw = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local m = raw:lower()
    if m == "y" or m == "n" or m == "r" or m == "stop" or m == "b" then return m end
    local a = m:match("^([yn])%s*[:;]")
    if a then local note = raw:match("^[yYnN]%s*[:;]%s*(.*)$"); return a, (note ~= "" and note or nil) end
    return nil
end
local function Describe(S)
    local item = S.items[S.i]; local c = item.cands[S.c]
    if S.review then
        return item, c, string.format("[Review %d/%d] %s", S.i, #S.items, item.name),
            string.format("%s  >>  %s [%s] (spell %s)", item.text ~= "" and item.text or "-", c.label, c.mode or item.mode, tostring(c.spell))
    end
    local what = c.kind == "lift" and "lift the pet up in the air" or string.format("%s (spell %s)", c.label, tostring(c.spell))
    return item, c, string.format("[Lab %d/%d] %s", S.i, #S.items, item.name),
        string.format("%s  >>  Trying: %s [%s]  candidate %d/%d", item.text ~= "" and item.text or "-", what, c.mode or item.mode, S.c, #item.cands)
end
local function Present(S)
    local pl = GetPlayerByGUID(S.pguid); if not pl then return end
    S.token = S.token + 1; S.state = "playing"
    local item, c, head, line = Describe(S)
    LAB.Big(pl, head .. " - " .. (c.label or ""))
    LAB.Say(pl, head .. ": " .. line)
    if not LAB.SpawnPair(S, item) then LAB.Say(pl, "spawn failed - stopping"); SESS[S.low] = nil; return end
    local tok = S.token
    After(700, function()
        if S.token ~= tok or SESS[S.low] ~= S then return end
        local dur = LAB.Play(S, item, c) or 3000
        After(dur, function()
            if S.token ~= tok or SESS[S.low] ~= S then return end
            S.state = "waiting"
            LAB.Say(GetPlayerByGUID(S.pguid), (S.review and ("Answer now:  y = fits   n: why not   r = replay   b = back one   stop = leave (your place is kept)   [" .. item.name .. "]") or ("Answer now:  y = good   n = not good   n: your comment   r = replay   (" .. item.name .. ")")))
        end)
    end)
end
local function Advance(S)
    S.i = S.i + 1; S.c = 1
    if S.review then while S.items[S.i] and S.done[S.items[S.i].id] do S.i = S.i + 1 end end   -- review: skip what already has a verdict
    if S.i > #S.items then
        local pl = GetPlayerByGUID(S.pguid)
        if S.review then LAB.Say(pl, "REVIEW COMPLETE: every ability has a verdict. Results: " .. RESULTS_R); Despawn(S); SESS[S.low] = nil; return end
        local y, n, bad = 0, 0, {}
        for _, r in ipairs(S.results) do if r.ans == "y" then y = y + 1 else n = n + 1; bad[#bad + 1] = r.name .. "/" .. r.label end end
        LAB.Say(pl, string.format("Batch finished: %d y, %d n. Saved to %s. Type .pblab for the next batch.%s", y, n, RESULTS, #bad > 0 and (" Not good: " .. table.concat(bad, ", ")) or ""))
        Despawn(S); SESS[S.low] = nil; return
    end
    Present(S)
end
-- one chat message from the session's player. Returns true when the message was consumed (it must not appear in chat).
function LAB.OnAnswer(S, raw)
    local ans, note = LAB.Parse(raw)
    if not ans then return false end
    local pl = GetPlayerByGUID(S.pguid)
    local item, c = S.items[S.i], S.items[S.i].cands[S.c]
    if ans == "stop" then S.token = S.token + 1; Despawn(S); SESS[S.low] = nil; LAB.Say(pl, string.format("Stopped at %d/%d (%s). Your place is saved: .pbreview continues at the next ability without a verdict.", S.i, #S.items, item.name)); return true end
    if ans == "b" then
        if not S.review or S.i <= 1 then LAB.Say(pl, "nothing to go back to"); return true end
        S.token = S.token + 1; S.i = S.i - 1; S.c = 1; S.state = "counting"
        LAB.Say(pl, "Going back to " .. S.items[S.i].name .. " - answer it again, the new answer replaces the old one.")
        After(800, function() if SESS[S.low] == S then Present(S) end end); return true
    end
    if S.state ~= "waiting" then
        LAB.Say(pl, string.format("'%s' ignored: %s is still %s. Wait for the 'Answer now' line, then type it again.", ans, item.name, S.state == "playing" and "playing" or "being counted"))
        return true
    end
    S.state = "counting"   -- nothing else is accepted until the next effect has finished: a double-typed answer can never skip an ability
    S.token = S.token + 1
    if ans == "r" then LAB.Say(pl, "Replaying " .. item.name .. "..."); After(600, function() if SESS[S.low] == S then Present(S) end end); return true end
    local rec = { id = item.id, name = item.name, label = c.label or "?", spell = c.spell or c.kind, ans = ans, note = note }
    S.results[#S.results + 1] = rec
    LAB.Append(table.concat({ LAB.Now(), item.id, item.name, tostring(rec.label) .. "=" .. tostring(rec.spell), ans, note or "" }, "\t"), S.review and RESULTS_R or nil)
    if S.review then S.done[item.id] = true; local left = 0; for _, it in ipairs(S.items) do if not S.done[it.id] then left = left + 1 end end; S.left = left end
    LAB.Say(pl, string.format("Counted %s for %s (%s)%s%s", ans:upper(), item.name, tostring(rec.label), note and (" - noted: " .. note) or "", S.left and (" | " .. S.left .. " left") or ""))
    if ans == "n" and S.c < #item.cands then S.c = S.c + 1; After(1200, function() if SESS[S.low] == S then Present(S) end end)
    else After(1200, function() if SESS[S.low] == S then Advance(S) end end) end
    return true
end
function LAB.Start(pl, items)
    local low = pl:GetGUIDLow()
    if SESS[low] then Despawn(SESS[low]); SESS[low] = nil end
    local S = { low = low, pguid = pl:GetGUID(), items = items, i = 1, c = 1, state = "playing", token = 0, results = {} }
    SESS[low] = S
    LAB.Say(pl, string.format("Ability lab: %d abilities. Answer with y / n / n: comment / r in chat after each effect.", #items))
    Present(S)
    return S
end
-- the abilities still to look at: no 'y' yet (or flagged retest = new candidates were added), minus the candidates that already got an answer
function LAB.Pending()
    local tried, yes = {}, {}
    for _, r in ipairs(LAB.ReadResults()) do
        local id = tonumber(r[2]); if id then tried[id] = tried[id] or {}; tried[id][r[4]] = true; if r[5] == "y" then yes[id] = true end end
    end
    local list = {}
    for _, e in ipairs(DATA) do
        if e.mode ~= "defer" and (not yes[e.id] or e.retest) then
            local cands = {}
            for _, c in ipairs(e.cands) do
                local key = tostring(c.label or "?") .. "=" .. tostring(c.spell or c.kind)
                if not (tried[e.id] and tried[e.id][key]) then cands[#cands + 1] = c end
            end
            if #cands > 0 then local copy = {}; for k, v in pairs(e) do copy[k] = v end; copy.cands = cands; list[#list + 1] = copy end
        end
    end
    return list
end
-- the REVIEW: every ability once, grouped by spell+mode; resumes at the first ability without a verdict
function LAB.ReviewDone()
    local done = {}; for _, r in ipairs(LAB.ReadResults(RESULTS_R)) do local id = tonumber(r[2]); if id and (r[5] == "y" or r[5] == "n") then done[id] = true end end
    return done
end
function LAB.StartReview(pl)
    local low = pl:GetGUIDLow()
    if SESS[low] then Despawn(SESS[low]); SESS[low] = nil end
    local done = LAB.ReviewDone(); local first, left = nil, 0
    for i, it in ipairs(REVIEW) do if not done[it.id] then left = left + 1; first = first or i end end
    if not first then LAB.Say(pl, "Review complete: every ability has a verdict (" .. RESULTS_R .. ")."); return end
    local S = { low = low, pguid = pl:GetGUID(), items = REVIEW, i = first, c = 1, state = "playing", token = 0, results = {}, review = true, done = done, left = left }
    SESS[low] = S
    LAB.Say(pl, string.format("Ability REVIEW: %d of %d left. Resuming at %d. Answer y / n: reason / r / b / stop in chat.", left, #REVIEW, first))
    Present(S)
    return S
end
function LAB.Items()
    local list = {}
    for _, e in ipairs(DATA) do if e.mode ~= "defer" then list[#list + 1] = e end end
    return list
end

-- ------------------------------------------------------------ hooks
RegisterPlayerEvent(18, function(_, player, msg)   -- PLAYER_EVENT_ON_CHAT: return false = the message is not sent
    local S = player and SESS[player:GetGUIDLow()]
    if S and LAB.OnAnswer(S, msg) then return false end
end)
local ReviewCommand
RegisterPlayerEvent(42, function(_, player, command)
    if not player or not command then return end
    local rv = command:match("^pbreview%s*(.-)%s*$")
    if rv then if player:GetGMRank() >= 2 then ReviewCommand(player, rv) end; return false end
    local arg = command:match("^pblab%s*(.-)%s*$"); if not arg then return end
    if player:GetGMRank() < 2 then return end
    local all = LAB.Items()
    if arg == "stop" then local S = SESS[player:GetGUIDLow()]; if S then Despawn(S); SESS[player:GetGUIDLow()] = nil end; LAB.Say(player, "lab stopped")
    elseif arg == "status" then local S = SESS[player:GetGUIDLow()]; LAB.Say(player, S and string.format("running: %d/%d %s, state %s", S.i, #S.items, S.items[S.i].name, S.state) or string.format("not running; %d abilities left to look at (.pblab)", #LAB.Pending()))
    elseif arg == "" or arg == "go" then
        local pend = LAB.Pending(); local items = {}
        for i = 1, math.min(BATCH, #pend) do items[#items + 1] = pend[i] end
        if #items == 0 then LAB.Say(player, "Nothing left to look at: every ability is settled.") else LAB.Say(player, string.format("%d abilities left in total; playing the next %d.", #pend, #items)); LAB.Start(player, items) end
    elseif arg:match("^id%s+%d+$") then
        local want = tonumber(arg:match("%d+")); local one
        for _, e in ipairs(all) do if e.id == want then one = e end end
        if one then LAB.Start(player, { one }) else LAB.Say(player, "no such ability in the lab") end
    elseif tonumber(arg) then
        local n = tonumber(arg); local items = {}
        for i = (n - 1) * BATCH + 1, math.min(n * BATCH, #all) do items[#items + 1] = all[i] end
        if #items == 0 then LAB.Say(player, "no such batch (there are " .. math.ceil(#all / BATCH) .. ")") else LAB.Start(player, items) end
    else LAB.Say(player, "usage: .pblab | stop | status") end
    return false
end)
ReviewCommand = function(player, arg)
    if arg == "stop" then local S = SESS[player:GetGUIDLow()]; if S then S.token = S.token + 1; Despawn(S); SESS[player:GetGUIDLow()] = nil end; LAB.Say(player, "review stopped; .pbreview resumes")
    elseif arg == "status" then
        local done = LAB.ReviewDone(); local n, y, nn = 0, 0, 0
        for _, it in ipairs(REVIEW) do if done[it.id] then n = n + 1 end end
        LAB.Say(player, string.format("review: %d of %d have a verdict, %d left", n, #REVIEW, #REVIEW - n))
    else LAB.StartReview(player) end
end
RegisterPlayerEvent(4, function(_, player) local S = SESS[player:GetGUIDLow()]; if S then Despawn(S); SESS[player:GetGUIDLow()] = nil end end)   -- logout
print("[pblab] loaded: " .. #LAB.Items() .. " abilities in the lab (.pblab <batch>)")
return LAB
