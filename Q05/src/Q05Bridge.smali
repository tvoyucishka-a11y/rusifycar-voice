.class public Lcom/stand/q05/Q05Bridge;
.super Ljava/lang/Object;
.source "Q05Bridge.java"


# static fields
.field static volatile active:Z

.field static volatile appCtx:Landroid/content/Context;


# direct methods
.method public static init(Landroid/content/Context;)V
    .locals 3

    const-string v0, "Q05Bridge"

    if-nez p0, :cond_0

    return-void

    :cond_0
    :try_start_0
    invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;

    move-result-object v1

    if-eqz v1, :cond_1

    move-object p0, v1

    :cond_1
    sput-object p0, Lcom/stand/q05/Q05Bridge;->appCtx:Landroid/content/Context;

    const/4 v1, 0x1

    sput-boolean v1, Lcom/stand/q07/Extra;->TEST:Z
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :goto_0

    :catch_0
    move-exception v1

    :goto_0
    :try_start_1
    invoke-static {p0}, Lcom/stand/q07/Q07Bridge;->init(Landroid/content/Context;)V

    const-string v1, "init: GigaAM + TeraTTS ready (Q05)"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_1
    .catch Ljava/lang/Throwable; {:try_start_1 .. :try_end_1} :catch_1

    goto :goto_1

    :catch_1
    move-exception v1

    const-string v2, "init"

    invoke-static {v0, v2, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :goto_1
    return-void
.end method

.method public static onVrReady(Z)V
    .locals 1

    const-string v0, "Q05Bridge"

    const-string p0, "VFramework ready"

    invoke-static {v0, p0}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method

.method public static feedSE([B)V
    .locals 1

    :try_start_0
    invoke-static {p0}, Lcom/stand/q05/Q05Bridge;->feedSE0([B)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :done

    :catch_0
    move-exception v0

    :done
    return-void
.end method

.method private static feedSE0([B)V
    .locals 8

    if-eqz p0, :done

    array-length v1, p0

    if-lez v1, :done

    move-object v0, p0

    const/4 v2, 0x2

    new-array v3, v1, [B

    move v4, v1

    const/4 v6, 0x2

    new-array v5, v6, [I

    invoke-static/range {v0 .. v5}, Lcom/iflytek/speech/LibISSSE2;->extractAudio([BII[BI[I)I

    move-result v6

    if-nez v6, :done

    const/4 v7, 0x0

    aget v6, v5, v7

    if-lez v6, :done

    new-array v7, v6, [B

    const/4 v0, 0x0

    invoke-static {v3, v0, v7, v0, v6}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V

    invoke-static {v7}, Lcom/stand/q07/Q07Bridge;->feedMono([B)V

    :done
    return-void
.end method

.method public static onListen(Ljava/lang/String;)V
    .locals 2

    const/4 v0, 0x1

    sput-boolean v0, Lcom/stand/q05/Q05Bridge;->active:Z

    const-string v0, "Q05Bridge"

    const-string v1, "listen start"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :try_start_0
    const/4 v0, 0x0

    invoke-static {v0}, Lcom/stand/q07/Q07Bridge;->onSpeechStart(Ljava/lang/Object;)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :done

    :catch_0
    move-exception v0

    :done
    return-void
.end method

.method public static onSleep()V
    .locals 1

    const/4 v0, 0x0

    sput-boolean v0, Lcom/stand/q05/Q05Bridge;->active:Z

    :try_start_0
    invoke-static {}, Lcom/stand/q07/Q07Bridge;->onSpeechEnd()V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :goto_0

    :catch_0
    move-exception v0

    :goto_0
    return-void
.end method

.method public static inject(Ljava/lang/String;)V
    .locals 4

    const-string v0, "Q05Bridge"

    if-eqz p0, :done

    :try_start_0
    invoke-static {}, Lcom/tinnove/wecarspeech/vframework/VFramework;->getInstance()Lcom/tinnove/wecarspeech/vframework/VFramework;

    move-result-object v1

    new-instance v2, Lcom/tinnove/vrcommon/app/LaunchParams$Builder;

    const/4 v3, 0x0

    invoke-direct {v2, v3}, Lcom/tinnove/vrcommon/app/LaunchParams$Builder;-><init>(I)V

    invoke-virtual {v2}, Lcom/tinnove/vrcommon/app/LaunchParams$Builder;->build()Lcom/tinnove/vrcommon/app/LaunchParams;

    move-result-object v2

    invoke-virtual {v1, p0, v2, v3}, Lcom/tinnove/wecarspeech/vframework/VFramework;->startSrByText(Ljava/lang/String;Lcom/tinnove/vrcommon/app/LaunchParams;Lcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "injectZh -> startSrByText: "

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    goto :done

    :catch_0
    move-exception v1

    const-string v2, "inject"

    invoke-static {v0, v2, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :done
    return-void
.end method

.method public static dropFinal(Z)Z
    .locals 1

    sget-boolean v0, Lcom/stand/q05/Q05Bridge;->active:Z

    if-nez v0, :cond_0

    const/4 v0, 0x0

    return v0

    :cond_0
    if-eqz p0, :cond_1

    const/4 v0, 0x0

    return v0

    :cond_1
    const/4 v0, 0x1

    return v0
.end method

.method public static dropTmp()Z
    .locals 1

    sget-boolean v0, Lcom/stand/q05/Q05Bridge;->active:Z

    return v0
.end method
