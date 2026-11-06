#!/usr/bin/env python3
"""Rebuild release confs from stock .dist files, then apply config-overrides/ (idempotent).
usage: apply_overrides.py <project_dir> <release_dir>"""
import re, shutil, sys, os, glob
proj, rel = sys.argv[1], sys.argv[2]
def apply(dist, out, ov):
    shutil.copyfile(dist, out)
    lines = open(out, errors='replace').read().split('\n')
    for l in open(ov):
        m = re.match(r'^([A-Za-z0-9_.]+)\s*=\s*(.*)$', l.strip())
        if not m or l.startswith('#'): continue
        k, v = m.groups(); done = False
        for i, x in enumerate(lines):
            if not x.lstrip().startswith('#') and re.match(r'^\s*' + re.escape(k) + r'\s*=', x):
                lines[i] = f'{k} = {v}'; done = True; break
        if not done: lines.append(f'{k} = {v}')
    open(out, 'w').write('\n'.join(lines))
for name in ('worldserver', 'authserver'):
    apply(f'{rel}/etc/{name}.conf.dist', f'{rel}/etc/{name}.conf', f'{proj}/config-overrides/{name}.conf')
for dist in glob.glob(f'{rel}/etc/modules/*.conf.dist'):
    out = dist[:-5]; ov = f'{proj}/config-overrides/modules/{os.path.basename(out)}'
    if os.path.exists(ov): apply(dist, out, ov)
    else: shutil.copyfile(dist, out)
print('overrides applied')
