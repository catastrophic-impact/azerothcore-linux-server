#!/usr/bin/env python3 -I
"""Collects the user's lab answers (release/logs/pb_abilab.tsv) into pet-battle/ability_visuals.tsv: per ability the ACCEPTED spell (the latest 'y'),
what was rejected and why (the user's comments), and abilities not looked at yet. Re-run after every lab batch. usage: python3 -I pet-battle/lab_accept.py"""
import re, collections
rows = [l.rstrip('\n').split('\t') for l in open('release/logs/pb_abilab.tsv') if l.strip()]
acc, rej, name = {}, collections.defaultdict(list), {}
for r in rows:
    t, aid, nm, cand, ans = r[:5]; note = r[5] if len(r) > 5 else ''
    name[aid] = nm
    if ans == 'y': acc[aid] = (cand, note)
    else: rej[aid].append('%s: %s' % (cand, note or 'no'))
# answers the user gave in words, or that follow from an accepted one (NOT shown again in the lab)
OVERRIDE = {'124': ('Rampage=25744', 'user: approved ("does it just do the same thing every round? Okay"): a 3-round ability, the same hit each round, as in retail'),
            '247': ('Hibernate#3=2637 [mode aura]', 'by analogy with Emerald Dream (the zzz applied as an aura on the pet itself, user y); user: stop wasting time on it')}
OVERRIDE.update({
  '228': ('Kick=1766 [melee run-up]', 'user (stop guessing): the mob runs up to the other and does Kick. The creature Tongue Lash landed (hp 1000->340) but has no hit visual; Lash of Pain did not land'),
  '312': ('Dodge=62951', 'buff effect good (user); the rabbit ran away only because the lab made it hostile without holding it in place - fixed in the lab, to be handled the same way in battles'),
  '339': ('Sticky Web=50295', 'effect good (user: yes); the Forest Spider is HUGE: pet-size rule gives it scale 1.45, user decision pending')})
for k, v in OVERRIDE.items(): acc[k] = v
# the lab queue order (what is still unseen)
data = open('pet-battle/lab/pb_abilab_data.lua').read()
queue = [(m.group(1), m.group(2)) for m in re.finditer(r'\{id = (\d+), name = "([^"]*)"', data)]
out = ['abilityId\tability\tstatus\taccepted(label=spell)\tnote\trejected']
for aid, nm in queue:
    if aid in acc: out.append('\t'.join([aid, nm, 'ACCEPTED', acc[aid][0], acc[aid][1], ' | '.join(rej.get(aid, []))]))
    elif aid in rej: out.append('\t'.join([aid, nm, 'ALL REJECTED', '', '', ' | '.join(rej[aid])]))
    else: out.append('\t'.join([aid, nm, 'not seen', '', '', '']))
open('pet-battle/ability_visuals.tsv', 'w').write('\n'.join(out) + '\n')
c = collections.Counter(l.split('\t')[2] for l in out[1:]); print(dict(c))
