#!/usr/bin/env python3 -I
"""Mechanic templates: groups the retail pet-battle ability pool by what the ability DOES (effects + params + cooldown, name ignored) and labels each group with a role and its baseline numbers.
Usage (repo root): python3 -I pet-battle/mechanic_templates.py <abil.json> <cand.json> > pet-battle/mechanic_templates.tsv
abil.json = per-ability rows from the filter step (id, name, fam, desc, P, top, shipped); cand.json = ids of unshipped candidate abilities.
Output per template: role, members (names), numbers of the first member (dmg/heal points, accuracy, cooldown, turns, auras applied). Damage family stays a SEPARATE axis (a template is reused per pet family)."""
import csv, collections, json, sys
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
ab = {a['ID']: a for a in R('BattlePetAbility')}
st = {s['ID']: s['LuaName'] for s in R('BattlePetState')}
abst = collections.defaultdict(dict)
for x in R('BattlePetAbilityState'): abst[x['BattlePetAbilityID']][st.get(x['BattlePetStateID'], x['BattlePetStateID'])] = int(x['Value'])
tu = collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): tu[t['BattlePetAbilityID']].append(t)
ef = collections.defaultdict(list)
for e in R('BattlePetAbilityEffect'): ef[e['BattlePetAbilityTurnID']].append(e)
DMG = {24, 222, 96, 62, 384, 385, 29, 141, 66, 149, 197, 68, 27, 179, 226}; HEAL = {23, 104, 32, 44}   # 22 is a no-op in the engine (FX28); APPLY = {26, 50, 52, 178, 172}
def walk(a, depth=0):
    """yield (prop, params, aura_id, depth) for the ability and its aura abilities"""
    for t in sorted(tu[a], key=lambda t: int(t['OrderIndex'])):
        for e in sorted(ef[t['ID']], key=lambda e: int(e['OrderIndex'])):
            x = e['AuraBattlePetAbilityID']; yield int(e['BattlePetEffectPropertiesID']), [int(e['Param_%d' % i]) for i in range(6)], x, depth, t['TurnTypeEnum']
            if x != '0' and depth < 2: yield from walk(x, depth + 1)
def sig(a):
    return (ab[a]['Cooldown'], tuple((p, tuple(q), x if x == '0' else sig2(x), t) for p, q, x, dep, t in walk(a) if dep == 0))
def sig2(x): return tuple((p, tuple(q)) for p, q, _, dep, t in walk(x))
def role(a):
    P = list(walk(a)); props = {p for p, *_ in P}; sts = set()
    for p, q, x, dep, t in P:
        if x != '0': sts |= set(abst[x])
    parts = []
    dmg = props & DMG; hl = props & HEAL
    nturns = len(tu[a])
    if 141 in props: parts.append('aoe-dmg')
    elif dmg: parts.append('dmg' + ('-multiturn' if nturns > 1 else ''))
    if 54 in props or 'Add_PeriodicDamageTaken' in sts or any(p == 24 and q[2] for p, q, x, dep, t in P if dep > 0): parts.append('dot')
    if hl: parts.append('heal')
    if 63 in props: parts.append('hot')
    if 'Mechanic_IsStunned' in sts or 'turnLock' in sts: parts.append('stun')
    if 'swapOutLock' in sts or 'swapInLock' in sts: parts.append('swaplock')
    if 'Mechanic_IsBlind' in sts: parts.append('blind')
    if sts & {'Mechanic_IsChilled', 'Mechanic_IsWebbed'} or ('Mod_SpeedPercent' in sts and False): parts.append('slow')
    if sts & {'Mechanic_IsPoisoned', 'Mechanic_IsBurning', 'Mechanic_IsBleeding'} and 'dot' not in parts: parts.append('dot')
    if 'Mod_DamageTakenPercent' in sts or 'Add_FlatDamageTaken' in sts or 'Mechanic_IsWall' in sts or 'untargettable' in sts or 'Mechanic_IsFlying' in sts or 'Mechanic_IsUnderground' in sts or 'Special_BlockedAttackCount' in sts: parts.append('defense')
    if sts & {'Mod_DamageDealtPercent', 'Mod_SpeedPercent', 'Stat_Accuracy', 'Stat_CritChance', 'Critical_Damage_Bonus', 'Mod_HealingDealtPercent', 'Add_FlatDamageDealt'}: parts.append('buff/debuff')
    if any(s.startswith('Weather') for s in sts): parts.append('weather')
    if 49 in props and not parts: parts.append('cleanse')
    return '+'.join(dict.fromkeys(parts)) or 'special'
abil = json.load(open(sys.argv[1])); cand = set(json.load(open(sys.argv[2])))
# effects the engine does not run for an unshipped ability (found by pet-battle/sim_wild_kits.lua via C.unknown): 248/358/363 not implemented at all; 145 (Portal) only works for the shipped abilities
BLOCK = {248, 358, 363, 112, 86, 45, 145}   # found by pet-battle/sim_skill_kits.lua (C.unknown); 145/112 belong to abilities whose live support is only partial (Sweep, Shell Rush, Mass Resurrection): re-enable one by one after test_abilities confirms them
import re
_src = open('scripts/pb_core.lua').read(); _a = _src.index('local EFFECTS = {'); _b = _src.index('\n}\n', _a)
SUPPORTED = set(int(n) for n in re.findall(r'f\.prop == (\d+)', _src[_a:_b]))   # strictly the effect dispatch table of the engine ...
for _t in ('DAMAGE', 'APPLY', 'INERT'): SUPPORTED |= set(int(n) for n in re.findall(r'\[(\d+)\]', re.search(r'local %s = \{(.*?)\}' % _t, _src).group(1)))
SUPPORTED |= {384, 385}   # ... plus the damage tables and the two explicit extra-hit props
import os
BLOCKED = set()   # base ability ids a test rejected (pet-battle/ability_blocklist.txt, written by tests_to_blocklist.py from the run_tests output)
if os.path.exists('pet-battle/ability_blocklist.txt'):
    for _l in open('pet-battle/ability_blocklist.txt'):
        if _l.strip() and not _l.startswith('#'): BLOCKED.add(_l.split('\t')[0].strip())
def runnable(x): return not (set(x['P']) & BLOCK) and set(x['P']) <= SUPPORTED and x['id'] not in BLOCKED and (x['desc'] or '').strip() != ''
pool = [x for x in abil if x['top'] and (x['shipped'] or x['id'] in cand) and runnable(x)]
g = collections.defaultdict(list)
for x in pool: g[sig(x['id'])].append(x)
FAM = ['Humanoid', 'Dragonkin', 'Flying', 'Undead', 'Critter', 'Magic', 'Elemental', 'Beast', 'Aquatic', 'Mechanical']
AR = open(sys.argv[3], 'w') if len(sys.argv) > 3 else None   # optional: per-ability roles for the design review
if AR: AR.write('ability_id\tname\tpet_family\tshipped\trole\tcooldown\n')
print('template\trole\tmembers\tshipped\tcooldown\tturns\tdmg_points\tdmg_acc\theal_points\tauras\tfamilies\texample_names\tmember_ids')
for i, (k, v) in enumerate(sorted(g.items(), key=lambda kv: -len(kv[1])), 1):
    a = v[0]['id']; P = list(walk(a))
    if AR:
        for x in v: AR.write('%s\t%s\t%s\t%d\t%s\t%s\n' % (x['id'], x['name'], FAM[int(x['fam'])] if int(x['fam']) >= 0 else '-', x['shipped'], role(a), ab[a]['Cooldown']))
    dmg = [(q[0], q[1]) for p, q, x, dep, t in P if dep == 0 and p in DMG and p not in (29, 384, 385)]
    heal = [q[0] for p, q, x, dep, t in P if dep == 0 and p in HEAL]
    auras = sorted({s for p, q, x, dep, t in P if x != '0' for s in abst[x]})
    fams = collections.Counter(FAM[int(x['fam'])] if int(x['fam']) >= 0 else '-' for x in v)
    print('M%03d\t%s\t%d\t%d\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s' % (i, role(a), len(v), sum(x['shipped'] for x in v), ab[a]['Cooldown'], len(tu[a]),
        '/'.join(str(p) for p, _ in dmg) or '-', '/'.join(str(c) for _, c in dmg) or '-', '/'.join(map(str, heal)) or '-', ','.join(auras)[:60] or '-',
        ','.join('%s:%d' % kv for kv in fams.most_common(4)), '; '.join(x['name'] for x in v[:6]), ','.join(x['id'] for x in v)))
