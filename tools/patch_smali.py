"""Smali edits for the mod dex (run inside smali_classes*/com/stand after baksmali).
1) Ru2Zh.ru2zhAll -> ru2zhAll0, new ru2zhAll delegates to com.stand.q07.Fix (pre/post rules)
2) TeraTts.playPcm: AudioTrack is created by Fix.newTrack (voice channel, usage 18) instead of STREAM_MUSIC
CaKey*.smali are replaced by the compiled mod-src/java CaKey; Fix*.smali are added."""
p = 'bridge/Ru2Zh.smali'; s = open(p, encoding='utf-8').read()
old = '.method public static ru2zhAll(Ljava/lang/String;I)[Ljava/lang/String;'
assert s.count(old) == 1
s = s.replace(old, '.method public static ru2zhAll0(Ljava/lang/String;I)[Ljava/lang/String;')
s += '''
.method public static ru2zhAll(Ljava/lang/String;I)[Ljava/lang/String;
    .registers 3

    invoke-static {p0, p1}, Lcom/stand/q07/Fix;->ru2zhAll(Ljava/lang/String;I)[Ljava/lang/String;

    move-result-object v0

    return-object v0
.end method
'''
open(p, 'w', encoding='utf-8').write(s)

p = 'tts/TeraTts.smali'; s = open(p, encoding='utf-8').read()
i = s.index('.method private static declared-synchronized playPcm([BI)V')
a = s.index('    new-instance v10, Landroid/media/AudioTrack;', i)
end = '    invoke-direct/range {v3 .. v9}, Landroid/media/AudioTrack;-><init>(IIIIII)V'
b = s.index(end, a) + len(end)
s = s[:a] + '''    array-length v3, p0

    invoke-static {v1, v3}, Ljava/lang/Math;->max(II)I

    move-result v8

    invoke-static {p1, v8}, Lcom/stand/q07/Fix;->newTrack(II)Landroid/media/AudioTrack;

    move-result-object v10''' + s[b:]
open(p, 'w', encoding='utf-8').write(s)
print('smali patched')
