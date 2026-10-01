"""Make a Q7PATCH1 (old.apk + patch -> new.apk). Entry data identical to the old APK is copied (C),
everything else is stored literally (L)."""
import sys, struct, zipfile, hashlib

def entries(path):
    z = zipfile.ZipFile(path); f = open(path, 'rb'); res = {}
    for i in z.infolist():
        f.seek(i.header_offset); h = f.read(30); n, e = struct.unpack('<HH', h[26:30])
        res[i.filename] = (i.header_offset + 30 + n + e, i.compress_size, i.CRC, i.compress_type)
    return res

def main(old, new, out):
    o = entries(old); nw = entries(new)
    fo = open(old, 'rb'); fn = open(new, 'rb')
    copies = []
    for name, (off, size, crc, ct) in nw.items():
        if name in o and size > 64:
            ooff, osize, ocrc, oct = o[name]
            if osize == size and ocrc == crc and oct == ct:
                copies.append((off, ooff, size))
    copies.sort()
    newsize = fn.seek(0, 2)
    ops = []; pos = 0
    for off, ooff, size in copies:
        if off > pos: ops.append(('L', pos, off - pos))
        ops.append(('C', ooff, size)); pos = off + size
    if pos < newsize: ops.append(('L', pos, newsize - pos))
    sha = lambda p: hashlib.sha256(open(p, 'rb').read()).digest()
    oldsize = fo.seek(0, 2)
    w = open(out, 'wb')
    w.write(b'Q7PATCH1'); w.write(struct.pack('<Q', oldsize)); w.write(sha(old))
    w.write(struct.pack('<Q', newsize)); w.write(sha(new)); w.write(struct.pack('<I', len(ops)))
    lit = 0
    for t, a, b in ops:
        if t == 'C':
            w.write(b'C' + struct.pack('<QQ', a, b))
        else:
            fn.seek(a); w.write(b'L' + struct.pack('<Q', b)); w.write(fn.read(b)); lit += b
    w.close()
    print(out, 'ops', len(ops), 'literal bytes', lit)

main(*sys.argv[1:4])
