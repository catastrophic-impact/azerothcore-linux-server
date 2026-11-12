#!/usr/bin/env python3 -I
"""Assign retail pet kits (abilities/family) to OUR creatures. Usage: python3 -I pet-battle/assign_kits.py [roster.tsv] > pet-battle/elwynn_kits.tsv
Rule (user, 2026-11-12): group our creatures by KIND (the last word of the name: Wolf, Bear, Spider...), take the retail species of that kind,
deal their kits out EVENLY and deterministically (sorted by creature entry, round robin). No kind match -> 'NOMATCH' (needs a family fallback or a hand-written kit).
Humanoid role rule (later phase): only deal kits whose ability school matches the creature's class (no wizard spells for warriors)."""
import csv, collections, sys
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
cr = {c['ID']: c for c in R('Creature')}
spc = R('BattlePetSpecies'); ab = {a['ID']: a for a in R('BattlePetAbility')}
sx = collections.defaultdict(list)
for x in R('BattlePetSpeciesXAbility'): sx[x['BattlePetSpeciesID']].append(x)
PT = ['Humanoid', 'Dragonkin', 'Flying', 'Undead', 'Critter', 'Magic', 'Elemental', 'Beast', 'Aquatic', 'Mechanical']
by_kind = collections.defaultdict(list)
for s in spc:
    c = cr.get(s['CreatureID'])
    if not c or not sx.get(s['ID']): continue
    by_kind[c['Name_lang'].split()[-1].lower()].append((c['Name_lang'], s))
def kit(s):
    out = []
    for x in sorted(sx[s['ID']], key=lambda x: (int(x['SlotEnum']), int(x['RequiredLevel']))):
        out.append('%s:%s' % (x['SlotEnum'], ab[x['BattlePetAbilityID']]['Name_lang']))
    return ' | '.join(out)
path = sys.argv[1] if len(sys.argv) > 1 else 'pet-battle/elwynn_roster.tsv'
rows = [l.rstrip('\n').split('\t') for l in open(path, encoding='utf-8') if not l.startswith('#')]
hdr = rows[0]; rows = [dict(zip(hdr, r)) for r in rows[1:] if r[0] == 'Y']
# world facts per creature (pet-battle/elwynn_meta.tsv = entry, unit_class, creature type, family, weapon class/subclass list from creature_equip_template)
meta = {}
for l in open(path.replace('roster', 'meta') if 'roster' in path else 'pet-battle/elwynn_meta.tsv', encoding='utf-8'):
    p = l.rstrip('\n').split('\t'); meta[p[0]] = p
def role(m):   # Humanoid role from class + weapon: staff (2/10) or wand (2/19) or mage/priest/warlock class = caster; dagger (2/15) = rogue; else melee
    cls, w = m[1], m[4].split(',')
    if cls in ('2',) and False: pass
    if cls in ('8', '5', '9') or '2/10' in w or '2/19' in w: return 'Caster'
    if '2/15' in w or cls == '4': return 'Rogue'
    return 'Melee'
AQUATIC = ('murloc', 'crab', 'turtle', 'fish', 'lurker', 'forager', 'streamrunner')
FLYING = ('bat', 'bird', 'owl', 'hawk', 'cockatrice', 'turkey', 'chicken')
def pet_type(r):
    m = meta.get(r['entry'], [0, '1', '7', '0', '']); nm = r['name'].lower()
    if any(k in nm for k in AQUATIC): return 'Aquatic', 'Melee'
    if m[2] == '8': return 'Critter', 'Melee'
    if m[2] == '1': return ('Flying' if any(k in nm for k in FLYING) else 'Beast'), 'Melee'
    rl = role(m); return ('Magic' if rl == 'Caster' else 'Humanoid'), rl
by_type = collections.defaultdict(list)
for s in spc:
    c = cr.get(s['CreatureID'])
    if c and sx.get(s['ID']) and s['SourceTypeEnum'] in ('4', '0'): by_type[PT[int(s['PetTypeEnum'])]].append((c['Name_lang'], s))   # fallback pools: ordinary wild/drop pets only (no promo, holiday, store, TCG pets)
for v in by_type.values(): v.sort(key=lambda t: int(t[1]['ID']))
groups = collections.defaultdict(list)
for r in rows:
    r['ptype'], r['role'] = pet_type(r); groups[r['name'].split()[-1].lower()].append(r)
cursor = collections.Counter()   # round robin position per retail pet type for creatures without a name match
print('\t'.join(['entry', 'name', 'role', 'how', 'retail_species', 'retail_name', 'pet_type', 'kit']))
for kind, g in sorted(groups.items()):
    for i, r in enumerate(sorted(g, key=lambda r: int(r['entry']))):
        cands = [t for t in by_kind.get(kind, []) if PT[int(t[1]['PetTypeEnum'])] == r['ptype']]   # same kind AND same retail pet type
        how = 'name'
        if not cands:
            cands, how = by_type[r['ptype']], 'type'
        j = (i if how == 'name' else cursor[r['ptype']]); cursor[r['ptype']] += (how == 'type')
        nm, s = cands[j % len(cands)]
        print('\t'.join([r['entry'], r['name'], r['role'], how, s['ID'], nm, PT[int(s['PetTypeEnum'])], kit(s)]))
