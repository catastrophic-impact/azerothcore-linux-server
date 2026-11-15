import struct,sys
def load(p):
    d=open(p,'rb').read(); _,c,f,rs,sz=struct.unpack('<4sIIII',d[:20]); return d,c,f,rs,20+c*rs
d,c,f,rs,sb=load('release/data/dbc/Spell.dbc')
vd,vc,vf,vrs,vsb=load('release/data/dbc/SpellVisual.dbc')
V={}
for i in range(vc):
    r=struct.unpack_from('<%dI'%vf,vd,20+i*vrs); V[r[0]]=r
S={}
for i in range(c):
    r=struct.unpack_from('<%dI'%f,d,20+i*rs)
    S[r[0]]=(d[sb+r[136]:d.index(b'\0',sb+r[136])].decode(errors='replace'),r[131],r[22],r[21])
for a in sys.argv[1:]:
    i=int(a); n,vis,speed_idx,_=S.get(i,('MISSING',0,0,0))
    v=V.get(vis); 
    print(i,n,'visual',vis,'hasMissile',v[7] if v else None,'missileModel',v[8] if v else None)
