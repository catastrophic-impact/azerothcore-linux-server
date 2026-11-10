#!/usr/bin/env python3
"""Generate the garrison catalog (server Lua + addon Lua) from garrison-config.json.
Names come from the world DB; object preview models come from GameObjectDisplayInfo.dbc (<release>/data/dbc).
usage: gen_garrison_catalog.py [release_dir]      env: ACORE_PREFIX (e.g. 'flatpak-spawn --host')"""
import json, os, re, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')
cfg = json.load(open(os.path.join(proj, 'garrison-config.json')))
# decor chosen on the review sheet (tools/find_decor.py -> decor-proposals/decor.tsv, include = Y): many-instance objects, kind d<entry> (never rename)
_sheet = os.path.join(proj, 'decor-proposals', 'decor.tsv')
if os.path.exists(_sheet):
    have = {i['entry'] for i in cfg['items'] if i['t'] == 'g'}
    for _l in open(_sheet).read().splitlines()[1:]:
        _c = _l.split('\t')
        if len(_c) < 6 or _c[0].strip().upper() not in ('Y', 'R') or int(_c[4]) in have: continue
        _cat = 'Removed' if _c[0].strip().upper() == 'R' else (_c[2].strip() or 'Decor')   # R = on the review shelf: category Removed, hidden from players
        _nm = _c[3].strip()
        if len(_c) > 11 and _c[6].strip() == '14' and _c[11].strip():   # stock type-14 names do not match their models ("Goldmine" = a pair of folded pants): name them after the model file
            _b = re.sub(r'\.(m2|mdx|mdl|wmo)$', '', _c[11].replace('\\', '/').split('/')[-1], flags=re.I).replace('_', ' ')
            _nm = re.sub(r'\s+', ' ', re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', _b)).strip().title()
        cfg['items'].append(dict(kind='d%s' % _c[4], tab='objects', category=_cat, t='g', entry=int(_c[4]), name=_nm, multi=True, theme=_c[1].strip(), fx=((len(_c) > 12 and _c[12] == 'pass4') or (len(_c) > 11 and _c[11].lower().endswith('.wmo')))))
        if _cat not in cfg['tabs']['objects']: cfg['tabs']['objects'].append(_cat)

# admin decisions from the in-game admin tool (claude_tools/admin_import.py): garrison-admin.json {removed:[kind], categories:{kind:cat}, cats:[ordered object categories]}
_af = os.path.join(proj, 'garrison-admin.json')
_prices = {}   # {'cats': {category: amount}, 'items': {kind: amount}} - price per placement, in the currency set by acore_settings.garrison.currency
if os.path.exists(_af):
    _a = json.load(open(_af)); _prices = _a.get('prices', {})
    _rm = set(_a.get('removed', []))
    cfg['items'] = [i for i in cfg['items'] if i['kind'] not in _rm]
    for i in cfg['items']:
        if i['kind'] in _a.get('categories', {}): i['category'] = _a['categories'][i['kind']]
        if i['kind'] in _a.get('names', {}): i['name'] = _a['names'][i['kind']]
    if _a.get('cats'): cfg['tabs']['objects'] = list(_a['cats'])
    for i in cfg['items']:
        if i['tab'] == 'objects' and i['category'] not in cfg['tabs']['objects']: cfg['tabs']['objects'].append(i['category'])
    print('admin overrides: %d removed, %d recategorised, %d renamed' % (len(_rm), len(_a.get('categories', {})), len(_a.get('names', {}))))

for i in cfg['items']:   # price = per-item override, else the category default, else free.  ip = the item-level override alone (the in-game curator recomputes the price when the category changes)
    i['price'] = int(_prices.get('items', {}).get(i['kind'], _prices.get('cats', {}).get(i.get('category', ''), 0)) or 0)
    if i['kind'] in _prices.get('items', {}): i['ip'] = int(_prices['items'][i['kind']] or 0)
for i in cfg['items']:   # categories Removed (review shelf) and Unsorted (not yet reviewed) = hidden from players
    if i['tab'] == 'objects' and i['category'] in ('Removed', 'Unsorted'): i['hid'] = True

def sql(q):
    cmd = os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
def q(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

d = open(os.path.join(rel, 'data', 'dbc', 'GameObjectDisplayInfo.dbc'), 'rb').read()
_, n, nf, rs, ss = struct.unpack('<4sIIII', d[:20])
strs = d[20 + n * rs:]
go_model = {}
for i in range(n):
    r = struct.unpack_from('<%dI' % nf, d, 20 + i * rs)
    go_model[r[0]] = strs[r[1]:strs.index(b'\0', r[1])].decode().replace('.mdx', '.m2').replace('.MDX', '.m2').replace('.mdl', '.m2').replace('.MDL', '.m2')

cids = [str(i['entry']) for i in cfg['items'] if i['t'] == 'c']
gids = [str(i['entry']) for i in cfg['items'] if i['t'] == 'g']
# humanoids (display has an extended-appearance record) cannot be textured in the preview window
import struct as _st
_d = open(os.path.join(rel, 'data', 'dbc', 'CreatureDisplayInfo.dbc'), 'rb').read()
_, _n, _nf, _rs, _ss = _st.unpack('<4sIIII', _d[:20])
extra = {}
for _i in range(_n):
    _r = _st.unpack_from('<%dI' % _nf, _d, 20 + _i * _rs); extra[_r[0]] = _r[3]
disp = {}
for l in sql("select CreatureID,CreatureDisplayID from acore_world.creature_template_model where Idx=0 and CreatureID in (%s)" % ','.join(str(i['entry']) for i in cfg['items'] if i['t'] == 'c')).splitlines():
    a, b = l.split('\t'); disp[int(a)] = int(b)
cre = {}
for l in sql("select entry,name,IFNULL(subname,'') from acore_world.creature_template where entry in (%s)" % ','.join(cids)).splitlines():
    e, nm, sub = l.split('\t'); cre[int(e)] = (nm, sub)
gob = {}
for l in sql("select entry,name,displayId,type from acore_world.gameobject_template where entry in (%s)" % ','.join(gids)).splitlines():
    e, nm, dp, ty = l.split('\t'); gob[int(e)] = (nm, int(dp), int(ty))

# every icon name must exist in the client's icon tables (a missing texture would leave the previous icon showing)
ICON_NAMES = set()
for _f, _col in (('SpellIcon.dbc', 1), ('ItemDisplayInfo.dbc', 5)):
    _d = open(os.path.join(rel, 'data', 'dbc', _f), 'rb').read()
    _, _n, _nf, _rs, _ss = struct.unpack('<4sIIII', _d[:20]); _st = _d[20 + _n * _rs:]
    for _i in range(_n):
        _o = struct.unpack_from('<%dI' % _nf, _d, 20 + _i * _rs)[_col]
        if _o: ICON_NAMES.add(_st[_o:_st.index(b'\0', _o)].decode().split('\\')[-1].lower())
for _it in cfg['items']:
    if _it.get('icon') and _it['icon'].lower() not in ICON_NAMES: print('WARNING: icon not found in client data:', _it['kind'], _it['icon'])
# model bounds (tools/model_bounds.py -> cache/model-bounds.tsv): vertical centre + largest dimension, so the preview can be fitted and centred
BOUNDS = {}
_bf = os.path.join(proj, 'cache', 'model-bounds.tsv')
if os.path.exists(_bf):
    for _l in open(_bf).read().splitlines():
        _p = _l.split('\t')
        BOUNDS[_p[0].lower().replace('.mdx', '.m2')] = ((float(_p[1]) + float(_p[2])) / 2, float(_p[3]), float(_p[2]))
items, missing, nobounds, t14, wmo_items = [], [], [], [], []
for it in cfg['items']:
    e = it['entry']
    if it['t'] == 'c':
        if e not in cre: missing.append(it['kind']); continue
        nm, sub = cre[e]
        label = it.get('name') or sub or nm
        detail = nm if (sub and not it.get('name')) else ''
        items.append(dict(it, label=label, detail=detail, model='', human=1 if extra.get(disp.get(e, 0), 0) else 0))
    else:
        if e not in gob: missing.append(it['kind']); continue
        nm, dp, ty = gob[e]
        if go_model.get(dp, '').lower().endswith('.wmo') and it.get('multi'):   # whole-building WMOs draw now (type 14, custom-sql/014): all of them go to Unsorted for review
            it['category'] = 'Unsorted'; it['hid'] = True; wmo_items.append(it['kind'])
        if it.get('theme') is not None and not it.get('fx') and BOUNDS and go_model.get(dp, '').lower() not in BOUNDS:
            nobounds.append(it['kind']); continue     # sheet decor whose model has no measurable geometry = particle/FX emitter
        items.append(dict(it, label=it.get('name') or nm, detail='', model=go_model.get(dp, ''), human=0))
if wmo_items: print('%d WMO decor items put in Unsorted for review' % len(wmo_items))
if t14: print('%d type-14 (map object) decor items forced to Removed: the client cannot draw them' % len(t14))
if nobounds: print('dropped %d sheet items with no model geometry (FX)' % len(nobounds))
if missing: print('MISSING from DB (dropped):', missing)

npcs = sorted({i['entry'] for i in items if i['t'] == 'c'})
if 'Removed' in cfg['tabs']['objects']: cfg['tabs']['objects'].remove('Removed')
cfg['tabs']['objects'].append('Removed')   # always last
_catprice = {c: int(v) for c, v in _prices.get('cats', {}).items() if v}
S = ['-- GENERATED by tools/gen_garrison_catalog.py from garrison-config.json. Do not edit by hand.', 'return {',
     '    npcs = { %s },' % ', '.join(map(str, npcs)),
     '    cats = { %s },' % ', '.join('{ %s, %d }' % (q(c), _catprice.get(c, 0)) for c in cfg['tabs']['objects']),   # object categories in order + default price (the in-game curator starts from this)
     '    items = {']
for i in items:
    S.append('        { kind = %s, t = %s, entry = %d, name = %s%s%s%s%s%s },' % (q(i['kind']), q(i['t']), i['entry'], q(i['label']), ', multi = true' if i.get('multi') else '', ', hid = true' if i.get('hid') else '', ', price = %d' % i['price'] if i.get('price') else '',
        (', obj = true, cat = %s' % q(i['category'])) if i['tab'] == 'objects' else '', ', ip = %d' % i['ip'] if 'ip' in i else ''))
S += ['    },', '}', '']
open(os.path.join(proj, 'scripts', 'garrison_catalog.lua'), 'w').write('\n'.join(S))

C = ['-- GENERATED by tools/gen_garrison_catalog.py. Do not edit by hand.', 'WotlkGarrisonCatalog = {', '    tabs = {']
for tab, cats in cfg['tabs'].items():
    C.append('        { key = %s, cats = { %s } },' % (q(tab), ', '.join(q(c) for c in cats)))
FIT = {}
_ff = os.path.join(proj, 'garrison-fit.json')    # measured preview view per model path (lowercase) {model: [scale, sideways, up]} (claude_tools/preview_audit.py fit/refine)
if os.path.exists(_ff): FIT = json.load(open(_ff))
C += ['    },', '    catprice = { %s },' % ', '.join('[%s] = %d' % (q(c), v) for c, v in _catprice.items()), '    items = {']
for i in items:
    bz = BOUNDS.get(i['model'].lower().replace('.mdx', '.m2'), (1.0, 2.0, 2.0) if i.get('fx') else (0, 0, 0))   # FX emitters have no vertices: default view box
    _f = FIT.get(i['model'].lower())
    fit = (', vs = %.3f, vy = %.3f, vz = %.3f' % tuple(_f[:3])) if _f else ''
    if _f and len(_f) > 3: fit += ', vr = %.3f' % _f[3]
    C.append('        { kind = %s, tab = %s, cat = %s, name = %s, detail = %s, npc = %d, model = %s, human = %d, icon = %s, multi = %d, cz = %.2f, sz = %.2f, tz = %.2f%s },' %
             (q(i['kind']), q(i['tab']), q(i['category']), q(i['label']), q(i['detail']), i['entry'] if i['t'] == 'c' else 0, q(i['model']), i['human'],
              q(i.get('icon', '')), 1 if i.get('multi') else 0, bz[0], bz[1], bz[2], fit + (', hid = 1' if i.get('hid') else '') + (', price = %d' % i['price'] if i.get('price') else '') + (', ip = %d' % i['ip'] if 'ip' in i else '')))
C += ['    },', '}', '']
open(os.path.join(proj, 'addons', 'wotlk_garrison', 'Catalog.lua'), 'w').write('\n'.join(C))
print(len(items), 'items;', len(npcs), 'creatures;', sum(1 for i in items if i['model']), 'object models')
