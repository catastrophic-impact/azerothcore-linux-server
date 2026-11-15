-- Presentation invariant: the visual spell of an ability must FIT ITS NAME (user QA failure: Snowball cast a Fireball).
-- luajit pet-battle/test_ability_vis.lua   (project root)
package.path = "scripts/?.lua;" .. package.path
local D = require("pb_data"); local C = require("pb_core")
local fails, passes = {}, 0
local function check(c, m) if c then passes = passes + 1 else fails[#fails + 1] = m end end
local FROST, FIRE, SHADOW, NATURE, LEAF, LIGHT, HOLY, ARCANE, WATER, EARTH, WIND = 116, 9053, 686, 9591, 5176, 403, 31759, 7269, 31012, 9483, 3044
local cases = {
    { "Snowball", FROST }, { "Frost Shock", FROST }, { "Deep Freeze", FROST }, { "Ice Lance", FROST }, { "Call Blizzard", FROST }, { "Gift of Winter Veil", FROST },
    { "Fire Blast", FIRE }, { "Flame Breath", FIRE }, { "Scorch", FIRE }, { "Immolation", FIRE }, { "Meteor", FIRE },
    { "Shadow Shock", SHADOW }, { "Nether Blast", SHADOW }, { "Death Coil", SHADOW }, { "Drain Power", SHADOW },
    { "Poison Spit", NATURE }, { "Acid Touch", NATURE }, { "Sticky Web", NATURE }, { "Creeping Ooze", NATURE }, { "Leech Seed", NATURE },
    { "Thorn Lash", LEAF }, { "Poisoned Branch", NATURE }, { "Wrath", LEAF },
    { "Lightning Shield", LIGHT }, { "Static Shock", LIGHT }, { "Thunderbolt", LIGHT },
    { "Smite", HOLY }, { "Sunlight", HOLY }, { "Light", HOLY },
    { "Arcane Blast", ARCANE }, { "Surge of Power", ARCANE }, { "Powerball", ARCANE },
    { "Water Jet", WATER }, { "Tidal Wave", WATER }, { "Mud Throw", WATER },
    { "Stone Rush", EARTH }, { "Rock Barrage", EARTH }, { "Sand Toss", EARTH }, { "Dust Kick", EARTH },
    { "Slicing Wind", WIND }, { "Whirlwind", WIND }, { "Screech", WIND },
}
for _, t in ipairs(cases) do local v = C.ThemeVis(t[1]); check(v == t[2], "ThemeVis('" .. t[1] .. "') = " .. tostring(v) .. ", expected " .. t[2]) end
-- icons follow the same themes
check(C.ThemeIcon("Snowball") == "Spell_Frost_FrostBolt02", "Snowball icon is a frost icon, got " .. tostring(C.ThemeIcon("Snowball")))
check(C.ThemeIcon("Flame Breath") == "Spell_Fire_FlameBolt", "Flame Breath icon is a fire icon")
check(C.ThemeIcon("Shadow Shock") == "Spell_Shadow_ShadowBolt", "Shadow Shock icon is a shadow icon")
check(C.ThemeIcon("Cleansing Rain") == nil or true, "ThemeIcon never errors")
-- words that merely CONTAIN a theme word must not match it
for _, n in ipairs({ "Launch Rocket", "Slice", "Sunder", "Sundering Strike", "Bite", "Claw", "Peck", "Kick", "Rip", "Slam" }) do check(C.ThemeVis(n) == nil, "ThemeVis('" .. n .. "') must have no theme, got " .. tostring((C.ThemeVis(n)))) end
-- every shipped ability: if its name has a theme, its visual is that theme's spell, unless it comes from an explicit table entry (VIS table / D.rename override) for a themed spell
local ids = {}; for e in pairs(D.species) do ids[#ids + 1] = e end; table.sort(ids)
local bad, total = {}, 0
for _, id in ipairs(ids) do
    local ok, kit = pcall(C.Kit, id)
    if ok then for _, k in ipairs(kit) do
        local a = k.ability; total = total + 1
        local theme = C.ThemeVis(a.name)
        if theme and a.vis and a.vis ~= theme then
            local ov = D.rename[id] and D.rename[id][a.retailName]
            local explicit = ov and ov.vis ~= nil or a.vis == 17253 or a.vis == 16827   -- hand-styled by the species table / the bite+claw styles
            if not explicit then bad[a.name .. " vis " .. a.vis .. " expected " .. theme] = true end
        end
    end end
end
local list = {}; for k in pairs(bad) do list[#list + 1] = k end; table.sort(list)
local generic = {}
for _, id in ipairs(ids) do local ok, kit = pcall(C.Kit, id); if ok then for _, k in ipairs(kit) do
    local a = k.ability
    if C.ThemeVis(a.name) and a.icon == "Ability_Warrior_Rampage" and a.name ~= "Rampage" then generic[a.name] = true end
end end end
local gl = {}; for k in pairs(generic) do gl[#gl + 1] = k end; table.sort(gl)
check(#gl == 0, #gl .. " themed abilities still show the generic Rampage icon: " .. table.concat(gl, "; "))
check(#list == 0, #list .. " abilities with a themed name use a different visual: " .. table.concat(list, "; "))
check(total > 5000, "kit enumeration covered " .. total .. " abilities")
print(string.format("ability visuals: %d checks passed, %d failed (%d kit abilities scanned)", passes, #fails, total))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
