-- SKILL SWEEP: does a greedy player beat the random enemy AI?  luajit pet-battle/sim_skill.lua [pairingsPerLevel=2000] [seed=7]
-- M1 random(P) vs random(E); M2 greedy(P) vs random(E) same teams/seeds; M3 greedy weak-team(P: bottom quartile by M1 rate) vs random(E: median band) (+M3r = same pairings, random P).
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local N = tonumber(arg and arg[1]) or 2000; local SEED = tonumber(arg and arg[2]) or 7
local LEVELS = { 5, 10, 15, 20, 25 }
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local T0, lastPrint = os.clock(), os.clock()
local function status(msg) if os.clock() - lastPrint >= 30 then lastPrint = os.clock(); print(string.format("[%4.0fs] %s", os.clock() - T0, msg)); io.stdout:flush() end end
local function mkrng(seed)   -- LCG, rng() / rng(n) / rng(a,b)
    local s = seed % 2147483647; if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 48271) % 2147483647; local r = s / 2147483647
        if not a then return r end
        if not b then return math.floor(r * a) + 1 end
        return a + math.floor(r * (b - a + 1))
    end
end
local FAM = Rules.FAMILIES
local DMG = { [24] = true, [222] = true, [96] = true, [62] = true }
local EXTRA = { [66] = 1, [226] = 1, [149] = 1, [197] = 0.7, [29] = 1, [59] = 1, [27] = 1, [384] = 0.5, [385] = 0.5, [141] = 1 }
local function hasAura(pet, id) for _, a in ipairs(pet.auras) do if a.id == id then return true end end return false end
-- returns dmg score, heal amount, utility flag
local function evalAbility(pet, ab, foe, fresh)
    local dmg, heal, util = 0, 0, 0
    local fam = (ab.family and ab.family >= 0 and FAM[ab.family + 1]) or pet.family
    for ti, turn in ipairs(ab.turns) do
        for _, f in ipairs(turn.fx) do
            local p = f.p or {}
            local pr = f.prop
            if DMG[pr] or EXTRA[pr] then
                local acc = math.min(1, (p[2] or 100) / 100); if acc <= 0 then acc = 1 end
                if (p[2] or 0) >= 200 then acc = 1 end
                dmg = dmg + Rules.Damage(p[1] or 0, pet.power, fam, foe.family, 0, 0) * acc * (EXTRA[pr] or 1)
            elseif pr == 23 or pr == 63 or pr == 44 then heal = heal + Rules.Heal(p[1] or 0, pet.power)
            elseif pr == 54 then
                if not (f.aura and hasAura(foe, f.aura)) then dmg = dmg + Rules.Damage(p[1] or 0, pet.power, fam, foe.family, 0, 0) * math.min(p[3] or 1, 3) * 0.8 end
            elseif pr == 26 or pr == 50 or pr == 52 or pr == 178 or pr == 172 or pr == 131 then
                local active = f.aura and f.aura ~= 0 and (hasAura(pet, f.aura) or hasAura(foe, f.aura))
                if not active then util = util + 1 end
            end
        end
    end
    return dmg, heal, util
end
local function greedy(b, state)
    local pet = b.P[b.active.P]; local foe = b.E[b.active.E]
    if pet.channel then return "A" .. pet.channel.slot end
    if pet.hp <= 0 then   -- forced swap: best matchup
        local best, bs = nil, -1e9
        for k, q in ipairs(b.P) do if q.hp > 0 then local s = Rules.Matchup(q.family, foe.family) - Rules.Matchup(foe.family, q.family) + q.hp / q.max * 0.1; if s > bs then best, bs = k, s end end end
        return "S" .. best
    end
    -- swap when at a family disadvantage and hurt, at most once per 3 rounds
    if b.round - (state.lastSwap or -9) >= 3 and pet.hp < pet.max * 0.5 and Rules.Matchup(foe.family, pet.family) > 1 and not C.Locked(pet, "swapOutLock") and not C.CantAct(pet) then
        local best, bs = nil, Rules.Matchup(pet.family, foe.family) - Rules.Matchup(foe.family, pet.family)
        for k, q in ipairs(b.P) do
            if k ~= b.active.P and q.hp > q.max * 0.4 then
                local s = Rules.Matchup(q.family, foe.family) - Rules.Matchup(foe.family, q.family)
                if s > bs + 0.05 then best, bs = k, s end
            end
        end
        if best then state.lastSwap = b.round; state.swaps = (state.swaps or 0) + 1; return "S" .. best end
    end
    local bestSl, bestSc, healSl, healAmt, utilSl = nil, -1, nil, 0, nil
    local maxDmg = 0
    local info = {}
    for sl = 1, 3 do
        if C.Ready(pet, sl) then
            local d, h, u = evalAbility(pet, pet.abil[sl], foe)
            info[sl] = { d, h, u }
            if d > maxDmg then maxDmg = d end
            if d > bestSc then bestSl, bestSc = sl, d end
            if h > healAmt and d <= 0 then healSl, healAmt = sl, h end
            if u > 0 and d <= 0 and not utilSl then utilSl = sl end
        end
    end
    if healSl and pet.hp < pet.max * 0.4 and pet.max - pet.hp >= healAmt * 0.5 then state.heals = (state.heals or 0) + 1; return "A" .. healSl end
    if utilSl and maxDmg > 0 and pet.hp > pet.max * 0.4 and foe.hp > foe.max * 0.3 and (b.round - (state.lastUtil or -9)) >= 2 then state.lastUtil = b.round; state.utils = (state.utils or 0) + 1; return "A" .. utilSl end
    if bestSl then
        -- cooldown (slow) abilities are normally the strongest: counted when picked while a cheaper one existed
        if pet.abil[bestSl].cd and pet.abil[bestSl].cd > 0 then state.cdUsed = (state.cdUsed or 0) + 1 end
        return "A" .. bestSl
    end
    if utilSl then return "A" .. utilSl end
    if healSl then return "A" .. healSl end
    return "A1"
end
local stalls = 0
local function play(P, E, seed, mode, stat)
    local b = C.NewBattle(P, E, mkrng(seed * 7 + 1))
    local state = {}
    for _ = 1, 300 do
        local cmd
        local pet = b.P[b.active.P]
        if mode == "greedy" then cmd = greedy(b, state)
        else
            if pet.hp <= 0 then for k, q in ipairs(b.P) do if q.hp > 0 then cmd = "S" .. k; break end end
            else
                local r = {}; for s = 1, 3 do if C.Ready(pet, s) then r[#r + 1] = s end end
                cmd = pet.channel and ("A" .. pet.channel.slot) or ("A" .. (#r > 0 and r[b.rng(1, #r)] or 1))
            end
        end
        local _, st = C.Round(b, cmd, C.AI(b))
        if st == "win" or st == "loss" then
            if stat then stat.swaps = (stat.swaps or 0) + (state.swaps or 0); stat.heals = (stat.heals or 0) + (state.heals or 0); stat.utils = (stat.utils or 0) + (state.utils or 0); stat.cdUsed = (stat.cdUsed or 0) + (state.cdUsed or 0); stat.rounds = (stat.rounds or 0) + b.round end
            return st == "win"
        end
    end
    stalls = stalls + 1
    return nil
end
local function team(rng, lv, pool)
    local t, sp = {}, {}
    for k = 1, 3 do local id = pool[rng(#pool)]; sp[k] = id; t[k] = C.NewPet(id, lv, nil, rng, { quality = rng(1, 4) }) end
    return t, sp
end
-- pairing = seed; builds both teams with the same seed in every mode
local function build(seed, lv, poolP, poolE)
    local rng = mkrng(seed)
    local P, sp = team(rng, lv, poolP); local E = team(rng, lv, poolE)
    return P, E, sp
end
local res = { M1 = {}, M2 = {}, M3 = {}, M3r = {} }
for _, k in pairs({ "M1", "M2", "M3", "M3r" }) do for _, lv in ipairs(LEVELS) do res[k][lv] = { w = 0, n = 0 } end end
local spW, spN = {}, {}
local stat2 = {}
local function rec(k, lv, r) local t = res[k][lv]; if r ~= nil then t.n = t.n + 1; if r then t.w = t.w + 1 end end end
for li, lv in ipairs(LEVELS) do
    for i = 1, N do
        local seed = SEED * 1000003 + lv * 10007 + i
        local P, E, sp = build(seed, lv, ids, ids)
        local r1 = play(P, E, seed, "random")
        rec("M1", lv, r1)
        if r1 ~= nil then for _, id in ipairs(sp) do spN[id] = (spN[id] or 0) + 1; if r1 then spW[id] = (spW[id] or 0) + 1 end end end
        local P2, E2 = build(seed, lv, ids, ids)
        rec("M2", lv, play(P2, E2, seed, "greedy", stat2))
        status(string.format("M1/M2 level %d pairing %d/%d", lv, i, N))
    end
end
-- species strength from M1 (species with >= 20 appearances)
local rated = {}
for _, id in ipairs(ids) do if (spN[id] or 0) >= 15 then rated[#rated + 1] = { id = id, r = (spW[id] or 0) / spN[id] } end end
table.sort(rated, function(a, b) return a.r < b.r end)
local q = math.floor(#rated / 4); local weak, mid = {}, {}
for i = 1, q do weak[#weak + 1] = rated[i].id end
for i = math.floor(#rated * 0.375) + 1, math.floor(#rated * 0.625) do mid[#mid + 1] = rated[i].id end
print(string.format("rated species %d, weak pool %d (win rate <= %.0f%%), median pool %d (%.0f%%-%.0f%%)", #rated, #weak, rated[q].r * 100, #mid, rated[math.floor(#rated * 0.375) + 1].r * 100, rated[math.floor(#rated * 0.625)].r * 100)); io.stdout:flush()
local stat3 = {}
for _, lv in ipairs(LEVELS) do
    for i = 1, N do
        local seed = SEED * 1000003 + lv * 10007 + i + 555
        local P, E = build(seed, lv, weak, mid)
        local P2, E2 = build(seed, lv, weak, mid)
        rec("M3r", lv, play(P, E, seed, "random"))
        rec("M3", lv, play(P2, E2, seed, "greedy", stat3))
        status(string.format("M3 level %d pairing %d/%d", lv, i, N))
    end
end
local function tot(k) local w, n = 0, 0; for _, lv in ipairs(LEVELS) do w = w + res[k][lv].w; n = n + res[k][lv].n end; return w / n * 100, n end
local function row(k) local s = {}; for _, lv in ipairs(LEVELS) do local t = res[k][lv]; s[#s + 1] = string.format("L%d %.1f%%", lv, t.w / math.max(1, t.n) * 100) end; return table.concat(s, "  ") end
local m1, m2, m3, m3r = tot("M1"), tot("M2"), tot("M3"), tot("M3r")
print("")
print(string.format("M1 random vs random          %.1f%%  | %s", m1, row("M1")))
print(string.format("M2 greedy vs random          %.1f%%  | %s", m2, row("M2")))
print(string.format("M3 greedy WEAK vs random MED  %.1f%%  | %s", m3, row("M3")))
print(string.format("M3r random WEAK vs random MED %.1f%%  | %s", m3r, row("M3r")))
local ds = {}; for _, lv in ipairs(LEVELS) do ds[#ds + 1] = string.format("L%d %+.1f", lv, (res.M2[lv].w / res.M2[lv].n - res.M1[lv].w / res.M1[lv].n) * 100) end
print(string.format("delta M2-M1 %+.1f pts  (%s)   M3-M3r %+.1f pts", m2 - m1, table.concat(ds, ", "), m3 - m3r))
print(string.format("stalls/timeouts (300 rounds): %d;  greedy per battle (M2): swaps %.2f heals %.2f buffs/dots %.2f cd-ability picks %.2f, rounds %.1f", stalls, stat2.swaps / (N * #LEVELS), stat2.heals / (N * #LEVELS), stat2.utils / (N * #LEVELS), stat2.cdUsed / (N * #LEVELS), stat2.rounds / (N * #LEVELS)))
print(string.format("GATE greedy >= random+15: %s   GATE M3 >= 45%%: %s   runtime %.0fs", (m2 - m1 >= 15) and "PASS" or "FAIL", (m3 >= 45) and "PASS" or "FAIL", os.clock() - T0))
