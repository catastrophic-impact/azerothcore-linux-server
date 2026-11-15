import struct,sys
d=open('release/data/dbc/Spell.dbc','rb').read(); _,c,f,rs,_=struct.unpack('<4sIIII',d[:20]); sb=20+c*rs
dur=open('release/data/dbc/SpellDuration.dbc','rb').read(); _,dc,df,drs,_=struct.unpack('<4sIIII',dur[:20])
D={struct.unpack_from('<%di'%df,dur,20+i*drs)[0]:struct.unpack_from('<%di'%df,dur,20+i*drs)[1] for i in range(dc)}
S={}
for i in range(c):
    r=struct.unpack_from('<%dI'%f,d,20+i*rs)
    nm=d[sb+r[136]:d.index(b'\0',sb+r[136])].decode(errors='replace')
    aura=any(r[95+e] for e in range(3)) or any(r[71+e]==6 for e in range(3))
    S[r[0]]=(nm,aura,D.get(r[40]),r[1],r[2]) # school mask at r[?] unknown
def chk(i):
    if i not in S: return 'MISSING'
    n,a,ms,_,_=S[i]; ok=not a and not ms
    return ('ok ' if ok else 'BAD ')+str(i)+' '+n+' dur=%s aura=%s'%(ms,a)
if __name__=='__main__':
    for a in sys.argv[1:]:
        if a.isdigit(): print(chk(int(a)))
        else:
            for i,(n,*_) in S.items():
                if n.lower()==a.lower(): print(chk(i))
