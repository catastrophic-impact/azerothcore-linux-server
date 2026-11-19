-- PRESENTATION INVARIANTS (found by reading all 110 status labels, 2026-11-15):
--  1. no aura tooltip resolves a formula to zero ("reduced by 0%", "dealing 0 damage", "for the next 0 round")  [Geyser, Volcano, Blinding Poison]
--  2. an aura that hurts its holder (hit chance cut, lock, sleep, root) applied by the ENEMY is shown as a DEBUFF and lands on the enemy  [Stench hit its own caster]
--  3. the user's own Silk Cocoon block is a buff
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); require("pb_rules"); local C = require("pb_core")
local fails = 0
local function bad(m) fails = fails + 1; print("FAIL " .. m) end
-- 1: every aura referenced by an ability that some species can use
local auras, n = {}, 0
for _, s in pairs(D.species) do local rs = R.species[s.retail]; if rs then for _, x in ipairs(rs.abil) do
    local a = R.abilities[x[3]]
    for _, t in ipairs(a and a.turns or {}) do for _, f in ipairs(t.fx) do if f.aura and f.aura ~= 0 and R.abilities[f.aura] then auras[f.aura] = true end end end
end end end
for id in pairs(auras) do
    n = n + 1
    local tip = C.AuraTip(id, 200)
    for _, pat in ipairs{ "by 0%%", "dealing 0 ", "take 0 ", "next 0 ", "for 0 ", "deals 0 ", "by %?" } do
        if tip:find(pat) then bad("aura " .. id .. " " .. R.abilities[id].name .. ": '" .. tip .. "' matches " .. pat) end
    end
end
-- 1b: the same zero check for every kit ability text (Spore Shrooms said "dealing 0 Elemental damage")
local nab, seenAb = 0, {}
for sid in pairs(D.species) do for _, k in ipairs(C.Kit(sid)) do local ab = k.ability
    if not seenAb[ab.id .. ab.name] then seenAb[ab.id .. ab.name] = true; nab = nab + 1
        local tip = C.Describe({ text = ab.text, turns = ab.turns, family = ab.family }, 200)
        for _, pat in ipairs{ "by 0%%", "dealing 0 ", "take 0 ", "next 0 ", "for 0 ", "deals 0 ", "by %?", "restoring 0 ", "Restores 0 " } do
            if tip:find(pat) then bad("ability " .. ab.name .. ": '" .. tip:sub(1, 140) .. "' matches " .. pat) end
        end
    end
end end
-- 2: Stench (Skunk) must put a harmful debuff on the ENEMY
local sid; for id, s in pairs(D.species) do local rs = R.species[s.retail]; if rs and not sid then for _, x in ipairs(rs.abil) do if x[3] == 527 then sid = id end end end end
if not sid then bad("no species with Stench") else
    local function mirror(x) return { E = x.P, P = x.E, active = { E = x.active.P, P = x.active.E }, rng = x.rng } end
    local seenCast
    for seed = 1, 20 do
        math.randomseed(seed)
        local b = C.NewBattle({ C.NewPet(sid, 10, nil, nil, { quality = 2 }) }, { C.NewPet(sid, 10, nil, nil, { quality = 2 }) })
        local ev = C.Round(b, C.AI(mirror(b)), C.AI(b))
        local caster
        for _, e in ipairs(ev) do
            if e.k == "act" and e.name == "Stench" then caster = e.side; seenCast = true
            elseif (e.k == "buff" or e.k == "debuff") and e.what == "stench" then
                if e.k ~= "debuff" then bad("Stench shown as " .. e.k) end
                if caster and e.side == caster then bad("Stench landed on its own caster (" .. caster .. ")") end
            end
        end
    end
    if not seenCast then bad("Stench never cast in 20 rounds") end
end
-- 3: statuses by source
local function status(auraId, src, holder) local p = holder; p.auras = {}
    p.auras[1] = { id = auraId, left = 2, states = R.states[auraId] or {}, src = src }
    return C.StatusList(p)[1] end
local P1, P2 = C.NewPet(sid, 5), C.NewPet(sid, 5)
local cocoon = status(505, P1, P1); if cocoon.bad then bad("own Silk Cocoon shown as a debuff") end
for _, id in ipairs{ 498, 822, 248, 370, 338, 526 } do local st = status(id, P2, P1); if not st.bad then bad("enemy aura " .. id .. " (" .. st.label .. ") shown as a buff") end end
-- 4: flavored abilities: no retail story left in the tooltip, name matches what the ability does
local allRen = {}; for sid, t in pairs(D.rename) do for old, ov in pairs(t) do allRen[#allRen + 1] = { sid, old, ov } end end
for sid in pairs(D.species) do local f = C.Family(sid); for old, ov in pairs(D.famrename[f] or {}) do if not (D.rename[sid] and D.rename[sid][old]) then allRen[#allRen + 1] = { sid, old, ov } end end end
for _, r in ipairs(allRen) do local sid, old, ov = r[1], r[2], r[3]; if ov.name and ov.name ~= old then
    for _, k in ipairs(C.Kit(sid)) do if k.ability.retailName == old then
        local tip = C.Describe({ text = k.ability.text, turns = k.ability.turns, family = k.ability.family }, 200)
        if tip:find("%f[%a]" .. old:gsub("%p", "%%%0") .. "%f[%A]") then bad("flavored " .. ov.name .. " still names the retail ability " .. old .. ": " .. tip) end
        local dmg, heal = false, false
        for _, tn in ipairs(k.ability.turns) do for _, f in ipairs(tn.fx) do if f.prop == 24 or f.prop == 222 or f.prop == 96 or f.prop == 54 then dmg = true end if f.prop == 23 or f.prop == 63 then heal = true end end end
        for _, w in ipairs{ "Mend", "Heal", "Renew", "Rejuv", "Restor" } do if ov.name:find(w) and dmg and not heal then bad("flavored name " .. ov.name .. " sounds like healing but " .. old .. " deals damage") end end
        if tip:find("brilliant light") or tip:find("cloud of spores") then bad("flavored " .. ov.name .. " keeps retail flavor text: " .. tip) end
    end end
end end
-- 5: the "cannot act" message names the real cause (asleep/polymorphed/stunned/passes), never "hibernating" for a sleeper
do
    local function msg(label, self, pass) return C.LockText({ label = label, self = self, pass = pass }) end
    if not msg("Asleep", true):find("asleep") then bad("Asleep message: " .. msg("Asleep", true)) end
    if not msg("Polymorphed", true):find("frog") then bad("Polymorphed message: " .. msg("Polymorphed", true)) end
    if not msg("Stunned"):find("stunned") then bad("Stunned message: " .. msg("Stunned")) end
    if msg(nil, true, true):find("hibernat") then bad("a pass (all abilities on cooldown) must not say hibernating: " .. msg(nil, true, true)) end
    -- end to end: put a real sleeper / polymorph on the active pet and read the event the round emits
    local function mirror(x) return { E = x.P, P = x.E, active = { E = x.active.P, P = x.active.E }, rng = x.rng } end
    for _, c in ipairs{ { 498, "Asleep" }, { 822, "Polymorphed" } } do
        local b = C.NewBattle({ C.NewPet(sid, 5) }, { C.NewPet(sid, 5) })
        local e = b.E[1]; e.auras[1] = { id = c[1], left = 3, states = R.states[c[1]] or {}, src = b.P[1] }
        local got
        for _, x in ipairs((C.Round(b, "A1", "A1"))) do if x.k == "stunned" and x.side == "E" then got = C.LockText(x) end end
        if not got or not got:lower():find(c[2] == "Asleep" and "asleep" or "frog") then bad(c[2] .. " round message: " .. tostring(got)) end
    end
end
print(string.format("presentation: %d aura tooltips checked, %d failures", n, fails))
os.exit(fails == 0 and 0 or 1)
