.class public Lcom/stand/q05/RuIssTts;
.super Ljava/lang/Object;
.source "RuIssTts.java"

# Drop-in replacement for com.iflytek.speech.libisstts inside l7.b (IflytekTTSEngine).
# Receives the Chinese reply text, maps it to Russian (Q07Bridge.ttsTextToRu) and
# synthesizes 24 kHz mono s16 PCM with TeraTTS; the stock write thread + AudioTrack play it.


# static fields
.field static volatile buf:[B

.field static volatile lsn:Lcom/iflytek/speech/tts/ITtsListener;

.field static volatile pos:I


# direct methods
.method public static appendText(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;I)I
    .locals 1

    invoke-static {p0, p1}, Lcom/stand/q05/RuIssTts;->start(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;)I

    move-result v0

    return v0
.end method

.method public static create(Lcom/iflytek/speech/NativeHandle;Lcom/iflytek/speech/tts/ITtsListener;)I
    .locals 2

    sput-object p1, Lcom/stand/q05/RuIssTts;->lsn:Lcom/iflytek/speech/tts/ITtsListener;

    const-wide/16 v0, 0x1

    iput-wide v0, p0, Lcom/iflytek/speech/NativeHandle;->native_point:J

    const/4 v0, 0x0

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v0
.end method

.method public static destroy(Lcom/iflytek/speech/NativeHandle;)I
    .locals 1

    const/4 v0, 0x0

    sput-object v0, Lcom/stand/q05/RuIssTts;->buf:[B

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v0
.end method

.method public static getAudioData(Lcom/iflytek/speech/NativeHandle;[BI[I)I
    .locals 6

    const/4 v1, 0x0

    sget-object v0, Lcom/stand/q05/RuIssTts;->buf:[B

    if-eqz v0, :drained

    sget v2, Lcom/stand/q05/RuIssTts;->pos:I

    array-length v3, v0

    sub-int v4, v3, v2

    if-lez v4, :drained

    move v5, p2

    if-le v5, v4, :haven

    move v5, v4

    :haven
    invoke-static {v0, v2, p1, v1, v5}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    add-int/2addr v2, v5

    sput v2, Lcom/stand/q05/RuIssTts;->pos:I

    aput v5, p3, v1

    iput v1, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v1

    :drained
    const/16 v2, 0x2714

    iput v2, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    aput v1, p3, v1

    return v2
.end method

.method public static initRes(Ljava/lang/String;I)I
    .locals 1

    const/4 v0, 0x0

    return v0
.end method

.method public static setLogCfgParam(ILjava/lang/String;)I
    .locals 1

    const/4 v0, 0x0

    return v0
.end method

.method public static setMachineCode(Ljava/lang/String;)I
    .locals 1

    const/4 v0, 0x0

    return v0
.end method

.method public static setParam(Lcom/iflytek/speech/NativeHandle;II)I
    .locals 1

    const/4 v0, 0x0

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v0
.end method

.method public static setParamEx(Lcom/iflytek/speech/NativeHandle;ILjava/lang/String;)I
    .locals 1

    const/4 v0, 0x0

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v0
.end method

.method public static start(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;)I
    .locals 5

    const/4 v0, 0x0

    :try_start_0
    invoke-static {p1}, Lcom/stand/q07/Q07Bridge;->ttsTextToRu(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    if-eqz v1, :empty

    invoke-virtual {v1}, Ljava/lang/String;->isEmpty()Z

    move-result v2

    if-nez v2, :empty

    const v2, 0x5dc0

    invoke-static {v1, v2}, Lcom/stand/tts/TeraTts;->synthPcm16(Ljava/lang/String;I)[B

    move-result-object v3

    goto :store

    :empty
    new-array v3, v0, [B

    :store
    sput-object v3, Lcom/stand/q05/RuIssTts;->buf:[B

    sput v0, Lcom/stand/q05/RuIssTts;->pos:I

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    sget-object v1, Lcom/stand/q05/RuIssTts;->lsn:Lcom/iflytek/speech/tts/ITtsListener;

    if-eqz v1, :done

    const/16 v2, 0x4e20

    const-string v4, ""

    invoke-interface {v1, v2, v0, v4}, Lcom/iflytek/speech/tts/ITtsListener;->onTtsMsgProc(IILjava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :done
    goto :ret

    :catch_0
    move-exception v1

    :ret
    return v0
.end method

.method public static stop(Lcom/iflytek/speech/NativeHandle;)I
    .locals 1

    const/4 v0, 0x0

    sput-object v0, Lcom/stand/q05/RuIssTts;->buf:[B

    iput v0, p0, Lcom/iflytek/speech/NativeHandle;->err_ret:I

    return v0
.end method

.method public static unInitRes()I
    .locals 1

    const/4 v0, 0x0

    return v0
.end method
