import struct,sys
d=open('release/data/dbc/Spell.dbc','rb').read(); _,c,f,rs,_=struct.unpack('<4sIIII',d[:20]); sb=20+c*rs
def row(i):
    for k in range(c):
        r=struct.unpack_from('<%dI'%f,d,20+k*rs)
        if r[0]==i: return r
fl=lambda x:struct.unpack('<f',struct.pack('<I',x))[0]
ref=row(116); fb=row(133)
cols=[k for k in range(f) if abs(fl(ref[k])-28)<0.01 and abs(fl(fb[k])-24)<0.01]
print('speed column candidates',cols)
col=cols[0] if cols else None
for a in sys.argv[1:]:
    r=row(int(a)); nm=d[sb+r[136]:d.index(b'\0',sb+r[136])].decode()
    bp=[struct.unpack('<i',struct.pack('<I',r[80+e]))[0] for e in range(3)]
    print(a,nm,'speed',fl(r[col]) if col else '?','effects',[r[71+e] for e in range(3)],'bp',bp)
