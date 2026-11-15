#!/usr/bin/env python3 -I
"""Draft a <zone>_picks.tsv from the roster (include=Y, not yet a species) by cycling through pools of ORDINARY retail kits chosen by name keywords + creature type (pet-battle/pools.py).
Kits with unimplemented abilities or boss/elite stats are skipped (gaplib). A STARTING POINT ONLY: review, then apply_zone.py, run_tests and the balance sweep. Usage: python3 -I pet-battle/auto_picks.py <zone> [excludeEntry ...]"""
import sys, re, itertools, os
sys.path.insert(0, 'pet-battle'); import pools as P
zone = sys.argv[1]; excl = set(sys.argv[2:])
cyc = {}
src = open('scripts/pb_data.lua').read(); existing = set(re.findall(r'\[(\d+)\] = \{ name', src))
out = ['# %s: entry, retail species, icon, flags (auto_picks.py draft)' % zone]
for l in open('pet-battle/%s_roster.tsv' % zone, encoding='utf-8'):
    if l.startswith('#') or l.startswith('include'): continue
    p = l.rstrip('\n').split('\t')
    if p[0] != 'Y' or p[1] in existing or p[1] in excl: continue
    c = P.candidates(p[2], p[4])
    if not c: print('NO POOL for', p[1], p[2], p[4]); continue
    kits, icon, crit, pn = c
    cyc.setdefault(pn, itertools.cycle(kits))
    out.append('%s\t%d\t%s%s' % (p[1], next(cyc[pn]), icon, '\tcritter' if crit else ''))
if len(out) == 1 and os.path.exists('pet-battle/%s_picks.tsv' % zone): sys.exit('no new species for %s: picks file left untouched' % zone)
open('pet-battle/%s_picks.tsv' % zone, 'w').write('\n'.join(out) + '\n')
print(len(out) - 1, 'picks drafted')
