import csv,collections,re
rows=list(csv.DictReader(open('pet-battle/.audit_vis.tsv'),delimiter='\t'))
print(len(rows), collections.Counter(r['source'] for r in rows))
T={'frost':r'frost|ice|icy|snow|freez|chill|blizzard|glacial|cold|hail|winter|rime',
'fire':r'fire|flame|burn|scorch|ember|lava|magma|ignit|inferno|blaze|sear|heat|meteor|cinder|candle|smolder|flare',
'shadow':r'shadow|dark|death|curse|void|drain|siphon|gloom|night|nether|haunt|dread|terror|ghost|spectr|soul',
'nature':r'leaf|thorn|vine|poison|toxic|acid|spore|fung|plague|nature|venom|sting|bloom|root|seed|photosyn|moss|ooze|slime|bile|rot|decay|infect|disease|web',
'arcane':r'arcane|magic|mana|spell|mystic|enchant|nova|surge|power|energy|beam',
'holy':r'holy|light|radian|smite|sunfire|sun|bless|divine|heal|prayer|sacred',
'lightning':r'lightning|thunder|shock|storm|static|zap|spark|volt|charge|bolt',
'water':r'water|wave|spray|tide|geyser|rain|splash|bubble|squirt|surf|torrent|drown|ink|mud',
'earth':r'rock|stone|boulder|quake|crystal|sand|dust|earth|pebble|gravel|rubble|burrow|landslide',
'wind':r'wind|gust|tornado|cyclone|breeze|whirl|gale|flutter|swoop|screech',
'phys':r'bite|claw|scratch|rake|pounce|maul|slam|punch|headbutt|gore|hoof|bash|crush|smash|stomp|tail|kick|sting|swipe|slash|cut|stab|whack|swing|tackle|charge|ram|peck|snap|lash|trample|clobber|jab|flank|thrash|mangle|rampage|flurry|devour|takedown'}
def theme(n):
    n=n.lower(); 
    for t in T:
        if re.search(T[t],n): return t
    return None
def icontheme(i):
    i=i.lower()
    for k,t in [('frost','frost'),('ice','frost'),('fire','fire'),('shadow','shadow'),('death','shadow'),('nature','nature'),('poison','nature'),('arcane','arcane'),('holy','holy'),('lightning','lightning'),('thunder','lightning'),('water','water'),('earth','earth'),('rock','earth'),('wind','wind')]:
        if k in i: return t
    return None
# vis themes by spell id (known)
VT={133:'fire',2948:'fire',116:'frost',403:'lightning',17253:'phys',16827:'phys',35290:'phys',49966:'phys',1752:'phys'}
fb=collections.defaultdict(set)
for r in rows:
    if r['source']=='FALLBACK': fb[(r['display'],r['vis'])].add(r['species'])
print('FALLBACK distinct',len(fb), sum(1 for r in rows if r['source']=='FALLBACK'))
mm=collections.defaultdict(lambda: [set(),None,None,None])
imm=collections.defaultdict(lambda: [set(),None,None])
for r in rows:
    t=theme(r['display']); v=VT.get(int(r['vis']) if r['vis'] else 0)
    if t and t!='phys' and r['vis'] and v!=t:
        e=mm[(r['display'],t,r['vis'],r['source'])]; e[0].add(r['species'])
    it=icontheme(r['icon'])
    if t and it and it!=t and t!='phys':
        imm[(r['display'],t,r['icon'])][0].add(r['species'])
bt=collections.Counter(); 
for k,v in mm.items(): bt[k[1]]+=len(v[0])
print('vis mismatch by theme (species-ability rows)',bt, 'distinct names',len({k[0] for k in mm}))
for k,v in sorted(mm.items()): print('V',k[0],k[1],k[2],k[3],len(v[0]),sep='|')
print('ICON mismatches',len(imm))
for k,v in sorted(imm.items()): print('I',k[0],k[1],k[2],len(v[0]),sep='|')
# vis used by non-phys melee on abilities with themed names but vis none
print('vis none themed damaging: n/a')
print(collections.Counter(r['vis'] for r in rows))
