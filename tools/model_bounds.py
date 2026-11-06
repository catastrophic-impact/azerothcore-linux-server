#!/usr/bin/env python3
"""Measure the bounding box of every garrison object model (from addons/wotlk_garrison/Catalog.lua) by extracting the .m2 files from the
client's MPQs (smpq in the build box) and reading their vertices. Writes cache/model-bounds.tsv (path<TAB>minz<TAB>maxz<TAB>radius).
gen_garrison_catalog.py then ships centre/size to the addon so the preview can be centred and fitted.
usage: model_bounds.py <client Data dir>     env: ACORE_PREFIX (e.g. 'flatpak-spawn --host'), BOX (default acore-box)"""
import os, re, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = sys.argv[1]
host = os.environ.get('ACORE_PREFIX', '').split()
box = os.environ.get('BOX', 'acore-box')
out = os.path.join(proj, 'cache', 'models'); os.makedirs(out, exist_ok=True)
cat = open(os.path.join(proj, 'addons', 'wotlk_garrison', 'Catalog.lua')).read()
paths = sorted({m.replace('\\\\', '\\') for m in re.findall(r'model = "([^"]+)"', cat) if m})
_sheet = os.path.join(proj, 'decor-proposals', 'decor.tsv')   # decor chosen (Y) or on the review shelf (R) have no catalog entry yet
if os.path.exists(_sheet):
    for _l in open(_sheet).read().splitlines()[1:]:
        _c = _l.split('\t')
        if len(_c) > 11 and _c[0] in ('Y', 'R') and _c[11].strip(): paths = sorted(set(paths) | {_c[11].strip()})

def mdx(p): return re.sub(r'(?i)\.m2$', '.mdx', p)
def mdl(p): return re.sub(r'(?i)\.m2$', '.mdl', p)
def index():
    ix = {}
    for root, _, files in os.walk(out):
        for f in files:
            ix[os.path.relpath(os.path.join(root, f), out).replace('/', '\\').lower()] = os.path.join(root, f)
    return ix
IX = index()
def find(p): return IX.get(p.lower()) or IX.get(mdx(p).lower()) or IX.get(mdl(p).lower())
archives = ['enUS/patch-enUS-3', 'enUS/patch-enUS-2', 'enUS/patch-enUS', 'enUS/lichking-locale-enUS', 'enUS/expansion-locale-enUS', 'enUS/locale-enUS', 'enUS/base-enUS', 'patch-3', 'patch-2', 'patch', 'Patch-X', 'Patch-S', 'Patch-H', 'Patch-G', 'Patch-F', 'lichking', 'expansion', 'common-2', 'common']
for a in archives:
    todo = [p for p in paths if not find(p)]
    if not todo: break
    f = os.path.join(data, a + '.MPQ')
    if not os.path.exists(f): continue
    for i in range(0, len(todo), 60):
        subprocess.run(host + ['distrobox', 'enter', box, '--', 'bash', '-c', 'cd "$0" && smpq -x -q "$1" "${@:2}" 2>/dev/null; true', out, f] + [y for x in todo[i:i + 60] for y in (x, mdx(x), mdl(x))], capture_output=True)
    IX.clear(); IX.update(index())
    print(a, 'remaining', sum(1 for p in paths if not find(p)), flush=True)
rows, bad = [], []
for p in paths:
    f = find(p)
    if not f: bad.append(p); continue
    b = open(f, 'rb').read()
    try:
        assert b[:4] == b'MD20'
        n, o = struct.unpack_from('<II', b, 0x3C)
        assert 0 < n < 200000 and o + n * 48 <= len(b)
        v = [struct.unpack_from('<3f', b, o + i * 48) for i in range(n)]
        xs, ys, zs = [a[0] for a in v], [a[1] for a in v], [a[2] for a in v]
        rad = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        rows.append((p, min(zs), max(zs), rad, (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2))
    except Exception:
        bad.append(p)
with open(os.path.join(proj, 'cache', 'model-bounds.tsv'), 'w') as w:
    for r in rows: w.write('%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\n' % r)
print(len(rows), 'measured,', len(bad), 'missing/unreadable', bad[:5])
