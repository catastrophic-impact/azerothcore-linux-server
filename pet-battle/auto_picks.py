#!/usr/bin/env python3 -I
"""Draft a <zone>_picks.tsv from the roster (include=Y, not yet a species) by cycling through pools of ORDINARY retail kits chosen by name keywords + creature type.
A STARTING POINT ONLY (like assign_kits.py): review, then apply_zone.py, run_tests (gaps) and the balance sweep. Usage: python3 -I pet-battle/auto_picks.py <zone> [excludeEntry ...]"""
import sys, re, itertools
zone = sys.argv[1]; excl = set(sys.argv[2:])
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
pools = {}
def kit(i, name, typ):
    for rx, pn, icon, kits, crit in POOLS:
        if re.search(rx, name.lower()):
            pools.setdefault(pn, itertools.cycle(kits)); return next(pools[pn]), icon, 'critter' if crit else ''
    h = {'Humanoid': ([1166, 1953, 2417, 1503, 1073, 1803, 888, 1725, 835, 1229, 1892, 1893, 1894, 2682, 1688, 2184, 2457], HUM), 'Undead': ([1146, 2553, 1523, 2751, 1963, 1968, 2749, 2411, 1428, 2408, 2485, 1442], UND), 'Beast': ([1542, 89, 1470, 303, 412, 400, 396, 407], WOLF), 'Elemental': ([204, 212, 1429, 1430, 535, 2014, 3409, 1811], ELE), 'Critter': ([417, 385, 379], DASH), 'Demon': ([1229, 2135, 2011, 2013, 1149, 1147], IMP), 'Dragonkin': ([57, 59, 87, 131, 382, 142], 'INV_Misc_Head_Dragon_01')}.get(typ)
    if not h: return None
    pools.setdefault('t' + typ, itertools.cycle(h[0])); return next(pools['t' + typ]), h[1], ''
src = open('scripts/pb_data.lua').read(); existing = set(re.findall(r'\[(\d+)\] = \{ name', src))
out = ['# %s: entry, retail species, icon, flags (auto_picks.py draft)' % zone]
for l in open('pet-battle/%s_roster.tsv' % zone, encoding='utf-8'):
    if l.startswith('#') or l.startswith('include'): continue
    p = l.rstrip('\n').split('\t')
    if p[0] != 'Y' or p[1] in existing or p[1] in excl: continue
    k = kit(p[1], p[2], p[4])
    if k: out.append('%s\t%d\t%s%s' % (p[1], k[0], k[1], ('\t' + k[2]) if k[2] else ''))
    else: print('NO POOL for', p[1], p[2], p[4])
open('pet-battle/%s_picks.tsv' % zone, 'w').write('\n'.join(out) + '\n')
print(len(out) - 1, 'picks drafted')
