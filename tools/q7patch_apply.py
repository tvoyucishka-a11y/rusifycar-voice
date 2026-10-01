import struct, hashlib, sys
def apply(old, patch, out):
    o = open(old,'rb'); p = open(patch,'rb'); w = open(out,'wb')
    assert p.read(8) == b'Q7PATCH1'
    osz, = struct.unpack('<Q', p.read(8)); osha = p.read(32).hex()
    nsz, = struct.unpack('<Q', p.read(8)); nsha = p.read(32).hex()
    n, = struct.unpack('<I', p.read(4))
    for _ in range(n):
        t = p.read(1)
        if t == b'C':
            off, ln = struct.unpack('<QQ', p.read(16)); o.seek(off)
            while ln:
                b = o.read(min(ln, 1<<22)); w.write(b); ln -= len(b)
        elif t == b'L':
            ln, = struct.unpack('<Q', p.read(8))
            while ln:
                b = p.read(min(ln, 1<<22)); w.write(b); ln -= len(b)
        else: raise Exception('bad op')
    w.close()
    return osha, nsha
if __name__ == '__main__':
    print(apply(*sys.argv[1:4]))
