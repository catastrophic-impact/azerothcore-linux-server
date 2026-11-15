#!/usr/bin/env python3 -I
"""Re-pick every shipped species whose retail kit is NOT usable (unimplemented effect/ability, see gaplib) with a usable kit from its pool (pools.py), via rekit.py.
Usage: python3 -I pet-battle/fix_gaps.py [--dry]"""
import sys, re, glob, subprocess
sys.path.insert(0, 'pet-battle'); import pools as P, gaplib
dry = '--dry' in sys.argv
src = open('scripts/pb_data.lua').read()
kits = {m.group(1): (m.group(2), m.group(3)) for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]*)", retail = (\d+)', src)}
typ = {}
for z in glob.glob('pet-battle/*_roster.tsv'):
    for l in open(z, encoding='utf-8'):
        c = l.rstrip('\n').split('\t')
        if len(c) > 5 and c[1].isdigit(): typ[c[1]] = c[4]
ch = []; i = 0
for e, (name, r) in kits.items():
    if r not in gaplib.gap_species() and len(gaplib.slots(r)) >= 3: continue   # only species whose kit has a REAL gap (boss-stat heuristics must not touch hand-approved kits)
    c = P.candidates(name, typ.get(e, ''))
    good = [k for k in (c[0] if c else []) if gaplib.usable(str(k)) and str(k) != r]
    if not good: print('NO usable alternative for', e, name, 'kit', r, gaplib.gap_species().get(r)); continue
    new = good[(int(e) + i) % len(good)]; i += 1
    ch.append('%s=%s' % (e, new)); print('%s %s: kit %s (%s) -> %s' % (e, name, r, gaplib.gap_species().get(r), new))
if ch and not dry: subprocess.run(['python3', '-I', 'pet-battle/rekit.py'] + ch, check=True)
print(len(ch), 'species re-picked' + (' (dry run)' if dry else ''))
