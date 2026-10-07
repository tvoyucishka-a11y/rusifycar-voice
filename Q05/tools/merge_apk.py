"""Build an APK from a base APK plus additions/replacements, copying compressed data raw (no recompression).
Usage: merge_apk.py base.apk out.apk spec.json
spec.json: {"drop_signature": true,
            "files":   {"entry/name": "local/path", ...},              # added/replaced from disk
            "from_apk": [["other.apk", "prefix-or-exact", "stored|deflate|keep"], ...],  # copy entries raw from another APK
            "store":   ["assets/gigaam/", ...]}                         # prefixes forced to STORED when taken from disk
Stored entries are 4-byte aligned (.so: 4096) with the Android zipalign extra field."""
import json, struct, sys, zipfile, zlib

def local_raw(f, info):
    f.seek(info.header_offset)
    h = f.read(30)
    sig, ver, flag, method, mtime, mdate, crc, csize, usize, nlen, elen = struct.unpack('<IHHHHHIIIHH', h)
    assert sig == 0x04034b50
    f.seek(info.header_offset + 30 + nlen + elen)
    return ver, flag, method, mtime, mdate, f.read(info.compress_size)

def main(base, out, specp):
    spec = json.load(open(specp))
    files = spec.get('files', {})
    store = tuple(spec.get('store', []))
    entries = {}   # name -> (kind, payload)
    order = []
    zb = zipfile.ZipFile(base); fb = open(base, 'rb')
    for i in zb.infolist():
        n = i.filename
        if spec.get('drop_signature', True) and (n == 'META-INF/MANIFEST.MF' or (n.startswith('META-INF/') and n.count('/') == 1 and n.upper().endswith(('.SF', '.RSA', '.DSA', '.EC')))):
            continue
        entries[n] = ('raw', (fb, i)); order.append(n)
    for apk, pref, mode in spec.get('from_apk', []):
        z = zipfile.ZipFile(apk); f = open(apk, 'rb'); hit = 0
        for i in z.infolist():
            n = i.filename
            if n == pref or (pref.endswith('/') and n.startswith(pref)):
                if n not in entries: order.append(n)
                entries[n] = ('raw', (f, i)) if mode == 'keep' else ('data', (z.read(i), mode == 'stored', i.date_time))
                hit += 1
        assert hit, 'nothing matched %s in %s' % (pref, apk)
    for n, p in files.items():
        if n not in entries: order.append(n)
        entries[n] = ('data', (open(p, 'rb').read(), n.startswith(store), (2009, 1, 1, 0, 0, 0)))
    o = open(out, 'wb'); central = []
    for n in order:
        kind, pl = entries[n]
        fname = n.encode('utf-8')
        if kind == 'raw':
            f, i = pl
            ver, flag, method, mtime, mdate, raw = local_raw(f, i)
            crc, csize, usize = i.CRC, i.compress_size, i.file_size
            flag &= ~0x08
            cver = i.create_version | (i.create_system << 8); ever = i.extract_version
            iattr, eattr = i.internal_attr, i.external_attr
        else:
            data, stored, dt = pl
            crc, usize = zlib.crc32(data) & 0xffffffff, len(data)
            if stored:
                method, raw = 0, data
            else:
                c = zlib.compressobj(9, zlib.DEFLATED, -15); raw = c.compress(data) + c.flush(); method = 8
            csize = len(raw); flag = 0x800 if any(b > 127 for b in fname) else 0
            mtime = (dt[3] << 11) | (dt[4] << 5) | (dt[5] // 2); mdate = ((dt[0] - 1980) << 9) | (dt[1] << 5) | dt[2]
            ver = ever = 20 if method == 8 else 10; cver = ever; iattr, eattr = 0, 0
        off = o.tell(); extra = b''
        if method == 0:
            align = 4096 if n.endswith('.so') else 4
            pad = (-(off + 30 + len(fname))) % align
            if pad:
                while pad < 6: pad += align
                extra = struct.pack('<HHH', 0xD935, pad - 4, align) + b'\0' * (pad - 6)
        o.write(struct.pack('<IHHHHHIIIHH', 0x04034b50, ver, flag, method, mtime, mdate, crc, csize, usize, len(fname), len(extra)))
        o.write(fname); o.write(extra); o.write(raw)
        central.append((fname, cver, ever, flag, method, mtime, mdate, crc, csize, usize, iattr, eattr, off))
    cd = o.tell()
    for fname, cver, ever, flag, method, mtime, mdate, crc, csize, usize, iattr, eattr, off in central:
        o.write(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, cver, ever, flag, method, mtime, mdate, crc, csize, usize, len(fname), 0, 0, 0, iattr, eattr, off))
        o.write(fname)
    n = len(central)
    assert o.tell() < 0xFFFFFFFF and n < 0xFFFF, 'needs zip64'
    o.write(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, n, n, o.tell() - cd, cd, 0))
    o.close()
    print('merged', out, n, 'entries')

if __name__ == '__main__':
    main(*sys.argv[1:4])
