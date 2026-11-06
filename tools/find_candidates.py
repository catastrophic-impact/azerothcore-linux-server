#!/usr/bin/env python3
"""Find pets/mounts that cannot be obtained on THIS server, writing shop-proposals/A_no-source.tsv and B_one-faction-vendor.tsv.
Definition: an item whose use-spell summons a companion (effect 28) or applies a mounted aura (78) -- any item class.
  excluded: crafted by a real PROFESSION recipe (spell in SkillLineAbility with a tradeskill line); junk/test names.
  A = no source (no drop/quest/achievement/vendor);  B = sold only by one faction's vendors.
usage: find_candidates.py [release_dir]   env: ACORE_PREFIX (e.g. 'flatpak-spawn --host')"""
import os, re, struct, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')
import json
EXCL = json.load(open(os.path.join(proj, 'shop-config.json'))).get('excludeNames', {})   # {reason: [name substrings]} -> written as include=N
EXTRA = set(json.load(open(os.path.join(proj, 'shop-config.json'))).get('extraItems', []))   # real items with an odd item class
TRADE = {164, 165, 171, 185, 197, 202, 333, 755, 773, 129}   # smithing, leather, alchemy, cooking, tailoring, engineering, enchanting, jewelcrafting, inscription, first aid
def sql(q):
    r = subprocess.run(os.environ.get('ACORE_PREFIX', '').split() + [os.path.join(rel, 'acore-admin'), 'sql', q], capture_output=True, text=True)
    if r.returncode: sys.exit('SQL failed: ' + (r.stdout + r.stderr)[-300:])
    return r.stdout
def dbc(name):
    d = open(os.path.join(rel, 'data', 'dbc', name), 'rb').read(); _, n, nf, rs, _ = struct.unpack('<4sIIII', d[:20])
    return [struct.unpack_from('<%dI' % nf, d, 20 + r * rs) for r in range(n)]
spells, sla = dbc('Spell.dbc'), dbc('SkillLineAbility.dbc')
kind_of = {}                      # spell -> 'pet' / 'mount'
created_by = {}                   # item -> [spells that create it]
for r in spells:
    for e in range(3):
        if r[110 + e] and r[71 + e] == 28: kind_of.setdefault(r[0], 'pet')
        if r[110 + e] and r[71 + e] == 6 and r[95 + e] == 78: kind_of.setdefault(r[0], 'mount')
        if r[71 + e] == 24 and r[107 + e]: created_by.setdefault(r[107 + e], []).append(r[0])
trade_spells = {r[2] for r in sla if r[1] in TRADE}
# also: spells taught by recipe items (class 9) or by trainers are real recipes even when the client data has no skill link
for l in sql('select spellid_1,spellid_2,spellid_3 from acore_world.item_template where class=9').splitlines():
    trade_spells.update(int(x) for x in l.split('\t') if x.isdigit())
for l in sql('select SpellID from acore_world.npc_trainer').splitlines():
    if l.strip().isdigit(): trade_spells.add(int(l))
rows = []
for l in sql('select entry,name,Quality,spellid_1,spellid_2,spellid_3,AllowableRace,class,subclass from acore_world.item_template where spellid_1>0 or spellid_2>0 or spellid_3>0').splitlines():
    c = l.split('\t')
    if len(c) < 9 or not c[0].isdigit(): continue
    if not ((c[7] == '15' and c[8] in ('2', '5')) or int(c[0]) in EXTRA): continue   # real pet/mount items only (other classes are mostly dead data)
    sp = next((int(s) for s in c[3:6] if s.isdigit() and int(s) not in (0, 483, 55884) and int(s) in kind_of), 0)
    if sp: rows.append(dict(item=int(c[0]), name=c[1], quality=int(c[2]), spell=sp, kind=kind_of[sp], race=c[6]))
JUNK = re.compile(r'(^\[|test|deprecated|PH\]|\(old\)|\bOLD\b|NYI|unused|DNT|zz|NPC Equip|NOT IN USE)', re.I)
rows = [r for r in rows if not JUNK.search(r['name'])]
ids = ','.join(str(r['item']) for r in rows)
Q = ['USE acore_world;',
 'CREATE TEMPORARY TABLE spawned (entry INT PRIMARY KEY);',
 'INSERT IGNORE INTO spawned SELECT DISTINCT id FROM creature;',
 'INSERT IGNORE INTO spawned SELECT difficulty_entry_1 FROM creature_template WHERE entry IN (SELECT id FROM creature) AND difficulty_entry_1>0;',
 'INSERT IGNORE INTO spawned SELECT difficulty_entry_2 FROM creature_template WHERE entry IN (SELECT id FROM creature) AND difficulty_entry_2>0;',
 'INSERT IGNORE INTO spawned SELECT difficulty_entry_3 FROM creature_template WHERE entry IN (SELECT id FROM creature) AND difficulty_entry_3>0;',
 # bosses are often summoned by their encounter script and have no spawn row: count instance bosses and scripted creatures too
 'INSERT IGNORE INTO spawned SELECT creditEntry FROM instance_encounters WHERE creditType=0;',
 "INSERT IGNORE INTO spawned SELECT entry FROM creature_template WHERE ScriptName<>'';",
 'CREATE TEMPORARY TABLE sp_base AS SELECT entry FROM spawned;',
 'INSERT IGNORE INTO spawned SELECT d.difficulty_entry_1 FROM creature_template d JOIN sp_base b ON b.entry=d.entry WHERE d.difficulty_entry_1>0;',
 'INSERT IGNORE INTO spawned SELECT d.difficulty_entry_2 FROM creature_template d JOIN sp_base b ON b.entry=d.entry WHERE d.difficulty_entry_2>0;',
 'INSERT IGNORE INTO spawned SELECT d.difficulty_entry_3 FROM creature_template d JOIN sp_base b ON b.entry=d.entry WHERE d.difficulty_entry_3>0;',
 'CREATE TEMPORARY TABLE gospawn (entry INT PRIMARY KEY);',
 'INSERT IGNORE INTO gospawn SELECT DISTINCT id FROM gameobject;',
 'CREATE TEMPORARY TABLE rq (q INT PRIMARY KEY);   -- quests a player can actually start',
 'INSERT IGNORE INTO rq SELECT s.quest FROM creature_queststarter s JOIN spawned p ON p.entry=s.id;',
 'INSERT IGNORE INTO rq SELECT s.quest FROM gameobject_queststarter s JOIN gospawn p ON p.entry=s.id;',
 'INSERT IGNORE INTO rq SELECT i.startquest FROM item_template i WHERE i.startquest>0 AND (i.entry IN (SELECT Item FROM creature_loot_template) OR i.entry IN (SELECT Item FROM gameobject_loot_template) OR i.entry IN (SELECT Item FROM reference_loot_template) OR i.entry IN (SELECT Item FROM item_loot_template) OR i.entry IN (SELECT Item FROM fishing_loot_template) OR i.entry IN (SELECT item FROM npc_vendor));   -- item-started quests only count if the starter item is itself obtainable (CE welcome gifts are not)',
 'INSERT IGNORE INTO rq SELECT ID FROM quest_template_addon WHERE PrevQuestID<>0 OR BreadcrumbForQuestId<>0;   -- chain follow-ups (conservative)',
 'CREATE TEMPORARY TABLE refs (r INT PRIMARY KEY);',
 'INSERT IGNORE INTO refs SELECT l.Reference FROM creature_loot_template l JOIN creature_template t ON t.lootid=l.Entry JOIN spawned s ON s.entry=t.entry WHERE l.Reference>0;',
 'CREATE TEMPORARY TABLE src (item INT PRIMARY KEY);      -- REACHABLE sources',
 f'INSERT IGNORE INTO src SELECT l.Item FROM creature_loot_template l JOIN creature_template t ON t.lootid=l.Entry JOIN spawned s ON s.entry=t.entry WHERE l.Reference=0 AND l.Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT r.Item FROM reference_loot_template r JOIN refs ON refs.r=r.Entry WHERE r.Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT l.Item FROM skinning_loot_template l JOIN creature_template t ON t.skinloot=l.Entry JOIN spawned s ON s.entry=t.entry WHERE l.Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT l.Item FROM pickpocketing_loot_template l JOIN creature_template t ON t.pickpocketloot=l.Entry JOIN spawned s ON s.entry=t.entry WHERE l.Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT l.Item FROM gameobject_loot_template l JOIN gameobject_template t ON t.Data1=l.Entry AND t.type=3 JOIN gospawn g ON g.entry=t.entry WHERE l.Reference=0 AND l.Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT Item FROM fishing_loot_template WHERE Reference=0 AND Item IN ({ids});',
 # containers (TCG loot cards etc.) only count if the container item itself can be obtained
 f'INSERT IGNORE INTO src SELECT l.Item FROM item_loot_template l WHERE l.Reference=0 AND l.Item IN ({ids}) AND (l.Entry IN (SELECT Item FROM creature_loot_template) OR l.Entry IN (SELECT Item FROM gameobject_loot_template) OR l.Entry IN (SELECT Item FROM reference_loot_template) OR l.Entry IN (SELECT Item FROM fishing_loot_template) OR l.Entry IN (SELECT item FROM npc_vendor) OR l.Entry IN (SELECT item FROM game_event_npc_vendor));',
 # holiday vendors (Hallow's End brooms, Brewfest, ...) are obtainable during their event
 f'INSERT IGNORE INTO src SELECT item FROM game_event_npc_vendor WHERE item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT Item FROM mail_loot_template WHERE Reference=0 AND Item IN ({ids});',
 f'INSERT IGNORE INTO src SELECT ItemID FROM achievement_reward WHERE ItemID IN ({ids});']
QCOLS = ['RewardItem1','RewardItem2','RewardItem3','RewardItem4','RewardChoiceItemID1','RewardChoiceItemID2','RewardChoiceItemID3','RewardChoiceItemID4','RewardChoiceItemID5','RewardChoiceItemID6']
Q += [f'INSERT IGNORE INTO src SELECT q.{c} FROM quest_template q JOIN rq ON rq.q=q.ID WHERE q.{c} IN ({ids});' for c in QCOLS]
# naive (any DB reference, reachable or not) -- only used to label "unreachable-only" items
Q += ['CREATE TEMPORARY TABLE srcany (item INT PRIMARY KEY);']
for t in ('creature_loot_template','gameobject_loot_template','fishing_loot_template','item_loot_template','pickpocketing_loot_template','skinning_loot_template','reference_loot_template','mail_loot_template'):
    Q.append(f'INSERT IGNORE INTO srcany SELECT Item FROM {t} WHERE Item IN ({ids});')
Q += [f'INSERT IGNORE INTO srcany SELECT {c} FROM quest_template WHERE {c} IN ({ids});' for c in QCOLS]
Q.append(f'INSERT IGNORE INTO srcany SELECT item FROM npc_vendor WHERE item IN ({ids});')
Q.append(f'INSERT IGNORE INTO srcany SELECT item FROM game_event_npc_vendor WHERE item IN ({ids});')
Q.append(f"""SELECT i.entry, IF(s.item IS NOT NULL,1,0), IFNULL(v.bits,-1), IFNULL(v.neutral,0), IF(a.item IS NOT NULL,1,0) FROM item_template i
 LEFT JOIN src s ON s.item=i.entry LEFT JOIN srcany a ON a.item=i.entry
 LEFT JOIN (SELECT n.item, BIT_OR(IFNULL(f.FactionGroup,0)&6) bits, SUM((IFNULL(f.FactionGroup,0)&6)=0) neutral FROM npc_vendor n JOIN creature_template c ON c.entry=n.entry
            JOIN spawned sp ON sp.entry=c.entry LEFT JOIN factiontemplate_dbc f ON f.ID=c.faction GROUP BY n.item) v ON v.item=i.entry WHERE i.entry IN ({ids});""")
q = '\n'.join(Q)
info = {}
for l in sql(q).splitlines():
    c = l.split('\t')
    if len(c) == 5 and c[0].isdigit(): info[int(c[0])] = (int(c[1]), int(c[2]), int(c[3]), int(c[4]))
A, B, crafted = [], [], []
for r in sorted(rows, key=lambda r: (r['kind'], r['name'].lower())):
    has_src, bits, neutral, anysrc = info.get(r['item'], (0, -1, 0, 0))
    if any(s in trade_spells for s in created_by.get(r['item'], [])): crafted.append(r); continue
    vf = '' if bits < 0 else ('any' if neutral else {2: 'ALLIANCE-only', 4: 'HORDE-only'}.get(bits, 'both'))
    src = ','.join(x for x in (('drop/quest/achieve' if has_src else ''), ('vendor' if bits >= 0 else '')) if x)
    note = 'only-UNREACHABLE-sources' if (not src and anysrc) else ''
    r.update(src=src, vf=vf, note=note, inc='Y')
    for why, subs in EXCL.items():
        if any(x.lower() in r['name'].lower() for x in subs): r.update(inc='N', note=why)
    if not src: A.append(r)
    elif src == 'vendor' and vf in ('HORDE-only', 'ALLIANCE-only'): B.append(r)
hdr = 'include\tkind\titem\tname\tquality\tteachSpell\tsources\tvendorFactions\tallowableRace\tnote\n'
def out(fn, rs):
    p = os.path.join(proj, 'shop-proposals', fn)
    if os.path.exists(p): os.replace(p, p + '.prev')
    open(p, 'w').write(hdr + ''.join(r.get('inc', 'Y') + '\t' + '\t'.join(map(str, [r['kind'], r['item'], r['name'], r['quality'], r['spell'], r['src'], r['vf'], r['race'], r['note']])) + '\n' for r in rs))
out('A_no-source.tsv', A); out('B_one-faction-vendor.tsv', B)
print('A (no source): pets %d, mounts %d | B (one-faction vendor): pets %d, mounts %d | profession-crafted excluded: %d' % (
    sum(r['kind'] == 'pet' for r in A), sum(r['kind'] == 'mount' for r in A), sum(r['kind'] == 'pet' for r in B), sum(r['kind'] == 'mount' for r in B), len(crafted)))
