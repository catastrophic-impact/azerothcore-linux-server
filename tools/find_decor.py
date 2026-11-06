#!/usr/bin/env python3
"""Propose stock GameObjects as garrison decor -> decor-proposals/decor.tsv (edit the `include` column Y/N, then run gen_garrison_catalog.py's decor import).
One row per distinct display model (stock templates are duplicated heavily): representative = the template with the most real spawns, then lowest entry.
Only plain, unscripted object types (generic 5, chair 7, spell focus 8, book 9); no script/AI, named, with a model.
usage: find_decor.py [release_dir]      env: ACORE_PREFIX (e.g. 'flatpak-spawn --host')"""
import os, re, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')

def sql(q):
    cmd = os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout

d = open(os.path.join(rel, 'data', 'dbc', 'GameObjectDisplayInfo.dbc'), 'rb').read()
_, n, nf, rs, ss = struct.unpack('<4sIIII', d[:20]); strs = d[20 + n * rs:]
model = {}
for i in range(n):
    r = struct.unpack_from('<%dI' % nf, d, 20 + i * rs)
    model[r[0]] = strs[r[1]:strs.index(b'\0', r[1])].decode().replace('.mdx', '.m2').replace('.MDX', '.m2').replace('.mdl', '.m2').replace('.MDL', '.m2')

BAD = re.compile(r'(\bDND\b|\[|\btest\b|\bPH\b|trap|portal|teleport|spawn|visual|invisible|bunny|dummy|do not|unused|quest|mailbox|\bnode\b|vein|deposit|herb|fishing|chest|loot|bonfire pit|aqwar|highlight|image|resource|burning|aura|smoke|steam|glow|target|replace|energy|beam|cleansing|impact|\beye\b|breakable|corrupt)', re.I)
rows = sql("""select t.entry,t.name,t.displayId,t.type,t.size,IFNULL(c.n,0)
  from acore_world.gameobject_template t
  left join (select id, count(*) n from acore_world.gameobject group by id) c on c.id=t.entry
  left join (select distinct entryorguid e from acore_world.smart_scripts where source_type=1) s on s.e=t.entry
  where t.type in (5,7,8,9) and t.ScriptName='' and t.AIName='' and t.name<>'' and t.displayId>0 and s.e is null""").splitlines()
by = {}
dropped = {}
NAMEF = set()
OLD = {}   # keep earlier include marks (Y/N) when the sheet is regenerated
_old = os.path.join(proj, 'decor-proposals', 'decor.tsv')
if os.path.exists(_old):
    for _l in open(_old).read().splitlines()[1:]:
        _c = _l.split('\t')
        if len(_c) > 4: OLD[_c[4]] = _c[0]
for l in rows:
    if l.count("\t") != 5: continue
    e, nm, dp, ty, sz, sp = l.split('\t'); e, dp, ty, sp = int(e), int(dp), int(ty), int(sp)
    why = 'nomodel' if (dp not in model or not model[dp]) else 'gm' if re.match(r'(?i)gm', model[dp].split('\\')[-1]) else 'name' if BAD.search(nm) else None
    if why and why != 'name': dropped.setdefault(why, set()).add(dp); continue
    if why == 'name': NAMEF.add(e)     # name-filtered rows stay in the sheet (include N) so the in-game audit can show whether they are usable
    by.setdefault(dp, []).append((-sp, e, nm, ty, sz))
def cat(m):
    p = m.replace('\\', '/').split('/')
    return '/'.join(x.title() for x in p[1:3]) if len(p) > 3 else (p[1].title() if len(p) > 1 else '')
ALLY = re.compile(r'(alliance|stormwind|human|dwarf|dwarven|ironforge|night ?elf|nightelf|gnome|gnomish|draenei|darnassus|teldrassil|elwynn|westfall|goldshire|dunmorogh|exodar|azuremyst|darkshire|menethil|lakeshire|kharanos|northshire|bloodmyst|ashenvale|stormpike|ravenholdt)', re.I)
HORDE = re.compile(r'(horde|orgrimmar|orc|orcish|tauren|undead|forsaken|undercity|troll|blood ?elf|bloodelf|silvermoon|thunder ?bluff|mulgore|durotar|tirisfal|razor ?hill|bloodhoof|sen.?jin|apothecary|warsong|frostwolf|goblin|taurajo|brill|darkspear|sunreaver|silverwing|ghostland|eversong)', re.I)
def theme(nm, path):
    a, h = bool(ALLY.search(nm)), bool(HORDE.search(nm))
    if a != h: return 'Alliance' if a else 'Horde'
    a, h = bool(ALLY.search(path)), bool(HORDE.search(path))
    if a != h: return 'Alliance' if a else 'Horde'
    return 'Neutral'
# function categories (the UI has room for ~11): first match wins
CATS = [('Holiday', r'xmas|christmas|mistletoe|wreath|stocking|gift|pumpkin|brewfest|valentine|candy|romantic|firework|\b(val|mff)\b|- (brewfest|mff|val|xmas)$'),
        ('Seating', r'chair|stool|bench|throne|hammock'),
        ('Crafting Stations', r'anvil|forge|cauldron|workbench|loom|\bstill\b|alchemy (table|lab)|cooking table|table cooker|lab table|work table|smelting pot|cookpot|washing tub|grinder'),
        ('Lighting & Fire', r'lamp|lantern|candle|candelabra|chandelier|brazier|campfire|bonfire|torch|fireplace|hearth|stove|oven|grill|\bspit\b|firepit|\bfire\b|blaze|embers|hot coals|incense'),
        ('Weapons & Armor', r'sword|\baxe|shield|spear|mace|hammer|armor|helm|breastplate|quiver|\bbow\b|\bstaff\b|weapon|catapult|cannon|mortar|armor stand'),
        ('Crates & Storage', r'barrel|crate|\bkeg|sack|chest|trunk|basket|bucket|\bpot\b|\bjar|urn|vase|bottle|hay|cart|wagon|wheelbarrow|footlocker|casket|jug|bag|bowl|platter|woodpile|wood stack|log pile|lumber|mailbox'),
        ('Furniture', r'table|\bbed\b|bunk|\bcot\b|bedroll|\brug|carpet|shelf|shelves|bookshelf|bookcase|desk|cabinet|wardrobe|dresser|mirror|clock|pillow|\bmug|goblet|\bcup\b|hourglass|counter'),
        ('Banners & Tents', r'banner|tent|flag|pennant|barricade|fence|pavilion|canopy|hanging|doghouse|outhouse|rowboat|boat'),
        ('Statues & Monuments', r'statue|fountain|obelisk|totem|idol|tombstone|gravestone|headstone|pillar|column|\barch\b|crystal|windmill|scarecrow|altar|monument|shrine|pedestal|moonwell|gong|drum|anchor')]
def fcat(nm):
    for c, rx in CATS:
        if re.search(rx, nm, re.I): return c
    return 'Nature' if re.search(r'plant|flower|bush|tree|grass|mushroom|marigold|vine|lily|fungus|kelp', nm, re.I) else 'Misc'
NOGOOD = re.compile(r'(sigil|hero portrait|backdrop|report from|rift|vortex|effect|particles|fog|marker|summoning|ritual circle|\bdoor\b|gate|zeppelin|bridge|stairs|platform|billboard|shoutbox|barbershop|bank|auction|inn$|tavern|general store|goods|supplies|armorers|weapons$)', re.I)
# suggest Y when the name looks like furniture/props; everything else starts as N
GOOD = re.compile('|'.join(rx for c, rx in CATS) + r'|plant|flower|bush|christmas tree|scroll|\bbook|\bmap\b|globe|\bsign\b|signpost|\bbars?\b|metalbar|skeleton|skull|bone|ragdoll|fruit|bread|turkey|apple|\bmeat|rack|cage|flagpole', re.I)
out, seen = [], set()
for dp, lst in sorted(by.items(), key=lambda kv: sorted(kv[1])[0]):
    lst.sort(); _, e, nm, ty, sz = lst[0]
    key = (nm.lower(), model[dp].lower().split('\\')[-1])
    if key in seen: continue
    seen.add(key)
    alts = sorted({x[2] for x in lst[1:] if x[2] != nm})[:3]
    clean = nm.replace('Doodad_', '').replace('_', ' ')
    inc = OLD.get(str(e)) or ('Y' if GOOD.search(nm) and not NOGOOD.search(nm) and e not in NAMEF else 'N')
    out.append((inc, theme(nm, model[dp]), fcat(clean), clean, e, dp, ty, sz, len(lst), model[dp].split('\\')[-1], '; '.join(alts), model[dp], 'name-filtered' if e in NAMEF else ''))
out.sort(key=lambda r: (r[1] != 'Neutral', r[1], r[2].lower(), r[3].lower()))
os.makedirs(os.path.join(proj, 'decor-proposals'), exist_ok=True)
with open(os.path.join(proj, 'decor-proposals', 'decor.tsv'), 'w') as f:
    f.write('include\ttheme\tcategory\tname\tentry\tdisplayId\ttype\tsize\tdupes\tmodel\talso_named\tmodelpath\tnote\n')
    for r in out: f.write('\t'.join(map(str, r)) + '\n')
from collections import Counter
print('dropped distinct models:', {k: len(v - set(by)) for k, v in dropped.items()})
print(len(out), 'distinct models ->', 'decor-proposals/decor.tsv', dict(Counter((r[1], r[0]) for r in out)))
