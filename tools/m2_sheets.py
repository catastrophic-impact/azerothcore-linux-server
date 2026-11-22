#!/usr/bin/env python3
"""Offline M2 (doodad) renderer + labelled CONTACT SHEETS for identifying garrison models by eye (no game, no server).
Extracts each .m2 + 00.skin + its BLP textures from the client MPQs (tools via claude_tools/mpqlib.py), rasterises with a numpy z-buffer (3/4 view, texture + simple light)
and tiles N models per sheet with a number label; writes a sheet index (number -> kind, name, model) next to each sheet.
Needs numpy + Pillow: run with cache/venv314/bin/python on the HOST (cache/venv is stale since the host python moved to 3.14).
usage: m2_sheets.py <client Data dir> <list.tsv> <out dir> [per-sheet=16] [cols=4] [cell px=256] [offset=0]
  list.tsv = one item per line: kind<TAB>name<TAB>model path (.m2); M2 and WMO models are rendered; anything else is listed in the index as NO-MODEL-TYPE."""
import os, struct, sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(proj, 'claude_tools'))
from mpqlib import Mpq
data, lst, out = sys.argv[1:4]; PER = int(sys.argv[4]) if len(sys.argv) > 4 else 16
COLS = int(sys.argv[5]) if len(sys.argv) > 5 else 4; CELL = int(sys.argv[6]) if len(sys.argv) > 6 else 256; OFFSET = int(sys.argv[7]) if len(sys.argv) > 7 else 0   # OFFSET = items before this slice (global numbering, sheet names)
os.makedirs(out, exist_ok=True)
m = Mpq(data, os.path.join(proj, 'cache', 'models'), host=[])

def skin_path(p): return p[:p.rfind('.')] + '00.skin'

TEX = {}
def texture(name):
    if not name: return None
    if name in TEX: return TEX[name]
    f = m.path(name); img = None
    if f:
        try: img = np.asarray(Image.open(f).convert('RGBA'))
        except Exception: img = None
    TEX[name] = img; return img

def load_m2(path):
    """-> list of (verts[3,3], uv[3,2], texname) or None"""
    mf, sf = m.path(path), m.path(skin_path(path))
    if not mf or not sf: return None
    b = open(mf, 'rb').read(); s = open(sf, 'rb').read()
    if b[:4] != b'MD20' or s[:4] != b'SKIN': return None
    nv, ov = struct.unpack_from('<II', b, 60)
    V = np.frombuffer(b, dtype='<f4', count=nv * 12, offset=ov).reshape(nv, 12)   # 48-byte vertex: pos3 weights(4B) bones(4B) normal3 uv2 uv2 = 12 floats
    pos =V[:, 0:3].copy(); uvs = V[:, 8:10].copy()   # float index: 0-2 pos, 3-4 (8 bytes of weights+bones), 5-7 normal, 8-9 uv
    nt, ot = struct.unpack_from('<II', b, 80)         # textures: 16-byte M2Texture {type, flags, nameLen, nameOfs}
    texnames = []
    for i in range(nt):
        ty, fl, ln, of = struct.unpack_from('<IIII', b, ot + i * 16)
        texnames.append((ty, b[of:of + ln].split(b'\0')[0].decode('latin1') if ty == 0 and ln else ''))
    nl, ol = struct.unpack_from('<II', b, 128); look = struct.unpack_from('<%dH' % nl, b, ol)   # texture lookup table
    ni, oi, ntri, ott, _np_, _op, nsub, osub, ntu, otu = struct.unpack_from('<10I', s, 4)
    ind = np.frombuffer(s, dtype='<u2', count=ni, offset=oi); tri = np.frombuffer(s, dtype='<u2', count=ntri, offset=ott)
    subs = [struct.unpack_from('<6H', s, osub + i * 48) for i in range(nsub)]   # skinSectionId, level, vertexStart, vertexCount, indexStart, indexCount
    out_t = []
    seen_sub = set()
    for i in range(ntu):
        u = struct.unpack_from('<BbHHHHHHHHHHH', s, otu + i * 24)   # flags, prio, shader, skinSection, geoset, color, material, layer, texCount, texCombo ...
        sec, tcombo = u[3], u[9]
        if sec >= nsub: continue
        sub = subs[sec]; seen_sub.add(sec)
        tn = ''
        if tcombo < len(look) and look[tcombo] < len(texnames): tn = texnames[look[tcombo]][1]
        idx = tri[sub[4]:sub[4] + sub[5]]
        for k in range(0, len(idx) - 2, 3):
            a, bb, c = (int(ind[j]) for j in idx[k:k + 3])
            if max(a, bb, c) >= nv: continue
            out_t.append((np.array([pos[a], pos[bb], pos[c]], 'f8'), np.array([uvs[a], uvs[bb], uvs[c]], 'f8'), tn))
    return out_t

def chunks(b, start=0, end=None):
    i, end = start, len(b) if end is None else end
    while i + 8 <= end:
        tag = b[i:i + 4][::-1].decode('latin1'); sz = struct.unpack_from('<I', b, i + 4)[0]
        yield tag, i + 8, sz
        i += 8 + sz

def load_wmo(path):
    """WMO root + group files -> list of (verts[3,3], uv[3,2], texname); very large buildings are thinned to ~25k triangles"""
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
    mt = [tex(t[3]) if t[3] < len(motx) else '' for t in mats]
    tris = []
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
                if mid == 0xFF: continue
                ix = movi[k]
                tris.append((movt[ix].astype('f8'), (motv[ix] if motv is not None and len(motv) > ix.max() else np.zeros((3, 2), 'f4')).astype('f8'), mt[mid] if mid < len(mt) else ''))
    if len(tris) > 25000: tris = tris[::-(-len(tris) // 25000)]
    return tris

def render(tris, size=384):
    P = np.array([t[0] for t in tris], dtype='f8')
    yaw, pitch = math.radians(38), math.radians(24)
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    rx = x * cy - y * sy; ry = x * sy + y * cy
    sxv = rx; syv = z * cp + ry * sp; dep = ry * cp - z * sp
    mnx, mxx, mny, mxy = sxv.min(), sxv.max(), syv.min(), syv.max()
    sc = (size * 0.9) / max(mxx - mnx, mxy - mny, 1e-3)
    X = (sxv - (mnx + mxx) / 2) * sc + size / 2; Y = size / 2 - (syv - (mny + mxy) / 2) * sc
    img = np.zeros((size, size, 3), 'f4'); img[:] = (0.10, 0.10, 0.12); zb = np.full((size, size), 1e18)
    light = np.array([0.4, -0.5, 0.75]); light /= np.linalg.norm(light)
    for k, (v, uv, tn) in enumerate(tris):
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
        tx = texture(tn)
        if tx is not None:
            u = (l0 * uv[0][0] + l1 * uv[1][0] + l2 * uv[2][0]) % 1.0; w = (l0 * uv[0][1] + l1 * uv[1][1] + l2 * uv[2][1]) % 1.0
            h, wd = tx.shape[:2]
            smp = tx[(w * h).astype(int) % h, (u * wd).astype(int) % wd]
            col = smp[..., :3].astype('f4') / 255.0; alpha = smp[..., 3] > 40
        n = np.cross(P[k][1] - P[k][0], P[k][2] - P[k][0]); nl = np.linalg.norm(n)
        f = 0.55 + 0.45 * abs(float(np.dot(n / nl, light))) if nl > 1e-9 else 1.0
        mask &= alpha
        sub = img[by0:by1 + 1, bx0:bx1 + 1]; sub[mask] = (col * f)[mask]; zsub[mask] = d[mask]
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype('u1'))

rows = [l.rstrip('\n').split('\t') for l in open(lst) if l.strip()]
need = []
for kind, name, model in rows:
    if model.lower().endswith(('.m2', '.mdx', '.mdl')):
        mp = model[:model.rfind('.')] + '.m2'; need += [mp, skin_path(mp)]
    elif model.lower().endswith('.wmo'): need.append(model)
m.fetch(need, verbose=False); m.reindex()
tex_need = set()
parsed = {}
for kind, name, model in rows:
    if not model.lower().endswith(('.m2', '.mdx', '.mdl', '.wmo')): continue
    mp = model[:model.rfind('.')] + '.m2'
    try: parsed[kind] = load_wmo(model) if model.lower().endswith('.wmo') else load_m2(mp)
    except Exception as e: print('PARSE FAIL', kind, e, flush=True); parsed[kind] = None
    for t in (parsed[kind] or []):
        if t[2]: tex_need.add(t[2])
m.fetch(sorted(tex_need), verbose=False); m.reindex()
try: FONT = ImageFont.truetype('DejaVuSans-Bold.ttf', 22)
except Exception: FONT = ImageFont.load_default()
S = CELL; cols = COLS; sheets = 0; index = []
for s0 in range(0, len(rows), PER):
    chunk = rows[s0:s0 + PER]; sheets += 1
    rws = (len(chunk) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * S, rws * S), (30, 30, 34)); dr = ImageDraw.Draw(sheet)
    for i, (kind, name, model) in enumerate(chunk):
        num = OFFSET + s0 + i + 1; t = parsed.get(kind)
        if t:
            try:
                im = render(t, 384).resize((S, S), Image.LANCZOS); sheet.paste(im, ((i % cols) * S, (i // cols) * S)); status = 'ok'
            except Exception as e: status = 'RENDER-FAIL'
        else: status = 'NO-MODEL-TYPE' if not model.lower().endswith(('.m2', '.mdx', '.mdl', '.wmo')) else 'NO-DATA'
        ox, oy = (i % cols) * S, (i // cols) * S
        dr.rectangle([ox, oy, ox + 56, oy + 30], fill=(0, 0, 0)); dr.text((ox + 4, oy + 2), str(num), fill=(255, 230, 80), font=FONT)
        dr.rectangle([ox, oy, ox + S - 1, oy + S - 1], outline=(70, 70, 80))
        if status != 'ok': dr.text((ox + 60, oy + S // 2), status, fill=(255, 90, 90), font=FONT)
        index.append((num, kind, name, model, status))
    sheet.save(os.path.join(out, 'sheet_%04d.png' % (OFFSET // PER + sheets)))
with open(os.path.join(out, 'index.tsv'), 'w') as fh:
    fh.write('num\tkind\tname\tmodel\tstatus\n'); [fh.write('\t'.join(map(str, r)) + '\n') for r in index]
print('sheets', sheets, 'items', len(index), 'not rendered', sum(1 for r in index if r[4] != 'ok'))
