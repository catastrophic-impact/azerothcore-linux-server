import struct,sys
def load(p):
    d=open(p,'rb').read(); _,c,f,rs,sz=struct.unpack('<4sIIII',d[:20]); return d,c,f,rs
d,c,f,rs=load('release/data/dbc/Spell.dbc'); sb=20+c*rs
vd,vc,vf,vrs=load('release/data/dbc/SpellVisual.dbc')
V={}
for i in range(vc):
    r=struct.unpack_from('<%dI'%vf,vd,20+i*vrs); V[r[0]]=r
S={}
for i in range(c):
    r=struct.unpack_from('<%dI'%f,d,20+i*rs); S[r[0]]=(d[sb+r[136]:d.index(b'\0',sb+r[136])].decode(errors='replace'),r[131])
for a in sys.argv[1:]:
    n,v=S[int(a)]; r=V.get(v)
    print(a,n,'visual',v,'precast',r[1],'cast',r[2],'impact',r[3],'state',r[4],'statedone',r[5],'channel',r[6],'missile',r[8])
