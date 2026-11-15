import sys,re,pickle,collections,csv
sys.path.insert(0,'pet-battle')
S='/tmp/claude-1000/-home-deck-Dev-vscode-azerothcore-portable-azerothcore-linux-server/33e7e193-b534-45fd-a11a-f789a7ec9638/scratchpad/cat.pkl'
sp,rs,bn=pickle.load(open(S,'rb'))
D=set(re.findall(r'^\s*\[(\d+)\] = \{ name = "[^"]*", retail',open('scripts/pb_data.lua').read(),re.M))
rows=[l.rstrip('\n').split('\t') for l in open('pet-battle/.companion_raw.tsv')]
C=collections.OrderedDict()
for r in rows:
    c=C.setdefault(r[1],dict(name=r[2],spells=[],type=r[3],ai=r[5],script=r[6],npcflag=r[7],disp=r[8]))
    c['spells'].append(r[0])
# manual: companion name -> (retail id, confidence, why)
M={
'Netherwing Whelp':(131,'close','Netherwhelp'),'Black Tabby Cat':(42,'exact',''),'Siamese Cat':(44,'exact',''),
'Cockatoo':(403,'close','Parrot kit'),'Blood Parrot':(403,'close','Parrot kit'),'Prairie Chicken':(646,'close','Chicken kit'),'White Plymouth Rock':(646,'close','Chicken kit'),
'Dark Whelpling':(56,'exact','in R.species (pinned)'),'Crimson Whelpling':(56,'close','no retail Crimson; Dark Whelpling kit'),'Onyxian Whelpling':(57,'close','Azure kit; or 1153 Death Talon Whelpguard'),'Celestial Dragon':(57,'guess','dragon kit'),
'Faeling':(557,'guess','Nether Faerie Dragon (Dragonkin); alt 1323 Ashleaf Spriteling'),
'Dart Frog':(4665,'close','Yellow Tropical Frog'),'Island Frog':(4666,'close','Tropical Frog'),
'Eagle Owl':(68,'close','Great Horned Owl'),
'Cottontail Rabbit':(378,'close','Rabbit'),'Spotted Rabbit':(378,'close','Rabbit'),
'Blue Racer':(387,'close','Snake'),'Scarlet Snake':(387,'close','Snake'),'Ribbon Snake':(387,'close','Snake'),'Green Water Snake':(418,'close','Water Snake'),
'Crimson Serpent':(78,'guess','Crimson Snake (Beast) - gem serpents are Dragonkin/Magic at retail'),'Ruby Serpent':(78,'guess','Crimson Snake'),'Living Ruby Serpent':(78,'guess','Crimson Snake'),'Deep Twilight Serpent':(387,'guess','Snake'),
'Elven Wisp':(547,'close','Nordrassil Wisp'),'Lil\' Smoky':(86,'exact','in R.species'),
'Corrupted Kitten':(46,'close','White Kitten'),'Mini Diablo':(1229,'guess','Fiendish Imp; retail Mini Diablo family unverified'),'Zergling':(465,'guess','Ravager Hatchling (Beast)'),
'Ar\'lia':(1725,'guess','unknown creature; verify in-game (Grumpling Humanoid placeholder)'),
'Human Orphan':(1166,'guess','Humanoid child; Kun-Lai Runt kit'),'Orcish Orphan':(1166,'guess','Humanoid child'),'Blood Elf Orphan':(1166,'guess','Humanoid child'),'Draenei Orphan':(1166,'guess','Humanoid child'),'Wolvar Orphan':(1166,'guess','Humanoid child'),'Oracle Orphan':(1166,'guess','Humanoid child'),'Alliance Deserter':(1803,'guess','Humanoid; Thistleleaf Adventurer'),
'Argent Squire':(1803,'guess','Humanoid'),'Argent Gruntling':(1803,'guess','Humanoid'),
'Loggerhead Snapjaw':(473,'close','Turquoise Turtle'),'Leatherback Snapjaw':(473,'close','Turquoise Turtle'),'Olive Snapjaw':(473,'close','Turquoise Turtle'),'Hawksbill Snapjaw':(473,'close','Turquoise Turtle'),'Albino Snapjaw':(473,'close','Turquoise Turtle'),'Empyrean Tortoise':(473,'close','Turquoise Turtle'),
'Blue Baby Murloc':(107,'close','Murky (Humanoid murloc)'),'Purple Baby Murloc':(107,'close','Murky'),'Pink Baby Murloc':(107,'close','Murky'),'Green Baby Murloc':(107,'close','Murky'),'Murkimus the Gladiator':(107,'close','Murky'),
'Baby Shark':(1911,'guess','Sting Ray Pup (Aquatic)'),
'Golden Hare':(448,'close','Hare'),'Ruby Hare':(448,'close','Hare'),
'Black Pearl Panther':(240,'close','Onyx Panther (Magic gem cat)'),'Nightseye Panther':(240,'close','Onyx Panther'),'Shadowsong Panther':(240,'close','Onyx Panther'),'White Tiger Cub':(301,'close','Panther Cub'),
'Emerald Owl':(845,'close','Jade Owl (Magic)'),'Sapphire Owl':(845,'close','Jade Owl'),'Talasite Owl':(845,'close','Jade Owl'),
'Black Diamond Crab':(3361,'close','Diamond Crab'),'Dawnstone Crab':(3362,'close','Sapphire Crab'),'Dark Iron Scorpid':(414,'close','Scorpid'),
'Mr. Kitty':(459,'close','Cat'),'Kitty':(459,'close','Cat'),'Manny':(459,'guess','Cat; creature family unknown'),'Mister Manny':(459,'guess','Cat; creature family unknown'),
'Fel Guard Hound':(89,'guess','Worg Pup (Beast); creature type 3 Demon, script npc_fel_guard_hound'),
'Toy RC Mortar Tank':(227,'guess','Warbot (Mechanical)'),'Clockwork Rocket Bot':(277,'close','Clockwork Gnome (Mechanical)'),'Alarming Clockbot':(227,'guess','Warbot'),'XS-001 Constructor Bot':(227,'guess','Warbot'),'Depleted War Golem':(227,'guess','Warbot'),'Lil\' XT':(227,'guess','Warbot (Mechanical)'),'Mini Thor':(227,'guess','Warbot (Mechanical)'),
'Miniwing':(194,'guess','Tickbird Hatchling (Flying)'),'Zeppit':(1761,'guess','Echo Batling (Flying); family unverified'),'Egbert':(646,'guess','Chicken (Flying bird)'),
'Hungry Nether Ray':(186,'close','Nether Ray Fry'),'Nether Ray Desummoner':(186,'close','Nether Ray Fry; two random models'),
'Living Flare':(3411,'guess','Blaze Spirit (Elemental)'),'Scorchling':(3411,'guess','Blaze Spirit (Elemental)'),
'Orphaned Mammoth Calf':(202,'guess','Baby Blizzard Bear (Beast); 4 random models'),'Seaspray Albatross':(534,'guess','Imperial Eagle Chick (Flying)'),
'Lafoo':(459,'guess','Beast placeholder (Sholazar hunter companion), SmartAI'),'Jaloot':(459,'guess','Beast placeholder (gorilla?)'),'Moodle':(459,'guess','Beast placeholder'),
'Goregek the Gorilla Hunter':(1692,'guess','Savage Cub (Beast)'),'Dajik the Wasp Hunter':(1692,'guess','Savage Cub (Beast)'),'Zepik the Gorloc Hunter':(1692,'guess','Savage Cub (Beast)'),
'Coyote Spirit':(89,'guess','Worg Pup (Beast); retail family may be Magic'),'Frosty':(117,'guess','Tiny Snowman (Elemental)'),'Kirin Tor Familiar':(1160,'guess','Arcane Eye (Magic)'),
'Faithful Mule':(434,'close','Ram (Beast)'),'Rented Pack Mule':(434,'close','Ram (Beast)'),
'Mulgore Hatchling':(194,'guess','Tickbird Hatchling (Flying plainstrider)'),'Venomhide Hatchling':(506,'close','Venomspitter Hatchling'),
'Core Hound Pup':(89,'close','Worg Pup'),'Perky Pug':(89,'guess','Worg Pup (Beast dog)'),'Grunty':(228,'exact','in R.species'),'Grunty ':(228,'exact',''),
}
VAN={'Toy RC Mortar Tank':'vanity toy','Enchanted Broom':'vanity object (broom)','Dragon Kite':'vanity object (kite)','Tuskarr Kite':'vanity object (kite)','Macabre Marionette':'vanity object (puppet)','Ghostly Skull':'vanity object (skull)','Sen\'jin Fetish':'vanity object','Sinister Squashling':'event vanity pet','Ethereal Soul-Trader':'NOT a battle pet candidate: vendor beacon (npcflag 129, script npc_pet_gen_soul_trader_beacon, 2 spells -> 1 creature)','Spirit of Competition':'promotional/event','Essence of Competition':'promotional/event','Pet Bombling':'engineering gadget pet','Mr. Chilly':'event vanity','Tiny Snowman':'event vanity','Father Winter\'s Helper':'event','Winter\'s Little Helper':'event','Tranquil Mechanical Yeti':'event','Argent Squire':'vendor/mount-bridle script npc_pet_gen_argent_pony_bridle, npcflag 129 (vendor pet) - exclude or strip flags','Argent Gruntling':'vendor script npc_pet_gen_argent_pony_bridle, npcflag 129 - exclude or strip flags','Mini Tyrael':'promotional','Mini Diablo':'promotional','Zergling':'promotional','Lil\' K.T.':'promotional','Murkimus the Gladiator':'promotional','Lil\' XT':'promotional','Mini Thor':'promotional','Perky Pug':'promotional','Pandaren Monk':'promotional','Celestial Dragon':'promotional','Spirit of Summer':'event'}
out=['creature\tname\tspells\tin_D\tretail_id\tretail_name\tfamily\tconfidence\tneeds_standin\tnotes']
dispcount=collections.Counter(c['disp'] for c in C.values())
cnt=collections.Counter(); stat=collections.Counter()
for e,c in C.items():
    n=c['name']; notes=[]
    inD=e in D
    if inD:
        rid=''; rn=''; fam=''; conf='in_D'
    elif n in M:
        rid,conf,why=M[n]; rid=str(rid)
        if why: notes.append(why)
    else:
        cand=bn.get(n.lower())
        pick=None
        if cand:
            inr=[k for k in cand if k in rs]
            pick=(inr or sorted(cand,key=int))[0]
        rid=pick; conf='exact'
        if rid is None: raise SystemExit('unmatched '+n)
    if not inD:
        assert rid in sp,(n,rid)
        rn,fam=sp[rid]
        if rid not in rs: notes.append('retail kit NOT in pb_retail yet: add id to pet-battle/pinned_species.txt (or gen_retail) and regen')
    needs='Y'  # every D species spawns a 9000000+entry clone
    bad=[]
    if c['type']!='12': bad.append('creature type %s (stand-in forces type 12->1 only if 12; others keep type)'%c['type'])
    if c['ai']: bad.append('AIName '+c['ai'])
    if c['script']: bad.append('ScriptName '+c['script'])
    if c['npcflag']!='0': bad.append('npcflag '+c['npcflag'])
    if bad: notes.append('standin strips: '+'; '.join(bad))
    if ',' in c['disp']: notes.append('multi-model '+c['disp'])
    if dispcount[c['disp']]>1 and not c['disp'].count(','): notes.append('shares display %s with another companion'%c['disp'])
    if n in VAN: notes.append('FLAG: '+VAN[n])
    if len(c['spells'])>1: notes.append('%d spells'%len(c['spells']))
    if not inD: cnt[conf]+=1
    out.append('\t'.join([e,n,','.join(c['spells']),'Y' if inD else 'N',rid or '',rn,fam,conf,needs,' | '.join(notes)]))
open('pet-battle/companion_census.tsv','w').write('\n'.join(out)+'\n')
print(cnt,len(C),sum(1 for e in C if e in D))
