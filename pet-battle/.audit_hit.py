import struct
d=open('release/data/dbc/Spell.dbc','rb').read(); _,c,f,rs,_=struct.unpack('<4sIIII',d[:20]); sb=20+c*rs
for i in range(c):
    r=struct.unpack_from('<%dI'%f,d,20+i*rs)
    for e in range(3):
        if r[95+e] in (55,) and r[71+e]==6:
            bp=struct.unpack('<i',struct.pack('<I',r[80+e]))[0]
            if bp>=9:
                nm=d[sb+r[136]:d.index(b'\0',sb+r[136])].decode(errors='replace')
                print(r[0],nm,'bp',bp,'dur',r[40],'tgtA',r[86+e],'attr0',hex(r[4]))
