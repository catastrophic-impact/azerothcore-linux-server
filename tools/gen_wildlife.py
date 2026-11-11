#!/usr/bin/env python3
"""Generate the garrison Wildlife catalog: one harmless immortal copy of a stock beast per distinct model (ground animals only).
Writes custom-sql/015_wildlife.sql (templates 940001+), updates the creatures tab in garrison-config.json, keeps ids stable in garrison-wildlife-ids.json.
Run on the HOST (needs the live DB):  python3 tools/gen_wildlife.py [release_dir]   then: apply custom-sql, gen_garrison_catalog.py, deploy, RESTART.
Re-runnable: models keep their entry (and so their kind w<entry>) forever; new models get new entries."""
import json, os, re, subprocess, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(proj, 'release')
def sql(q):
    return subprocess.run([os.path.join(rel, 'acore-admin'), 'sql', q], capture_output=True, text=True, check=True).stdout
FAMILY_CAT = {1: 'Wolves', 2: 'Cats', 3: 'Spiders', 4: 'Bears', 5: 'Boars', 6: 'Crocolisks', 21: 'Turtles', 35: 'Serpents', 11: 'Raptors', 39: 'Devilsaurs',
              12: 'Tallstriders', 8: 'Crabs', 42: 'Worms', 20: 'Scorpids', 41: 'Silithids', 9: 'Gorillas', 25: 'Hyenas', 38: 'Chimaeras', 31: 'Ravagers',
              32: 'Warp Stalkers', 45: 'Core Hounds', 43: 'Rhinos', 46: 'Spirit Beasts'}   # one category per hunter pet family
FLYERS = {7, 24, 26, 27, 30, 33, 34, 37, 44}   # never placed yet: they would need flying movement
# no-family beasts and critters: sorted by name keywords; anything else is left out
KEYWORDS = [('Horses & Mounts', r'\b(horse|warhorse|mare|stallion|steed|charger|pony|palomino|mule|donkey|zhevra|kodo|ram)\b'),
            ('Farm Animals', r'\b(cow|bull|sheep|lamb|pig|piglet|chicken|rooster|hen|goat|yak|ox|llama|goose|duck|turkey)\b'),
            ('Deer & Elk', r'\b(deer|stag|doe|fawn|elk|caribou|antelope|gazelle|moose|reindeer)\b'),
            ('Mammoths', r'\b(mammoth|mammoths)\b'),
            ('Critters', r'\b(rabbit|bunny|hare|squirrel|rat|mouse|frog|toad|roach|cockroach|beetle|snake|lizard|gecko|chipmunk|skunk|prairie dog|monkey|parrot|cat|kitten|dog|puppy|fox|raccoon|opossum|hedgehog|porcupine|mole|owl|crow|seagull|pigeon|dove)\b')]
BAD_NAME = re.compile(r'[\[\](){}0-9]|unused|\bdnd\b|test|dummy|trigger|visual|placeholder|\bnpc\b|spirit|ghost|zzold|obsolete|\bold\b|reuse|deprecated|image|trap|accumulator|\bform\b|apparition|\bmount\b|transform|stabled|captured|imprisoned|phantasmal|multi-spectrum|companion|specimen|corrupted|infected|plagued|diseased|cursed|rented|dying|injured|emaciated|abandoned|faithful|designer|tamable|enraged|\boak\b|broom|\bof\b|\bthe\b|\bking\b|\bqueen\b|\blord\b|polymorphed|event|channel|\bevil\b|maximum|equipment|mesmerized|attuned|raging', re.I)

rows = sql("""select t.entry, t.name, t.family, t.type, t.`rank`,
   (select count(*) from acore_world.creature c where c.id = t.entry) spawns,
   (select count(*) from acore_world.creature_template x where x.name = t.name) same_name,
   m.CreatureDisplayID, IFNULL(mv.Flight,0), IFNULL(mv.Swim,0), IFNULL(mv.Ground,1)
 from acore_world.creature_template t
 join acore_world.creature_template_model m on m.CreatureID = t.entry and m.Idx = 0
 left join acore_world.creature_template_movement mv on mv.CreatureId = t.entry
 where t.type in (1, 8) and t.entry < 900000 and t.npcflag = 0 and (t.`rank` in (0, 1) or t.family = 46) and t.VehicleId = 0""").splitlines()
best = {}   # display id -> (score, row)
for l in rows:
    e, nm, fam, ty, rk, sp, same, disp, fl, sw, gr = l.split('\t')
    e, fam, ty, rk, sp, same, disp = int(e), int(fam), int(ty), int(rk), int(sp), int(same), int(disp)
    if (BAD_NAME.search(nm) and fam != 46) or fam in FLYERS or int(fl) or (int(sw) and not int(gr)): continue
    low = nm.lower()
    cat = FAMILY_CAT.get(fam) if ty == 1 else None
    if cat is None:
        if fam not in (0,) and ty == 1 and fam not in FAMILY_CAT: continue   # other families (demons etc. are not beasts; unknown beast families: skip)
        for c, rx in KEYWORDS:
            if re.search(rx, low): cat = c; break
    if cat is None: continue
    score = (rk == 0, same, sp, -e)
    if disp not in best or score > best[disp][0]: best[disp] = (score, dict(src=e, name=nm.strip(), cat=cat, disp=disp))
mapf = os.path.join(proj, 'garrison-wildlife-ids.json')   # tracked: a model keeps its entry (and kind) for good
idmap = json.load(open(mapf)) if os.path.exists(mapf) else {}
# the six first test animals keep their entries
LEGACY = {299: 940001, 1186: 940002, 3425: 940003, 2955: 940004, 1127: 940005, 3127: 940006}
for d, (s, r) in best.items():
    k = str(d)
    if k not in idmap: idmap[k] = LEGACY.get(r['src']) if r['src'] in LEGACY and LEGACY[r['src']] not in idmap.values() else None
nxt = max([940000] + [v for v in idmap.values() if v]) + 1
for d in sorted(best, key=lambda d: (best[d][1]['cat'], best[d][1]['name'], d)):
    if idmap.get(str(d)) is None: idmap[str(d)] = nxt; nxt += 1
os.makedirs(os.path.dirname(mapf), exist_ok=True); json.dump(idmap, open(mapf, 'w'), indent=0)
assert nxt <= 949999, 'wildlife id range exhausted'
# unique names inside a category: "Timber Wolf", "Timber Wolf 2", ...
items, seen = [], {}
for d in sorted(best, key=lambda d: (best[d][1]['cat'], best[d][1]['name'], d)):
    r = best[d][1]; new = idmap[str(d)]
    base = re.sub(r'\s+', ' ', re.sub(r'^Tamable ', '', r['name'])); seen[base] = seen.get(base, 0) + 1
    r['label'] = base if seen[base] == 1 else '%s %d' % (base, seen[base])
    r['new'] = new; items.append(r)
q = lambda s: s.replace("'", "''")
o = ["""-- Garrison wildlife: harmless, immortal copies of stock beasts, one per distinct model (generated by tools/gen_wildlife.py - re-run it, do not edit by hand). Idempotent.
-- Each copy = the stock template with: friendly faction 35, no npcflag, no AI/script, no loot, and unit flags NON_ATTACKABLE(2) | IMMUNE_TO_PC(256) |
-- IMMUNE_TO_NPC(512) = nobody can target or hurt it (immortal); flags_extra CIVILIAN(2) | NO_XP(64) so guards ignore it. Ground movement is done by
-- scripts/garrison_wildlife.lua (MovementType 0 = the core never wanders them off). Only the first model row is copied (one look per entry).
USE acore_world;
DELETE FROM creature_template WHERE entry BETWEEN 940001 AND 949999;
DELETE FROM creature_template_model WHERE CreatureID BETWEEN 940001 AND 949999;
CREATE TEMPORARY TABLE tmp_map (new_entry INT, src INT, nm VARCHAR(100));"""]
for i in range(0, len(items), 200):
    o.append('INSERT INTO tmp_map VALUES ' + ', '.join("(%d, %d, '%s')" % (r['new'], r['src'], q(r['label'])) for r in items[i:i + 200]) + ';')
o.append("""CREATE TEMPORARY TABLE tmp_t SELECT t.* FROM creature_template t JOIN tmp_map m ON t.entry = m.src;
UPDATE tmp_t t JOIN tmp_map m ON t.entry = m.src SET t.entry = m.new_entry, t.name = m.nm, t.subname = 'Wildlife', t.npcflag = 0, t.faction = 35, t.gossip_menu_id = 0,
  t.ScriptName = '', t.AIName = '', t.MovementType = 0, t.difficulty_entry_1 = 0, t.difficulty_entry_2 = 0, t.difficulty_entry_3 = 0, t.KillCredit1 = 0, t.KillCredit2 = 0,
  t.lootid = 0, t.pickpocketloot = 0, t.skinloot = 0, t.mingold = 0, t.maxgold = 0, t.unit_flags = 770, t.flags_extra = 66, t.`rank` = 0, t.minlevel = 1, t.maxlevel = 1;
INSERT INTO creature_template SELECT * FROM tmp_t;
INSERT INTO creature_template_model (CreatureID, Idx, CreatureDisplayID, DisplayScale, Probability, VerifiedBuild)
  SELECT m.new_entry, 0, x.CreatureDisplayID, x.DisplayScale, 1, x.VerifiedBuild FROM tmp_map m JOIN creature_template_model x ON x.CreatureID = m.src AND x.Idx = 0;
DROP TEMPORARY TABLE tmp_t; DROP TEMPORARY TABLE tmp_map;
""")
open(os.path.join(proj, 'custom-sql', '015_wildlife.sql'), 'w').write('\n'.join(o))
cfgf = os.path.join(proj, 'garrison-config.json'); cfg = json.load(open(cfgf))
cfg['items'] = [i for i in cfg['items'] if i.get('tab') != 'creatures']
cats = sorted({r['cat'] for r in items})
for r in items:
    cfg['items'].append(dict(kind='w%d' % r['new'], tab='creatures', category='Wildlife > ' + r['cat'], t='c', entry=r['new'], name=r['label'], multi=True, wild=True, icon='Ability_Hunter_BeastCall'))
cfg['tabs']['creatures'] = ['Wildlife > ' + c for c in cats]
json.dump(cfg, open(cfgf, 'w'), indent=1)
from collections import Counter
print(len(items), 'wildlife models'); [print('  %-24s %d' % (c, n)) for c, n in sorted(Counter(r['cat'] for r in items).items())]
