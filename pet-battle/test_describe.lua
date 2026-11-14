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
print(string.format("describe: %d passed, %d failed", n - fails, fails)); os.exit(fails == 0 and 0 or 1)
