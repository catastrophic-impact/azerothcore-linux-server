#!/usr/bin/env python3
"""Measure the length of every jukebox track (jukebox-proposals/tracks.tsv) by extracting the mp3s from a WoW 3.3.5 client's MPQs
(smpq inside the build box) and probing them with ffprobe (host). Writes jukebox-proposals/durations.tsv (path<TAB>seconds).
usage: jukebox_durations.py <client Data dir>     env: ACORE_PREFIX (e.g. 'flatpak-spawn --host'), BOX (default acore-box)"""
import csv, os, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = sys.argv[1]
host = os.environ.get('ACORE_PREFIX', '').split()
box = os.environ.get('BOX', 'acore-box')
out = os.path.join(proj, 'cache', 'music'); os.makedirs(out, exist_ok=True)
paths = [r['path'] for r in csv.DictReader(open(os.path.join(proj, 'jukebox-proposals', 'tracks.tsv')), delimiter='\t')]
import re
IDX = {}
def norm(p): return '\\'.join(x for x in re.split(r'[\\/]+', p) if x).lower()
def reindex():  # the cache can hold the same folder in several cases (Sound/ and sound/); index every file by its lowercase path
    IDX.clear()
    for root, _, files in os.walk(out):
        for f in files: IDX[norm(os.path.relpath(os.path.join(root, f), out))] = os.path.join(root, f)
reindex()
def local(p): return IDX.get(norm(p))
def have(p): return local(p) is not None
archives = ['enUS/patch-enUS-3', 'enUS/patch-enUS-2', 'enUS/patch-enUS', 'enUS/lichking-locale-enUS', 'enUS/expansion-locale-enUS', 'enUS/locale-enUS', 'enUS/base-enUS', 'enUS/backup-enUS', 'patch-3', 'patch-2', 'patch', 'Patch-X', 'Patch-S', 'Patch-H', 'Patch-G', 'Patch-F', 'lichking', 'expansion', 'common-2', 'common']
for a in archives:
    todo = [p for p in paths if not have(p)]
    if not todo: break
    f = os.path.join(data, a + '.MPQ')
    if not os.path.exists(f): continue
    for i in range(0, len(todo), 80):
        chunk = todo[i:i + 80]
        subprocess.run(host + ['distrobox', 'enter', box, '--', 'bash', '-c', 'cd "$0" && smpq -x -q "$1" "${@:2}" 2>/dev/null; true', out, f] + chunk,
                       capture_output=True)
    reindex(); print(a, 'remaining', sum(1 for p in paths if not have(p)), flush=True)
rows, missing = [], 0
for p in paths:
    f = local(p)
    if not f: missing += 1; continue
    r = subprocess.run(host + ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f], capture_output=True, text=True)
    try: rows.append((p, float(r.stdout.strip())))
    except ValueError: missing += 1
with open(os.path.join(proj, 'jukebox-proposals', 'durations.tsv'), 'w') as o:
    for p, s in rows: o.write('%s\t%.1f\n' % (p, s))
print(len(rows), 'measured,', missing, 'missing')
