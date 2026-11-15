#!/usr/bin/env python3 -I
"""Dump retail abilities (text + turns + effects with param labels): python3 -I pet-battle/dump_ability.py <abilityId> ..."""
import csv, sys, collections
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
ab = {a['ID']: a for a in R('BattlePetAbility')}
turns = collections.defaultdict(list)
for t in R('BattlePetAbilityTurn'): turns[t['BattlePetAbilityID']].append(t)
effs = collections.defaultdict(list)
for e in R('BattlePetAbilityEffect'): effs[e['BattlePetAbilityTurnID']].append(e)
props = {p['ID']: p for p in R('BattlePetEffectProperties')}
for a in sys.argv[1:]:
    x = ab.get(a)
    if not x: print(a, 'unknown'); continue
    print('== %s %s cd=%s type=%s :: %s' % (a, x['Name_lang'], x['Cooldown'], x['PetTypeEnum'], x['Description_lang'][:300]))
    for t in sorted(turns[a], key=lambda t: int(t['OrderIndex'])):
        print('  turn order=%s type=%s event=%s' % (t['OrderIndex'], t['TurnTypeEnum'], t['EventTypeEnum']))
        for e in sorted(effs[t['ID']], key=lambda e: int(e['OrderIndex'])):
            p = props.get(e['BattlePetEffectPropertiesID'], {})
            labels = [p.get('ParamLabel_%d' % i, '') for i in range(6)]
            print('    prop %s aura=%s  %s' % (e['BattlePetEffectPropertiesID'], e['AuraBattlePetAbilityID'], ', '.join('%s=%s' % (l or '_', e['Param_%d' % i]) for i, l in enumerate(labels))))
