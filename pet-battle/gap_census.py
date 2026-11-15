#!/usr/bin/env python3 -I
"""GAP CENSUS: which retail effect types (props) does scripts/pb_core.lua NOT handle, how many ORDINARY retail species (non-boss/elite, with abilities) use each, and which abilities carry them.
Usage: python3 -I pet-battle/gen_gap... -> python3 -I pet-battle/gap_census.py [min_species]   (static: handled = numbers in 'prop == N', the DAMAGE/APPLY/INERT tables and C.PROPS_HANDLED_EXTRA)"""
import csv, re, sys, collections
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
core = open('scripts/pb_core.lua').read()
handled = set(re.findall(r'prop == (\d+)', core))
for m in re.finditer(r'^local (DAMAGE|APPLY|INERT) = \{([^}]*)\}', core, re.M): handled |= set(re.findall(r'\[(\d+)\]', m.group(2)))
handled |= set(re.findall(r'\[(\d+)\] = true', ' '.join(re.findall(r'^C\.PROPS_HANDLED_EXTRA.*$', core, re.M))))
eff = collections.defaultdict(list)   # ability -> [(prop, aura)]
turns = {t['ID']: t['BattlePetAbilityID'] for t in R('BattlePetAbilityTurn')}
for e in R('BattlePetAbilityEffect'):
    a = turns.get(e['BattlePetAbilityTurnID'])
    if a: eff[a].append((e['BattlePetEffectPropertiesID'], e['AuraBattlePetAbilityID']))
name = {a['ID']: a['Name_lang'] for a in R('BattlePetAbility')}
def closure(a, seen=None):
    seen = seen if seen is not None else set()
    if a in seen: return set()
    seen.add(a); out = set()
    for p, aura in eff.get(a, []):
        out.add((p, a))
        if aura and aura != '0': out |= closure(aura, seen)
    return out
sx = collections.defaultdict(list)
for x in R('BattlePetSpeciesXAbility'): sx[x['BattlePetSpeciesID']].append(x['BattlePetAbilityID'])
stn = {s['ID']: s['LuaName'] for s in R('BattlePetState')}
bad = set()
for x in R('BattlePetSpeciesState'):
    k = stn.get(x['BattlePetStateID'], ''); v = int(x['Value'])
    if 'Passive_Boss' in k or 'Passive_Elite' in k or k == 'Internal_InitialLevel' or (k == 'Stat_Power' and v >= 200) or (k == 'Stat_Stamina' and v >= 300) or (k == 'Stat_Speed' and v >= 300): bad.add(x['BattlePetSpeciesID'])
elig = [s['ID'] for s in R('BattlePetSpecies') if s['ID'] in sx and s['ID'] not in bad and int(s['PetTypeEnum']) <= 9]
use = collections.defaultdict(set); ab_of = collections.defaultdict(set)
for sid in elig:
    for a in sx[sid]:
        for p, src in closure(a):
            if p not in handled: use[p].add(sid); ab_of[p].add(src)
mn = int(sys.argv[1]) if len(sys.argv) > 1 else 1
print('eligible species: %d; unhandled effect types: %d (handled set: %d)' % (len(elig), len(use), len(handled)))
blocked = set().union(*use.values()) if use else set()
print('species with at least one unhandled effect: %d (%.0f%%)' % (len(blocked), 100.0 * len(blocked) / max(1, len(elig))))
for p, sp in sorted(use.items(), key=lambda kv: -len(kv[1])):
    if len(sp) >= mn: print('prop %-4s species %-4d abilities: %s' % (p, len(sp), ', '.join(sorted({'%s(%s)' % (name.get(a, '?'), a) for a in ab_of[p]}))[:260]))
