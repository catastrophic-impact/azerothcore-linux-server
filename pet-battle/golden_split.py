#!/usr/bin/env python3 -I
"""Splits golden_effects.tsv into the PLAYER list (used by at least one retail pet a player can obtain: BattlePetSpecies.SourceTypeEnum >= 0)
and the NPC-ONLY reference list (every pet using the effect has no source: bosses/NPC pets). instakill/choosedebuff/forcedexit are removed by decision (user 2026-11-19) and go to the reference list.
Run from repo root after golden_effects.py."""
import csv, collections
d = 'pet-battle/retail_data/'
spc = {r['ID']: r for r in csv.DictReader(open(d + 'BattlePetSpecies.csv', encoding='utf8'))}
use = collections.defaultdict(set)
for x in csv.DictReader(open(d + 'BattlePetSpeciesXAbility.csv')): use[x['BattlePetAbilityID']].add(x['BattlePetSpeciesID'])
REMOVED = ('instakill', 'choosedebuff', 'forcedexit')
rows = [l.split('\t') for l in open('pet-battle/golden_effects.tsv').read().split('\n') if l]
hdr, rows = rows[0], rows[1:]
P, N = [], []
for f in rows:
    sp = set().union(*(use[a] for a in f[5].split(',')))
    obtainable = any(s in spc and int(spc[s]['SourceTypeEnum']) >= 0 for s in sp)
    why = 'removed by decision' if f[0].startswith(REMOVED) else ('' if obtainable else 'npc-only')
    (P if obtainable and not f[0].startswith(REMOVED) else N).append(f[:6] + [why] + f[6:])
for name, data, h in (('golden_effects_player', P, hdr), ('golden_effects_npc_only', N, hdr[:6] + ['reason'] + hdr[6:])):
    with open('pet-battle/%s.tsv' % name, 'w') as fh:
        fh.write('\t'.join(h if name.endswith('only') else hdr) + '\n' if name.endswith('only') else '\t'.join(hdr) + '\n')
        for r in data: fh.write('\t'.join(r[:6] + r[7:]) + '\n' if not name.endswith('only') else '\t'.join(r) + '\n')
print('player list', len(P), '| npc-only reference', len(N))
