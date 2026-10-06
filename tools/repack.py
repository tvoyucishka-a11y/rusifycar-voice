"""Copy an APK entry-by-entry (raw, no recompression), replace one entry, drop old signature,
keep 4-byte alignment for stored entries and 4096 for stored .so files."""
import sys, struct, zipfile, zlib

def main(src, dst, entry, newfile):
    zin = zipfile.ZipFile(src)
    f = open(src, 'rb')
    out = open(dst, 'wb')
    newdata = open(newfile, 'rb').read()
    central = []
    replaced = False
    for info in zin.infolist():
        name = info.filename
        if name.startswith('META-INF/') and name.split('/')[-1].upper().endswith(('.SF', '.RSA', '.DSA', '.EC')) or name == 'META-INF/MANIFEST.MF':
            continue
        f.seek(info.header_offset)
        h = f.read(30)
        sig, ver, flag, method, mtime, mdate, crc, csize, usize, nlen, elen = struct.unpack('<IHHHHHIIIHH', h)
        assert sig == 0x04034b50
        fname = f.read(nlen)
        f.read(elen)
        if name == entry:
            data = zlib.compressobj(9, zlib.DEFLATED, -15)
            comp = data.compress(newdata) + data.flush()
            method, crc, csize, usize = 8, zlib.crc32(newdata) & 0xffffffff, len(comp), len(newdata)
            raw = comp
            flag &= ~0x08
            replaced = True
        else:
            raw = f.read(info.compress_size)
            crc, csize, usize = info.CRC, info.compress_size, info.file_size
            flag &= ~0x08  # sizes are in the local header now
        off = out.tell()
        extra = b''
        if method == 0:
            align = 4096 if name.endswith('.so') else 4
            pad = (-(off + 30 + len(fname))) % align
            if pad:
                # 0xD935 = Android zipalign extra field id
                while pad < 6:
                    pad += align
                extra = struct.pack('<HHH', 0xD935, pad - 4, align) + b'\0' * (pad - 6)
        out.write(struct.pack('<IHHHHHIIIHH', 0x04034b50, ver, flag, method, mtime, mdate, crc, csize, usize, len(fname), len(extra)))
        out.write(fname)
        out.write(extra)
        out.write(raw)
        central.append((info, fname, flag, method, mtime, mdate, crc, csize, usize, off))
    assert replaced, 'entry not found: ' + entry
    cd = out.tell()
    for info, fname, flag, method, mtime, mdate, crc, csize, usize, off in central:
        out.write(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, info.create_version | (info.create_system << 8), info.extract_version,
                              flag, method, mtime, mdate, crc, csize, usize, len(fname), 0, 0, 0, info.internal_attr, info.external_attr, off))
        out.write(fname)
    cdsize = out.tell() - cd
    n = len(central)
    out.write(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, n, n, cdsize, cd, 0))
    out.close()
    print('repacked', dst, n, 'entries')

if __name__ == '__main__':
    main(*sys.argv[1:5])
