#!/usr/bin/env python3
"""Second decor pass: harmless object types find_decor.py never scanned (map objects 14, mailboxes 19, guild banks 34,
doors 0, empty chests 3, inert goobers 10). Appends rows to decor-proposals/decor.tsv with include=Y, category Unsorted
(review in the admin tool, move the good ones, send the rest to Removed). Skips models/entries already in the sheet or config.
usage: find_decor_more.py [release_dir]   env: ACORE_PREFIX"""
import json, os, re, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')
def sql(q):
    return subprocess.run(os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q], capture_output=True, text=True, check=True).stdout
d = open(os.path.join(rel, 'data', 'dbc', 'GameObjectDisplayInfo.dbc'), 'rb').read()
_, n, nf, rs, ss = struct.unpack('<4sIIII', d[:20]); strs = d[20 + n * rs:]; model = {}
for i in range(n):
    r = struct.unpack_from('<%dI' % nf, d, 20 + i * rs)
    model[r[0]] = strs[r[1]:strs.index(b'\0', r[1])].decode().replace('.mdx', '.m2').replace('.MDX', '.m2').replace('.mdl', '.m2').replace('.MDL', '.m2')
sheet = os.path.join(proj, 'decor-proposals', 'decor.tsv')
lines = open(sheet).read().splitlines()
haveE, haveD, haveN = set(), set(), set()
for l in lines[1:]:
    c = l.split('\t')
    if len(c) > 5: haveE.add(c[4]); haveD.add(c[5]); haveN.add((c[3].lower(), c[9].lower()))
for i in json.load(open(os.path.join(proj, 'garrison-config.json')))['items']:
    if i['t'] == 'g': haveE.add(str(i['entry']))
BAD = re.compile(r'(\bDND\b|\[|\btest\b|\bPH\b|trap|portal|teleport|spawn|visual|invisible|bunny|dummy|do not|unused|quest|\bnode\b|vein|deposit|herb|fishing|loot|aqwar|highlight|image|resource|aura|target|replace|energy|beam|cleansing|impact|breakable|corrupt|summon|ritual|rift|vortex|effect|particles|fog|marker|sigil|backdrop|portrait|report from|zeppelin|elevator|lift|teleporter|instance|boss|key\b|lever|button|switch)', re.I)
BADPATH = re.compile(r'(skillactivated|tradeskillnodes|\\gm|worldtrigger|\\spells\\|\\pvp\\.*flag|dungeon.*(boss|event))', re.I)
cond = {14: '1', 19: '1', 34: '1',
        3: 'Data1=0 and Data6=0 and Data7=0 and Data8=0',
        0: 'Data1=0',
        10: 'Data1=0 and Data2=0 and Data10=0 and Data12=0 and Data19=0'}
cats = []
for ty, c in cond.items():
    rows = sql("select entry,name,displayId,type,size from acore_world.gameobject_template t where type=%d and name<>'' and displayId>0 and ScriptName='' and AIName='' and %s and not exists (select 1 from acore_world.smart_scripts s where s.source_type=1 and s.entryorguid=t.entry)" % (ty, c)).splitlines()
    cats.append(rows)
by = {}
for rows in cats:
    for l in rows:
        p = l.split('\t')
        if len(p) != 5: continue
        e, nm, dp, ty, sz = p; dp = int(dp)
        if dp not in model or not model[dp] or BAD.search(nm) or BADPATH.search(model[dp]) or re.match(r'(?i)gm', model[dp].split('\\')[-1]): continue
        if e in haveE or str(dp) in haveD: continue
        by.setdefault(dp, []).append((int(e), nm, int(ty), sz))
new, seen = [], set()
for dp, lst in sorted(by.items()):
    lst.sort(); e, nm, ty, sz = lst[0]
    clean = nm.replace('Doodad_', '').replace('_', ' ')
    mf = model[dp].split('\\')[-1]
    key = (clean.lower(), mf.lower())
    if key in seen or key in haveN: continue
    seen.add(key)
    new.append(('Y', 'Neutral', 'Unsorted', clean, e, dp, ty, sz, len(lst), mf, '; '.join(sorted({x[1] for x in lst[1:] if x[1] != nm})[:3]), model[dp], 'pass2'))
with open(sheet, 'a') as f:
    for r in new: f.write('\t'.join(map(str, r)) + '\n')
from collections import Counter
print(len(new), 'new rows appended', dict(Counter(r[6] for r in new)))
