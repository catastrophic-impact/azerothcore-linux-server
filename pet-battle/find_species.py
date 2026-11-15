#!/usr/bin/env python3 -I
"""Retail species that have a given ability in their kit: python3 -I pet-battle/find_species.py <abilityId> ...  (to PIN them in pinned_species.txt or to pick kits)"""
import csv, sys, collections
d = 'pet-battle/retail_data/'
R = lambda n: list(csv.DictReader(open(d + n + '.csv', encoding='utf-8')))
cr = {c['ID']: c['Name_lang'] for c in R('Creature')}; spc = {s['ID']: s for s in R('BattlePetSpecies')}
sx = collections.defaultdict(set)
for x in R('BattlePetSpeciesXAbility'): sx[x['BattlePetAbilityID']].add(x['BattlePetSpeciesID'])
for a in sys.argv[1:]: print(a, ', '.join('%s=%s' % (s, cr.get(spc[s]['CreatureID'], '?')) for s in sorted(sx[a], key=int) if s in spc)[:400])
