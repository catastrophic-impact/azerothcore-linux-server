#!/usr/bin/env python3
"""Offline WMO preview renderer (experiment): extracts a WMO root + group files + their BLP textures from the client MPQs, rasterises the geometry with a
tiny numpy z-buffer (orthographic 3/4 view, texture + simple light) and writes PNGs to cache/wmo_previews/. Needs Pillow + numpy: run with cache/venv/bin/python on the HOST.
usage: wmo_render.py <client Data dir> <wmo path> [<wmo path> ...]"""
import os, re, struct, sys, math
import numpy as np
from PIL import Image
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(proj, 'claude_tools'))
from mpqlib import Mpq
data = sys.argv[1]; paths = sys.argv[2:]
if paths and paths[0].startswith('@'): paths = [l.strip() for l in open(paths[0][1:]).read().splitlines() if l.strip()]   # @file = one path per line, or 'kind<TAB>path' (output is then <kind>.png)
m = Mpq(data, os.path.join(proj, 'cache', 'wmo_models'), host=[])
out = os.path.join(proj, 'cache', 'wmo_previews'); os.makedirs(out, exist_ok=True)

def chunks(b, start=0, end=None):
    i, end = start, len(b) if end is None else end
    while i + 8 <= end:
        tag = b[i:i + 4][::-1].decode('latin1'); sz = struct.unpack_from('<I', b, i + 4)[0]
        yield tag, i + 8, sz
        i += 8 + sz

def load_wmo(path):
    m.fetch([path], verbose=False); m.reindex()
    f = m.path(path)
    if not f: return None
    root = open(f, 'rb').read(); ng = 0; motx = b''; mats = []
    for tag, o, sz in chunks(root):
        if tag == 'MOHD': ng = struct.unpack_from('<I', root, o + 4)[0]
        elif tag == 'MOTX': motx = root[o:o + sz]
        elif tag == 'MOMT': mats = [struct.unpack_from('<IIII', root, o + k * 64) for k in range(sz // 64)]
    base = path[:-4]; groups = ['%s_%03d.wmo' % (base, k) for k in range(ng)]
    m.fetch(groups, verbose=False); m.reindex()
    def tex(off):
        e = motx.index(b'\0', off); return motx[off:e].decode('latin1')
    matinfo = [(tex(t[3]) if t[3] < len(motx) else '', t[1], t[2]) for t in mats]
    tris = []   # (verts[3,3], uvs[3,2], matid)
    for g in groups:
        gf = m.path(g)
        if not gf: continue
        b = open(gf, 'rb').read()
        for tag, o, sz in chunks(b):
            if tag != 'MOGP': continue
            movt = movi = mopy = motv = None
            for t2, o2, s2 in chunks(b, o + 68, o + sz):
                if t2 == 'MOVT': movt = np.frombuffer(b, '<f4', s2 // 4, o2).reshape(-1, 3)
                elif t2 == 'MOVI': movi = np.frombuffer(b, '<u2', s2 // 2, o2).reshape(-1, 3)
                elif t2 == 'MOPY': mopy = np.frombuffer(b, '<u1', s2, o2).reshape(-1, 2)
                elif t2 == 'MOTV' and motv is None: motv = np.frombuffer(b, '<f4', s2 // 4, o2).reshape(-1, 2)
            if movt is None or movi is None: continue
            for k in range(len(movi)):
                mid = int(mopy[k][1]) if mopy is not None and k < len(mopy) else 0
                fl = int(mopy[k][0]) if mopy is not None and k < len(mopy) else 0
                if mid == 0xFF: continue
                ix = movi[k]
                tris.append((movt[ix], motv[ix] if motv is not None and len(motv) > ix.max() else np.zeros((3, 2), 'f4'), mid))
    return tris, matinfo

TEX = {}
def texture(name):
    if not name: return None
    if name in TEX: return TEX[name]
    m.fetch([name], verbose=False); m.reindex()
    f = m.path(name); img = None
    if f:
        try: img = np.asarray(Image.open(f).convert('RGBA'))
        except Exception: img = None
    TEX[name] = img; return img

def render(path, size=480):
    r = load_wmo(path)
    if not r or not r[0]: return None
    tris, matinfo = r
    P = np.array([t[0] for t in tris], dtype='f8')   # (n,3,3) wow model coords: x,y horizontal, z up
    yaw, pitch = math.radians(38), math.radians(24)
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    rx = x * cy - y * sy; ry = x * sy + y * cy            # spin around the vertical axis
    sxv = rx; syv = z * cp + ry * sp; dep = ry * cp - z * sp  # camera above looking down: screen x, screen up, depth (bigger = farther)
    mnx, mxx, mny, mxy = sxv.min(), sxv.max(), syv.min(), syv.max()
    sc = (size * 0.9) / max(mxx - mnx, mxy - mny, 1e-3)
    X = (sxv - (mnx + mxx) / 2) * sc + size / 2; Y = size / 2 - (syv - (mny + mxy) / 2) * sc
    img = np.zeros((size, size, 3), 'f4'); img[:] = (0.10, 0.10, 0.12); zb = np.full((size, size), 1e18)   # dark neutral ground, like the preview panel
    light = np.array([0.4, -0.5, 0.75]); light /= np.linalg.norm(light)
    for k, (v, uv, mid) in enumerate(tris):
        x0, x1, x2 = X[k]; y0, y1, y2 = Y[k]
        bx0, bx1 = int(max(0, math.floor(min(x0, x1, x2)))), int(min(size - 1, math.ceil(max(x0, x1, x2))))
        by0, by1 = int(max(0, math.floor(min(y0, y1, y2)))), int(min(size - 1, math.ceil(max(y0, y1, y2))))
        if bx1 < bx0 or by1 < by0: continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9: continue
        gx, gy = np.meshgrid(np.arange(bx0, bx1 + 1) + 0.5, np.arange(by0, by1 + 1) + 0.5)
        l0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
        l1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
        l2 = 1 - l0 - l1
        mask = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not mask.any(): continue
        d = l0 * dep[k][0] + l1 * dep[k][1] + l2 * dep[k][2]
        zsub = zb[by0:by1 + 1, bx0:bx1 + 1]
        mask &= d < zsub
        if not mask.any(): continue
        col = np.full(mask.shape + (3,), 0.6, 'f4'); alpha = np.ones(mask.shape, bool)
        tn = matinfo[mid][0] if mid < len(matinfo) else ''
        tx = texture(tn)
        if tx is not None:
            u = (l0 * uv[0][0] + l1 * uv[1][0] + l2 * uv[2][0]) % 1.0; w = (l0 * uv[0][1] + l1 * uv[1][1] + l2 * uv[2][1]) % 1.0
            h, wd = tx.shape[:2]
            s = tx[(w * h).astype(int) % h, (u * wd).astype(int) % wd]
            col = s[..., :3].astype('f4') / 255.0; alpha = s[..., 3] > 40
        n = np.cross(P[k][1] - P[k][0], P[k][2] - P[k][0]); nl = np.linalg.norm(n)
        f = 0.55 + 0.45 * abs(float(np.dot(n / nl, light))) if nl > 1e-9 else 1.0
        mask &= alpha
        sub = img[by0:by1 + 1, bx0:bx1 + 1]; sub[mask] = (col * f)[mask]; zsub[mask] = d[mask]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype('u1'))

done = []
for p in paths:
    kind, _, wp = p.partition('\t')
    if not wp: kind, wp = re.sub(r'[^A-Za-z0-9]+', '_', os.path.basename(p)[:-4]), p
    try: im = render(wp, 384)
    except Exception as e: print('FAILED', kind, wp, e, flush=True); continue
    if im is None: print('FAILED', kind, wp, flush=True); continue
    im = im.resize((256, 256), Image.LANCZOS)   # drawn at 384, shown at 256: smooth edges
    im.save(os.path.join(out, kind + '.png')); done.append((kind, im)); print('ok', kind, flush=True)
if done:
    cols = min(5, len(done)); rows = (len(done) + cols - 1) // cols; S = 256
    sheet = Image.new('RGB', (cols * S, rows * S), (255, 255, 255))
    for i, (n, im) in enumerate(done): sheet.paste(im, ((i % cols) * S, (i // cols) * S))
    sheet.save(os.path.join(out, 'sheet_%d.png' % os.getpid())); print('sheet.png')
