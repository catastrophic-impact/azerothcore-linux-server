#!/usr/bin/env python3 -I
"""Re-pick every shipped species that uses a kit in pools.BANNED (kits the balance sweeps showed to be over/under-powered for every host)."""
import re, sys, glob, subprocess
sys.path.insert(0, 'pet-battle'); import pools as P
src = open('scripts/pb_data.lua').read(); typ = {}
for z in glob.glob('pet-battle/*_roster.tsv'):
    for l in open(z, encoding='utf-8'):
        c = l.rstrip('\n').split('\t')
        if len(c) > 5 and c[1].isdigit(): typ[c[1]] = c[4]
ch = []; i = 0
for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]*)", retail = (\d+)', src):
    e, n, r = m.groups()
    if int(r) in P.BANNED and 'critter = true' not in src.split(m.group(0))[1].split('\n')[0]:
        c = P.candidates(n, typ.get(e, '')); good = [k for k in (c[0] if c else []) if k not in P.BANNED and str(k) != r]
        if good: ch.append('%s=%s' % (e, good[(int(e) + i) % len(good)])); i += 1
        else: print('no alternative for', e, n, r)
print(len(ch), 'species re-picked')
if ch: subprocess.run(['python3', '-I', 'pet-battle/rekit.py'] + ch, check=True, capture_output=True)
