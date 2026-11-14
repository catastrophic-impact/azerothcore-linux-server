-- ABILITY CONFORMANCE: does every ability do what its own description says?  luajit pet-battle/test_abilities.lua [verbose|<ability name>]
-- Every ability of every species kit is played in a controlled battle (dice forced) and the claims found in its RESOLVED description are checked against the engine events:
-- damage amount, number of hits, healing, "% chance to stun", "always goes first", "if the user attacks first", "if the target is Bleeding/Burning/...", damage to self, lifesteal,
-- aura durations, "unattackable", "removes all buffs", forced swap, damage reduction. A claim that cannot be checked is listed as UNCHECKED so nothing hides.
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); local Rules = require("pb_rules"); local C = require("pb_core")
local only = arg and arg[1]
local verbose = only == "verbose"
local fails, passes, unchecked = {}, 0, {}
local function check(name, claim, ok, detail)
    if ok then passes = passes + 1 else fails[#fails + 1] = name .. ": " .. claim .. " -- " .. tostring(detail) end
end
local function unchecked_(name, why) unchecked[#unchecked + 1] = name .. ": " .. why end

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
local function dmgEvents(evs, side) local t = {}; for _, x in ipairs(evs) do if (x.k == "dmg" or x.k == "dot") and (not side or x.side == side) then t[#t + 1] = x end end; return t end
local function sum(t, f) local n = 0; for _, x in ipairs(t) do n = n + f(x) end; return n end

-- all distinct abilities of all species kits
local abilities, byName = {}, {}
for entry in pairs(D.species) do
    for _, k in ipairs(C.Kit(entry)) do
        local a = k.ability
        if not abilities[a.id] then abilities[a.id] = a; byName[#byName + 1] = a end
    end
end
table.sort(byName, function(x, y) return x.retailName < y.retailName end)

for _, ab in ipairs(byName) do
    local name = ab.retailName .. " (" .. ab.id .. ")"
    if not only or only == "verbose" or ab.retailName == only then
        local desc = C.Describe({ text = ab.text, turns = ab.turns, family = ab.family }, C.NewPet(721, 10, { 1, 1, 1 }, dice(6), { quality = 3 }).power)
        local checked = 0
        -- 1. damage: "dealing N Family damage" = the first hit of the ability against a neutral target
        local N = tonumber(desc:match("dealing (%d+) %a+ damage")) or tonumber(desc:match("Deals (%d+) %a+ damage"))
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
            local okFirst = first and first.dmg == N
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
            local extra = (desc:find("additional time") or desc:find("an additional")) and 1 or 0
            local nHi, nLo = #dmgEvents(evsHi, "P"), #dmgEvents(evsLo, "P")
            check(name, "hits up to " .. hi .. " times (+1 when first: " .. extra .. ")", nHi == tonumber(hi) + extra, "got " .. nHi)
            check(name, "hits at least " .. lo .. " time", nLo >= tonumber(lo), "got " .. nLo)
        end
        -- 3. healing: "Restores N health" (damaged user)
        local H = tonumber(desc:match("Restores (%d+) health")) or tonumber(desc:match("heals? .-for (%d+)"))
        if H and not desc:find("every round") and not desc:find("each round") then
            checked = checked + 1
            local evs, b, a = run(ab, { hpFrac = 0.4 }, #ab.turns)
            local healed = 0; for _, x in ipairs(evs) do if x.k == "heal" and x.side == "P" then healed = healed + (x.amt or 0) end end
            check(name, "heals " .. H, healed == H, "healed " .. healed)
        end
        -- 4. stun chance: "N% chance to stun"
        local sp = tonumber(desc:match("(%d+)%% chance to stun")) or tonumber(desc:match("(%d+)%%%% chance to stun"))
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
        -- 6. "if the user attacks first" bonus: more damage when first than when second
        if desc:find("if the user strikes first") or desc:find("if the user attacks first") or desc:find("Hits an additional time if") or desc:find("goes first") and not desc:find("always goes first") then
            checked = checked + 1
            local f = sum(dmgEvents(run(ab, { attackerFirst = true }), "P"), function(x) return x.dmg end)
            local s = sum(dmgEvents(run(ab, { attackerFirst = false }), "P"), function(x) return x.dmg end)
            local stunClaim = desc:find("stuns the opponent if the user goes first") or desc:find("Interrupts")
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
        local lp = tonumber(desc:match("healed for (%d+)%% of the damage dealt"))
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
        if dur and dur > 0 and not N and #ab.turns ~= dur and #ab.turns > 0 then
            checked = checked + 1
            local evs, b, a, e = run(ab, {})
            local seen = 0
            for _, au in ipairs(a.auras) do seen = math.max(seen, au.left) end
            for _, au in ipairs(e.auras) do seen = math.max(seen, au.left) end
            if b.weather then seen = math.max(seen, b.weather.left) end
            -- the round ends by ticking the duration down once: left == dur or dur - 1 are both an aura of that length
            check(name, "applies an aura of " .. dur .. " rounds", seen == dur or seen == dur - 1, "longest aura left " .. seen)
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
        local spUp, spN = desc:match("(%a+)s? your speed by (%d+)%%")
        if spN and (spUp == "increase" or spUp == "reduce") then
            checked = checked + 1
            local evs, b, a = run(ab, {})
            local sp = 0; for _, au in ipairs(a.auras) do sp = sp + (au.states.Mod_SpeedPercent or 0) end
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
            check(name, "deals the damage of the last hit taken", taken > 0 and dealt == taken, "took " .. taken .. " dealt " .. dealt)
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
        if checked == 0 then unchecked_(name, desc:sub(1, 150)) end
    end
end

print(string.format("abilities: %d passed, %d failed, %d abilities with nothing checkable", passes, #fails, #unchecked))
for _, f in ipairs(fails) do print("FAIL " .. f) end
if verbose then for _, u in ipairs(unchecked) do print("UNCHECKED " .. u) end end
os.exit(#fails == 0 and 0 or 1)
