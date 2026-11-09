#!/usr/bin/env python3
"""Fold the in-game curation (Curator mode: garrison_curate.lua tables in the characters DB) into the repo files, so fresh installs get it:
  item category / name / price -> garrison-admin.json (categories, names, prices.items)
  category list + category prices -> garrison-admin.json (cats, prices.cats)
  preview views -> garrison-fit.json
Then run tools/gen_garrison_catalog.py (and deploy). The DB tables are left alone: after the export they simply equal the new base.
usage: ACORE_PREFIX="flatpak-spawn --host" python3 tools/export_curation.py [release_dir]"""
import json, os, shutil, subprocess, sys, time
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')
def sql(q):
    cmd = os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
def rows(q): return [l.split('\t') for l in sql(q).splitlines() if l.strip()]
af, ff = os.path.join(proj, 'garrison-admin.json'), os.path.join(proj, 'garrison-fit.json')
a = json.load(open(af)); fit = json.load(open(ff))
stamp = time.strftime('%Y%m%d-%H%M%S')
os.makedirs(os.path.join(proj, 'cache'), exist_ok=True)
shutil.copy(af, os.path.join(proj, 'cache', 'garrison-admin.before-export-%s.json' % stamp)); shutil.copy(ff, os.path.join(proj, 'cache', 'garrison-fit.before-export-%s.json' % stamp))
a.setdefault('categories', {}); a.setdefault('names', {}); a.setdefault('prices', {}); a['prices'].setdefault('items', {}); a['prices'].setdefault('cats', {})
n = [0, 0, 0, 0]
for kind, cat, name, price in rows("select kind,cat,name,price from acore_characters.dc_garrison_cur_item"):
    if cat: a['categories'][kind] = cat; n[0] += 1
    if name: a['names'][kind] = name; n[1] += 1
    if int(price) >= 0: a['prices']['items'][kind] = int(price); n[2] += 1
cats = rows("select name,price from acore_characters.dc_garrison_cur_cat order by seq")
if cats:
    a['cats'] = [c[0] for c in cats]
    a['prices']['cats'] = {c[0]: int(c[1]) for c in cats if int(c[1]) > 0}
for model, vs, vy, vz, vr in rows("select model,vs,vy,vz,vr from acore_characters.dc_garrison_cur_fit"):
    fit[model.lower()] = [round(float(vs), 3), round(float(vy), 3), round(float(vz), 3), round(float(vr), 3)]; n[3] += 1
json.dump(a, open(af, 'w'), indent=0, ensure_ascii=False); json.dump(fit, open(ff, 'w'), indent=0, ensure_ascii=False)
print('exported: %d categories, %d names, %d item prices, %d views%s' % (n[0], n[1], n[2], n[3], (', %d category list entries' % len(cats)) if cats else ''))
print('previous files saved in cache/*.before-export-%s.json. Next: python3 tools/gen_garrison_catalog.py' % stamp)
