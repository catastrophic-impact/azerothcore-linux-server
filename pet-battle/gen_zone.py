#!/usr/bin/env python3 -I
"""Roster + meta files for a NEW zone from the live world DB (server MySQL must be up).
Usage: python3 -I pet-battle/gen_zone.py <name> <map> <x1> <x2> <y1> <y2> <maxlevel>      e.g.  westfall 0 -11500 -9500 600 2400 20
Writes pet-battle/<name>_roster.tsv (same columns as elwynn_roster.tsv; include = Y/N by the rules below) and <name>_meta.tsv (entry, unit_class, creature type, family, weapons).
Rules (same as the earlier zones): non-elite (rank 0) creatures that have >= 3 spawns inside the box, level <= maxlevel, no npcflag (vendors, trainers, guards), no names that mark
citizens / guards / event NPCs, no pet-type 12/"non-combat" duplicates of an existing species name is NOT excluded (a species already in pb_data is reused: note 'already a species')."""
import subprocess, sys, os, re, shlex
name, mp, x1, x2, y1, y2, maxlvl = sys.argv[1], *sys.argv[2:7], int(sys.argv[7])
root = os.getcwd()
def sql(q):
    out = subprocess.run(['flatpak-spawn', '--host', 'sh', '-c', 'cd %s/release && ./acore-admin sql %s' % (root, shlex.quote(q))], capture_output=True, text=True).stdout
    return [l.split('\t') for l in out.splitlines() if l.strip() and not l.startswith('ERROR')]
rows = sql("SELECT t.entry, t.name, t.minlevel, t.maxlevel, t.type, t.family, t.`rank`, COUNT(*) sp, IFNULL(m.CreatureDisplayID,0), t.unit_class, t.npcflag "
           "FROM acore_world.creature c JOIN acore_world.creature_template t ON t.entry=c.id LEFT JOIN acore_world.creature_template_model m ON m.CreatureID=t.entry AND m.Idx=0 "
           "WHERE c.map=%s AND c.position_x BETWEEN %s AND %s AND c.position_y BETWEEN %s AND %s GROUP BY t.entry HAVING sp>=3 ORDER BY t.minlevel, t.name" % (mp, x1, x2, y1, y2))
TYPE = {'1': 'Beast', '2': 'Dragonkin', '3': 'Demon', '4': 'Elemental', '5': 'Giant', '6': 'Undead', '7': 'Humanoid', '8': 'Critter', '9': 'Mechanical', '10': 'Not specified', '11': 'Totem', '12': 'Non-combat Pet'}
BAD = ('guard', 'citizen', 'celebrant', 'protector', 'woodworker', 'lumberjack', 'spirit', 'turkey', 'farmer', 'militia', 'watchman', 'deputy', 'peasant', 'dockworker', 'merchant', 'innkeeper')
existing = set(re.findall(r'\[(\d+)\] = \{ name = "[^"]*", retail =', open('scripts/pb_data.lua').read()))
out, meta = [], []
for r in rows:
    entry, nm, lo, hi, typ, fam, rk, sp, disp, cls, npc = r[:11]
    inc, note = 'Y', ''
    if int(rk) != 0: inc, note = 'N', 'rank %s (elite/rare)' % rk
    elif int(npc) != 0: inc, note = 'N', 'npcflag %s' % npc
    elif int(hi) > maxlvl: inc, note = 'N', 'level > %d' % maxlvl
    elif any(b in nm.lower() for b in BAD): inc, note = 'N', 'citizen/guard/event name'
    elif typ in ('11', '12', '10'): inc, note = 'N', 'type ' + TYPE.get(typ, typ)
    if entry in existing: note = (note + '; ' if note else '') + 'already a species'
    out.append('\t'.join([inc, entry, nm, lo if lo == hi else '%s-%s' % (lo, hi), TYPE.get(typ, typ), fam, rk, sp, disp, 'Melee', '', note]))
    wq = sql("SELECT IFNULL(CONCAT(i.class,'/',i.subclass),'') FROM acore_world.creature_equip_template e JOIN acore_world.item_template i ON i.entry IN (e.ItemID1,e.ItemID2,e.ItemID3) WHERE e.CreatureID=%s AND i.class=2" % entry)
    meta.append('\t'.join([entry, cls, typ, fam, ','.join(w[0] for w in wq if w and w[0])]))
hdr = '# %s pet roster (map %s box x %s..%s, y %s..%s, mobs level <= %d, rank 0, no npcflag/citizen/guard names; include Y/N by gen_zone.py). Same columns as elwynn_roster.tsv.\n# archetype is obsolete (retail kits now).\ninclude\tentry\tname\tlevels\ttype\tfamily\trank\tspawns\tdisplay\tarchetype\tabilities\tnotes\n' % (name, mp, x1, x2, y1, y2, maxlvl)
open('pet-battle/%s_roster.tsv' % name, 'w').write(hdr + '\n'.join(out) + '\n')
open('pet-battle/%s_meta.tsv' % name, 'w').write('\n'.join(meta) + '\n')
print('%d creatures, %d included' % (len(out), sum(1 for l in out if l.startswith('Y'))))
