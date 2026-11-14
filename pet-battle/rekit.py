#!/usr/bin/env python3 -I
"""Change the retail kit of already-added species: python3 -I pet-battle/rekit.py <entry>=<retailId> ...   (edits scripts/pb_data.lua, regenerates pb_retail.lua). Then re-run the balance sweep."""
import re, sys, subprocess
src = open('scripts/pb_data.lua').read()
for a in sys.argv[1:]:
    e, r = a.split('=')
    src, n = re.subn(r'(\[%s\] = \{ name = "[^"]*", retail = )\d+' % e, r'\g<1>%s' % r, src)
    if n != 1: sys.exit('entry %s not found exactly once' % e)
open('scripts/pb_data.lua', 'w').write(src)
import glob
for f in glob.glob('pet-battle/*_picks.tsv'):   # keep the zone picks files in step (they were stale drafts after a re-pick)
    out, ch = [], False
    for l in open(f, encoding='utf-8'):
        c = l.rstrip('\n').split('\t')
        for a in sys.argv[1:]:
            e, r = a.split('=')
            if len(c) >= 3 and c[0] == e and c[1] != r: c[1] = r; ch = True
        out.append('\t'.join(c) + '\n')
    if ch: open(f, 'w', encoding='utf-8').writelines(out)
ids = sorted(set(re.findall(r'retail = (\d+)', src)), key=int)
subprocess.run(['python3', '-I', 'pet-battle/gen_retail.py'] + ids, check=True)
