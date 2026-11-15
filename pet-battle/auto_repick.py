#!/usr/bin/env python3 -I
"""ONE-ROUND outlier re-picker. Reads a sim_balance output file, finds non-critter species past the line (win >= HI or <= LO), swaps each to the next usable kit of its pool (pet-battle/pools.py) and applies it with rekit.py.
Usage: python3 -I pet-battle/auto_repick.py <sweep.txt> [HI=82] [LO=5] [--dry]    (HI/LO = the PM rule: act only more than 4 points past the 78% / 8% lines; critters are exempt)"""
import sys, re, glob, subprocess
sys.path.insert(0, 'pet-battle'); import pools as P, gaplib
args = [a for a in sys.argv[1:] if not a.startswith('--')]; dry = '--dry' in sys.argv
f = args[0]; HI = int(args[1]) if len(args) > 1 else 82; LO = int(args[2]) if len(args) > 2 else 5
src = open('scripts/pb_data.lua').read()
kit = dict(re.findall(r'\[(\d+)\] = \{ name = "[^"]*", retail = (\d+)', src))
crit = set(re.findall(r'\[(\d+)\] = \{[^}]*critter = true', src))
typ = {}
for z in glob.glob('pet-battle/*_roster.tsv'):
    for l in open(z, encoding='utf-8'):
        c = l.rstrip('\n').split('\t')
        if len(c) > 5 and c[1].isdigit(): typ[c[1]] = c[4]
changes = []
for l in open(f):
    m = re.match(r'\s+(.*?)\s+\(\s*(\d+)\) win rate\s+(\d+)%', l)
    if not m: continue
    name, e, w = m.group(1), m.group(2), int(m.group(3))
    if e in crit or e not in kit or not (w >= HI or w <= LO): continue
    c = P.candidates(name, typ.get(e, ''))
    if not c: print('no pool for', e, name); continue
    kits = [k for k in c[0] if str(k) != kit[e]]
    if not kits: print('no alternative kit for', e, name); continue
    # a too-strong species gets a kit from the pool; spread the choice by entry id so different species do not all take the same kit
    new = kits[int(e) % len(kits)]
    changes.append('%s=%s' % (e, new)); print('%s %s %d%%: kit %s -> %s' % (e, name, w, kit[e], new))
if changes and not dry: subprocess.run(['python3', '-I', 'pet-battle/rekit.py'] + changes, check=True)
print(len(changes), 'species re-picked' + (' (dry run)' if dry else ''))
