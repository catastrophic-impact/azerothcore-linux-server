#!/usr/bin/env python3 -I
"""Add several zones in ONE go from pet-battle/zone_ranges.tsv (the sourced manifest): gen_zone -> prune -> auto_picks -> apply_zone (-> regenerates pb_retail). Stops before deploy.
Usage: python3 -I pet-battle/zone_batch.py <zone> [<zone> ...]   then: run_tests, sim_balance, auto_repick (one round), gen_standins_sql ON THE HOST, deploy, ONE restart, audit_standins.
Rows need numeric box + range + a source URL/text, else the zone is refused (no guesses). A zone whose D.zones id exists is skipped."""
import sys, re, subprocess
rows = {}
for l in open('pet-battle/zone_ranges.tsv', encoding='utf-8'):
    if l.startswith('#') or not l.strip(): continue
    c = l.rstrip('\n').split('\t'); rows[c[0]] = c
PRUNE = re.compile(r'\b(corpse|bunny|trigger|dummy|target|orphan|reveler|celebrant|invisible|stalker bunny|\[dn[dt]\]|training|projection|event|worker|guard|citizen|villager|peasant)\b', re.I)
for z in [a for a in sys.argv[1:] if not a.startswith('--')]:
    r = rows.get(z)
    if not r: print('REFUSED %s: not in zone_ranges.tsv' % z); continue
    zone, zid, mp, x1, x2, y1, y2, mx, lo, hi, mn, mxm, name, source = r[:14]
    status = r[14] if len(r) > 14 else ''
    if status.strip() and not status.lower().startswith(('ready', 'done')) and '--force' not in sys.argv: print('REFUSED %s: status is %r (review it, then use --force)' % (z, status[:60])); continue
    if not source.strip() or source.strip() in ('-', '?'): print('REFUSED %s: no source for the pet range' % z); continue
    if '[%s] = {' % zid in open('scripts/pb_data.lua').read().split('D.zones = {')[1].split('\n}')[0]: print('SKIP %s: zone id %s already in D.zones' % (z, zid)); continue
    if '-' in (x1, x2, y1, y2): print('REFUSED %s: no coordinate box yet' % z); continue
    print('== %s (%s) range %s-%s source: %s' % (z, name, lo, hi, source))
    subprocess.run(['python3', '-I', 'pet-battle/gen_zone.py', zone, mp, x1, x2, y1, y2, mx], check=True)
    out = []
    for l in open('pet-battle/%s_roster.tsv' % zone, encoding='utf-8'):   # prune event/NPC-like names
        c = l.rstrip('\n').split('\t')
        if len(c) > 11 and c[0] == 'Y' and PRUNE.search(c[2]) and 'already a species' not in c[11]: c[0] = 'N'; c[11] = 'excluded (zone_batch prune: event/NPC-like name)'
        out.append('\t'.join(c) + '\n')
    open('pet-battle/%s_roster.tsv' % zone, 'w', encoding='utf-8').writelines(out)
    subprocess.run(['python3', '-I', 'pet-battle/auto_picks.py', zone], check=True)
    subprocess.run(['python3', '-I', 'pet-battle/apply_zone.py', zone, zid, lo, hi, mn, mxm, name], check=True)
    print('applied %s: now run_tests / sim_balance / auto_repick' % z)
