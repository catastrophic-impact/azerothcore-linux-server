#!/usr/bin/env python3 -I
"""Measures every pet species' REAL visible size from the client's model meshes (not the loose bounding box): for each CreatureModelData model the .m2 vertices + .skin triangles are extracted
from the client MPQs, rasterized into three silhouettes (top, side, front) and the filled areas are averaged: S = sqrt(mean(area)) yards, times the CreatureDisplayInfo model scale. Scaling
every pet to the same S gives the same visible size for any shape (a spider's empty leg-box no longer counts like solid gorilla). Output: pet-battle/.s/model_size.tsv (model id, S, w, h).
Run INSIDE the build box (needs smpq):  distrobox enter acore-box -- python3 -I pet-battle/gen_model_size.py   (project root; cache in pet-battle/.s/m2)"""
import os, struct, subprocess, sys, math
D = "/home/deck/.var/app/com.usebottles.bottles/data/bottles/bottles/DadCraft/drive_c/ChromieCraft_3.3.5a/Data"
ARCH = ["common", "common-2", "expansion", "lichking", "patch", "patch-2", "patch-3", "Patch-F", "Patch-G", "Patch-H", "Patch-S", "Patch-X"]
OUT = "pet-battle/.s/m2"
# the CLIENT's patched DBC is the truth for what is drawn (hundreds of rows differ from the server's copy); extracted with smpq into .s/cdbc by hand (see DEVNOTES)
CDI = 'pet-battle/.s/cdbc/DBFilesclient/Creaturedisplayinfo.dbc'; CMD = 'pet-battle/.s/cdbc/DBFilesclient/Creaturemodeldata.dbc'
def rows(p):
    d = open(p, 'rb').read(); m, n, f, rs, ss = struct.unpack('<4sIIII', d[:20]); body = d[20:20 + n * rs]
    return [struct.unpack('<%dI' % f, body[i * rs:(i + 1) * rs]) for i in range(n)], d[20 + n * rs:]
fl = lambda x: struct.unpack('<f', struct.pack('<I', x))[0]
disp = {r[0]: r for r in rows(CDI)[0]}
mrows, mstr = rows(CMD); mod = {r[0]: r for r in mrows}
def mname(off): return mstr[off:mstr.index(b'\0', off)].decode()
ed = {}   # entry -> list of display ids (every model row of the species: a species can show several different models, e.g. 4 crab models)
for l in open('pet-battle/.s/entry_displays_all.tsv'):
    p = l.split()
    if len(p) == 3: ed.setdefault(int(p[0]), []).append(int(p[2]))
species = [int(l.split()[0]) for l in open('pet-battle/.s/scales.tsv') if l.strip()]
models = {}   # model id -> (path, display scale list)
for e in species:
    for d in ed.get(e, []):
        if d in disp and disp[d][1] in mod:
            mid = disp[d][1]; models.setdefault(mid, mname(mod[mid][2]).replace('.mdx', '.m2').replace('.MDX', '.m2'))
print("models to measure:", len(models)); sys.stdout.flush()
if not os.path.isdir(OUT + "/Creature") or "--extract" in sys.argv:
    os.makedirs(OUT, exist_ok=True)
    names = []
    for mid, path in models.items():
        names.append(path); names.append(path[:path.rfind('.')] + "00.skin")
    for a in ARCH:
        for i in range(0, len(names), 400):
            subprocess.run(["smpq", "-x", "-f", D + "/" + a + ".MPQ"] + names[i:i + 400], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("extracted from", a); sys.stdout.flush()
def find(path):   # case-insensitive across the case-variant folders the extractor creates; the newest file wins (later patch archives are extracted later)
    parts = path.replace('\\', '/').split('/'); cands = [OUT]
    for part in parts:
        nxt = []
        for cur in cands:
            if not os.path.isdir(cur): continue
            for x in os.listdir(cur):
                if x.lower() == part.lower(): nxt.append(cur + "/" + x)
        cands = nxt
    cands = [c for c in cands if os.path.isfile(c)]
    return max(cands, key=os.path.getmtime) if cands else None
N = 96
def silhouette(tris, ax, ay):   # tris: list of 3 (x,y,z) points; returns filled area in world units
    xs = [p[ax] for t in tris for p in t]; ys = [p[ay] for t in tris for p in t]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys); span = max(x1 - x0, y1 - y0)
    if span <= 1e-6: return 0.0
    cell = span / N; grid = set()
    for t in tris:
        a, b, c = [((p[ax] - x0) / cell, (p[ay] - y0) / cell) for p in t]
        minx, maxx = int(min(a[0], b[0], c[0])), int(max(a[0], b[0], c[0])); miny, maxy = int(min(a[1], b[1], c[1])), int(max(a[1], b[1], c[1]))
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        for gy in range(miny, maxy + 1):
            for gx in range(minx, maxx + 1):
                if (gx, gy) in grid: continue
                px, py = gx + 0.5, gy + 0.5
                l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / den; l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / den; l3 = 1 - l1 - l2
                if l1 >= -0.5 / max(1, (maxx - minx + 1)) and l2 >= -0.5 / max(1, (maxx - minx + 1)) and l3 >= -0.5 / max(1, (maxx - minx + 1)): grid.add((gx, gy))
                elif (maxx - minx) <= 1 and (maxy - miny) <= 1: grid.add((gx, gy))   # a sliver inside one cell still marks it
    return len(grid) * cell * cell
res = {}
for mid, path in models.items():
    mp = find(path); sp = find(path[:path.rfind('.')] + "00.skin")
    if not mp or not sp: res[mid] = None; continue
    try:
        m = open(mp, 'rb').read(); s = open(sp, 'rb').read()
        if m[:4] != b'MD20' or s[:4] != b'SKIN': res[mid] = None; continue
        nv, ov = struct.unpack('<II', m[60:68]); verts = [struct.unpack('<3f', m[ov + i * 48:ov + i * 48 + 12]) for i in range(nv)]
        ni, oi, nt, ot = struct.unpack('<IIII', s[4:20])
        look = struct.unpack('<%dH' % ni, s[oi:oi + ni * 2]); tri = struct.unpack('<%dH' % nt, s[ot:ot + nt * 2])
        tris = [(verts[look[tri[i]]], verts[look[tri[i + 1]]], verts[look[tri[i + 2]]]) for i in range(0, nt - 2, 3) if max(tri[i], tri[i + 1], tri[i + 2]) < ni and max(look[tri[i]], look[tri[i + 1]], look[tri[i + 2]]) < nv]
        if not tris: res[mid] = None; continue
        areas = [silhouette(tris, 0, 1), silhouette(tris, 0, 2), silhouette(tris, 1, 2)]
        res[mid] = (math.sqrt(sum(areas) / 3), areas)
    except Exception as ex:
        res[mid] = None
ok = sum(1 for v in res.values() if v)
print("measured", ok, "of", len(res)); sys.stdout.flush()
with open("pet-battle/.s/model_size.tsv", "w") as f:
    for mid in sorted(res):
        if res[mid]: f.write("%d\t%.5f\t%.5f\t%.5f\t%.5f\n" % (mid, res[mid][0], *res[mid][1]))
