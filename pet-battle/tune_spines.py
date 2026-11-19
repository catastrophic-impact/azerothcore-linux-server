#!/usr/bin/env python3 -I
"""Rate every kit SPINE (theme|family: the three shared slots) from the skilled sweep and re-roll the outliers.
Usage (repo root): python3 -I pet-battle/tune_spines.py [band=6] [min_species=12]
Reads pet-battle/kits_prototype.tsv (entry, theme, family) + pet-battle/.s/ratings_new.tsv (sim_skill_kits.lua), writes pet-battle/spine_salts.tsv (salt per spine; assemble_kits.py reads it).
A spine whose species average more than `band` points from 50% skilled win rate (with >= min_species rated species) gets salt+1 = a different random draw of its 3 shared slots."""
import sys, collections, os
band = float(sys.argv[1]) if len(sys.argv) > 1 else 6; minn = int(sys.argv[2]) if len(sys.argv) > 2 else 12
kit = {}
for l in list(open('pet-battle/kits_prototype.tsv'))[1:]:
    x = l.rstrip('\n').split('\t'); kit[x[1]] = '%s|%s' % (x[4], x[3])
rate = {}
for l in list(open('pet-battle/.s/ratings_new.tsv'))[1:]:
    x = l.rstrip('\n').split('\t'); rate[x[0]] = float(x[3])
sp = collections.defaultdict(list)
for e, r in rate.items():
    if e in kit: sp[kit[e]].append(r)
salt = {}
if os.path.exists('pet-battle/spine_salts.tsv'):
    for l in open('pet-battle/spine_salts.tsv'): k, v = l.rstrip('\n').split('\t'); salt[k] = int(v)
rows = sorted(((sum(v) / len(v) * 100, len(v), k) for k, v in sp.items() if len(v) >= minn), reverse=True)
bad = [(m, n, k) for m, n, k in rows if abs(m - 50) > band]
print('spines rated (>=%d species): %d | outside +-%g pts of 50%%: %d' % (minn, len(rows), band, len(bad)))
for m, n, k in bad: print('  %5.1f%%  n=%-4d %s (salt %d)' % (m, n, k, salt.get(k, 0)))
for m, n, k in bad: salt[k] = salt.get(k, 0) + 1
open('pet-battle/spine_salts.tsv', 'w').write(''.join('%s\t%d\n' % kv for kv in sorted(salt.items())))
print('salts written for', len(bad), 'spines')
