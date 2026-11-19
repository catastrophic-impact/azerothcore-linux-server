#!/usr/bin/env python3 -I
"""Collapse pet-battle/mechanic_templates.tsv into canonical BASELINE templates: same role, cooldown, turns, auras and effect shape, with points in the same ~15% band and accuracy in the same 10% band
(20/21/22 point hits merge; 15 and 40 stay separate tiers). Baseline numbers = the group's median.
Usage (repo root): python3 -I pet-battle/mechanic_baseline.py > pet-battle/mechanic_baseline.tsv"""
import math, statistics, collections
rows = [l.rstrip('\n').split('\t') for l in open('pet-battle/mechanic_templates.tsv')][1:]
def num(s): return [int(x) for x in s.split('/')] if s != '-' else []
def band(p): return 0 if p <= 0 else round(math.log(p) / math.log(1.15))
g = collections.OrderedDict()
for r in rows:
    tid, role, mem, sh, cd, turns, pts, acc, heal, auras, fams, names, mids = r
    k = (role, cd, turns, auras, tuple(band(p) for p in num(pts)), tuple(a // 10 for a in num(acc)), tuple(band(h) for h in num(heal)))
    g.setdefault(k, []).append(r)
print('baseline\trole\tmembers\tshipped\tmech_templates\tcooldown\tturns\tdmg_points\tdmg_acc\theal_points\tauras\tfamilies\texample_names\tmember_ids')
out = []
for k, v in g.items():
    role, cd, turns, auras = k[:4]
    med = lambda col: '/'.join(str(int(statistics.median(num(x[col])[i] for x in v))) for i in range(len(num(v[0][col])))) or '-'
    fam = collections.Counter()
    for x in v:
        for kv in x[10].split(','):
            n, c = kv.rsplit(':', 1); fam[n] += int(c)
    names = []
    ids = []
    for x in v: names += x[11].split('; '); ids += x[12].split(',')
    out.append((sum(int(x[2]) for x in v), role, sum(int(x[3]) for x in v), len(v), cd, turns, med(6), med(7), med(8), auras, ','.join('%s:%d' % kv for kv in fam.most_common(5)), '; '.join(names[:8]), ','.join(ids)))
for i, o in enumerate(sorted(out, key=lambda o: -o[0]), 1):
    print('B%03d\t%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' % ((i, o[1], o[0]) + o[2:]))
