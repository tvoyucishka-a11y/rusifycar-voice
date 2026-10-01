import zipfile, struct, sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
an={i.filename:i for i in a.infolist()}; bn={i.filename:i for i in b.infolist()}
print('only old:', sorted(set(an)-set(bn)), 'only new:', sorted(set(bn)-set(an)))
print('changed:', [n for n in an if n in bn and (an[n].CRC!=bn[n].CRC or an[n].file_size!=bn[n].file_size or an[n].compress_type!=bn[n].compress_type)])
f=open(sys.argv[2],'rb'); bad=0
for i in b.infolist():
    if i.compress_type==0:
        f.seek(i.header_offset); h=f.read(30); n,e=struct.unpack('<HH',h[26:30]); off=i.header_offset+30+n+e
        if off % (4096 if i.filename.endswith('.so') else 4): bad+=1
print('misaligned stored:', bad, '| testzip:', b.testzip())
