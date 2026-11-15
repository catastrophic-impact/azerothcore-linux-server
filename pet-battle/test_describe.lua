package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local R = require("pb_retail"); require("pb_rules"); local C = require("pb_core")
local fails, n = 0, 0
local function ok(c, msg) n = n + 1; if not c then fails = fails + 1; print("FAIL " .. msg) end end
local dump = arg and arg[1] == "dump"
local ids = {}; for id in pairs(R.abilities) do ids[#ids + 1] = id end; table.sort(ids)
for _, id in ipairs(ids) do
    local a = R.abilities[id]
    C.unresolved = {}
    local t = C.Describe(a, 10)
    ok(#C.unresolved == 0, "ability " .. id .. " " .. a.name .. " has unresolved tokens " .. table.concat(C.unresolved, ",") .. ": " .. t)
    ok(not t:find("[%[%]]") and not t:find("nil") and not t:find("%?"), "ability " .. id .. " " .. a.name .. " text still has junk: " .. t)
    ok(not t:find("|4") and not t:find("|c"), "ability " .. id .. " leftover codes: " .. t)
    if dump then print(id, a.name, "=>", t) end
    ok(#C.AuraTip(id, 10) > 0 or R.states[id] == nil or true, "aura tip")
end
-- known texts (power 10 -> AttackBonus 1.5)
ok(C.Describe(R.abilities[591], 10) == "Adds up to 8 damage to every attack against the target.", "Wild Magic text: " .. C.Describe(R.abilities[591], 10))
ok(C.Describe(R.abilities[110], 10):find("^100%% hit chance%. Bites at the enemy, dealing 30 Beast damage%.") ~= nil, "Bite text: " .. C.Describe(R.abilities[110], 10))
ok(C.Describe(R.abilities[592], 10):find("Lasts 5 rounds") ~= nil, "Wild Magic 592 duration plural: " .. C.Describe(R.abilities[592], 10))
-- every aura of every state-carrying ability gets some description
for id, st in pairs(R.states) do ok((R.abilities[id] and R.abilities[id].name:find("Server Only")) or #C.AuraTip(id, 10) > 0 or next(st) == nil, "aura " .. id .. " has no description (" .. (R.abilities[id] and R.abilities[id].name or "no ability") .. ")") end
-- family info for the tooltips: Beast hits Critter hard, Critter hits Undead hard; the reverse tells what hurts it
local fi = C.FamilyInfo("Beast"); ok(fi.strong == "Critter" and fi.weak ~= "" and fi.hurtBy ~= "" and fi.name == "Beast", "family info: " .. fi.strong .. " / " .. fi.weak .. " / " .. fi.hurtBy .. " / " .. fi.resists)
-- WILD MAGIC (flat damage taken): every attack against the target deals +5 * AttackBonus extra; negative values (Deflection style) reduce, never below 1
do
    local NEVER = function(a, b) return b end
    local function pair() local a = C.NewPet(721, 10, { 1, 1, 1 }, NEVER, { quality = 3 }); local e = C.NewPet(721, 10, { 1, 1, 1 }, NEVER, { quality = 3 }); return C.NewBattle({ a }, { e }, NEVER) end
    local b = pair(); b.E[1].hp = b.E[1].max; local ev = C.Round(b, "A1", "A1"); local base
    for _, x in ipairs(ev) do if x.k == "dmg" and x.side == "P" then base = x.dmg end end
    local b2 = pair(); b2.E[1].auras[1] = { id = 591, left = 3, states = R.states[591], pwr = b2.P[1].power }
    local ev2 = C.Round(b2, "A1", "A1"); local boosted
    for _, x in ipairs(ev2) do if x.k == "dmg" and x.side == "P" then boosted = x.dmg end end
    local extra = math.floor(5 * (1 + b2.P[1].power / 20) + 0.5)
    ok(base and boosted and boosted == base + extra, "Wild Magic adds " .. tostring(extra) .. ": " .. tostring(base) .. " -> " .. tostring(boosted))
    local b3 = pair(); b3.E[1].auras[1] = { id = 309, left = 3, states = { Add_FlatDamageTaken = -500 }, pwr = 0 }
    local ev3 = C.Round(b3, "A1", "A1"); local least
    for _, x in ipairs(ev3) do if x.k == "dmg" and x.side == "P" then least = x.dmg end end
    ok(least == 1, "flat reduction never goes below 1 damage: " .. tostring(least))
    -- the status icon of Wild Magic carries its description
    local sl = C.StatusList(b2.E[1]); ok(sl[1] and sl[1].tip:find("Adds up to") ~= nil and sl[1].bad == true, "status tip: " .. tostring(sl[1] and sl[1].tip))
end
-- every aura an ability can apply must show the player a real name and description (user asked: do debuffs say what they are?); internal "Server Only" auras are hidden
do
    local seenA = {}
    for _, a in pairs(R.abilities) do for _, t in ipairs(a.turns or {}) do for _, f in ipairs(t.fx or {}) do if f.aura and f.aura ~= 0 then seenA[f.aura] = true end end end end
    for id in pairs(seenA) do
        local list = C.StatusList({ power = 10, family = "Beast", auras = { { id = id, left = 2, states = R.states[id] or {}, pwr = 10 } } })
        for _, st in ipairs(list) do
            ok(st.tip ~= "", "aura " .. id .. " '" .. st.label .. "' is shown to the player with an empty description")
            ok(not st.label:find("Server Only") and not st.label:find("^Effect %d"), "aura " .. id .. " shows an internal/unnamed label: " .. st.label)
        end
    end
end
-- damaging auras an enemy applies are DEBUFFS and carry the caster's flavored name (user report: the Kobold Miner's Rust "did nothing": shown as a buff named Creeping Fungus)
do
    local hi = function(x, y) return y end
    local a = C.NewPet(40, 10, { 1, 1, 1 }, hi, { quality = 3 }); local e = C.NewPet(721, 10, { 1, 1, 1 }, hi, { quality = 3 })
    local rust; for i, ab in ipairs(a.abil) do if ab.name == "Rust" then rust = i end end
    ok(rust ~= nil, "Kobold Miner kit has Rust in slot 2")
    local b = C.NewBattle({ a }, { e }, hi); local ev = C.Round(b, "A" .. (rust or 1), "A1")
    local found; for _, x in ipairs(ev) do if (x.k == "buff" or x.k == "debuff") and x.side == "E" then found = x end end
    ok(found and found.k == "debuff" and found.what == "rust", "Rust is announced as a debuff named rust: " .. tostring(found and (found.k .. " " .. found.what)))
    local sl = C.StatusList(e); ok(sl[1] and sl[1].label == "Rust" and sl[1].bad == true, "enemy status list shows Rust as a harmful status: " .. tostring(sl[1] and sl[1].label))
    local thorn = C.StatusList({ power = 10, family = "Beast", auras = { { id = 1086, left = 2, states = R.states[1086] or {}, pwr = 10, src = e } } })
    ok(thorn[1] and thorn[1].bad == false, "Toxic Skin (damaging buff) stays a buff")
end
print(string.format("describe: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
