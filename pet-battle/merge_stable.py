#!/usr/bin/env python3 -I
"""Keep a previous kits file (builds the user already played) and take the NEW fit only for creatures whose old kit breaks a naming rule (a family-only spell on another family).
python3 -I pet-battle/merge_stable.py <old kits.tsv> <new kits.tsv> > merged.tsv"""
import sys, importlib.util
old_p, new_p = sys.argv[1:3]; sys.argv = ['x']
spec = importlib.util.spec_from_file_location('fb', 'pet-battle/fit_builds.py'); fb = importlib.util.module_from_spec(spec); spec.loader.exec_module(fb)
meta = {}
for fn in ('pet-battle/family_assign.tsv', 'pet-battle/shipped_assign.tsv'):
    for l in open(fn).read().split('\n')[1:]:
        f = l.split('\t')
        if len(f) > 5: meta[f[1]] = f
BL = {l.split('\t')[0] for l in open('pet-battle/ability_blocklist.txt') if l.strip() and not l.startswith('#') and 'status label audit' not in l}
def rd(p): return {l.split('\t')[1]: l for l in open(p).read().split('\n')[1:] if l.count('\t') >= 12}
old, new = rd(old_p), rd(new_p); head = open(new_p).readline().rstrip('\n'); taken = 0; out = [head]
def bad(row):
    f = row.split('\t'); own = fb.FAMS.get(int(meta[f[1]][4]))
    for c in f[7:13]:
        p = c.split('|'); n = p[3]
        if n in fb.PET_ONLY and n not in fb.OPEN_MOVES and ('pet:' + (own or '')) not in fb.PET_ONLY[n] and 'pet:Ghoul' not in fb.PET_ONLY[n]: return True
        if p[1] in BL: return True   # an ability the tests rejected since
    return False
for e, nr in new.items():
    o = old.get(e)
    if o is None or bad(o): out.append(nr); taken += 1
    else: out.append(o)
print('kept old %d, new fit for %d' % (len(new) - taken, taken), file=sys.stderr)
print('\n'.join(out))
