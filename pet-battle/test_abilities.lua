-- ABILITY CONFORMANCE: does every ability do what its own description says?  luajit pet-battle/test_abilities.lua [verbose|<ability name>]
-- Every ability of every species kit is played in a controlled battle (dice forced) and the claims found in its RESOLVED description are checked against the engine events:
-- damage amount, number of hits, healing, "% chance to stun", "always goes first", "if the user attacks first", "if the target is Bleeding/Burning/...", damage to self, lifesteal,
-- aura durations, "unattackable", "removes all buffs", forced swap, damage reduction. A claim that cannot be checked is listed as UNCHECKED so nothing hides.
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local only = arg and arg[1]
local verbose = only == "verbose"
local fails, passes, unchecked = {}, 0, {}
local claimsRan = {}
local function check(name, claim, ok, detail)
    claimsRan[claim:match('^%a+ %a+') or claim] = true
    if ok then passes = passes + 1 else fails[#fails + 1] = name .. ": " .. claim .. " -- " .. tostring(detail) end
end
local function unchecked_(name, why) unchecked[#unchecked + 1] = name .. ": " .. why end

-- KNOWN ENGINE GAP (2026-11-21): effect 145 (swap) is not implemented in pb_core: Sweep 457 / Retrieve 1944 (force the enemy's HIGHEST health pet in) and Shell Rush 1989 / Fight and Flight 2484 (swap the user out after the hit) hit but never swap.
-- Claims 67/68 below prove it; they are reported as UNCHECKED for these ids until the engine implements 145 (then delete this table). These abilities are NOT in the playable pool (golden status engine-gap).
local KNOWN_GAP_145 = {}   -- 2026-11-21: effect 145 implemented (FX145 in pb_core), so the swap claims 67/68 now run for Sweep, Retrieve, Shell Rush, Fight and Flight
-- dice: a constant roll clamped into range. 6 = every chance proc / hit lands and nothing crits (crit needs <= 5), 100 = every chance fails, 50 = 50% things land
local function dice(v) return function(a, b) return math.max(a, math.min(b, v)) end end
local PASS = { id = 0, name = "Pass", icon = "x", tip = "", cd = 0, turns = { { fx = {} } } }
local function neutralFamily(ab, fam0)
    local fam = (ab.family and ab.family >= 0) and Rules.FAMILIES[ab.family + 1] or fam0
    for _, f in ipairs(Rules.FAMILIES) do if Rules.Matchup(fam, f) == 1 and Rules.Matchup(f, fam) == 1 then return f end end
    return "Critter"
end
local function setup(ab, o)
    o = o or {}
    local rng = dice(o.roll or 6)
    local a = C.NewPet(721, o.level or 10, { 1, 1, 1 }, rng, { quality = 3 })
    local copy = {}; for k, v in pairs(ab) do copy[k] = v end
    copy.tip = C.Describe({ text = copy.text, turns = copy.turns, family = copy.family }, a.power)
    a.abil = { copy }; a.cd = { 0, 0, 0 }
    local e = C.NewPet(721, o.level or 10, { 1, 1, 1 }, rng, { quality = 3 })
    e.abil = { o.enemyAbility or PASS }; e.cd = { 0, 0, 0 }
    e.family = o.enemyFamily or neutralFamily(ab, a.family)
    a.speed = o.attackerFirst == false and 1 or 100000; e.speed = o.attackerFirst == false and 100000 or 1
    local team2 = { e }
    if o.enemyBench then local e2 = C.NewPet(721, o.level or 10, { 1, 1, 1 }, rng, { quality = 3 }); e2.abil = { PASS }; e2.cd = { 0, 0, 0 }; e2.family = e.family; team2[2] = e2 end
    local b = C.NewBattle({ a }, team2, rng)
    if o.hpFrac then a.hp = math.max(2, math.floor(a.max * o.hpFrac)) end
    return b, a, e
end
local function run(ab, o, rounds)
    local b, a, e = setup(ab, o)
    if o.prep then o.prep(b, a, e) end
    local evs = {}
    for r = 1, rounds or 1 do if r == 2 and o.thenPass then a.abil = { PASS }; a.cd = { 0, 0, 0 } end local ev = C.Round(b, "A1", "A1"); for _, x in ipairs(ev) do evs[#evs + 1] = x end end
    return evs, b, a, e
end
local function dmgEvents(evs, side) local t = {}; for _, x in ipairs(evs) do if not x.recoil and (x.k == "dmg" or x.k == "dot") and (not side or x.side == side) then t[#t + 1] = x end end; return t end
local function sum(t, f) local n = 0; for _, x in ipairs(t) do n = n + f(x) end; return n end

-- PINNED species: retail species listed in pet-battle/pinned_species.txt are generated into pb_retail for the test layer even when no shipped kit uses them, so abilities the engine
-- implements (1156 Mini Mindslayer: 277 Life Exchange) keep their checks after a kit re-pick
local PIN_KEEP = {}
do   -- one pinned test species per line of pinned_species.txt (ids 999990+)
    local i = 0
    for l in io.lines("pet-battle/pinned_species.txt") do
        local code = l:gsub("#.*", "")
        local id, keep = code:match("(%d+)%s*(.*)")   -- "<species> [abilityId ...]": with ability ids only THOSE kit abilities are pinned (the rest of that kit is not under test)
        if id then
            i = i + 1; D.species[999990 + i] = { name = "Pinned test species " .. id, retail = tonumber(id) }
            if keep and keep:match("%d") then PIN_KEEP[999990 + i] = {}; for k in keep:gmatch("%d+") do PIN_KEEP[999990 + i][tonumber(k)] = true end end
        end
    end
end
-- all distinct abilities of all species kits
local abilities, byName = {}, {}
for entry in pairs(D.species) do
    for _, k in ipairs(C.Kit(entry)) do
        local a = k.ability
        if (not PIN_KEEP[entry] or PIN_KEEP[entry][a.id]) and not abilities[a.id] then abilities[a.id] = a; byName[#byName + 1] = a end
    end
end
table.sort(byName, function(x, y) return x.retailName < y.retailName end)

for _, ab in ipairs(byName) do
    local name = ab.retailName .. " (" .. ab.id .. ")"
    if not only or only == "verbose" or ab.retailName == only then
        local desc = C.Describe({ text = ab.text, turns = ab.turns, family = ab.family }, C.NewPet(721, 10, { 1, 1, 1 }, dice(6), { quality = 3 }).power)
        local checked = 0
        -- 1. damage: "dealing N Family damage" = the first hit of the ability against a neutral target
        local eachUpTo = tonumber(desc:match("each dealing up to (%d+) %a+ damage"))   -- barrage: the number is PER HIT (Moth Balls: 4 hits)
        local upTo = (not eachUpTo) and tonumber(desc:match("dealing up to (%d+) %a+ damage"))
        if eachUpTo then
            checked = checked + 1
            local evs = run(ab, { roll = 6 }, 1); local hs = dmgEvents(evs, "P")
            local okEach = #hs >= 2; for _, x in ipairs(hs) do if math.abs(x.dmg - eachUpTo) > 3 then okEach = false end end
            check(name, "every hit deals up to " .. eachUpTo, okEach, #hs .. " hits, first " .. tostring(hs[1] and hs[1].dmg))
        end
        if upTo then
            checked = checked + 1
            local evs = run(ab, { roll = 6 }, 1); local tot = sum(dmgEvents(evs, "P"), function(x) return x.dmg end)
            check(name, "all hits of one use total " .. upTo, math.abs(tot - upTo) <= 3, "total " .. tot)
        end
        local pairForm = desc:match("or (%d+) %a+ damage if the user strikes (%a+)")
        local N = (not upTo) and (not pairForm) and (tonumber(desc:match("dealing (%d+) %a+ damage")) or tonumber(desc:match("Deals (%d+) %a+ damage")) or tonumber(desc:match("[Ii]nstantly deals (%d+) %a+ damage")))
        if N then
            checked = checked + 1
            local evs = run(ab, {}, #ab.turns)
            local d = dmgEvents(evs, "P")
            local first = d[1]
            if ab.turns[1] and #ab.turns > 1 and not first then   -- multi-turn: the damage lands on a later round, play them all
                evs = run(ab, {}, #ab.turns + 1); d = dmgEvents(evs, "P"); first = d[1]
            end
            if not first then   -- damage over time / reactive auras / delayed effects: let the enemy attack and play 8 rounds
                local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
                evs = run(ab, { enemyAbility = scratch }, 8); d = {}; for _, x in ipairs(evs) do if (x.k == "dmg" and x.side == "P") or (x.k == "dot" and x.side == "E") then d[#d + 1] = x end end; first = d[1]
            end
            local boostTaken = tonumber(desc:match("increasing damage taken by (%d+)%%")) or 0   -- a DoT that raises the damage taken also raises its own ticks
            local okFirst = first and (first.dmg == N or (boostTaken > 0 and math.abs(first.dmg - N * (100 + boostTaken) / 100) <= 1))
            if first and not okFirst then   -- "dealing N" may be the total of several hits of ONE use (Spiderling Swarm: 2 x half)
                local total = 0; for _, x in ipairs(d) do if x.round == nil and x.k == "dmg" and total < N then total = total + x.dmg end end
                okFirst = (total == N) or (#d >= 2 and d[1].dmg + d[2].dmg == N)
            end
            check(name, "first hit deals " .. N, okFirst, first and ("got " .. first.dmg) or "no damage event")
        end
        -- 2. hit count: "1-2 times", "1-3 blades", "1-2 Quills", "1-2 lashes"
        local lo, hi = desc:match("(%d)%-(%d) %a+")
        if lo and desc:find("per hit") or (lo and desc:find("per lash")) or (lo and desc:find("per attack")) then
            checked = checked + 1
            local evsHi = run(ab, { roll = 6 }); local evsLo = run(ab, { roll = 100 })
            local extra = ((desc:find("additional time") or desc:find("an additional")) and not desc:find("attacks last")) and 1 or 0   -- (+1 only for the FIRST-mover form; the "last" form is claim 5c)
            local nHi, nLo = #dmgEvents(evsHi, "P"), #dmgEvents(evsLo, "P")
            check(name, "hits up to " .. hi .. " times (+1 when first: " .. extra .. ")", nHi == tonumber(hi) + extra, "got " .. nHi)
            check(name, "hits at least " .. lo .. " time", nLo >= tonumber(lo), "got " .. nLo)
        end
        -- 2b. Life Exchange: "Equalizes the health between the user and his enemy" -> both active pets end on the same health (capped by their own maximum)
        if desc:find("Equalizes the health") then
            checked = checked + 1
            local _, b, a, e = run(ab, { hpFrac = 0.4 }, 1)
            check(name, "equalizes health (user 40% -> same hp as enemy)", math.abs(a.hp - e.hp) <= 1 and a.hp > a.max * 0.4 and e.hp < e.max, "user " .. a.hp .. " enemy " .. e.hp)
            local _, b2, a2, e2 = run(ab, { prep = function(bb, aa, ee) ee.hp = math.floor(ee.max * 0.2) end }, 1)
            local _, b3, a3, e3 = run(ab, { prep = function(bb, aa, ee) aa.hp = 1 end }, 1)   -- user at 1 hp vs a full enemy: the user gains, nobody faints, nobody above their max
            check(name, "equalizes health (user 1 hp)", a3.hp > 1 and a3.hp <= a3.max and e3.hp >= 1 and math.abs(a3.hp - e3.hp) <= 1, "user " .. a3.hp .. " enemy " .. e3.hp)
            local _, b4, a4, e4 = run(ab, { prep = function(bb, aa, ee) ee.hp = 1 end }, 1)   -- enemy at 1 hp vs a full user: the user pays but keeps at least 1 hp
            check(name, "equalizes health (enemy 1 hp)", a4.hp >= 1 and e4.hp > 1 and e4.hp <= e4.max and math.abs(a4.hp - e4.hp) <= 1, "user " .. a4.hp .. " enemy " .. e4.hp)
            local _, b5, a5, e5 = run(ab, { prep = function(bb, aa, ee) ee.hp = aa.hp end }, 1)   -- equal health: nothing changes
            check(name, "equalizes health (already equal)", a5.hp == a5.max and e5.hp == e5.max, "user " .. a5.hp .. " enemy " .. e5.hp)
            check(name, "equalizes health (enemy 20%, user full: the user pays)", math.abs(a2.hp - e2.hp) <= 1 and a2.hp < a2.max and e2.hp > e2.max * 0.2, "user " .. a2.hp .. " enemy " .. e2.hp)
        end
        -- 3b. "healing up to N% of your health" (Buried Treasure): a % of the MAXIMUM health
        local pctHeal = tonumber(desc:match("healing up to (%d+)%% of your health"))
        if pctHeal then
            checked = checked + 1
            local _, b, a = run(ab, { hpFrac = 0.4 }, 1)
            local want = math.floor(a.max * pctHeal / 100)
            local lost = a.max - math.floor(a.max * 0.4)
            check(name, "heals " .. pctHeal .. "% of max health", a.hp == math.max(2, math.floor(a.max * 0.4)) + math.min(want, a.max - math.max(2, math.floor(a.max * 0.4))), "hp " .. a.hp .. " max " .. a.max)
        end
        -- 3. healing: "Restores N health" (damaged user)
        local H = tonumber(desc:match("Restores (%d+) health")) or tonumber(desc:match("heals? .-for (%d+) health")) or tonumber(desc:match("heals? .-for (%d+)[^%d%%]"))
        if H and not desc:find("every round") and not desc:find("each round") then
            checked = checked + 1
            local evs, b, a = run(ab, { hpFrac = 0.4 }, #ab.turns)
            local healed = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then healed = healed + (x.amt or 0) end end
            check(name, "heals " .. H, healed == H, "healed " .. healed)
        end
        -- 4. stun chance: "N% chance to stun"
        local sp = tonumber(desc:match("(%d+)%% chance to stun")) or tonumber(desc:match("(%d+)%%%% chance to stun"))
        if sp and desc:match("chance to stun[^.]*if the target is") then unchecked_(name, "conditional stun (target state)"); sp = nil end
        if sp then
            checked = checked + 1
            local function stunned(roll) local evs = run(ab, { roll = roll, attackerFirst = true }); for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then return true end end return false end
            check(name, sp .. "% chance to stun (lands on a good roll)", stunned(6), "no stun")
            if sp < 100 then check(name, "no stun on a bad roll", not stunned(100), "stunned anyway") end
        end
        -- 5. always goes first
        if desc:find("always goes first") then
            checked = checked + 1
            local evs = run(ab, { attackerFirst = false, enemyAbility = nil })
            local firstAct; for _, x in ipairs(evs) do if x.k == "act" then firstAct = x.side; break end end
            check(name, "always goes first even when slower", firstAct == "P", "first act " .. tostring(firstAct))
        end
        -- 5b. pair form: "dealing A damage, or B damage if the user strikes first/last" (Arcane Slash, Tail Sweep, Scrabble)
        if pairForm then
            checked = checked + 1
            local base = tonumber(desc:match("[Dd]eal[a-z]* (%d+) %a+ damage, or")) or tonumber(desc:match("(%d+) %a+ damage, or"))
            local alt, cond = desc:match("or (%d+) %a+ damage if the user strikes (%a+)")
            alt = tonumber(alt)
            local function hit1(first) local d = dmgEvents(run(ab, { attackerFirst = first }), "P"); return d[1] and d[1].dmg end
            local whenCond, otherwise = hit1(cond == "first"), hit1(cond ~= "first")
            check(name, "deals " .. tostring(alt) .. " when it strikes " .. cond, whenCond == alt, "got " .. tostring(whenCond))
            check(name, "deals " .. tostring(base) .. " otherwise", otherwise == base, "got " .. tostring(otherwise))
        end
        -- 5d. walls: "blocks two attacks. Allied and enemy attacks both count" -> exactly two attacks are blocked, the third lands
        if desc:find("blocks two attacks") or desc:find("blocks 2 attacks") then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local evs = run(ab, { enemyAbility = scratch, attackerFirst = true }, 4)
            local blocked, landed = 0, 0
            for _, x in ipairs(evs) do if x.k == "dodge" and x.text == "Blocked!" then blocked = blocked + 1 end; if x.k == "dmg" and x.side == "E" and x.tside == "P" then landed = landed + 1 end end
            check(name, "blocks exactly two attacks", blocked == 2, "blocked " .. blocked)
            check(name, "the third attack lands", landed >= 1, "landed " .. landed)
        end
        -- 5c. "Hits an additional time if the user attacks last"
        if desc:find("Hits an additional time if the user attacks last") then
            checked = checked + 1
            local n1 = #dmgEvents(run(ab, { attackerFirst = false, roll = 6 }), "P"); local n2 = #dmgEvents(run(ab, { attackerFirst = true, roll = 6 }), "P")
            check(name, "hits an additional time when it attacks last", n1 == n2 + 1, n1 .. " vs " .. n2)
        end
        -- 6. "if the user attacks first" bonus: more damage when first than when second
        if desc:find("if the user strikes first") or desc:find("if the user attacks first") or desc:find("Hits an additional time if the user attacks first") or desc:find("goes first") and not desc:find("always goes first") and not desc:find("goes first if the weather") then
            checked = checked + 1
            local f = sum(dmgEvents(run(ab, { attackerFirst = true }), "P"), function(x) return x.dmg end)
            local s = sum(dmgEvents(run(ab, { attackerFirst = false }), "P"), function(x) return x.dmg end)
            local stunClaim = desc:find("stuns the opponent if the user goes first") or desc:find("stunning the opponent if the user goes first") or desc:find("Interrupts")
            if stunClaim then
                local function stunnedWhenFirst(first) local evs, _, _, e = run(ab, { attackerFirst = first }, 2); for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then return true end end return false end
                check(name, "stuns/interrupts the enemy when it goes first", stunnedWhenFirst(true), "no stun when first")
                check(name, "no stun when it goes second", not stunnedWhenFirst(false), "stunned when second")
            else check(name, "deals more when attacking first", f > s, "first " .. f .. " second " .. s) end
        end
        -- 7. conditional bonus: "if the target is Bleeding/Burning/Chilled/Webbed/Blinded/Poisoned"
        local stateOf = { Bleeding = "Mechanic_IsBleeding", Burning = "Mechanic_IsBurning", Chilled = "Mechanic_IsChilled", Webbed = "Mechanic_IsWebbed", Blinded = "Mechanic_IsBlind", Poisoned = "Mechanic_IsPoisoned" }
        local cond = (desc:find("double damage if the target is") or desc:find("additional damage if the target is") or desc:find("additional %a+ damage if the target is")) and (desc:match("if the target is (%a+)")) or nil
        local always = desc:match("Always hits if the target is (%a+)")
        if always and ({ Bleeding = 1, Blinded = 1 })[always] then
            checked = checked + 1
            local key = ({ Bleeding = "Mechanic_IsBleeding", Blinded = "Mechanic_IsBlind" })[always]
            local function hits(withState) local evs = run(ab, { roll = 100, prep = function(b, a, e) if withState then e.auras[#e.auras + 1] = { id = 9999, left = 3, states = { [key] = 1 }, pwr = 0 } end end }); return #dmgEvents(evs, "P") > 0 end
            check(name, "always hits a " .. always .. " target", hits(true), "missed")
            check(name, "can miss a target that is not " .. always, not hits(false), "hit anyway")
        end
        if cond and stateOf[cond] then
            checked = checked + 1
            local function total(withState)
                local evs = run(ab, { prep = function(b, a, e) if withState then e.auras[#e.auras + 1] = { id = 9999, left = 3, states = { [stateOf[cond]] = 1 }, pwr = 0 } end end })
                return sum(dmgEvents(evs, "P"), function(x) return x.dmg end)
            end
            check(name, "extra damage if the target is " .. cond, total(true) > total(false), total(true) .. " vs " .. total(false))
        end
        -- 8. damage to self: "dealing N X damage to themselves / to the user"
        local selfN = tonumber(desc:match("dealing (%d+) %a+ damage to themselves")) or tonumber(desc:match("(%d+) %a+ damage to the user"))
        if selfN then
            checked = checked + 1
            local evs, b, a = run(ab, {})
            local lost = a.max - a.hp
            check(name, "user takes " .. selfN .. " damage", lost == selfN, "user lost " .. lost)
        end
        -- 9. lifesteal: "healed for N% of the damage dealt"
        local lp = tonumber(desc:match("healed for (%d+)%% of the damage dealt")) or tonumber(desc:match("heals the user for (%d+)%% of the damage dealt"))
        if lp then
            checked = checked + 1
            local evs, b, a = run(ab, { hpFrac = 0.5 }, #ab.turns)
            local dealt = sum(dmgEvents(evs, "P"), function(x) return x.dmg end)
            local got = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got = got + (x.amt or 0) end end
            check(name, "heals " .. lp .. "% of damage dealt", dealt > 0 and math.abs(got - math.floor(dealt * lp / 100)) <= 1, "dealt " .. dealt .. " healed " .. got)
        end
        -- 10. "removes all buffs and debuffs from the user"
        if desc:find("removes all buffs and debuffs from the user") or desc:find("Removes all buffs and debuffs from the user") then
            checked = checked + 1
            local evs, b, a = run(ab, { prep = function(b, a, e) a.auras[#a.auras + 1] = { id = 9998, left = 3, states = { Mechanic_IsBleeding = 1 }, pwr = 0 }; a.auras[#a.auras + 1] = { id = 9999, left = 3, states = { Mod_SpeedPercent = 25 }, pwr = 0 } end })
            local left = 0; for _, au in ipairs(a.auras) do if au.id == 9998 or au.id == 9999 then left = left + 1 end end
            check(name, "removes all buffs and debuffs from the user", left == 0, left .. " left")
        end
        -- 11. forced swap: "forces an opponent's pet to swap into battle"
        if desc:find("forces an opponent's pet to swap") then
            checked = checked + 1
            local evs, b = run(ab, { enemyBench = true })
            check(name, "forces the enemy to swap", b.active.E == 2, "enemy active " .. b.active.E)
        end
        -- 12. "reducing all damage taken by N%": a hit on the user is smaller afterwards
        local red = tonumber(desc:match("reducing all damage taken by (%d+)%%"))
        if red then
            checked = checked + 1
            local scratch = nil; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local function taken(withAbility)
                local b, a, e = setup(ab, { enemyAbility = scratch, attackerFirst = true })
                if not withAbility then a.abil = { PASS } end
                local evs = {}; for _ = 1, 1 do for _, x in ipairs(C.Round(b, "A1", "A1")) do evs[#evs + 1] = x end end
                return sum(dmgEvents(evs, "E"), function(x) return x.dmg end)
            end
            local base, reduced = taken(false), taken(true)
            check(name, "damage taken reduced by " .. red .. "%", base > 0 and math.abs(reduced - math.floor(base * (100 - red) / 100 + 0.5)) <= 1, base .. " -> " .. reduced)
        end
        -- 13. "unattackable" / "Avoids enemy attacks made during the round": the enemy's hit that round does nothing
        if desc:find("unattackable") or desc:find("Avoids enemy attacks") or desc:find("Cannot be hit") then
            checked = checked + 1
            local scratch = nil; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local evs, b, a = run(ab, { enemyAbility = scratch, attackerFirst = true })
            local took = sum(dmgEvents(evs, "E"), function(x) return x.dmg end)
            check(name, "avoids the enemy attack in the round it is used", took == 0, "took " .. took)
        end
        -- 14. aura durations: "for N rounds" / "Lasts N rounds" with an aura applied to someone
        local dur = tonumber(desc:match("[Ll]asts (%d+) rounds?")) or tonumber(desc:match("for (%d+) rounds"))
        if dur and dur > 0 and not N and #ab.turns ~= dur and #ab.turns > 0 and not desc:find("next ability") then   -- ("next ability ... locked out for N rounds" is a cooldown lock, not an aura length)
            checked = checked + 1
            local evs, b, a, e = run(ab, {})
            local seen = 0
            for _, au in ipairs(a.auras) do seen = math.max(seen, au.left) end
            for _, au in ipairs(e.auras) do seen = math.max(seen, au.left) end
            if b.weather then seen = math.max(seen, b.weather.left) end
            -- the round ends by ticking the duration down once: left == dur or dur - 1 are both an aura of that length
            local delay = tonumber(desc:match("After (%d+) rounds?")) or 0   -- "After 1 round, the ground erupts for 2 rounds" = an aura of delay + dur
            check(name, "applies an aura of " .. (dur + delay) .. " rounds", seen == dur + delay or seen == dur + delay - 1, "longest aura left " .. seen)
        end
        local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
        local function enemyDamage(evs) return sum(dmgEvents(evs, "E"), function(x) return x.dmg end) end
        -- 15. "Stun the target for N round(s)": the enemy loses N actions
        local stunN = tonumber(desc:match("^100%% hit chance%. Stun the target for (%d+) round")) or tonumber(desc:match("Stun the target for (%d+) round"))
        if stunN then
            checked = checked + 1
            local evs = run(ab, { attackerFirst = true, enemyAbility = scratch, thenPass = true }, stunN + 2)
            local lost = 0; for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then lost = lost + 1 end end
            check(name, "stuns for " .. stunN .. " round(s)", lost == stunN, "enemy lost " .. lost .. " actions")
        end
        -- 16. "increases your chance to dodge ... by N%. Lasts M round": the enemy's attack in the same round is dodged
        local dodgeN = tonumber(desc:match("chance to dodge [^%d]*by (%d+)%%"))
        if dodgeN and desc:find("Lasts") then
            checked = checked + 1
            local evs = run(ab, { attackerFirst = true, enemyAbility = scratch, roll = 6 })
            check(name, "dodges the enemy attack in the round it is used (dodge " .. dodgeN .. "%)", enemyDamage(evs) == 0, "took " .. enemyDamage(evs))
        end
        -- 17. heal all allies: "restores N health to all allies" / "to each" (bench pets damaged)
        local healAll = tonumber(desc:match("restores (%d+) health to all allies")) or tonumber(desc:match("restoring (%d+) health to all allies")) or tonumber(desc:match("restoring (%d+) health to each"))
        if healAll then
            checked = checked + 1
            local rng = dice(6); local a = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 })
            local copy = {}; for k, v in pairs(ab) do copy[k] = v end; a.abil = { copy }; a.cd = { 0, 0, 0 }
            local mates = { a }; for i = 2, 3 do local m = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 }); m.abil = { PASS }; m.cd = { 0, 0, 0 }; m.hp = math.floor(m.max * 0.3); mates[i] = m end
            a.hp = math.floor(a.max * 0.3)
            local e = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 }); e.abil = { PASS }; e.cd = { 0, 0, 0 }; a.speed = 1000; e.speed = 1
            local b = C.NewBattle(mates, { e }, rng)
            local evs = C.Round(b, "A1", "A1"); local per = {}
            for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then per[x.idx] = (per[x.idx] or 0) + x.amt end end
            local okAll = true; for i = (desc:find("other friendly") and 2 or 1), 3 do if per[i] ~= healAll then okAll = false end end
            check(name, "heals every ally for " .. healAll, okAll, "per pet: " .. tostring(per[1]) .. "/" .. tostring(per[2]) .. "/" .. tostring(per[3]))
        end
        -- 18. blocks: "blocking the next attack(s)" / "blocking the next two attacks"
        local blockWord = desc:match("blocking the next (%a+) attacks") or (desc:find("blocking the next attack") and "one")
        if blockWord then
            checked = checked + 1
            local n = ({ one = 1, two = 2, three = 3 })[blockWord] or 1
            local evs = run(ab, { attackerFirst = true, enemyAbility = scratch, thenPass = true }, n + 1)
            local hitsTaken = #dmgEvents(evs, "E")
            check(name, "blocks " .. n .. " attack(s), then the next hits", hitsTaken == 1, "hits taken in " .. (n + 1) .. " rounds: " .. hitsTaken)
        end
        -- 19. next-attack buffs: "increases the damage of your next attack made within N round(s) by P%" (needs a second ability to attack with)
        local buffP = tonumber(desc:match("next attack made within %d+ rounds? by (%d+)%%"))
        if buffP then
            checked = checked + 1
            local function secondDamage(useBuff)
                local b, a, e = setup(ab, { attackerFirst = true })
                a.abil = { useBuff and ab or PASS, scratch }; a.cd = { 0, 0, 0 }
                C.Round(b, "A1", "A1"); local ev2 = C.Round(b, "A2", "A1")
                return sum(dmgEvents(ev2, "P"), function(x) return x.dmg end)
            end
            local base, buffed = secondDamage(false), secondDamage(true)
            check(name, "next attack deals +" .. buffP .. "%", base > 0 and math.abs(buffed - base * (100 + buffP) / 100) <= 2, base .. " -> " .. buffed)
        end
        -- 20. speed buffs: "(increases|reduces) your speed by N%"
        local spUp, spN = desc:match("(%a+)s your speed by (%d+)%%")
        if spN and (spUp == "increase" or spUp == "reduce") then
            checked = checked + 1
            local evs, b, a = run(ab, {})
            local sp = 0; for _, au in ipairs(a.auras) do sp = sp + (au.states.Mod_SpeedPercent or 0) end   -- still on after the round it was cast in: it matters at the start of the NEXT round
            check(name, "speed " .. spUp .. "s by " .. spN .. "%", sp == (spUp == "increase" and 1 or -1) * tonumber(spN), "speed mod " .. sp)
        end
        -- 21. healing over rounds: "restoring A health on the first round, B on the second, then C on the third" (Hibernate / Nap Time)
        local h1, h2, h3 = desc:match("restoring (%d+) health on the first round, (%d+) health on the second, then (%d+) health on the third")
        if h1 then
            checked = checked + 1
            local evs = run(ab, { hpFrac = 0.1 }, 3)
            local got = {}; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got[#got + 1] = x.amt end end
            check(name, "heals " .. h1 .. "/" .. h2 .. "/" .. h3 .. " over three rounds", got[1] == tonumber(h1) and got[2] == tonumber(h2) and got[3] == tonumber(h3), table.concat(got, "/"))
        end
        local st1, st2 = desc:match("restores (%d+) health each turn for (%d+) turns")
        if st1 then
            checked = checked + 1
            local evs = run(ab, { hpFrac = 0.1 }, tonumber(st2))
            local got = {}; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got[#got + 1] = x.amt end end
            local allEq = #got == tonumber(st2); for gi, g in ipairs(got) do if g ~= tonumber(st1) and gi < #got then allEq = false end end   -- the last one may be cut by the maximum health
            check(name, "heals " .. st1 .. " for " .. st2 .. " turns", allEq, table.concat(got, "/"))
        end
        -- 22. Wish: next round the pet is healed for 50% of max
        local wishP = tonumber(desc:match("healed for (%d+)%% of its maximum health"))
        if wishP then
            checked = checked + 1
            local evs, b, a = run(ab, { hpFrac = 0.1 }, 2)
            local got = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got = got + x.amt end end
            check(name, "heals " .. wishP .. "% of max health next round", math.abs(got - math.floor(a.max * wishP / 100)) <= 1, "healed " .. got .. " of max " .. a.max)
        end
        -- 23. Vengeance: damage equal to the last hit taken
        if desc:find("equal to the last hit taken") then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = false }); e.abil = { scratch }; a.abil = { ab }
            local evs = C.Round(b, "A1", "A1")
            local taken = sum(dmgEvents(evs, "E"), function(x) return x.dmg end); local dealt = sum(dmgEvents(evs, "P"), function(x) return x.dmg end)
            local pw = 100; for _, t in ipairs(ab.turns) do for _, f in ipairs(t.fx) do if f.prop == 197 then pw = f.p[1] end end end   -- retail Power (Dark Fate 150 = 150% of the last hit)
            check(name, "deals the damage of the last hit taken", taken > 0 and dealt == math.floor(taken * pw / 100), "took " .. taken .. " dealt " .. dealt)
        end
        -- 24. Haymaker: "If the ability misses, the user is stunned for 1 round"
        if desc:find("If the ability misses, the user is stunned") then
            checked = checked + 1
            local function userStunned(roll) local evs = run(ab, { roll = roll, thenPass = true }, 2); for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "P" then return true end end return false end
            local stunnedAfterMiss, stunnedAfterHit = userStunned(100), userStunned(6)
            check(name, "a miss stuns the user, a hit does not", stunnedAfterMiss and not stunnedAfterHit, "miss stun " .. tostring(stunnedAfterMiss) .. " hit stun " .. tostring(stunnedAfterHit))
        end
        -- 25. delayed damage: "After N rounds, the ice hits, causing ... M damage" (Ice Tomb) / "fall N rounds from now" (Apocalypse)
        local delayN, delayD = desc:match("After (%d+) rounds, .-causing the current enemy pet to take (%d+) %a+ damage")
        if delayN then
            checked = checked + 1
            local evs = run(ab, { enemyAbility = nil, thenPass = true }, tonumber(delayN) + 1)
            local total = 0; for _, x in ipairs(evs) do if (x.k == "dmg" and x.side == "P") or (x.k == "dot" and x.side == "E") then total = total + x.dmg end end
            check(name, "deals " .. delayD .. " after " .. delayN .. " rounds", total == tonumber(delayD), "dealt " .. total)
        end
        local apoc = tonumber(desc:match("meteor, which will fall (%d+) rounds from now"))
        if apoc then
            checked = checked + 1
            local evs, b, a, e = run(ab, { roll = 6, thenPass = true }, apoc + 1)
            check(name, "kills the active pets after " .. apoc .. " rounds", e.hp <= 0 or a.hp <= 0, "pets alive: " .. a.hp .. " / " .. e.hp)
        end
        -- 26. Wombo Combo: "dealing 20, 29, and 25 damage. The last hit will always critically strike"
        local w1, w2, w3 = desc:match("dealing (%d+), (%d+), and (%d+) %a+ damage")
        if w1 then
            checked = checked + 1
            local evs = run(ab, { roll = 6 }); local d = dmgEvents(evs, "P")
            check(name, "hits for " .. w1 .. ", " .. w2 .. ", " .. w3 .. " (last one crits: x2)", d[1] and d[2] and d[3] and d[1].dmg == tonumber(w1) and d[2].dmg == tonumber(w2) and d[3].dmg == tonumber(w3) * 2 and d[3].crit, (d[1] and d[1].dmg or "?") .. "/" .. (d[2] and d[2].dmg or "?") .. "/" .. (d[3] and (d[3].dmg .. (d[3].crit and "crit" or "")) or "?"))
        end
        -- 27. Chew: "On the next round, you will deal N damage in addition to your next attack"
        local chewN = tonumber(desc:match("you will deal (%d+) %a+ damage in addition to your next attack"))
        if chewN then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true }); a.abil = { ab, scratch }; a.cd = { 0, 0, 0 }
            C.Round(b, "A1", "A1"); local ev2 = C.Round(b, "A2", "A1")
            local total = sum(dmgEvents(ev2, "P"), function(x) return x.dmg end)
            local b2, a2 = setup(ab, { attackerFirst = true }); a2.abil = { PASS, scratch }; a2.cd = { 0, 0, 0 }; C.Round(b2, "A1", "A1")
            local base = sum(dmgEvents(C.Round(b2, "A2", "A1"), "P"), function(x) return x.dmg end)
            check(name, "next round deals " .. chewN .. " extra damage", total >= base + chewN - 2, "with " .. total .. " without " .. base)
        end
        -- 28. Survival: health cannot drop below 1 until the end of the next round
        if desc:find("preventing your health from being reduced below 1") then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); a.hp = 1
            local evs = C.Round(b, "A1", "A1")
            check(name, "survives a lethal hit with 1 health", a.hp >= 1, "hp " .. a.hp)
        end
        -- 29. Soothe: drowsy targets fall asleep at the end of next round unless hit
        if desc:find("Drowsy targets will fall asleep") then
            checked = checked + 1
            local evs, b, a, e = run(ab, { enemyAbility = nil }, 2)
            local asleep = false; for _, au in ipairs(e.auras) do if au.states.Mechanic_IsStunned or au.states.turnLock then asleep = true end end
            local seenStun = false; for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then seenStun = true end end
            check(name, "the target falls asleep after the drowsy round", asleep or seenStun, "no sleep seen")
        end
        -- 30. Reckless Strike: "increases the damage you take for N round by P%" (the user's own penalty)
        local recklessP = tonumber(desc:match("increases the damage you take for %d+ rounds? by (%d+)%%"))
        if recklessP then
            checked = checked + 1
            local function taken(useAb)
                local b, a, e = setup(ab, { attackerFirst = true }); e.abil = { scratch }; if not useAb then a.abil = { PASS } end
                return sum(dmgEvents(C.Round(b, "A1", "A1"), "E"), function(x) return x.dmg end)
            end
            local base, pen = taken(false), taken(true)
            check(name, "the USER takes +" .. recklessP .. "% damage afterwards", base > 0 and math.abs(pen - base * (100 + recklessP) / 100) <= 2, base .. " -> " .. pen)
        end
        -- 31. Horn Attack: "If the user is faster than the target, they have a N% chance to be trampled and lose their turn"
        local trampleP = tonumber(desc:match("faster than the target, they have a (%d+)%% chance to be trampled"))
        if trampleP then
            checked = checked + 1
            local function lost(first, roll) local evs = run(ab, { attackerFirst = first, roll = roll }); for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then return true end end return false end
            check(name, "faster user + good roll tramples the target", lost(true, 6), "no lost turn")
            check(name, "bad roll: no trample", not lost(true, 100), "trampled anyway")
            check(name, "slower user never tramples", not lost(false, 6), "trampled while slower")
        end
        -- 32. Snail Mail: "Builds up power during the first round. The next round ... dealing N damage"
        if desc:find("Builds up power during the first round") then
            checked = checked + 1
            local evs1 = run(ab, {}, 1); local evs2 = run(ab, {}, 2)
            check(name, "no damage in the first (build-up) round", #dmgEvents(evs1, "P") == 0, #dmgEvents(evs1, "P") .. " hits in round 1")
            check(name, "damage lands in the second round", #dmgEvents(evs2, "P") >= 1, "no damage by round 2")
        end
        -- 33. Sniff Out: "removes any objects on the battlefield"
        if desc:find("removes any objects on the battlefield") then
            checked = checked + 1
            local evs, b, a, e = run(ab, { prep = function(b, a, e) e.auras[#e.auras + 1] = { id = 9997, left = 3, states = { Mechanic_IsObject = 1 }, pwr = 0 }; a.auras[#a.auras + 1] = { id = 9996, left = 3, states = { Mechanic_IsObject = 1 }, pwr = 0 } end })
            local left = 0; for _, au in ipairs(e.auras) do if au.states.Mechanic_IsObject then left = left + 1 end end; for _, au in ipairs(a.auras) do if au.states.Mechanic_IsObject then left = left + 1 end end
            check(name, "removes every object from the battlefield", left == 0, left .. " objects left")
        end
        -- 34. Spiny Carapace: "Effectiveness is tripled for N round if this ability is used while already active"
        if desc:find("Effectiveness is tripled") then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true }); e.abil = { scratch }
            local r1 = sum(dmgEvents(C.Round(b, "A1", "A1"), "P"), function(x) return x.dmg end)   -- the reflect damage of round 1 (base)
            a.cd = { 0, 0, 0 }   -- (the cooldown is respected now: reset it to use the ability again while the aura is active)
            local r2 = sum(dmgEvents(C.Round(b, "A1", "A1"), "P"), function(x) return x.dmg end)   -- used again while active: tripled
            check(name, "re-using it while active triples the reflect", r1 > 0 and math.abs(r2 - 3 * r1) <= 3, "round 1 " .. r1 .. " round 2 " .. r2)
        end
        -- 35. Mana Surge: "Deals N additional damage when the weather is Arcane Winds"
        local surgeN = tonumber(desc:match("Deals (%d+) additional damage when the weather is"))
        if surgeN then
            checked = checked + 1
            R.states[99999] = R.states[99999] or { Weather_ArcaneStorm = 1 }
            local function total(weather) local evs = run(ab, { prep = function(b) if weather then b.weather = { id = 99999, left = 5 } end end }, 1); return sum(dmgEvents(evs, "P"), function(x) return x.dmg end) end
            local plain, boosted = total(false), total(true)
            check(name, "Arcane Winds adds " .. surgeN .. " damage", boosted - plain >= surgeN - 2, plain .. " -> " .. boosted)
        end
        -- 36. Nature's Ward: "your type is transformed into Elemental" while healing
        local typeTo = desc:match("your type is transformed into (%a+)")
        if typeTo then
            checked = checked + 1
            local function taken(useAb)
                local b, a, e = setup(ab, { attackerFirst = true }); e.abil = { scratch }; e.family = "Beast"; a.family = "Critter"
                if useAb then a.abil = { ab } else a.abil = { PASS }; a.family = typeTo end
                return sum(dmgEvents(C.Round(b, "A1", "A1"), "E"), function(x) return x.dmg end)
            end
            local viaAbility, direct = taken(true), taken(false)
            check(name, "defends as " .. typeTo .. " while the aura lasts", viaAbility > 0 and viaAbility == direct, "with the ability " .. viaAbility .. " as a real " .. typeTo .. " " .. direct)
        end
        -- 37. Perk Up: "increases the maximum health of your active pet by N per level for M rounds"
        local perkN, perkM = desc:match("maximum health of your active pet by (%d+) per level for (%d+) rounds")
        if perkN then
            checked = checked + 1
            local b, a = setup(ab, { attackerFirst = true }); local max0 = a.max
            C.Round(b, "A1", "A1")
            check(name, "max health +" .. perkN .. " per level", a.max == max0 + tonumber(perkN) * a.level, max0 .. " -> " .. a.max)
            a.abil = { PASS }; a.cd = { 0, 0, 0 }
            for _ = 1, tonumber(perkM) + 1 do C.Round(b, "A1", "A1") end
            check(name, "bonus ends after " .. perkM .. " rounds", a.max == max0, "max health still " .. a.max)
        end
        -- 38. Frog Kiss: "N% chance to transform the target into a frog for M round"
        local frogP = tonumber(desc:match("(%d+)%% chance to transform the target into a frog"))
        if frogP then
            checked = checked + 1
            local function frogged(roll) local evs = run(ab, { roll = roll, attackerFirst = true }); for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then return true end end return false end
            check(name, frogP .. "% chance to turn the target into a frog (it loses its turn)", frogged(6), "no frog")
            check(name, "no frog on a bad roll", not frogged(100), "frogged anyway")
        end
        -- 39. WEATHER abilities: the aura's states act on the whole battlefield (type damage bonus, sandstorm accuracy / flat damage, rain shortens DoTs)
        local weatherAura; for _, t in ipairs(ab.turns) do for _, f in ipairs(t.fx) do if f.prop == 80 then weatherAura = f.aura end end end
        if weatherAura and R.states[weatherAura] then
            checked = checked + 1
            local st = R.states[weatherAura]
            local evs, b = run(ab, {})
            check(name, "sets the weather (aura " .. weatherAura .. ")", b.weather and b.weather.id == weatherAura, "weather " .. tostring(b.weather and b.weather.id))
            if st.Mod_PetTypeDamageDealtPercent then
                local fam = Rules.FAMILIES[st.Mod_PetType_ID]
                local boostedAb
                for entry in pairs(D.species) do for _, k in ipairs(C.Kit(entry)) do
                    local a2 = k.ability
                    if not boostedAb and a2.family == st.Mod_PetType_ID - 1 and a2.cd == 0 and a2.turns[1] and a2.turns[1].fx[1] and (a2.turns[1].fx[1].prop == 24 or a2.turns[1].fx[1].prop == 222) and #a2.turns == 1 then boostedAb = a2 end
                end end
                if boostedAb then
                    local function dmgWith(weather) local evs = run(boostedAb, { prep = function(bb) if weather then bb.weather = { id = weatherAura, left = 5 } end end }); local d = dmgEvents(evs, "P")[1]; return d and d.dmg or 0 end
                    local plain, w = dmgWith(false), dmgWith(true)
                    local flatBonus = (weatherAura == 203 or st.Weather_LightningStorm) and 20 or 0   -- Lightning Storm also adds a flat bonus per attack (checked separately below)
                    local exp = plain * (100 + st.Mod_PetTypeDamageDealtPercent) / 100
                    check(name, fam .. " abilities deal +" .. st.Mod_PetTypeDamageDealtPercent .. "% in this weather (" .. boostedAb.retailName .. ")", plain > 0 and w >= exp - 2 and w <= exp + 2 + flatBonus, plain .. " -> " .. w)
                else unchecked_(name, "no family-" .. tostring(fam) .. " damage ability found to test the weather bonus") end
            end
            if st.Stat_Accuracy then   -- Sandstorm: every hit chance lowered: a 100% hit now misses on a roll above 100 + mod
                local function hits(weather, roll) local evs = run(scratch, { roll = roll, prep = function(bb) if weather then bb.weather = { id = weatherAura, left = 5 } end end }); return #dmgEvents(evs, "P") > 0 end
                local roll = 100 + st.Stat_Accuracy + 1
                check(name, "hit chance " .. st.Stat_Accuracy .. "%: a roll of " .. roll .. " hits without it, misses in it", hits(false, roll) and not hits(true, roll), "no change")
            end
            if st.Add_FlatDamageTaken then
                local function dmgWith(weather) local evs = run(scratch, { prep = function(bb) if weather then bb.weather = { id = weatherAura, left = 5 } end end }); local d = dmgEvents(evs, "P")[1]; return d and d.dmg or 0 end
                local plain, w = dmgWith(false), dmgWith(true)
                check(name, "flat damage " .. st.Add_FlatDamageTaken .. " on every attack", w == math.max(1, plain + st.Add_FlatDamageTaken), plain .. " -> " .. w)
            end
        end
        -- 40. per-round damage: "causing A damage on the first round, B on the second round, and C on the third round" (Stampede / Flock)
        local rA, rB, rC = desc:match("causing (%d+) %a+ damage on the first round, (%d+) %a+ on the second round, and (%d+) %a+ on the third round")
        if rA then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true }); local per = {}
            for r = 1, 3 do local evs = C.Round(b, "A1", "A1"); per[r] = sum(dmgEvents(evs, "P"), function(x) return x.dmg end) end
            local boost = tonumber(desc:match("take (%d+)%% increased damage")) or 0   -- Stampede / Flock: the first round's debuff raises rounds 2 and 3
            local function near(x, y, k) return math.abs(x - tonumber(y) * k) <= 3 end
            local k2 = 1 + boost / 100
            check(name, "deals " .. rA .. " / " .. rB .. " / " .. rC .. " in rounds 1-3 (x" .. k2 .. " after round 1 from its own debuff)", near(per[1], rA, 1) and near(per[2], rB, k2) and near(per[3], rC, k2), per[1] .. " / " .. per[2] .. " / " .. per[3])
        end
        -- 41. team-split channel: "deals N damage split across the enemy team ... additional damage if the weather is Cleansing Rain" (Dreadful Breath)
        local splitN = tonumber(desc:match("deals (%d+) %a+ damage split across the enemy team"))
        if splitN then
            checked = checked + 1
            local function total(weather)
                local evs = run(ab, { enemyBench = true, prep = function(bb) if weather then bb.weather = { id = 229, left = 5 } end end }, 1)
                local t = 0; for _, x in ipairs(evs) do if x.k == "dmg" and x.side == "P" then t = t + x.dmg end end; return t
            end
            local plain, rain = total(false), total(true)
            check(name, "round damage is split across the team (total " .. splitN .. ")", math.abs(plain - splitN) <= 3, "total " .. plain)
            if desc:find("weather is Cleansing Rain") then check(name, "extra damage in Cleansing Rain", rain > plain * 1.3, plain .. " -> " .. rain) end
        end
        -- 42. Pump: "First use: Increases your damage dealt by P%. Second use: ... dealing N damage"
        local pumpP, pumpN = desc:match("First use: Increases your damage dealt by (%d+)%%%. Second use: .-dealing (%d+) %a+ damage")
        if pumpP then
            checked = checked + 1
            local evs = run(ab, {}, 2); local per = {}
            local b, a, e = setup(ab, {}); local r1 = dmgEvents(C.Round(b, "A1", "A1"), "P"); local r2 = dmgEvents(C.Round(b, "A1", "A1"), "P")
            check(name, "first use deals no damage, second deals " .. pumpN, #r1 == 0 and r2[1] and r2[1].dmg == tonumber(pumpN), #r1 .. " hits then " .. (r2[1] and r2[1].dmg or "none"))
        end
        -- 43. Powerball: "increasing your speed by P%. Your speed continues to increase each time you use it"
        local ballP = tonumber(desc:match("increasing your speed by (%d+)%%%.? +Your speed continues to increase"))
        if ballP then
            checked = checked + 1
            local b, a = setup(ab, {}); local function spd() local t = 0; for _, au in ipairs(a.auras) do t = t + (au.states.Mod_SpeedPercent or 0) end return t end
            C.Round(b, "A1", "A1"); local s1 = spd(); C.Round(b, "A1", "A1"); local s2 = spd()
            check(name, "speed +" .. ballP .. "% per use, stacking", s1 == ballP and s2 == 2 * ballP, s1 .. " then " .. s2)
        end
        -- 44. "restoring N of the user's health" (Digest Brains)
        local selfHeal = tonumber(desc:match("restoring (%d+) of the user's health"))
        if selfHeal then
            checked = checked + 1
            local evs = run(ab, { hpFrac = 0.3 }, 1); local got = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got = got + x.amt end end
            check(name, "heals " .. selfHeal, got == selfHeal, "healed " .. got)
        end
        -- 45. "healing for N health every round for M rounds" (Reanimate)
        local hotN, hotM = desc:match("healing for (%d+) health every round for (%a+) rounds")
        if hotN then
            checked = checked + 1
            local rounds = ({ two = 2, three = 3, four = 4, five = 5 })[hotM] or tonumber(hotM) or 3
            local evs = run(ab, { hpFrac = 0.1, thenPass = true }, rounds + 1); local got = {}
            for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then got[#got + 1] = x.amt end end
            local ok = #got == rounds; for _, g in ipairs(got) do if g ~= tonumber(hotN) then ok = false end end
            check(name, "heals " .. hotN .. " every round for " .. rounds .. " rounds", ok, table.concat(got, "/"))
        end
        -- 46. "performing no actions for two rounds, then recovers/repairs N health" (Reboot / Repair)
        local restN = tonumber(desc:match("performing no actions for two rounds, then %a+ (%d+) health"))
        if restN then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true }); a.hp = 1; a.abil = { ab, scratch }; a.cd = { 0, 0, 0 }; e.abil = { PASS }
            local evsAll = {}; for r = 1, 4 do for _, x in ipairs(C.Round(b, r == 1 and "A1" or "A2", "A1")) do x.round = r; evsAll[#evsAll + 1] = x end end
            local healRound, healAmt, actions = nil, 0, 0
            for _, x in ipairs(evsAll) do
                if x.k == "heal" and x.side == "P" and not healRound then healRound = x.round; healAmt = x.amt end
                if x.k == "act" and x.side == "P" and x.round > 1 and (not healRound or x.round <= healRound) and x.slot == 2 then actions = actions + 1 end
            end
            check(name, "recovers " .. restN .. " after doing nothing for two rounds", healAmt == restN and healRound and healRound >= 3 and actions == 0, "heal " .. healAmt .. " in round " .. tostring(healRound) .. ", extra actions " .. actions)
        end
        -- 47. damage over time: "causing / dealing N X damage each round" (the aura damages its holder every round; only when the claim is about ticks, not the first hit)
        local tickN = tonumber(desc:match("causing (%d+) %a+ damage each round")) or tonumber(desc:match("dealing (%d+) %a+ damage each round")) or tonumber(desc:match("deals (%d+) %a+ damage every round"))
        if tickN and not desc:find("to your team each round") then
            checked = checked + 1
            local evs = run(ab, { roll = 6, thenPass = true }, 3)
            local ticks = {}; for _, x in ipairs(evs) do if (x.k == "dot" and x.side == "E") or (x.k == "dmg" and x.side == "P" and x.auraHit) then ticks[#ticks + 1] = x.dmg end end
            local ok = #ticks >= 1; for _, t in ipairs(ticks) do if math.abs(t - tickN) > 1 and math.abs(t - tickN * 1.25) > 1 then ok = false end end   -- (1.25: a poison that raises damage taken also raises its own ticks)
            check(name, "the target takes " .. tickN .. " damage every round", ok, #ticks .. " ticks: " .. table.concat(ticks, "/"))
        end
        -- 48. hit chance on aura damage: "Deals N damage to your team each round. M% Hit Chance" (Cyclone: each tick lands only M% of the time)
        local cycN = tonumber(desc:match("Deals (%d+) %a+ damage to your team each round"))
        local cycAcc = tonumber(desc:match("(%d+)%% hit chance"))
        if cycN and cycAcc and cycAcc < 100 then
            checked = checked + 1
            local misses = run(ab, { roll = 100, thenPass = true }, 4); local landed = 0
            for _, x in ipairs(misses) do if x.k == "dot" and x.side == "E" then landed = landed + 1 end end
            local hits = run(ab, { roll = 1, thenPass = true }, 4); local landed2 = 0
            for _, x in ipairs(hits) do if x.k == "dot" and x.side == "E" then landed2 = landed2 + 1 end end
            check(name, "aura damage respects its " .. cycAcc .. "% hit chance (no ticks on a bad roll, ticks on a good one)", landed == 0 and landed2 >= 1, "bad roll ticks " .. landed .. ", good roll ticks " .. landed2)
        end
        -- 49. Cyclone kit text: "Creates a cyclone which has a N% chance to deal D damage to the enemy team each round. Lasts M rounds."
        local cyN, cyD = desc:match("has a (%d+)%% chance to deal (%d+) %a+ damage to the enemy team each round")
        if cyN then
            checked = checked + 1
            local function ticks(roll) local evs = run(ab, { roll = roll, thenPass = true }, 4); local t = {}; for _, x in ipairs(evs) do if x.k == "dot" and x.side == "E" then t[#t + 1] = x.dmg end end return t end
            local good, bad = ticks(1), ticks(100)
            check(name, cyN .. "% chance per round: ticks of " .. cyD .. " on a good roll, none on a bad one", #bad == 0 and #good >= 1 and math.abs(good[1] - tonumber(cyD)) <= 3, "bad " .. #bad .. " good " .. #good .. " first tick " .. tostring(good[1]))
        end
        -- 50. Leech Seed: "Each round, the seed deals N damage and restores that damage as health to the user"
        local seedN = tonumber(desc:match("Each round, the seed deals (%d+) %a+ damage and restores that damage as health"))
        if seedN then
            checked = checked + 1
            local evs = run(ab, { roll = 6, hpFrac = 0.3, thenPass = true }, 3); local dots, heals = {}, {}
            for _, x in ipairs(evs) do if x.k == "dot" and x.side == "E" then dots[#dots + 1] = x.dmg elseif x.k == "heal" and x.side == "P" then heals[#heals + 1] = x.amt end end
            local okTick = #dots >= 1 and math.abs(dots[1] - seedN) <= 1
            local okHeal = false; for _, h in ipairs(heals) do if dots[1] and h == dots[1] then okHeal = true end end
            check(name, "each round the seed deals " .. seedN .. " and the caster is healed for the same", okTick and okHeal, "ticks " .. table.concat(dots, "/") .. " heals " .. table.concat(heals, "/"))
        end
        -- 51. Lightning Storm: "All pets deal N bonus Mechanical damage each time they attack"
        local lsN = tonumber(desc:match("deal (%d+) bonus %a+ damage each time they attack"))
        if lsN then
            checked = checked + 1
            local function dmgWith(weather) local evs = run(scratch, { prep = function(bb) if weather then bb.weather = { id = 203, left = 5 } end end }, 1); local d = dmgEvents(evs, "P")[1]; return d and d.dmg or 0 end
            local plain, w = dmgWith(false), dmgWith(true)
            check(name, "every attack deals extra Mechanical damage (about " .. lsN .. " at power 10)", w > plain, plain .. " -> " .. w)
        end
        -- 52. Brittle Webbing: "Takes N damage each time they attack"; Plagued Blood: "When damaged, the attacker is healed"
        local bwN = tonumber(desc:match("^Takes (%d+) %a+ damage each time they attack"))
        if bwN then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true }); local webbed = e; webbed.auras[#webbed.auras + 1] = { id = 381, left = 3, states = R.states[381], pwr = a.power, fam = "Beast", src = a }
            webbed.abil = { scratch }; webbed.cd = { 0, 0, 0 }; a.abil = { PASS }
            local hp0 = webbed.hp; local evs = C.Round(b, "A1", "A1")
            local selfDmg = 0; for _, x in ipairs(evs) do if x.reflect and x.tside == "E" then selfDmg = selfDmg + x.dmg end end
            check(name, "the webbed pet takes damage each time it attacks", selfDmg > 0, "self damage " .. selfDmg)
        end
        -- 53. Plant: "Activate: ... While planted your pet cannot swap. Deactivate: For every round spent planted, you gain N health"
        local plantN = tonumber(desc:match("For every round spent planted, you gain (%d+) health"))
        if plantN then
            checked = checked + 1
            local b, a = setup(ab, { attackerFirst = true, hpFrac = 0.2 }); local ev1 = C.Round(b, "A1", "A1"); local locked = C.Locked(a, "swapOutLock")
            a.abil = { PASS }; a.cd = { 0, 0, 0 }; local heals = {}; for _ = 1, 2 do for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "heal" and x.side == "P" then heals[#heals + 1] = x.amt end end end
            check(name, "planted: cannot swap and heals " .. plantN .. " every round", locked and #heals == 2 and heals[1] == plantN and heals[2] == plantN, "locked " .. tostring(locked) .. " heals " .. table.concat(heals, "/"))
            a.abil = { ab }; a.cd = { 0, 0, 0 }; C.Round(b, "A1", "A1"); a.abil = { PASS }; local after = 0; for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "heal" and x.side == "P" then after = after + 1 end end
            check(name, "using it again deactivates it (no more healing, can swap)", after == 0 and not C.Locked(a, "swapOutLock"), "heals after deactivation " .. after)
        end
        -- 54. Refuge: "A natural shield surrounds the user and each friendly critter, blocking the next attack they would take"
        if desc:find("each friendly critter, blocking the next attack") then
            checked = checked + 1
            local rng = dice(6); local mk = function(fam) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.family = fam; q.abil = { PASS }; q.cd = { 0, 0, 0 }; return q end
            local user = mk("Critter"); user.abil = { ab }; local critter, beast = mk("Critter"), mk("Beast")
            local e = mk("Beast"); e.abil = { PASS }; user.speed = 100; e.speed = 1
            local b = C.NewBattle({ user, critter, beast }, { e }, rng); C.Round(b, "A1", "A1")
            local function blocks(q) for _, au in ipairs(q.auras) do if au.charges and au.charges > 0 then return true end end return false end
            check(name, "the user and each friendly Critter get a block, a Beast does not", blocks(user) and blocks(critter) and not blocks(beast), "user " .. tostring(blocks(user)) .. " critter " .. tostring(blocks(critter)) .. " beast " .. tostring(blocks(beast)))
        end
        -- 55. Portal: "jumps through a magical portal, avoiding the opponent's attack. The user then swaps automatically with your highest health pet"
        if desc:find("swaps automatically with your highest health pet") or desc:find("The user then swaps with a random pet") then
            checked = checked + 1
            local rng = dice(6); local mk = function(frac) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; q.hp = math.floor(q.max * frac); q.speed = 50; return q end
            local user = mk(1); user.abil = { ab }; local low, high = mk(0.3), mk(0.9)
            local e = mk(1); e.abil = { scratch }; e.speed = 100
            local b = C.NewBattle({ user, low, high }, { e }, rng); local ev = C.Round(b, "A1", "A1")
            local hurt = 0; for _, x in ipairs(ev) do if x.k == "dmg" and x.side == "E" and x.tside == "P" then hurt = hurt + 1 end end
            check(name, "avoids the enemy attack that round", hurt == 0, hurt .. " hits taken")
            if desc:find("random pet") then check(name, "then swaps with a living ally", b.active.P ~= 1, "active " .. b.active.P)
            else check(name, "then swaps with the highest-health ally (index 3)", b.active.P == 3, "active " .. b.active.P) end
        end
        -- 56. Death Grip: "forces the opponent's lowest health pet to swap into battle"
        if desc:find("forces the opponent's lowest health pet to swap") then
            checked = checked + 1
            local rng = dice(6); local mk = function(frac) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; q.hp = math.floor(q.max * frac); return q end
            local user = mk(1); user.abil = { ab }; user.speed = 100; local e1, e2, e3 = mk(1), mk(0.6), mk(0.2); e1.speed = 1
            local b = C.NewBattle({ user }, { e1, e2, e3 }, rng); C.Round(b, "A1", "A1")
            check(name, "pulls the LOWEST health living enemy into battle (index 3)", b.active.E == 3, "active " .. b.active.E)
        end
        -- 57. Consume Corpse: "Consumes an allied corpse to restore N% of total health. Corpses can only be used once"
        local corpseP = tonumber(desc:match("Consumes an allied corpse to restore (%d+)%% of total health"))
        if corpseP then
            checked = checked + 1
            local rng = dice(6); local mk = function() local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; return q end
            local user = mk(); user.abil = { ab }; user.hp = math.floor(user.max * 0.2); user.speed = 100; local dead = mk(); dead.hp = 0; local e = mk(); e.speed = 1
            local b = C.NewBattle({ user, dead }, { e }, rng); local hp0 = user.hp; C.Round(b, "A1", "A1")
            check(name, "restores " .. corpseP .. "% of max health from a corpse", user.hp - hp0 == math.floor(user.max * corpseP / 100), hp0 .. " -> " .. user.hp)
            user.hp = math.floor(user.max * 0.2); user.cd = { 0, 0, 0 }; local hp1 = user.hp; C.Round(b, "A1", "A1")
            check(name, "the corpse can only be used once", user.hp == hp1, "healed again: " .. hp1 .. " -> " .. user.hp)
            local u2 = mk(); u2.abil = { ab }; u2.hp = math.floor(u2.max * 0.2); u2.speed = 100; local b2 = C.NewBattle({ u2 }, { mk() }, rng); local h2 = u2.hp; C.Round(b2, "A1", "A1")
            check(name, "without a corpse nothing happens", u2.hp == h2, h2 .. " -> " .. u2.hp)
        end
        -- 58. Corpse Explosion: "Instantly kills the user ... infects the target. Infected targets receive N% of their maximum health as damage every round for M rounds"
        local ceN, ceM = desc:match("receive (%d+)%% of their maximum health as %a+ damage every round for (%d+) rounds")
        if ceN then
            checked = checked + 1
            local evs, b, a, e = run(ab, { roll = 6, thenPass = true }, 3)
            local ticks = {}; for _, x in ipairs(evs) do if x.k == "dot" and x.side == "E" then ticks[#ticks + 1] = x.dmg end end
            check(name, "the user dies and the target takes " .. ceN .. "% of its max health each round", a.hp == 0 and #ticks >= 2 and ticks[1] == math.floor(e.max * tonumber(ceN) / 100), "user hp " .. a.hp .. " ticks " .. table.concat(ticks, "/") .. " max " .. e.max)
        end
        -- 59. "causing N damage every round. Lasts M rounds. Opponents struck by the flock take P% increased damage" (Falcosaur Swarm)
        local fsN, fsM = desc:match("causing (%d+) %a+ damage every round%. Lasts (%d+) rounds")
        if fsN then
            checked = checked + 1
            local boost = tonumber(desc:match("take (%d+)%% increased damage")) or 0
            local b, a, e = setup(ab, { attackerFirst = true }); local per = {}
            for r = 1, tonumber(fsM) do per[r] = sum(dmgEvents(C.Round(b, "A1", "A1"), "P"), function(x) return x.dmg end) end
            local ok2 = math.abs(per[1] - tonumber(fsN)) <= 3; for r = 2, tonumber(fsM) do if math.abs(per[r] - tonumber(fsN) * (1 + boost / 100)) > 3 then ok2 = false end end
            check(name, "deals " .. fsN .. " in round 1 and " .. fsN * (1 + boost / 100) .. " afterwards (its own +" .. boost .. "% debuff)", ok2, table.concat(per, "/"))
        end
        -- 60. plain stun: "stunning them for N round" (Crystal Prison): the target loses its next action
        if desc:find("stunning them for %d+ round") and not desc:find("%% chance") then
            checked = checked + 1
            local evs = run(ab, { roll = 6, enemyAbility = nil }, 2)
            local st = 0; for _, x in ipairs(evs) do if x.k == "stunned" and x.side == "E" then st = st + 1 end end
            check(name, "the target is stunned", st >= 1, st .. " stunned events")
        end
        -- 61. "Increases damage by N% for 1 round" (Inner Vision): the NEXT attack deals N% more
        local ivN = tonumber(desc:match("^Increases damage by (%d+)%% for 1 round"))
        if ivN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local function second(withBuff)
                local b, a, e = setup(ab, { attackerFirst = true }); a.abil = { withBuff and ab or PASS, scratch }; a.cd = { 0, 0, 0 }
                C.Round(b, "A1", "A1"); local hs = dmgEvents(C.Round(b, "A2", "A1"), "P"); return hs[1] and hs[1].dmg or 0
            end
            local base, buffed = second(false), second(true)
            check(name, "the next attack deals " .. ivN .. "% more", base > 0 and math.abs(buffed / base - (1 + ivN / 100)) < 0.05, base .. " -> " .. buffed)
        end
        -- 62. Minefield: "The next pet to swap into the battle will receive N Mechanical damage"
        local mfN = tonumber(desc:match("next pet to swap into the battle will receive (%d+) %a+ damage"))
        if mfN then
            checked = checked + 1
            local b, a, e = setup(ab, { attackerFirst = true, enemyBench = true }); C.Round(b, "A1", "A1")
            local e2 = b.E[2]; local hp0 = e2.hp; b.E[1].hp = 0; a.abil = { PASS }; a.cd = { 0, 0, 0 }; C.Round(b, "A1", "A1")   -- the front pet faints: the next one steps on the mine
            check(name, "the pet that swaps in takes " .. mfN, math.abs((hp0 - e2.hp) - mfN) <= 3, hp0 .. " -> " .. e2.hp)
            do   -- the mine laid on the PLAYER's team: swapping in triggers it too
                local rng = dice(6); local function mk() local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; return q end
                local p1, p2, en = mk(), mk(), mk(); en.abil = { ab }; en.speed = 100; p1.speed = 1
                local b2 = C.NewBattle({ p1, p2 }, { en }, rng); C.Round(b2, "A1", "A1"); local h = p2.hp; C.Round(b2, "S2", "A1")
                check(name, "swapping into the enemy's mine hurts the swapped-in pet", h - p2.hp >= mfN - 3, h .. " -> " .. p2.hp)
            end
        end
        -- 63. Explode: "Instantly kills the caster, dealing damage equal to N% of the user's total health to the current enemy"
        local exN = tonumber(desc:match("damage equal to (%d+)%% of the user's total health"))
        if exN then
            checked = checked + 1
            local evs, b, a, e = run(ab, { roll = 6 }, 1)
            local d = sum(dmgEvents(evs, "P"), function(x) return x.dmg end)
            check(name, "the caster dies and the enemy takes " .. exN .. "% of the caster's max health", a.hp == 0 and math.abs(d - math.floor(a.max * exN / 100)) <= 2, "caster hp " .. a.hp .. " dealt " .. d .. " expected " .. math.floor(a.max * exN / 100))
        end
        -- 64. "restoring N health to the user, and half that to other <family> allies" (Healing Stream, Draconic Remedy, Rebuild)
        local hsN, hsFam = desc:match("restoring (%d+) health to %a+, and half that amount? to other (%a+) allies")
        if not hsN then hsN, hsFam = desc:match("restoring (%d+) health to the user, and half that to other (%a+) allies") end
        if hsN then
            checked = checked + 1
            local fam = hsFam:sub(1, 1):upper() .. hsFam:sub(2); if fam == "Aquatic" or fam == "Dragonkin" or fam == "Mechanical" then else fam = nil end
            local rng = dice(6); local function mk(f) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 3 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; if f then q.family = f end; q.hp = math.floor(q.max * 0.1); return q end
            local user = mk(fam); user.abil = { ab }; user.speed = 100; local same, other = mk(fam), mk(fam == "Mechanical" and "Beast" or "Mechanical"); local e = mk(); e.hp = e.max; e.speed = 1
            local hu, hs2, ho = user.hp, same.hp, other.hp
            local b = C.NewBattle({ user, same, other }, { e }, rng); C.Round(b, "A1", "A1")
            check(name, "heals the user " .. hsN, math.abs((user.hp - hu) - tonumber(hsN)) <= 3, hu .. " -> " .. user.hp)
            check(name, "heals a same-family ally half (" .. math.floor(tonumber(hsN) / 2) .. ")", math.abs((same.hp - hs2) - tonumber(hsN) / 2) <= 3, hs2 .. " -> " .. same.hp)
            check(name, "does not heal another family", other.hp == ho, ho .. " -> " .. other.hp)
        end
        -- 65. Blinding Poison: "reducing their hit chance by N% for 1 round": with N = 100 the enemy's next attack misses
        local bpN = tonumber(desc:match("reducing their hit chance by (%d+)%% for 1 round"))
        if bpN and bpN >= 100 then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); local hits = 0
            for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "E" and x.tside == "P" then hits = hits + 1 end end
            check(name, "the poisoned enemy cannot hit", hits == 0, hits .. " hits landed")
        end
        -- 66. Spirit Spikes: "deals N Magic damage each time you take direct damage" - the attacker takes N back
        local ssN = tonumber(desc:match("deals (%d+) %a+ damage each time you take direct damage%. Lasts 1 round"))
        if ssN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); local back = 0
            for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "P" and x.tside == "E" then back = back + x.dmg end end
            check(name, "the attacker takes " .. ssN .. " back", math.abs(back - ssN) <= 3, "reflected " .. back)
        end
        -- 67. "forces the opponent's HIGHEST health pet to swap into battle" (Sweep, Retrieve): the highest-health living enemy bench pet comes in
        if desc:find("forces the opponent's highest health pet to swap") then
            checked = checked + 1
            local rng = dice(6); local mk = function(frac) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; q.hp = math.floor(q.max * frac); return q end
            local user = mk(1); user.abil = { ab }; user.speed = 100; local e1, e2, e3 = mk(1), mk(0.6), mk(0.9); e1.speed = 1
            local b = C.NewBattle({ user }, { e1, e2, e3 }, rng); C.Round(b, "A1", "A1")
            if KNOWN_GAP_145[ab.id] then unchecked_(name, "known gap: effect 145 forced swap (highest health) not implemented") else check(name, "pulls the HIGHEST health living enemy into battle (index 3)", b.active.E == 3, "active " .. b.active.E) end
        end
        -- 68. "Deals X damage to the enemy team and swaps the user with your highest health pet" (Shell Rush, Fight and Flight): after the hit the user swaps with the highest-health ally
        if desc:find("swaps the user with your highest health pet") then
            checked = checked + 1
            local rng = dice(6); local mk = function(frac) local q = C.NewPet(721, 10, { 1, 1, 1 }, rng, { quality = 2 }); q.abil = { PASS }; q.cd = { 0, 0, 0 }; q.hp = math.floor(q.max * frac); return q end
            local user = mk(1); user.abil = { ab }; user.speed = 100; local p2, p3 = mk(0.5), mk(0.9); local e = mk(1); e.speed = 1
            local b = C.NewBattle({ user, p2, p3 }, { e }, rng); C.Round(b, "A1", "A1")
            if KNOWN_GAP_145[ab.id] then unchecked_(name, "known gap: effect 145 swap-self after the hit not implemented") else check(name, "swaps the user with the highest-health ally (index 3)", b.active.P == 3, "active " .. b.active.P) end
        end
        -- 69. damage shields lasting 2+ rounds ("deals N damage each time you take direct damage. Lasts M rounds", Thorns, Fire Shield ...; claim 66 covers the 1-round form): the attacker takes N back
        local shN = (not desc:find("Lasts 1 round")) and tonumber(desc:match("[Dd]eals (%d+) %a+ damage each time you take direct damage%. Lasts"))
        if shN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); local back = 0
            for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "P" and x.tside == "E" then back = back + x.dmg end end
            check(name, "the attacker takes " .. shN .. " back from the shield", math.abs(back - shN) <= 3, "reflected " .. back)
        end
        -- 70. "Reduces up to N damage from each attack against you" (Spiked Skin, Spiked Shell, Spirit Spikes): a hit on the shielded user is smaller by min(N, hit)
        local rdN = tonumber(desc:match("[Rr]educes up to (%d+) damage from each attack against you"))
        if rdN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local function hitOnUser(shield)
                local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); if not shield then a.abil = { PASS }; a.cd = { 0, 0, 0 } end
                local taken = 0; for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "E" and x.tside == "P" then taken = taken + x.dmg end end
                return taken
            end
            local base, withShield = hitOnUser(false), hitOnUser(true)
            check(name, "a hit on the shielded user is reduced by up to " .. rdN, base > 0 and math.abs(withShield - math.max(0, base - rdN)) <= 1, base .. " -> " .. withShield)
        end
        -- 71. "dealing N% of the damage they take to their attacker" (Reflective Shield): the attacker takes N% of the hit back
        local rpN = tonumber(desc:match("dealing (%d+)%% of the damage they take to their attacker"))
        if rpN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local b, a, e = setup(ab, { attackerFirst = true, enemyAbility = scratch }); local hit, back = 0, 0
            for _, x in ipairs(C.Round(b, "A1", "A1")) do
                if x.k == "dmg" and x.side == "E" and x.tside == "P" then hit = hit + x.dmg elseif x.k == "dmg" and x.side == "P" and x.tside == "E" then back = back + x.dmg end
            end
            check(name, "the attacker takes " .. rpN .. "% of the hit back", hit > 0 and math.abs(back - math.floor(hit * rpN / 100)) <= 1, "hit " .. hit .. " back " .. back)
        end
        -- 72. "increasing damage taken by N%" on the ENEMY (Acidic Goo): the user's next direct hit on it is N% bigger
        local vtN, vtD = desc:match("increasing damage taken by (%d+)%% for (%d+) round")
        vtN = (tonumber(vtD) or 0) >= 2 and tonumber(vtN) or nil   -- a 1-round debuff is gone before the user's NEXT round (Call the Pack); only 2+ round debuffs are checked this way
        if vtN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local function nextHit(apply)
                local b, a, e = setup(ab, { attackerFirst = true }); if not apply then a.abil = { PASS }; a.cd = { 0, 0, 0 } end
                C.Round(b, "A1", "A1"); a.abil = { scratch }; a.cd = { 0, 0, 0 }
                local d = 0; for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "P" and x.tside == "E" then d = d + x.dmg end end
                return d
            end
            local base, boosted = nextHit(false), nextHit(true)
            check(name, "the next hit on the target is " .. vtN .. "% bigger", base > 0 and math.abs(boosted - math.floor(base * (100 + vtN) / 100 + 0.5)) <= 1, base .. " -> " .. boosted)
        end
        -- 73. "Increases the damage done by your active pet by N%" (Amplify Magic): the user's next hit is N% bigger
        local duN = tonumber(desc:match("[Ii]ncreases the damage done by your active pet by (%d+)%%"))
        if duN then
            checked = checked + 1
            local scratch; for _, k in ipairs(C.Kit(721)) do if k.ability.retailName == "Scratch" then scratch = k.ability end end
            local function nextHit(apply)
                local b, a, e = setup(ab, { attackerFirst = true }); if not apply then a.abil = { PASS }; a.cd = { 0, 0, 0 } end
                C.Round(b, "A1", "A1"); a.abil = { scratch }; a.cd = { 0, 0, 0 }
                local d = 0; for _, x in ipairs(C.Round(b, "A1", "A1")) do if x.k == "dmg" and x.side == "P" and x.tside == "E" then d = d + x.dmg end end
                return d
            end
            local base, boosted = nextHit(false), nextHit(true)
            check(name, "the user's next hit is " .. duN .. "% bigger", base > 0 and math.abs(boosted - math.floor(base * (100 + duN) / 100 + 0.5)) <= 1, base .. " -> " .. boosted)
        end
        if checked == 0 then unchecked_(name, desc:sub(1, 150)) end
    end
end

print(string.format("abilities: %d passed, %d failed, %d abilities with nothing checkable", passes, #fails, #unchecked))
for _, f in ipairs(fails) do print("FAIL " .. f) end
if verbose then for _, u in ipairs(unchecked) do print("UNCHECKED " .. u) end end
-- CANARY: pinned abilities must really be checked (a deleted/failed pin made the Life Exchange claims vanish silently)
if not only then
    local lifeX = false; for k in pairs(claimsRan) do if k:find("equalizes health") then lifeX = true end end
    if not lifeX then fails[#fails + 1] = "CANARY: no Life Exchange claim ran (pinned species 1156 / PINNED lost?)"; print("FAIL " .. fails[#fails]) end
end
os.exit(#fails == 0 and 0 or 1)
