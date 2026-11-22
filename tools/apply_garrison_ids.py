#!/usr/bin/env python3
"""Apply identified garrison model names/categories (from a proposals TSV) to garrison-admin.json AND the live Curator tables, with an UNDO log.
proposals TSV columns (header row): kind, tier, new name, category [, expected old category]   (extra columns ignored)
usage: ACORE_PREFIX="flatpak-spawn --host" python3 tools/apply_garrison_ids.py <proposals.tsv> --tiers A[,B] [--dry] [--no-db]
       ACORE_PREFIX="flatpak-spawn --host" python3 tools/apply_garrison_ids.py --undo <undo-file.tsv>
Rules: only rows whose tier is in --tiers; an item whose CURRENT category is not the expected old one (column 5, when given) is SKIPPED (you changed it since);
new categories (Nature > Herbs, Rocks > Ore Nodes, Bridges & Docks) are added to the category list in alphabetical place; names are cleaned like the Curator does.
Afterwards: python3 tools/gen_garrison_catalog.py, copy to release/lua_scripts, `reload ale`."""
import csv, json, os, re, subprocess, sys, time
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = os.path.join(proj, 'release')
af = os.path.join(proj, 'garrison-admin.json')
def sql(q):
    cmd = os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
def Q(s): return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"
def clean(s, mx=60): return re.sub(r'[~;|\x00-\x1f]', ' ', str(s)).strip()[:mx]
NEW_CATS = {'Nature > Herbs': 'Nature > Fossils', 'Rocks > Ore Nodes': 'Rocks', 'Bridges & Docks': 'Bottles & Jars'}   # new category -> the existing one it is placed AFTER
def remap(name, cat):
    if cat == 'Nature' and name.endswith(' Herb'): return 'Nature > Herbs'
    if cat == 'Rocks' and name.endswith(' Ore Rock'): return 'Rocks > Ore Nodes'
    if cat == 'Platform' and re.search(r'\b(Bridge|Dock)\b', name): return 'Bridges & Docks'
    return cat
def db_sync(items, cats, dry):
    """items: list of (kind, cat, name); writes dc_garrison_cur_item (upsert, price kept) and rewrites dc_garrison_cur_cat from `cats` (keeping prices), bumps the revision."""
    if dry: return
    for i in range(0, len(items), 25):
        part = items[i:i + 25]
        sql("INSERT INTO acore_characters.dc_garrison_cur_item (kind,cat,name,price) VALUES " + ",".join("(%s,%s,%s,-1)" % (Q(k), Q(c), Q(n)) for k, c, n in part) +
            " ON DUPLICATE KEY UPDATE cat=VALUES(cat), name=VALUES(name)")
    old = {l.split('\t')[0]: int(l.split('\t')[1]) for l in sql("select name,price from acore_characters.dc_garrison_cur_cat").splitlines() if '\t' in l}
    sql("DELETE FROM acore_characters.dc_garrison_cur_cat")
    sql("INSERT INTO acore_characters.dc_garrison_cur_cat (seq,name,price) VALUES " + ",".join("(%d,%s,%d)" % (i + 1, Q(c), old.get(c, 0)) for i, c in enumerate(cats)))
    sql("UPDATE acore_characters.dc_garrison_cur_meta SET v = v + 1 WHERE k='rev'")

args = sys.argv[1:]
dry = '--dry' in args; nodb = '--no-db' in args
a = json.load(open(af)); a.setdefault('categories', {}); a.setdefault('names', {})
stamp = time.strftime('%Y%m%d-%H%M%S')
os.makedirs(os.path.join(proj, 'cache', 'garrison_id'), exist_ok=True)

if '--undo' in args:
    uf = args[args.index('--undo') + 1]; rows = list(csv.DictReader(open(uf), delimiter='\t')); db_items = []
    for r in rows:
        k = r['kind']
        if r['old_cat'] == '(base)': a['categories'].pop(k, None)
        else: a['categories'][k] = r['old_cat']
        if r['old_name'] == '': a['names'].pop(k, None)
        else: a['names'][k] = r['old_name']
        db_items.append((k, r['old_cat'] if r['old_cat'] != '(base)' else '', r['old_name']))
    cats = [c for c in a['cats'] if c not in NEW_CATS or any(v == c for v in a['categories'].values())]
    a['cats'] = cats
    if not dry: json.dump(a, open(af, 'w'), indent=0, ensure_ascii=False)
    if not nodb: db_sync(db_items, cats, dry)
    print('undone', len(rows)); sys.exit(0)

prop = args[0]; tiers = set(args[args.index('--tiers') + 1].split(',')) if '--tiers' in args else {'A'}
rows = [r for r in csv.DictReader(open(prop), delimiter='\t') if r.get('tier') in tiers and r.get('new name')]
undo, db_items, skipped, applied = [], [], [], 0
for r in rows:
    k = r['kind']; name = clean(r['new name']); cat = remap(name, r['category'])
    cur = a['categories'].get(k, '(base)'); exp = r.get('old category', None)
    ok = {exp, '(base)'} | ({'Unsorted', 'Removed'} if exp == 'Unsorted' else set())   # the generator shows a stale 'Removed' on whole-building WMOs as Unsorted
    if exp and cur not in ok: skipped.append((k, cur, exp)); continue
    undo.append((k, cur, a['names'].get(k, ''), cat, name))
    a['categories'][k] = cat; a['names'][k] = name; db_items.append((k, cat, name)); applied += 1
need = sorted({c for _, c, _ in db_items if c not in a['cats']})
for c in need:
    if c not in NEW_CATS: print('UNKNOWN CATEGORY (not added):', c); sys.exit(1)
    after = NEW_CATS[c]; a['cats'].insert(a['cats'].index(after) + 1, c)
print('rows %d | applied %d | skipped %d | new categories %s' % (len(rows), applied, len(skipped), need))
for s in skipped[:10]: print('  skipped', s)
uf = os.path.join(proj, 'cache', 'garrison_id', 'undo_%s.tsv' % stamp)
with open(uf, 'w') as fh:
    fh.write('kind\told_cat\told_name\tnew_cat\tnew_name\n'); [fh.write('\t'.join(u) + '\n') for u in undo]
if dry: print('DRY RUN: nothing written'); sys.exit(0)
shutil_bk = os.path.join(proj, 'cache', 'garrison_id', 'garrison-admin.before-%s.json' % stamp)
import shutil; shutil.copy(af, shutil_bk)
json.dump(a, open(af, 'w'), indent=0, ensure_ascii=False)
if not nodb: db_sync(db_items, a['cats'], dry)
print('written; undo file', uf, '; backup', shutil_bk)
