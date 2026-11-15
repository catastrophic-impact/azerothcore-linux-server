"""Kit pools by creature name keywords / creature type (shared by auto_picks.py and auto_repick.py). candidates(name, type) -> (kits, icon, critter_flag) with unusable kits (unimplemented abilities, boss/elite) removed."""
import re, sys
sys.path.insert(0, "pet-battle"); import gaplib
BEAR='Ability_Hunter_Pet_Bear'; CAT='Ability_Hunter_Pet_Cat'; CRAB='Ability_Hunter_Pet_Crab'; BAT='Ability_Hunter_Pet_Bat'; BOAR='Ability_Hunter_Pet_Boar'; WOLF='Ability_Hunter_Pet_Wolf'
SP='Ability_Hunter_Pet_Spider'; FISH='INV_Misc_Fish_02'; HUM='INV_Misc_Bandana_03'; UND='Spell_Nature_NullifyDisease'; MAG='Spell_Shadow_ShadowBolt'; ELE='Spell_Nature_HealingWay'; IMP='Spell_Shadow_SummonImp'; RAP='Ability_Hunter_Pet_Raptor'; ST='Spell_Nature_StoneClawTotem'; CRO='Ability_Hunter_Pet_Crocolisk'; DASH='Ability_Druid_Dash'; BIRD='Ability_Hunter_Pet_Bat'
POOLS = [  # (regex on the name, pool name, icon, kits)
 (r'cockroach', 'cockroach', DASH, [497], True), (r'tainted rat', 'rat', DASH, [499], True), (r'deer', 'deer', ELE, [486], True), (r'\bram\b', 'ram', BOAR, [434, 437], True),
 (r'spider|tarantula|spindleweb|spinner|leecher', 'spider', SP, [412, 400, 396, 407, 470, 699, 880], False),
 (r'murloc|naga|grimscale|blacksilt|wrathscale|siltfin', 'murloc', FISH, [1892, 1893, 1894, 2682, 2683, 1892], False),
 (r'flutterer|moth', 'moth', BIRD, [138, 139, 140, 141, 421, 464], False),
 (r'whelp|broodling|dragon', 'drake', 'INV_Misc_Head_Dragon_01', [57, 59, 87, 131, 382, 142], False),
 (r'crawler|crab|tide', 'crab', CRAB, [388, 401, 2374, 2381, 2386, 2399, 2400, 2425], False),
 (r'frenzy|reef|fin ', 'fish', FISH, [2695, 2652, 2694, 2651], False),
 (r'thistle|bear|ursa', 'bear', BEAR, [202, 440, 306, 508, 317, 205], False),
 (r'moonstalker|lurker|cat\b|lynx', 'cat', CAT, [301, 303, 41, 45, 224, 46], False),
 (r'strider|fledgling|buzzard|owl|hawk|wyvern|bat\b', 'bird', BIRD, [1470, 1469, 1468, 1471, 1709, 1710, 1713, 1907], False),
 (r'thresher|croc|behemoth|threshadon', 'croc', CRO, [959, 960, 961, 999, 1009], False),
 (r'boar', 'boar', BOAR, [1756, 1757, 1384, 124], False),
 (r'highborne|ghost|wraith|spirit|apparition', 'ghost', UND, [1750, 1868, 439, 190, 2754, 1740, 1790, 2397], False),
 (r'golem|elemental', 'golem', ST, [1811, 3447, 2086, 3511, 1008], False),
 (r'moonkin', 'moonkin', MAG, [296, 298, 1229, 2135], False),
]
TYPE_POOLS = {'Humanoid': ([1166, 1953, 2417, 1503, 1073, 1803, 888, 1725, 835, 1229, 1892, 1893, 1894, 2682, 1688, 2184, 2457], HUM), 'Undead': ([1146, 2553, 1523, 2751, 1963, 1968, 2749, 2411, 1428, 2408, 2485, 1442], UND), 'Beast': ([1542, 89, 1470, 303, 412, 400, 396, 407], WOLF), 'Elemental': ([204, 212, 1429, 1430, 535, 2014, 3409, 1811], ELE), 'Critter': ([417, 385, 379], DASH), 'Demon': ([1229, 2135, 2011, 2013, 1149, 1147], IMP), 'Dragonkin': ([57, 59, 87, 131, 382, 142], 'INV_Misc_Head_Dragon_01')}
def candidates(name, typ):
    for rx, pn, icon, kits, crit in POOLS:
        if re.search(rx, name.lower()):
            return [k for k in kits if gaplib.usable(str(k))] or kits, icon, bool(crit), pn
    h = TYPE_POOLS.get(typ)
    if not h: return None
    return [k for k in h[0] if gaplib.usable(str(k))] or h[0], h[1], False, "t" + typ
