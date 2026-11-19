-- SKILL SWEEP for the COMPOSED wild kits: balance measured the way strategy would play it.
--   R  random vs random (the old test)      G  greedy vs greedy (both sides play the family-aware greedy player of sim_skill.lua)
-- Same random 3-species teams in both modes; every species is rated from G (and R) over its appearances on either side; the two rankings are compared.
-- Usage (host): luajit pet-battle/sim_skill_kits.lua [pairings per level] [seed] [existing]      "existing" = the shipped wild species instead of the composed ones
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local N = tonumber(arg and arg[1]) or 2000; local SEED = tonumber(arg and arg[2]) or 7; local existing = arg and arg[3] == "existing"
local haveSyn = false; for _, sp in pairs(D.species) do if sp.synthetic then haveSyn = true; break end end
if not existing and not haveSyn then dofile("pet-battle/.s/wild_kits.lua") end   -- the composed kits are normally loaded by pb_data itself (scripts/pb_wild_kits.lua)
local LEVELS = { 10, 20 }
local ids = {}; for e, s in pairs(D.species) do if (existing and s.wild and not s.synthetic) or (not existing and s.synthetic) then ids[#ids + 1] = e end end; table.sort(ids)
local T0, lastPrint = os.clock(), os.clock()
local function status(msg) if os.clock() - lastPrint >= 45 then lastPrint = os.clock(); print(string.format("[%4.0fs] %s", os.clock() - T0, msg)); io.stdout:flush() end end
local function mkrng(seed)
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
local function greedy(b, state, S)
    S = S or 'P'; local O = (S == 'P') and 'E' or 'P'
    local pet = b[S][b.active[S]]; local foe = b[O][b.active[O]]
    if pet.channel then return "A" .. pet.channel.slot end
    if pet.hp <= 0 then   -- forced swap: best matchup
        local best, bs = nil, -1e9
        for k, q in ipairs(b[S]) do if q.hp > 0 then local s = Rules.Matchup(q.family, foe.family) - Rules.Matchup(foe.family, q.family) + q.hp / q.max * 0.1; if s > bs then best, bs = k, s end end end
        return "S" .. best
    end
    -- swap when at a family disadvantage and hurt, at most once per 3 rounds
    if b.round - (state.lastSwap or -9) >= 3 and pet.hp < pet.max * 0.5 and Rules.Matchup(foe.family, pet.family) > 1 and not C.Locked(pet, "swapOutLock") and not C.CantAct(pet) then
        local best, bs = nil, Rules.Matchup(pet.family, foe.family) - Rules.Matchup(foe.family, pet.family)
        for k, q in ipairs(b[S]) do
            if k ~= b.active[S] and q.hp > q.max * 0.4 then
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

local function randomCmd(b, S)
    local pet = b[S][b.active[S]]
    if pet.hp <= 0 then for k, q in ipairs(b[S]) do if q.hp > 0 then return "S" .. k end end end
    if pet.channel then return "A" .. pet.channel.slot end
    local r = {}; for s = 1, 3 do if C.Ready(pet, s) then r[#r + 1] = s end end
    return "A" .. (#r > 0 and r[b.rng(1, #r)] or 1)
end
local slotPick, picks = { 0, 0, 0 }, 0
local function play(P, E, seed, mode)
    local b = C.NewBattle(P, E, mkrng(seed * 7 + 1)); local sp, se = {}, {}
    for _ = 1, 300 do
        local cp, ce
        if mode == "G" then cp = greedy(b, sp, "P"); ce = greedy(b, se, "E") else cp = randomCmd(b, "P"); ce = randomCmd(b, "E") end
        if mode == "G" and cp:sub(1, 1) == "A" then local n = tonumber(cp:sub(2)); if n then slotPick[n] = slotPick[n] + 1; picks = picks + 1 end end
        local _, st = C.Round(b, cp, ce)
        if st == "win" then return true elseif st == "loss" then return false end
    end
    return nil
end
local function team(rng, lv)
    local t, sp = {}, {}
    for k = 1, 3 do local id = ids[rng(#ids)]; sp[k] = id; t[k] = C.NewPet(id, lv, nil, rng, { quality = rng(1, 4) }) end
    return t, sp
end
local rate = { R = {}, G = {} }; local fam = {}
local function add(m, id, won) local r = rate[m][id]; if not r then r = { 0, 0 }; rate[m][id] = r end; r[2] = r[2] + 1; if won then r[1] = r[1] + 1 end end
local tot = { R = { 0, 0 }, G = { 0, 0 } }; local timeouts = 0
for _, lv in ipairs(LEVELS) do
    for i = 1, N do
        local seed = SEED * 1000003 + lv * 10007 + i
        for _, m in ipairs({ "R", "G" }) do
            local rng = mkrng(seed); local P, spP = team(rng, lv); local E, spE = team(rng, lv)
            local r = play(P, E, seed, m)
            if r == nil then timeouts = timeouts + 1 else
                for _, id in ipairs(spP) do add(m, id, r) end; for _, id in ipairs(spE) do add(m, id, not r) end
                tot[m][2] = tot[m][2] + 1; if r then tot[m][1] = tot[m][1] + 1 end
            end
        end
        status(string.format("level %d pairing %d/%d", lv, i, N))
    end
end
-- ratings
local rows = {}
for _, id in ipairs(ids) do
    local g, r = rate.G[id], rate.R[id]
    if g and g[2] >= 15 and r and r[2] >= 15 then rows[#rows + 1] = { id = id, g = g[1] / g[2], r = r[1] / r[2], fam = C.Family(id), n = g[2] } end
end
table.sort(rows, function(a, b) return a.g > b.g end)
local function rank(key) local t = {}; for i, x in ipairs(rows) do t[i] = x end; table.sort(t, function(a, b) return a[key] > b[key] end); local rk = {}; for i, x in ipairs(t) do rk[x.id] = i end; return rk end
local rg, rr = rank("g"), rank("r"); local n = #rows; local d2 = 0
for _, x in ipairs(rows) do d2 = d2 + (rg[x.id] - rr[x.id]) ^ 2 end
local spearman = 1 - 6 * d2 / (n * (n * n - 1))
local hi, lo, mean, var = 0, 0, 0, 0
for _, x in ipairs(rows) do mean = mean + x.g end; mean = mean / n
for _, x in ipairs(rows) do var = var + (x.g - mean) ^ 2; if x.g >= 0.65 then hi = hi + 1 end; if x.g <= 0.35 then lo = lo + 1 end end
print(string.format("\nspecies rated %d (>=15 appearances) | skilled (G) mean %.1f%% sd %.1f pts | >=65%%: %d  <=35%%: %d | rank agreement random-vs-skilled (Spearman) %.2f", n, mean * 100, math.sqrt(var / n) * 100, hi, lo, spearman))
local rf = io.open(existing and "pet-battle/.s/ratings_old.tsv" or "pet-battle/.s/ratings_new.tsv", "w"); rf:write("entry\tname\tfamily\tskilled\trandom\tn\n")
for _, x in ipairs(rows) do rf:write(string.format("%d\t%s\t%s\t%.4f\t%.4f\t%d\n", x.id, D.species[x.id].name, x.fam, x.g, x.r, x.n)) end; rf:close()
local fs, fn, fr = {}, {}, {}
for _, x in ipairs(rows) do fs[x.fam] = (fs[x.fam] or 0) + x.g; fr[x.fam] = (fr[x.fam] or 0) + x.r; fn[x.fam] = (fn[x.fam] or 0) + 1 end
local out = {}; for f, v in pairs(fs) do out[#out + 1] = string.format("%s %.0f%%(R %.0f%%,n%d)", f, v / fn[f] * 100, fr[f] / fn[f] * 100, fn[f]) end; table.sort(out); print("skilled win by family:", table.concat(out, "  "))
print(string.format("R random mean team win %.1f%% | G %.1f%% | timeouts %d | greedy ability use by slot: %.0f%% / %.0f%% / %.0f%%", tot.R[1] / tot.R[2] * 100, tot.G[1] / tot.G[2] * 100, timeouts, slotPick[1] / picks * 100, slotPick[2] / picks * 100, slotPick[3] / picks * 100))
for i = 1, 6 do print(string.format("TOP %5.1f%% (R %4.1f%%) %s [%s]", rows[i].g * 100, rows[i].r * 100, D.species[rows[i].id].name, rows[i].fam)) end
for i = n, n - 5, -1 do print(string.format("LOW %5.1f%% (R %4.1f%%) %s [%s]", rows[i].g * 100, rows[i].r * 100, D.species[rows[i].id].name, rows[i].fam)) end
local unk = {}; for p, k in pairs(C.unknown) do unk[#unk + 1] = p .. ":" .. k end; print("unimplemented effect hits:", #unk == 0 and "none" or table.concat(unk, " "))
print(string.format("runtime %.0fs", os.clock() - T0))
