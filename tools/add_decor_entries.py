#!/usr/bin/env python3
"""Adds gameobject_template entries to the garrison decor sheet (decor-proposals/decor.tsv) as category Unsorted (hidden from players until sorted in the admin tool).
Input file: tab separated "entry<TAB>name" per line (name optional). Entries already on the sheet, non-static types and missing templates are skipped. Safe to re-run.
usage: add_decor_entries.py FILE [note]     env: ACORE_PREFIX (e.g. 'flatpak-spawn --host')"""
import os, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); rel = os.path.join(proj, 'release')
rows = [l.rstrip('\n').split('\t') for l in open(sys.argv[1]) if l.strip()]
note = sys.argv[2] if len(sys.argv) > 2 else 'added by add_decor_entries'
def sql(q): return subprocess.run(os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q], capture_output=True, text=True, check=True).stdout
d = open(os.path.join(rel, 'data', 'dbc', 'GameObjectDisplayInfo.dbc'), 'rb').read()
_, n, nf, rs, ss = struct.unpack('<4sIIII', d[:20]); sb = 20 + n * rs; model = {}
for i in range(n):
    r = d[20 + i * rs:20 + (i + 1) * rs]; did, off = struct.unpack('<II', r[:8]); model[did] = d[sb + off:d.index(b'\0', sb + off)].decode('latin1')
tm = {}
for l in sql("select entry,type,displayId,name from acore_world.gameobject_template where entry in (%s)" % ','.join(r[0] for r in rows)).splitlines():
    c = l.split('\t'); tm[int(c[0])] = (int(c[1]), int(c[2]), c[3] if len(c) > 3 else '')
sheet = os.path.join(proj, 'decor-proposals', 'decor.tsv'); have = {l.split('\t')[4] for l in open(sheet).read().splitlines()[1:] if len(l.split('\t')) > 4}
add, skip = [], 0
for r in rows:
    e = int(r[0])
    if str(e) in have or e not in tm or tm[e][0] != 5 or tm[e][1] not in model: skip += 1; continue
    t, did, nm = tm[e]
    add.append('\t'.join(['Y', 'Neutral', 'Unsorted', (r[1] if len(r) > 1 and r[1] else nm) or ('Prop %d' % e), str(e), str(did), str(t), '1', '1', os.path.basename(model[did].replace('\\', '/')), '', model[did], note]))
open(sheet, 'a').write('\n'.join(add) + ('\n' if add else ''))
print('%d added to decor.tsv as Unsorted, %d skipped (already there / not a static object)' % (len(add), skip))
