#!/usr/bin/env python3 -I
"""For every effect of the PLAYER golden list: which mapped spells can dress it (token superset) and how close the spell's real cooldown is to the effect's retail cooldown.
Cooldown buckets (spell seconds -> retail rounds): <=1.5s:0, <=8:1, <=15:2, <=30:3, <=60:4, <=180:5, else 8. Writes pet-battle/effect_spell_candidates.tsv. Run from repo root."""
import re, csv, collections
V = {'damage', 'dot', 'heal', 'hot', 'drain', 'stun', 'noswap', 'speeddown', 'speedup', 'dmgup', 'dmgdown', 'vuln', 'defense', 'dodge', 'block', 'untargetable', 'damageshield', 'cleanse', 'critup',
     'accdown', 'interrupt', 'aoe', 'multihit', 'rebirth', 'stunchance', 'conditional'}
def bucket(ms):
    s = ms / 1000.0
    return 0 if s <= 1.5 else 1 if s <= 8 else 2 if s <= 15 else 3 if s <= 30 else 4 if s <= 60 else 5 if s <= 180 else 8
spells = []
for l in open('pet-battle/spell_effect_map.tsv').read().split('\n')[1:]:
    f = l.split('\t')
    if len(f) > 5: spells.append((f[2], set(f[3].split()), bucket(int(f[5] or 0)), f[4]))
rows = [l.split('\t') for l in open('pet-battle/golden_effects_player.tsv').read().split('\n')[1:] if l]
out = []; gaps = collections.defaultdict(list)
for f in rows:
    toks = set(re.sub(r'-p\d+', '', f[0].split('-cd')[0]).split('-')) & V - {'conditional'}
    if not toks: toks = {'damage'}
    # swap/weather/etc tokens are not spell-expressible here: they are marked by status in the list
    order = [t for t in re.sub(r'-p\d+', '', f[0].split('-cd')[0]).split('-') if t in toks]
    primary = order[0] if order else 'damage'
    cands = [(n, abs(b - int(f[1])), basis, len(toks & t)) for n, t, b, basis in spells if primary in t]
    cands.sort(key=lambda c: (-c[3], c[1], c[0]))
    full = [c for c in cands if c[3] == len(toks)]
    near = [c for c in cands if c[1] <= 1]
    out.append((f[0], f[1], f[4], len(cands), len(full), len(near), '; '.join(c[0] for c in cands[:4])))
    if not cands: gaps[primary].append(f[0])
with open('pet-battle/effect_spell_candidates.tsv', 'w') as fh:
    fh.write('effect\tcooldown\tstatus\tspells_with_primary_effect\tspells_with_all_parts\tspells_within_1_cd_bucket\tbest_4\n')
    for o in out: fh.write('\t'.join(map(str, o)) + '\n')
print('effects', len(out), '| no spell for the primary effect', sum(1 for o in out if o[3] == 0), '| no spell with ALL parts', sum(1 for o in out if o[4] == 0), '| none near the cooldown', sum(1 for o in out if o[5] == 0))
for st, v in gaps.items(): print(st, len(v), v[:40])
