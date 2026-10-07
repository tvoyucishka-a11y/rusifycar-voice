# Q05 (com.tinnove.wecarspeech, WT_TSpeech 2.5.3.19_beta) – ASR result -> NLU -> execution path, and text injection

KEY = asr_nlu. Everything below was verified against the jadx sources
(`q05x/jx/sources`) and the smali (`q05x/smq05/smali*`), plus the decoded
assets (`q05x/resq05/assets/public/cfg/*.cfg`), the manifest and the arm64 ELFs
in `lib/arm64-v8a`. Where something is not statically certain I say so and name
the runtime log line that would settle it.

Abbreviations:
`S1 = q05x/smq05/smali`, `S2 = q05x/smq05/smali_classes2`, `S3 = q05x/smq05/smali_classes3`,
`J = q05x/jx/sources`.
`IAE = com.tinnove.wecarspeech.speechengine.engine.engineofiflytek.ability.IflytekAsrEngine`.
`IE  = com.tinnove.wecarspeech.speechengine.engine.engineofiflytek.IflytekEngine`.

Logger: `com.tinnove.wecarspeechtools.q` -> `com.tinnove.wecarspeechtools.f` -> `android.util.Log.{d,e,i,v,w}`, tag
`TSpeech_2.5.3.19_beta`, but the master gate `q.b` is `false` by default (`J/com/tinnove/wecarspeechtools/q.java:25`).
`comm.cfg:"logEnabled":true` and `q.m(...)` flip it on at init, so logs DO reach logcat under tag
`TSpeech_2.5.3.19_beta` (each line prefixed with the component tag string). The per-component "TAG" strings quoted
below (e.g. `"IflytekAsrEngine"`, `"SessionManager"`, `"DuplexSessionManagerInner"`, `"TinnoveNluFusion"`,
`"VFrameWkDispatcher"`) appear inside the message text, not as the logcat tag.

---------------------------------------------------------------------------------------------------

## 0. Summary (verdicts first)

* The previous investigation's claim **"text is fed into command processing via VFramework.startAsrByText"** is
  only partly right. `VFramework.startAsrByText(String)` exists and reaches the engine, **but the shipped build
  never calls it from any first-class path** — the only in-app caller is `com.tinnove.vrlogic.server.ExtraService`
  (an **exported** `<service>`, intent extra `"nluStr"`). The engine method `IAE.startAsrByText(String,boolean)`
  **does NOT inject a plain phrase**: it treats the argument as a query for the NLU/cloud-semantic engine
  (`mspSearch`/`localNli`) and returns a *semantic JSON*; it never runs ASR. Verified at
  `J/.../ability/IflytekAsrEngine.java:1421` and smali `S2/.../IflytekAsrEngine.smali:7849`.
* **The real, recommended text-injection point for a Ru2Zh mod is `VFramework.startSrByText(String, LaunchParams, IStartResultCallback)`**
  (`J/com/tinnove/wecarspeech/vframework/VFramework.java:1717`) OR, lower and simpler,
  `VFramework.getSemanticByText(String, lb.a[], cd.k)` (`VFramework.java:838`). Both route the **Chinese query text**
  through `IAE.startAsrByText -> mspSearch/localNli` (iFlytek NLU; cloud if online, local `libiFlyNLI.so` otherwise),
  wrap the resulting semantic JSON, and feed it into the normal session/NLU/dispatch pipeline that executes vehicle
  commands, apps, navigation and media, and shows text + speaks a reply. This is the Q05 analogue of Q07's
  `NluManager.onFinalAsrResult(reqId "stand...", zone, zhText, true)` — except Q05 wants the **Chinese command text**,
  not a finished semantic, and the stock engine does the zh-text->semantic step for you.
* **Confirmed: Q05 TTS is NOT in `l7.b`.** The engine's synthesized/offline reply speech goes through
  `com.tinnove.wecarspeech.vframework.voiceplayer.VoicePlayer` + `libissxtts40.so/libxtts.so`. (`l7.b` is unrelated;
  not pursued here — that is the `tts` KEY's job.)
* **Audio** goes through `IflytekEngine`/`IflytekApartEngine` + `IflytekAsrEngine` as the audio report already
  established; the native SR callback enters Java at
  `IflytekApartEngine$1.onSRMsgProc_ -> mSRMessageHandler.post -> IAE.handleSRMessage(...)` on a dedicated
  `HandlerThread("handleSRMessage_thread")`.
* **Two session managers exist and only one is live at a time**: simplex (`session/simplex/c`) and duplex
  (`session/duplex/d`). With the shipped `comm.cfg` (`voiceRegion:2`, `debugForceEnableDuplex:true`) **duplex is the
  active path** (see §6). The drop hooks and the injection must therefore work in the duplex manager primarily, and
  defensively also in simplex.
* **Best single DROP point (equivalent of Q07 dropFinalAsr/dropCloud/dropArb combined):**
  `IAE.onFinalResult(I Ljava/lang/String; ZZZZ Ljava/lang/String;)V` and `IAE.onTmpResult(...)` in
  `S2/.../ability/IflytekAsrEngine.smali` — these are the two private funnels through which **every** recognized
  result (offline ESR, cloud, PGS/tmp, mm/full-time) leaves the engine toward NLU. Early-returning from them for
  requests that are not ours drops the stock Chinese result without touching the session state machine (they only
  forward to a listener; returning does nothing else). See §3 and §7.
* **How to tag our injected request so the drop filter lets it through:** unlike Q07 there is no `requestId` string
  on this path. Use a boolean latch (static flag set just before you call `startSrByText`/`getSemanticByText`, cleared
  when the injected semantic is dispatched) OR tag the injected semantic JSON with a private key
  (e.g. put `"stand":true` into the semantic/intent JSON you build) and let the drop filter pass any result that
  carries it. Details and the exact register meanings in §7.

---------------------------------------------------------------------------------------------------

## 1. Where native ASR/NLU results enter Java

### 1.1 The single SR-message funnel
Native `libisssr.so` (and `libw_esr*.so`) deliver results through the iFlytek JNI `ISRListener.onSRMsgProc_`.
`IflytekApartEngine` is the active `lb.i` implementation (selected by
`IflytekEngineAbilityFactory` when `enginesdk.cfg:"isNewEngine"` is false — it is absent/false, so **Apart**, not
`IflytekMsEngine`; `J/.../IflytekEngineAbilityFactory.java:40`).

* `J/com/iflytek/speech/IflytekApartEngine.java:57` builds `mSRListener`; `onSRMsgProc_(long,long,String)` posts to
  `mSRMessageHandler` (a `Handler` on `HandlerThread("handleSRMessage_thread")`, started in `initHandler()`), then
  calls `this.mISRListener.a(j10, j11, str, -1)` — i.e. `lb.d.a(JJLjava/lang/String;I)V`.
  Smali: `S1/com/iflytek/speech/IflytekApartEngine$1$1.smali:70` `invoke-interface {v1..v7}, Llb/d;->a(JJLjava/lang/String;I)V`.
* The `lb.d` listener is `IflytekAsrEngine$e` (`new e()` at `IAE.java:238`; `S2/.../ability/IflytekAsrEngine$e.smali`),
  whose `a(JJLjava/lang/String;I)V` calls the bridge `IAE.d(...)` = **`IAE.handleSRMessage(JJLjava/lang/String;I)Z`**.
  Smali: `S2/.../IflytekAsrEngine$e.smali:46` -> `IAE.smali:579` (`bridge synthetic d`) -> `IAE.smali:805`
  (`handleSRMessage`).

So **`IAE.handleSRMessage(JJLjava/lang/String;I)Z`** is the one place every native SR/NLU message arrives.
Thread: `handleSRMessage_thread`. Signature (smali `S2/.../IflytekAsrEngine.smali:805`):
`Lcom/tinnove/wecarspeech/speechengine/engine/engineofiflytek/ability/IflytekAsrEngine;->handleSRMessage(JJLjava/lang/String;I)Z`
with `.locals 22`, `p1:p2 = uMsg (long)`, `p3:p4 = wParam (long)`, `p5 = lParam (String, the JSON/text payload)`,
`p6 = nSRInstIndex (int, sound-zone instance, -1 = none)`.

### 1.2 Message switch (`handleSRMessage`) – what each uMsg means
`J/.../ability/IflytekAsrEngine.java:330-748`. Relevant `uMsg` constants from
`J/com/iflytek/speech/libisssr.java` / `libisssr2.java`:

| uMsg (dec) | const | meaning | leads to |
|---|---|---|---|
| 20005 | ISS_SR_MSG_SpeechStart | VAD speech start | `onStatusUpdate(VOICE_START)` |
| 20007 | ISS_SR_MSG_SpeechEnd | VAD speech end -> recognize | `onStatusUpdate(RECOGNITION_START)` |
| 20055 | ISS_SR_MSG_SRResult | **partial/running ASR text** | `onTmpResult(...)` |
| 22000 | ISS_SR_MSG_LocalPGSFinalResult | **offline PGS final ASR** | `onTmpResult(... true ...)` |
| 22001 | ISS_SR_MSG_CloudPGSFinalResult | **cloud PGS final ASR** | `onTmpResult(... false ...)` |
| 20009 / 20204(NLP) / 90008 | ISS_SR_MSG_Result / NLP | **final semantic (offline NLI / AIUI)** | `handleSemanticData(...)` |
| 20051 / 20052 | ISS_SR_MSG_Cloud/LocalResult | eye-gaze store of cloud/local semantic | `ub.f.d().h(...)` |
| 21064 | ISS_SRMM_MSG_Result | **DMS/multi-mode (full-time) semantic** | `onTmpResult` + `onFinalResult(...,true,true,...)` |
| 21069 | ISS_SRMM_MSG_SRResult | mm ASR text | parsed only |
| 90001/90002/90004 | full-time wake-up semantic | **no-wakeup semantic** | builds `semanticJson`, `onTmpResult`+`onFinalResult` |
| 20008 | ISS_SR_MSG_Error | ASR error | `onStatusUpdate(ASR_ERROR)` (+ CuiAI fallback) |

`handleSemanticData(int uMsg, String semanticJson, int nSRInstIndex[, boolean mm])`
(`IAE.java:751` and `:1673`) parses the semantic JSON, adds `channel`, `mmResult`, vocal-print, etc., then calls
`onTmpResult(...)` (to publish the recognized text) and finally **`onFinalResult(...)`** (to publish the semantic).

### 1.3 Gating flags
`handleSRMessage` first consults `ub.g.a().p()` = `isNewEngine` (false here) for a drop of mis-indexed
messages. The `20009/20204/90008` branch only dispatches when `IAE.isStartASR == true` OR
`com.tinnove.wecarspeech.speechengine.utils.a.b().a()` (eye-saw active) OR `mIsStartIflytekMultiMode`. The
`90001/2/4` branch builds a "noWakeupSemantic" even when `!isStartASR` (full-time path). All of this still ends at
`onFinalResult`/`onTmpResult`, confirming those two are the universal funnels.

---------------------------------------------------------------------------------------------------

## 2. The two result funnels (`onTmpResult`, `onFinalResult`) and the listener boundary

Both are private and simply forward to `mAsrStatusListener` (`mb.a$a`), returning void. Smali
(`S2/.../IflytekAsrEngine.smali`):

```
.method private onFinalResult(ILjava/lang/String;ZZZZLjava/lang/String;)V   # line 4381
    iget-object v0, p0, IAE;->mAsrStatusListener:Lmb/a$a;
    if-nez v0, :cond_0
    return-void
    :cond_0
    invoke-interface/range {v0 .. v7}, Lmb/a$a;->b(ILjava/lang/String;ZZZZLjava/lang/String;)V
    return-void
.end method
.method private onTmpResult(ILjava/lang/String;ZZLjava/lang/String;ZI)V     # line 4429
    ... invoke-interface/range {v0 .. v7}, Lmb/a$a;->c(ILjava/lang/String;ZZLjava/lang/String;ZI)V
```

Parameter meaning of `onFinalResult(I,String,Z,Z,Z,Z,String)` (from `IAE.java` callers):
`p1=channel(int, sound zone)`, `p2=semanticJson(String)`, `p3=isOnline/bislocalresult`, `p4=isVoiceToSemantic(true)`,
`p5=isMmResult(full-time/DMS)`, `p6=isFromTextToNlu(true only on the startAsrByText text path)`, `p7=extra(String)`.

`mb.a$a` (`J/mb/a.java:14`) is implemented by **`IflytekEngine$a`** (`new a()` wired via
`mAsrEngine.init(cfg, mAsrStatusListener)` at `IAE.java:1324`, `IflytekEngine.java` constructor; smali
`S2/.../IflytekEngine.smali:485`). So the result flows:

```
native -> IAE.handleSRMessage -> IAE.onFinalResult/onTmpResult
       -> mb.a$a.b/.c  (= IflytekEngine$a.b / .c)
```

`IflytekEngine$a.c(...)` (onTmpResult handler) calls `IE.arbitrateAsrToSA(...)` then
`mEngineListener.onSpeechResult(channel, text, isFinal, false, isCheck, source)` — this is the **recognized text**
going to the UI/clients.

`IflytekEngine$a.b(...)` (onFinalResult handler, `IflytekEngine.java:414`) runs the "RcError" post-processor:
`new com.tinnove.wecarspeech.speechengine.engine.engineofiflytek.l().e(result, new C0197a(...))`. `l.e` (`J/.../l.java:160`)
inspects `intent.rc` and either calls `bVar.a(semantic)` (normal) or does an HTTP info-source fetch, eventually
`bVar.a(...)`. `C0197a.a(String)` (`IflytekEngine$a$a`, smali `S2/.../IflytekEngine$a$a.smali:289`) is where the
**final semantic** is pushed outward:

* mm/eye-saw branch: `mEngineListener.onSemantic(channel, semantic, isVoiceToSemantic, true, extra)`.
* `!isMmResult`: if `isVoiceToSemantic` -> `mEngineListener.onSemantic(...)`; else
  `mEngineListener.onExtraSemantic(channel, semantic, false, null)`.
* full-time (`isMmResult`): posts `onWakeupResult("深蓝你好", ...)` then `onSemantic(...)`.

`mEngineListener` is wired through `lb.k` ("SpeechResultDecide"): `IflytekEngine.init` is given
`k.h().j()` as the listener (`J/lb/b.java:222-223`), and `k.l(realListener)` stores the session-level listener
(`SessionManager$a`). `lb.k` is a thin forwarder unless `supportMllmModel` (comm config, **absent/false** here) —
so by default `k` passes `onSemantic/onSpeechResult/onExtraSemantic` straight to `SessionManager$a`
(`session/e$a`). (`J/lb/k.java:157-178`).

---------------------------------------------------------------------------------------------------

## 3. Session-manager boundary (`session/e$a` = SessionManager$a) and arbitration

`com.tinnove.wecarspeech.vframework.session.e` is the `IEngineListener` owner (`f7444k = new a()`,
`J/.../session/e.java:97`). Its inner `a` (`session/e$a`, smali `S3/.../session/e$a.smali`) is the hinge between the
engine and the active session manager `e.this.f7437d` (duplex `d` or simplex `c`).

Key methods (smali line refs in `S3/.../session/e$a.smali`):

* `onSpeechResult(ILjava/lang/String;ZZZI)V` (line 746): forwards recognized text to `f7437d.z(...)`; and if
  wake/ASR active and final, calls `e.b0(channel, text, source)` = **`getTinnoveNlu`**, the self-developed rule NLU,
  unless the text was already seen (dedupe via `f7443j` AtomicReference). This is the SECOND NLU engine (iFlytek NLI
  vs. Tinnove rule) — see §4.
* `onSemantic(ILjava/lang/String;ZZLjava/lang/String;)V` (line 631): the main **final-semantic** entry. If
  `f7441h` (Tinnove fusion present) and `z11`(isMmResult/isCheck) -> `f7440g.b(channel,"iflytek",semantic,1)`
  (arbitration, §4); else `f7437d.H(channel, semantic, isOnline, isReject, extra)` -> **dispatch/execute** (§5).
* `onExtraSemantic(ILjava/lang/String;ZLab/a;)I` (line 261): `f7437d.onExtraSemantic(...)` (launches a new session
  that dispatches the semantic).

`e.b0` (`session/e.java:434`, smali `S3/.../session/e.smali:205`) runs the **Tinnove rule engine** `ac.d`
(`f7439f.b(text, callback)`); the callback `e.d0` posts the rule semantic into the same fusion
`f7440g.b(-1, "rule", json, source)`.

### Tinnove NLU fusion / arbitration
`com.tinnove.wecarspeech.vframework.fusion.b` ("TinnoveNluFusion", `J/.../fusion/b.java`, smali
`S3/.../fusion/b.smali`). `b(int channel, String type, String semantic, int source)` collects one result per
engine (`type` in {`iflytek`,`rule`,`tinnove`}); once `nluTypeSet.size()==mEngineSize` it arbitrates by domain
weights (`SemanticArbitrationCfg`) and calls the winner through `a.InterfaceC0206a.a(channel, winnerType, winnerJson)`.
The sink `InterfaceC0206a` is `session/e$c` (`session/e.java:306`): for `"tinnove"` it converts via
`ISemanticConverter`, otherwise calls `f7437d.H(channel, json, true, true, type)`. So **all roads converge on
`session/d.H(...)`** — the per-manager "handleSemantic" — which is the execution entry.

This is the Q05 analogue of Q07's `NluManager.onArbitrationResult` (drop point `dropArb`): the equivalent drop is
inside `fusion.b.b(...)` or at `session/e$a.onSemantic/onSpeechResult` before fusion.

---------------------------------------------------------------------------------------------------

## 4. Which NLU engines exist (iFlytek NLI, cloud, rule) and where they run

* **iFlytek local NLI (EdgeIntent)**: native. `libisssr.so` NEEDS `libiFlyNLI.so`, `libiFlyPResBuild.so`,
  `libcata*.so`, `libSpWord.so` (readelf). Strings in `libisssr.so`: `ISSSRLocalNli`, `ISSSRMspSearch`,
  `CLocalEdgeIntentMgr::Init`, `aiui_nli.cfg`, `Not Enabled Local NLU`. The `libEdgeIntent.so` lib in the APK is the
  edge-intent model engine. Java entry: `IflytekApartEngine.localNli(szText,szScene)` -> `libisssr.localNli(...)`
  (`IflytekApartEngine.java:303`), `mspSearch(szText,szExternParam)` -> `libisssr.mspSearch(...)` (`:344`). These are
  **called from `IAE.startAsrByText`** (the text path, §8) — NOT from the audio path. The audio path gets its
  semantics as `uMsg=20009/20204/90008` messages already decoded by native.
* **Cloud ASR/semantic**: online, selected by `NetworkUtils.isNetworkAvailable`. For the text path, `mspSearch`
  is the cloud semantic query (returns `cbm_semantic`/AIUI JSON); `ub.c` ("AISemanticManager", big-model/CuiAI)
  may rewrite it when `isOpenCuiAI`/`supportMllmModel` set. `enginesdk.cfg` has `isOpenBigModule:true`,
  `isOpenCuiAI:true`, but `supportMllmModel` (comm.cfg) is **absent -> false**, so `lb.k` stays a pass-through
  and `ub.g.x()` depends on `Settings.Global "tinnove_big_module_switch"` (default 1) AND `isOpenBigModule`.
  When `x()` is true, the engine passes results through `ub.c.x(...)` (CuiAI). This matters because our injected
  Chinese command must survive this rewrite (it will — CuiAI only rewrites chat/QA-style payloads).
* **Tinnove rule engine**: `com.tinnove.wecarspeech.tinnoveengine.nlu.TRuleEngine` (registered as `"rule"` by
  `xb.a.b()`, `J/xb/a.java:24`), run on a thread pool in `ac.d.b(...)`. Pure offline; converts text -> rule
  semantic JSON (voice-control-v2). Runs in parallel with iFlytek for every final ASR text (via `e.b0`).

**Offline execution**: yes. With no network, `startAsr(2)` is used (offline SR), results arrive as 20009/20204 with
`bislocalresult=1`, and `TRuleEngine` provides offline semantics; `fusion.b` arbitrates and `session/d.H` -> dispatch
executes vehicle commands locally. So a Ru2Zh injected Chinese command executes offline as long as the local NLI /
rule engine recognizes that Chinese phrase.

---------------------------------------------------------------------------------------------------

## 5. Execution: how a semantic reaches skills / car control / apps / navi / media

`session/d.H(int channel, String semantic, boolean isOnline, boolean isReject, String type)` is the manager's
"handleSemantic". Duplex version `J/.../session/duplex/d.java:455`, smali `S3/.../session/duplex/d.smali:1659`:

1. Large-model short-circuit `ea.a` (ISAModelManager) — **not present** (`SAModelManager` class absent; `largeModelCfg`
   stays 0, `comm.cfg` has no `largeModelCfg`), so skipped.
2. Rejection: if `type` not in {tinnove,rule}, `zc.c.e().b()` then `z0(semantic)` = `IflytekRejection`
   (`zc.b.a`, `J/zc/b.java:88`). If rejected -> `hd.c.t(...)` and **return (dropped)**. Self-developed/rule semantics
   skip rejection. `isRejectEnable` default true. (Our injected Chinese command, being a concrete car/app/navi
   intent with `rc!=4` and non-chat service, will NOT be rejected.)
3. `f7236d.H()` (container), `b.p().c()`, top session `B.d()`.
4. If a text-request callback `f7234a` is pending (`!f7241i`) -> `onTextSemanticResult` (the `getSemanticByText`
   path with a `cd.k` callback, see §8).
5. Otherwise `f7239g.onSemantic(semantic, isOnline, false, channel, false)` (closure listener) OR enqueue into
   `SemanticHandler`/`SemanticQueue` (`session/duplex/e`,`f`) -> `container.d(semantic,...)` ->
   `cd.e.f(...)` -> state machine CMD_DISPATCHING_RESULT(16) -> `cd.a.n(...)` ->
   **`sc.c.g(sessionId, semantic, SemanticData)`**.

`sc.g` ("VFrameWkDispatcher", `J/sc/g.java`) is the dispatcher:
`g(long,String,SemanticData)` (`:1897`) parses `SemanticData` (domain/intent/query), then
`K(...)` (`:1302`) resolves clients by `(domain,skill)` via `ClientManager`, arbitrates if multiple, and
`C(oc.d client, ...)` (`:922`) enqueues an `id.f` task that calls the client wrapper `u(...)` — i.e. the actual
AIDL call to the car-control / app / navi / media client. Unhandled domain -> `O(...)` ("unhandledDomain").
Command-word (offline hot word) dispatch uses `F(...)` / `d(...)`. So vehicle commands, apps, navigation and media
are all executed here through registered `IClientWrapper` clients. This is downstream of H() and does not need
touching by the mod.

`session/d.H` also drives on-screen text + TTS reply: `this.b.y(query, json, ...)` -> `AbsSessionMgrInner.r(...)` ->
posts `onSemantic(...)` to all `cd.h` listeners on `HandlerThread("semantic_notify_thread")` and
`SoundPoolPlayer.playSoundWhenSemanticResult()`; the dispatched skill's client then produces the spoken/visible
reply (TTS via VoicePlayer). So an injected semantic both executes and yields a reply, exactly as a spoken command.

---------------------------------------------------------------------------------------------------

## 6. Which session manager is live (duplex vs simplex)

`VFramework.initSessionManager` calls `mSessionMgr.O(..., sDuplexEnabled, ...)` (`VFramework.java:389`).
`sDuplexEnabled = sDuplexSwitchON && SessionConfigUtils.isModifiedPlatform()` (`VFramework.java:193`).
`isModifiedPlatform()` returns `mIsPlatformModified` which is set by
`setIsModifiedPlatform(voiceRegion>1 || comm.cfg:debugForceEnableDuplex)` (`VFramework.java:1890`,
`SessionConfigUtils.java:223`). Shipped `comm.cfg`: `voiceRegion:2` (>1) and `debugForceEnableDuplex:true`, and
`enableDuplex(true)` is called at client init (`VrClient.java:256` via `a8.a`). So **duplex is enabled**; `e.O`
sets `f7437d = f7436c` (the duplex `d`) when `z10==true`. `session/e.enableDuplex` can still toggle
`f7437d` between `b`(simplex) and `f7436c`(duplex) at runtime. **Conclusion: patch the duplex manager primarily,
and apply the same drop/inject logic to simplex for safety.** A runtime log `"SessionManager duplexEnabled = true"`
confirms which is live.

---------------------------------------------------------------------------------------------------

## 7. DROP points (equivalent of Q07 dropFinalAsr / dropCloud / dropArb)

Goal: silently discard every stock Chinese recognition that is NOT our injected one, without disturbing the session
state machine. Candidates, best first:

### 7.1 Best: engine-level funnels `IAE.onFinalResult` and `IAE.onTmpResult` (S2)
These are the two narrow funnels for ALL results (offline ESR, cloud, PGS/tmp, mm/full-time) — §2. They only
forward to a listener and return void, so an early `return-void` cleanly drops a result and the state machine is
untouched (the session simply times out as if nothing was recognized, which is the same as the Russian speech not
matching anything — exactly the desired behavior).

* `onFinalResult(ILjava/lang/String;ZZZZLjava/lang/String;)V` — smali `S2/.../IflytekAsrEngine.smali:4381`.
  Registers on entry: `p1=channel`, `p2=semanticJson`, `p3..p6` booleans (p6=isFromTextToNlu), `p7=extra`.
  Inject at method start:
  `invoke-static {p0,p2,p6}, Lcom/stand/q05/Bridge;->dropFinal(Lcom/.../IflytekAsrEngine;Ljava/lang/String;Z)Z`
  move-result -> if nonzero `return-void`.
* `onTmpResult(ILjava/lang/String;ZZLjava/lang/String;ZI)V` — smali `S2/.../IflytekAsrEngine.smali:4429`.
  `p2=recognized text`. Inject the same guard (so the mis-recognized Chinese text never flashes on screen / to
  clients).

Filter logic (recommended): keep a `static volatile boolean injecting` latch in our bridge, set true just before we
call the text-injection API and false when our semantic has been dispatched (or after a short timeout). `p6==true`
(isFromTextToNlu) already distinguishes the **text path** (our injected call) from the **voice path**, so a minimal
filter is: *drop `onFinalResult`/`onTmpResult` whenever the result is a VOICE result (p6==false) and `injecting`
is true or capture-armed*. More robust: drop ALL voice-origin finals/tmps unconditionally once the mod is active for
a session, because the Russian ASR is handled entirely by our own GigaAM path (as on Q07), and only our injected
text results (p6==true) are allowed through.

### 7.2 Alternative/defense-in-depth: session boundary `session/e$a` (S3)
* `session/e$a.onSemantic(ILjava/lang/String;ZZLjava/lang/String;)V` — smali `S3/.../session/e$a.smali:631`.
* `session/e$a.onSpeechResult(ILjava/lang/String;ZZZI)V` — smali `S3/.../session/e$a.smali:746`.
* `session/e$a.onExtraSemantic(ILjava/lang/String;ZLab/a;)I` — smali `:261`.
Early-return here to drop; returning void/0 is safe (these just forward). Dropping `onSpeechResult` also suppresses
the on-screen Chinese ASR text.

### 7.3 Arbitration-level: `fusion.b.b(ILjava/lang/String;Ljava/lang/String;I)V` (S3:/fusion/b.smali) — the Q07
`dropArb` analogue. Early-return drops an engine's contribution to arbitration. Less ideal because it can leave
`nluTypeSet` incomplete and stall the fusion counter; prefer 7.1.

### 7.4 "Let ours through" tagging
There is no stock `requestId`. Two clean ways:
* **Latch**: `Bridge.injecting` true during our call window; drop filter ignores results while false→voice only.
  Simplest, mirrors the Q07 behavior of dropping everything not from us.
* **JSON tag**: when we inject via `getSemanticByText`/`startSrByText`, the stock engine builds the semantic from our
  Chinese text and sets `isFromTextToNlu=true` (p6) on `onFinalResult` (see `IAE.startAsrByText` ->
  `onFinalResult(-1, json, isOnline, isOnlineReq, false, true, "")`, `IAE.java:1457`). **p6==true is itself the
  "ours" marker** for the text path. So the drop rule can be: `drop if p6==false` (voice) — our injected text result
  (p6==true) always passes. This is the cleanest tag and needs no extra state.

---------------------------------------------------------------------------------------------------

## 8. Text-injection APIs (startAsrByText, startSrByText, getSemanticByText, putSemantic, broadcasts)

### 8.1 `VFramework.startAsrByText(String)` — reaches engine but is NOT a plain injector
Chain (all verified in smali):
`VFramework.startAsrByText` (`S3/.../VFramework.smali:1469`) -> `mSessionMgr.x(str)` (`session/e.x`,
`session/e.smali:2895`) -> `session/c` -> `f7437d.startAsrByText(str)` (`session/b.startAsrByText`,
`S3/.../session/b.smali:3051` -> `this.b.l().startAsrByText(str)`) -> `lb.b.startAsrByText` -> `IE.startAsrByText`
(`IE.smali:10849` -> `mAsrEngine.startAsrByText(str,false)`) -> **`IAE.startAsrByText(String,boolean)`**
(`S2/.../IflytekAsrEngine.smali:7849`).

`IAE.startAsrByText(String query, boolean z)` (`IAE.java:1421`) does:
`mIsWakeUp=true; setEveryTimeASRParam(); mIflytekEngine.loadNLIRes();`
if online -> `result = mspSearch(query,"all")` (cloud semantic); if empty -> `localNli(query,"all")` (offline NLI);
offline -> `localNli(query,"all")`. Then (if `ub.g.x()`) `ub.c.k().g(result)`; if empty `return`; else parse JSON,
`addProperty("channel",2)`, ensure an `"intent"` wrapper, and call
`onFinalResult(-1, json, isOnline, isOnline, false, /*isFromTextToNlu*/ true, "")`.

So `startAsrByText` is **"turn this Chinese text into a semantic via the stock NLU and inject that semantic as a final
result"**. It does NOT run ASR. It is suitable for injecting a Chinese *command phrase* (our Ru2Zh output). BUT: it
only works when the stock NLU can understand the phrase, it fixes `channel=2` (front-passenger — wrong for driver),
and the in-app wiring only calls it from `ExtraService` (§8.5). For our mod, `startSrByText`/`getSemanticByText`
are better because they also open a session for UI/TTS.

### 8.2 `VFramework.getSemanticByText(String, lb.a[], cd.k)` — lowest-level text->semantic
`VFramework.smali:3716` -> `mSessionMgr.n(str, aVarArr, kVar)` (`session/b.n`, `J/.../session/b.java:632`):
guards `f7234a==null` (one text request at a time), sets `f7234a=kVar`, `a0()` (arms a 15s TXT2SEMANTIC timeout
message 3001), then `this.b.l().getSemanticByText(str, aVarArr)` -> `IE.getSemanticByText` ->
`mAsrEngine.startAsrByText(str,false)` — same engine method as §8.1. When the semantic comes back through
`session/d.H` and `f7234a!=null`, it calls `f7234a.onTextSemanticResult(semantic, channel)` (if a callback was
passed) instead of dispatching, OR dispatches if no callback. **Pass `cd.k kVar = null`** to make it dispatch and
execute like a spoken command (that is what `startSrByText` does).

### 8.3 `VFramework.startSrByText(String, LaunchParams, IStartResultCallback)` — RECOMMENDED injector
`VFramework.smali:6742`, `J/.../VFramework.java:1717`:
```
public void startSrByText(String str, LaunchParams launchParams, IStartResultCallback cb) {
    mSessionMgr.k(launchParams, cb);          // opens an SR-by-text session (UI + TTS)
    getSemanticByText(str, new lb.a[0], null);// null callback -> dispatch & execute
}
```
`session/b.k(LaunchParams,cb)` (`session/b.java:598`) sets `f7241i=true` (marks text mode) and starts a session via
`c0(1, new SessionParams(cb))` unless a session is already active; `f7242j = launchType==100` toggles the
`semanticFile.log` dump. Because the callback is null, the semantic goes through the normal
`session/d.H -> dispatch` path and executes, shows text and speaks the reply. **Preconditions**: a session is opened
for you by `k()`, so you do NOT need an active session first; it works from idle. Thread: called on whatever thread
you invoke it; the engine hops to `handleSRMessage_thread` and the state machine to `session_state_machine` /
`semantic_notify_thread`. **This is the closest Q05 equivalent of Q07's injectZh**, with the difference that you pass
the **Chinese text** and the stock NLU produces the semantic.

`LaunchParams`: `new LaunchParams.Builder(100).build()` is used by `ExtraService`'s path; launchType 100 enables the
`KEY_SAVE_SEMANTIC` dump. For injection pass a plain `new LaunchParams.Builder(<type>).build()` or `null`.

### 8.4 `VFramework.putSemantic(String)` / `sendSemantic` — inject a FINISHED semantic JSON
`VFramework.smali:4912`, `J/.../VFramework.java:1073`: opens a WAKE_TYPE_SDK session via `mSessionMgr.f(...)`, and on
success (or SESSION_IN_CLOSURE) calls `mSessionMgr.t(semanticJson)` -> `session/d.t` -> `H(-1, json, true, true, "")`
(`session/b.java:734`). This **bypasses the NLU entirely** and dispatches a ready semantic. This is the true analogue
of Q07's `onFinalAsrResult` injecting an NLU result — but here you must supply a full Tinnove/iFlytek
`SemanticData` JSON (domain/intent/query/Payload), which is harder than supplying Chinese text. Exposed over AIDL as
`IVrLogicService.sendSemantic` (`vrlogic/server/a.java:940`) and via broadcast `"ACTION_TO_SEMANTIC"` extra
`"KEY_TEXT"` (see §8.5). **Use this only if Ru2Zh maps directly to semantics rather than to Chinese phrases.**

### 8.5 Broadcast / service entry points (no code patch required to drive injection)
* **Exported service `com.tinnove.vrlogic.server.ExtraService`** (manifest line 96, `exported=true`): `onStartCommand`
  reads extra `"nluStr"`, debounces 1s, then on `w.f(...)` thread runs
  `VFramework.stopSR(); VFramework.startAsrByText(nluStr);` (`J/.../ExtraService.java:63`, smali
  `S2/.../ExtraService.smali`). So `am startservice -n com.tinnove.wecarspeech/com.tinnove.vrlogic.server.ExtraService
  --es nluStr "打开空调"` injects a Chinese phrase via the §8.1 path. Useful for testing from adb; not ideal as the
  mod's main path (fixed channel=2, no session UI).
* **`d8.a` ("Text2SemanticManager")** registers a dynamic receiver (from `VrClient` init,
  `J/com/tinnove/vrclient/a.java:140`) for actions:
  - `"ACTION_TEXT_TO_SEMANTIC"`, extras `"KEY_TEXT"`, `"KEY_SAVE_SEMANTIC"(bool)` ->
    `VrInterfaceImpl.startSrByText(text, LaunchParams(100|null), null)` (`J/d8/a.java:39`). This is the
    **broadcast front-door to `startSrByText`** (§8.3) — the recommended injector, reachable without patching.
  - `"ACTION_TO_SEMANTIC"`, extra `"KEY_TEXT"` -> unescapes `\\uXXXX` then `VrInterfaceImpl.sendSemantic(json)`
    -> `putSemantic` (§8.4).
  These receivers are **registered at runtime (not in manifest)** and the registering context is the speech process;
  they are not declared `exported`, so an external `am broadcast` may be refused unless same-uid. For an in-process
  mod this does not matter.
* **AIDL**: `IVrLogicService` (service `com.tinnove.vrlogic.server.VrLogicService`, manifest line 86,
  **exported=false**) exposes `startSrByText`, `getSemanticByText(query,domain,intent,cb)`, `sendSemantic`,
  `startAsrByText` indirectly. Since the mod runs inside the same app (and the app is `sharedUserId
  android.uid.system`), direct Java calls to `VFramework.getInstance().startSrByText(...)` are simplest.

### 8.6 Recommended injection recipe for the Ru2Zh mod
1. After GigaAM yields the Russian phrase and `Ru2Zh` maps it to a Chinese command string `zh`:
   set `Bridge.injecting=true`, then on a background thread call
   `VFramework.getInstance().startSrByText(zh, new LaunchParams.Builder(0).build(), null)` (opens a session, runs
   stock NLU on `zh`, dispatches and speaks). Smali target:
   `Lcom/tinnove/wecarspeech/vframework/VFramework;->startSrByText(Ljava/lang/String;Lcom/tinnove/vrcommon/app/LaunchParams;Lcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V`.
   Alternatively `getSemanticByText(zh, new lb.a[0], null)` if no new session is wanted.
2. The stock engine will emit `onFinalResult(..., isFromTextToNlu=true)`, which the drop filter (§7.4) lets through.
3. All stock VOICE results (`isFromTextToNlu=false`) are dropped by the §7.1 guard, so Russian speech never triggers
   a Chinese misfire.
4. Channel/zone: `startAsrByText` hard-codes `channel=2`; `getSemanticByText`/`startSrByText` use
   `DoaManager.getCurrentDirection()`. If you need the driver zone, set DOA/`wakeZone` before injecting, or
   post-set `semanticJson.channel`. (Q07 tracked `wakeZone`; Q05 exposes `DoaUtils.getWakeDirectionInt()` and
   `DoaManager`.)

---------------------------------------------------------------------------------------------------

## 9. Exact smali files / signatures (patch targets)

Drop (voice results):
* `S2/com/tinnove/wecarspeech/speechengine/engine/engineofiflytek/ability/IflytekAsrEngine.smali`
  - `onFinalResult(ILjava/lang/String;ZZZZLjava/lang/String;)V`  @ line 4381  (p2=semantic, p6=isFromTextToNlu)
  - `onTmpResult(ILjava/lang/String;ZZLjava/lang/String;ZI)V`    @ line 4429  (p2=text)
* (defensive) `S3/com/tinnove/wecarspeech/vframework/session/e$a.smali`
  - `onSemantic(ILjava/lang/String;ZZLjava/lang/String;)V`       @ line 631
  - `onSpeechResult(ILjava/lang/String;ZZZI)V`                   @ line 746
  - `onExtraSemantic(ILjava/lang/String;ZLab/a;)I`               @ line 261
* (arb, optional) `S3/com/tinnove/wecarspeech/vframework/fusion/b.smali` -> `b(ILjava/lang/String;Ljava/lang/String;I)V`

Inject (call these; usually no patch, just invoke from our code):
* `S3/com/tinnove/wecarspeech/vframework/VFramework.smali`
  - `startSrByText(Ljava/lang/String;Lcom/tinnove/vrcommon/app/LaunchParams;Lcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V` @ 6742  (RECOMMENDED)
  - `getSemanticByText(Ljava/lang/String;[Llb/a;Lcd/k;)I` @ 3716
  - `putSemantic(Ljava/lang/String;)V` @ 4912  (finished-semantic injection)
  - `startAsrByText(Ljava/lang/String;)V` @ 1469  (text->NLU, channel fixed 2)
  - `getInstance()Lcom/tinnove/wecarspeech/vframework/VFramework;` @ 1010
* Engine text path: `S2/.../IflytekAsrEngine.smali->startAsrByText(Ljava/lang/String;Z)V` @ 7849
  (calls `mspSearch`/`localNli`, then `onFinalResult(... isFromTextToNlu=true)` @ 8180).

Session managers (to know which is live / to mirror patches):
* duplex: `S3/com/tinnove/wecarspeech/vframework/session/duplex/d.smali` -> `H(ILjava/lang/String;ZZLjava/lang/String;)V` @ 1659
* simplex: `S3/com/tinnove/wecarspeech/vframework/session/simplex/c.smali` -> `H(...)` (same signature)

Dispatcher (execution; informational, no patch):
* `S3/sc/g.smali` -> `g(JLjava/lang/String;Lcom/tinnove/wecarspeech/speechcommon/parser/SemanticData;)Z`

---------------------------------------------------------------------------------------------------

## 10. Uncertainties / what a runtime log would settle

* **Which NLU branch fires for an injected Chinese phrase online vs offline** (`mspSearch` cloud vs `localNli`):
  settled by `IflytekAsrEngine` log lines `"startAsrByText:  请求云端语义结果 = ..."` /
  `"请求离线语义结果 = ..."`. If the car is offline most of the time, confirm local NLI returns a usable semantic
  for the mapped Chinese commands (otherwise rely on `TRuleEngine` / `putSemantic`).
* **Which session manager is active at runtime**: confirm via `"SessionManager duplexEnabled = true"` and
  `"DuplexSessionManagerInner ..."` vs `"SimplexSessionManagerInner ..."`. The static analysis says duplex.
* **isFromTextToNlu reliability as the "ours" tag**: confirm `onFinalResult` from the audio path always passes
  `isFromTextToNlu=false`. Grep of `handleSRMessage` callers shows every voice-path `onFinalResult` passes literal
  `false` for p6 and only `startAsrByText` passes `true` (`IAE.java:1457`), so this holds statically; a logcat check
  of the 5th boolean in the `"mAsrEngine->onFinalResult ... isFromTextToNlu = "` line (printed in
  `IflytekEngine$a.b`) confirms it live.
* **CuiAI/big-model rewrite of our injected command** (`ub.c.x/g`): if `tinnove_big_module_switch`+`isOpenBigModule`
  make `ub.g.x()` true, verify the injected concrete command isn't turned into a chat answer. Log
  `"AISemanticManager handleSemantic..."`.
* **Rejection of injected command**: verify `IflytekRejection` does not reject (log `"isRejection == false"` for
  our semantic). Concrete car/app/navi intents with `rc!=4` are not rejected per `zc.b.a`.
