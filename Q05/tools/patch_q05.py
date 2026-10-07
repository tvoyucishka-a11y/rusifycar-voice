#!/usr/bin/env python3
"""Apply the Q05 port hooks to the baksmali'd Q05 app and the mod dex."""
import io, re, sys

MOD = sys.argv[1]   # .../m10/sm/smali_classes7
Q05 = sys.argv[2]   # .../q05x/smq05

def rd(p): return io.open(p, encoding='utf-8').read()
def wr(p, s): io.open(p, 'w', encoding='utf-8').write(s); print("patched", p)

def insert_after_locals(path, method_sig, inject):
    s = rd(path)
    i = s.index(method_sig)
    # find the .locals or .registers line after the method start
    m = re.search(r'\n(\s*\.(?:locals|registers)\s+\d+)\n', s[i:])
    assert m, "no .locals in " + method_sig
    at = i + m.end()
    s = s[:at] + inject + s[at:]
    wr(path, s)

def insert_after_text(path, anchor, inject, occurrence=1):
    s = rd(path)
    idx = -1
    for _ in range(occurrence):
        idx = s.index(anchor, idx + 1)
    # end of the anchor line
    at = s.index('\n', idx) + 1
    s = s[:at] + inject + s[at:]
    wr(path, s)

def replace_method(path, start_sig, new_body):
    s = rd(path)
    i = s.index(start_sig)
    j = s.index('.end method', i) + len('.end method')
    s = s[:i] + new_body.strip() + '\n' + s[j+1:]
    wr(path, s)

# 0. mod: injectZh -> Q05Bridge.inject
replace_method(MOD + '/com/stand/q07/Q07Bridge.smali',
    '.method public static injectZh(Ljava/lang/String;)V',
    '''.method public static injectZh(Ljava/lang/String;)V
    .locals 0

    invoke-static {p0}, Lcom/stand/q05/Q05Bridge;->inject(Ljava/lang/String;)V

    return-void
.end method''')

# 1. init
insert_after_text(Q05 + '/smali_classes2/com/tinnove/wecarspeech/app/VrAppEntry.smali',
    'if-eqz p0, :cond_0',
    '\n    invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->init(Landroid/content/Context;)V\n')

# 3. audio tap: after SE process()
insert_after_text(Q05 + '/smali_classes2/com/tinnove/wecarspeech/speechengine/engine/engineofiflytek/IflytekEngine$h.smali',
    'Lcom/iflytek/speech/se2/IISeEngine;->process([B[B[I)I',
    '\n    invoke-static {v7}, Lcom/stand/q05/Q05Bridge;->feedSE([B)V\n')

# 4/5. listen start / sleep
bpath = Q05 + '/smali_classes3/com/tinnove/wecarspeech/vframework/session/b.smali'
insert_after_locals(bpath, '.method public F(Ljava/lang/String;)I',
    '\n    invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onListen(Ljava/lang/String;)V\n')
insert_after_locals(bpath, '.method public G()I',
    '\n    invoke-static {}, Lcom/stand/q05/Q05Bridge;->onSleep()V\n')

# 6. drop stock Chinese voice results
apath = Q05 + '/smali_classes2/com/tinnove/wecarspeech/speechengine/engine/engineofiflytek/ability/IflytekAsrEngine.smali'
insert_after_locals(apath, '.method private onFinalResult(ILjava/lang/String;ZZZZLjava/lang/String;)V',
    '''
    invoke-static {p6}, Lcom/stand/q05/Q05Bridge;->dropFinal(Z)Z

    move-result v0

    if-eqz v0, :stand_ok_f

    return-void

    :stand_ok_f
''')
insert_after_locals(apath, '.method private onTmpResult(ILjava/lang/String;ZZLjava/lang/String;ZI)V',
    '''
    invoke-static {}, Lcom/stand/q05/Q05Bridge;->dropTmp()Z

    move-result v0

    if-eqz v0, :stand_ok_t

    return-void

    :stand_ok_t
''')

# 7. TTS: retarget every libisstts call in l7.b to RuIssTts
lpath = Q05 + '/smali_classes2/l7/b.smali'
s = rd(lpath)
n = s.count('Lcom/iflytek/speech/libisstts;->')
s = s.replace('Lcom/iflytek/speech/libisstts;->', 'Lcom/stand/q05/RuIssTts;->')
wr(lpath, s)
print("retargeted libisstts calls:", n)
print("ALL PATCHES DONE")
