# Q05 (com.tinnove.wecarspeech / WT_TSpeech 2.5.3.19_beta) – app lifecycle & voice-session state machine

Paths used below:

* JX = `q05x/jx/sources` (jadx Java)
* SM2 = `q05x/smq05/smali_classes2`, SM3 = `q05x/smq05/smali_classes3` (apktool smali, these are the names you patch)
* All paths are relative to the scratchpad `/tmp/claude-0/-home-user-rusifycar-voice/44add113-a2d7-5101-9472-9cd565837855/scratchpad/`.

**Watch out:** jadx sometimes renames members. For example, the jadx `VrApplication.f()` is `g()V` in smali. The smali names below were checked against the smali files.

---

## 0. TL;DR

| Q07 concept | Q05 equivalent (verified in code) |
|---|---|
| `VoiceApp.onCreate -> Q07Bridge.init(ctx)` | `Lcom/tinnove/wecarspeech/app/VrAppEntry;->initVrApp(Landroid/content/Context;)V`, inside its main-process branch (SM2). Use `VrApplication.onVrAllInitCompleted(ZLjava/lang/String;)V` for anything that needs `VFramework` (it is ready by then). |
| `SrSession.updateCurrentSid -> onSpeechStart` (arm capture) | `Lcom/tinnove/wecarspeech/vframework/session/b;->F(Ljava/lang/String;)I` = **AbsSessionMgrInner.switchToSRMode(wakeType)**. It is the single choke point where the stock engine goes to SR (listening) for every source: wake word, steering key, screen/click, SDK, multi-turn re-listen. Alternative without patching: an in-process `cd.h` listener (`onRecordStart()`, `onRecordSessionStart(...)`). |
| `SrSession.startWaitNlu -> onSpeechEnd` | Engine VAD event `EngineState.VOICE_END = 200003`, delivered through `cd.h.onEngineState(200003, ...)` and `duplex/d.L(ILjava/lang/String;)V`, then `cd.e.handleSpeechEnd()`. |
| `VoiceStateCache.isWakeUp()` | `AbsSessionMgrInner.U()Z` (field `o:Z`, "speech active"). It is set by `X(Z)V`: true in `F()` (SR start), false in `G()` (back to wake-word mode, MVW). Coarser public check: `VFramework.isOpenSR()Z` (engine mode == SR). |
| `BusinessController.startWakeupAsync(...)` (wake like voice) | Private `IflytekEngine.onWakeupResult(ILjava/lang/String;IIZLjava/lang/String;)V` with `(1001, "<word>", seatChannel, 2001, false, "")`. The engine itself does exactly this for "执行唤醒" (IflytekEngine.java:1567). Simpler public click-wake: `VFramework.getInstance().startSR("click"/"click_right", false, IStartResultCallback)`. |
| `BusinessController.changeInteraction(2)` (click/key wake) | `Lcom/tinnove/wecarspeech/vframework/VFramework;->startSR(Ljava/lang/String;ZLcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V`. wakeType is `"sdk"` for the steering key and `"click"` for the icon/launcher. |
| Steering-wheel key (Q07 CaKey / sdakeyservice) | **No KeyEvent handling inside TSpeech.** An external system app sends `startService(action "com.tinnove.wecarspeech.Launch", extra_launch_type=7)` to `LaunchService`, which builds `LaunchParams(1, wakeType "sdk", asrSound true)` and ends in `VFramework.startSR("sdk", true, cb)`. That starts a **stock session**, so capture can arm in `F("sdk")`. Pressing the key again while in SR toggles the session off. Evidence: test button "模拟方控启动语音" (simulate steering-wheel voice start) sends exactly this intent. |
| exit/close session | `VFramework.getInstance().stopSR()` (interrupt all sessions + `G()` switchToVWMode). Or LaunchService `extra_launch_type=6` (also stops all TTS). |
| zone (`mCurrentDirect` 1..5) | `DoaManager.getInstance().getCurrentDirection()` returns `DoaDirectionMode`: `DIRECTION_LEFT(2)` = driver (主驾), `DIRECTION_RIGHT(3)` = passenger (副驾). Raw engine channel is 0 = driver, 1 = passenger. `voiceRegion=2` in `assets/public/cfg/comm.cfg`. |

The session manager actually used on Q05 is **Duplex** (`com.tinnove.wecarspeech.vframework.session.duplex.d`, DuplexSessionManagerInner). Simplex is compiled in but not selected (see §3.1).

---

## 1. Processes and Application start

### 1.1 Manifest (resq05/AndroidManifest.xml)

* `android:sharedUserId="android.uid.system"`, Application `com.tinnove.wecarspeech.app.VrApplication`.
* **Two processes**:
  * main `com.tinnove.wecarspeech`: VrLogicService (no `android:process`, `foregroundServiceType=camera|location|microphone`), LaunchService, WecarService (SDK binder), MainActivity, providers, and so on.
  * `:intraspeechserver`: `com.tencent.wecarintraspeech.intervrlogic.IntraVrLogicService` and `com.tencent.wecarintraspeech.fusionadapter.service.FusionService` (Tencent fusion/intra-speech adapter, no VFramework).
* `VrApplication.onCreate` therefore runs **in both processes**. The stock code guards only the heavy part with a process-name check.

### 1.2 VrApplication.onCreate (SM2/com/tinnove/wecarspeech/app/VrApplication.smali)

```
.method public onCreate()V            ; .locals 2, main thread
    invoke-super {p0}, Landroid/app/Application;->onCreate()V
    Log.d("VrApplication","onCreate")
    invoke-direct {p0}, Lcom/tinnove/wecarspeech/app/VrApplication;->g()V   ; jadx name: f()
```

`g()V` (jadx `f()`):
* If sdcard is not mounted (`com.tinnove.vrcommon.utils.e.i()`), it re-posts itself after 500 ms (`ThreadUtils.postDelayed`). Init can therefore be delayed.
* When mounted:
  * `d()` (`qd.a.b(this)`)
  * `VrApp.getInstance().registerInitCallback(this)` (the Application is the `IVrClientEventCallback`)
  * `VrAppEntry.getInstance().onCreate(appCtx)`
  * register PACKAGE_ADDED/REPLACED/REMOVED receiver
  * `c()` (skin)

`VrAppEntry.onCreate(ctx)` calls `g8.a.a(ctx)`, then `initVrApp(ctx)`:

```
.method private initVrApp(Landroid/content/Context;)V      ; SM2/com/tinnove/wecarspeech/app/VrAppEntry.smali:76, .locals 1
    Log.e("VrAppEntry","initVrApp")
    invoke-static {p1}, Lcom/tinnove/wecarspeechtools/PackageUtils;->getProcessName(Landroid/content/Context;)Ljava/lang/String;
    move-result-object p0
    invoke-virtual {p1}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
    move-result-object v0
    invoke-static {p0, v0}, Landroid/text/TextUtils;->equals(...)Z
    move-result p0
    if-eqz p0, :cond_0                      ; <- only main process continues
    invoke-static {}, Lcom/tinnove/wecarspeech/app/VrApp;->getInstance()...
    invoke-virtual {p0, p1}, Lcom/tinnove/wecarspeech/app/VrApp;->init(Landroid/content/Context;)V
    :cond_0
    return-void
```

**Recommended `init(Context)` injection (Q07Bridge.init equivalent):** right after `if-eqz p0, :cond_0`. There `p1` is the application context and we are guaranteed to be in the main process. No extra registers are needed:

```
    if-eqz p0, :cond_0
    invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->init(Landroid/content/Context;)V
```

Alternative: at the top of `VrApplication.onCreate` with our own process check (`Application.getProcessName()` on API 28+). Do **not** do the heavy init (onnxruntime, models) in `:intraspeechserver`.

### 1.3 VR stack bring-up chain (all in the main process)

```
VrApp.init(ctx)                              [SM2 com/tinnove/wecarspeech/app/VrApp.smali:1107]
 └ initialize(): initUtils, configureDataPath, initLogUtil, initRegionConfig
      └ VirtualCarManager.init(...) (virtualcarFeature=true) -> initVrClient()
          └ VrClient.getInstance().init(ctx, VrApp, VrApp.b callback)
              └ VrInterfaceImpl.init(...)  -> bindService(VrLogicService)   (same process; binder is local)
VrLogicService.onCreate  -> VFramework.install(appCtx)   (sets com.tinnove.wecarspeechtools.ContextHolder)
VrLogicBinder (com/tinnove/vrlogic/server/a.java:765) -> VrLogic.setInitCallback(...); VrLogic.init()
 └ new com.tinnove.vrlogic.b(ctx).a(ctx, VrLogic.a)      ("VrServerProcess", runs on w.d thread pool)
     ├ RunnableC0180b: config agents, SpeechRecordManagerImpl, RoleManager, WakeupWordManager(p9.b), FusionAdapter ...
     └ v(): VFramework.getInstance().init(ctx, VrServerProcess.c)   <- creates IflytekEngine, SessionManager, VoicePlayer
            init done: VrServerProcess.c.onInitialized -> VrLogic.a.onCompleted -> ISpeechServerInitCallback
VrClient.b.BinderC0165b.onCompleted -> mVrClientInitCallback.onVrAllInitCompleted(true, msg)
 └ VrApp.b.onVrAllInitCompleted -> VrApplication.onVrAllInitCompleted(ZLjava/lang/String;)V   (SM2 VrApplication.smali:288)
    + VrClient.syncToServer() -> VrInterfaceImpl.enableDuplex(a8.a.a().c())
```

**Important:** do **not** call `VFramework.getInstance()` from `Q05Bridge.init`. Its constructor (`VFramework.<init>`) uses `com.tinnove.wecarspeechtools.ContextHolder`, which is only set by `VFramework.install()` in `VrLogicService.onCreate`. That happens after `Application.onCreate`.

To register session listeners or call `VFramework` APIs, use one of these:
* (a) a second hook at the very top of `VrApplication.onVrAllInitCompleted(ZLjava/lang/String;)V`: `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onVrReady(Z)V`. It must go **before** `.line 1`, because `p1` is overwritten by `move-result-object p1`.
* (b) a background poll on the static `VFramework.mInstance` (smali field `mInstance`, private static volatile) until it is non-null and `isInited()Z` returns true.

Stock precedent for in-process registration: `p9.b` (WakeupWordManager) does `VFramework.getInstance().registerSessionListener(this.f13489h)` (JX/p9/b.java:206).

---

## 2. Class map (obfuscated ↔ readable, from `compiled from:` comments)

| Obfuscated | Readable | Role |
|---|---|---|
| `com.tinnove.wecarspeech.vframework.VFramework` | VFramework | facade; holds `mSessionMgr:Lcom/tinnove/wecarspeech/vframework/session/c;` |
| `vframework.session.c` (interface) / `vframework.session.e` | ISessionManager / **SessionManager** | owns `IEngineListener k` (inner `e$a`) and the active inner manager `d` |
| `vframework.session.d` (interface) | ISessionManagerInner | |
| `vframework.session.b` (abstract) | **AbsSessionMgrInner** | `F` = switchToSRMode, `G` = switchToVWMode, `Q` = handleMainWakeup, `X(Z)` = notifySpeechActive, `U()` = isSpeechActive |
| `vframework.session.duplex.d` | **DuplexSessionManagerInner** (the active one on Q05) | `c0` = startRecordSession, `L` = engine-state handler, `H` = handleSemantic |
| `vframework.session.duplex.d$a` | its `cd.i` ISessionObserver | `a` = onInteractionComplete, `b` = onRecordSessionFinish, `c` = onRecordSessionStart, `d` = onRecordSessionRestart |
| `vframework.session.simplex.c` | SimplexSessionManagerInner | not selected on Q05 |
| `vframework.session.a` | AbsSessionContainer | session lists, `B()` = top session |
| `vframework.session.duplex.c` | **DuplexSessionContainer** | field `l:Z` = mIsInSeriesRecognize (dialog window active), `j` = InteractionController |
| `vframework.session.duplex.a` | **DuplexInteractionController** (`"InteractionController"`) | multi-turn active-time timer |
| `vframework.session.duplex.b` | DuplexSession (implements `cd.e` via `cd.a` AbsSession) | one record session |
| `vframework.session.duplex.DuplexSessionStateMachine` | per-session HSM | Init/Dispatchable/Start/ReStart/Record/SR/SeriesSR/Route/FirstRoute/SeriesRoute/Handle/End |
| `vframework.session.common.statemachine.c` | StateMachine (AOSP-like HSM) | |
| `vframework.session.common.statemachine.Cmd` | message codes | |
| `vframework.session.common.d` | SessionMgrContainer | `A()` = listener list (`CopyOnWriteArrayList<cd.h>`), `l()` = engine `lb.e`, `n()` = current EngineMode |
| `vframework.session.duplex.e` / `duplex.f` | SemanticHandler (thread "SemanticHandler") / SemanticQueue | |
| `cd.h` / `cd.n` | ISessionListener / SimpleSessionListener (empty impl, public class) | |
| `cd.i`, `cd.e`, `cd.a`, `cd.l` | ISessionObserver, ISession, AbsSession, interaction-complete cb | |
| `lb.e` / `lb.b` | Engine interface / Engine wrapper | `lb.b` private field `a:IEngineInterface` = IflytekEngine |
| `com.tinnove.wecarspeech.vframework.EngineManager` | public singleton holding `lb.e` | |
| `com.tinnove.wecarspeech.speechengine.engine.engineofiflytek.IflytekEngine` | iFlytek engine | mode switch, wake dispatch |
| `com.tinnove.vrlogic.VrLogic` / `com.tinnove.vrlogic.b` | VrLogic / VrServerProcess | |
| `f8.b` / `f8.d` / `f8.e` | VrAppManager / VrAppManagerHandler / VrMessageHandler | client UI-side controller; mostly stubbed in this build |
| `com.tinnove.vrclient.VrClient`, `com.tinnove.vrinterface.VrInterfaceImpl` | client facade + binder proxy to VrLogicService (same process) | |

---

## 3. Session state machine

### 3.1 Which session manager is active

`VFramework.init` -> `initSessionManager()` passes the static `sDuplexEnabled`. Its smali default is `true` (`.field private static sDuplexEnabled:Z = true`), and `checkDuplexEnableStatus()` is dead code. So `SessionManager.O(...)` picks `this.d = this.c` (duplex.d).

Later `VrClient.syncToServer()` -> `VFramework.enableDuplex(z)`. This **ignores z** and sets `sDuplexEnabled = SessionConfigUtils.isModifiedPlatform()`, which equals `voiceRegion > 1`. `comm.cfg` has `"voiceRegion":2`, so Duplex stays.

Runtime log to confirm: `[SessionManager]duplexEnabled  = true` and `[VFramework]duplexEnabled: true  sDuplexEnabled: true`.

"Duplex" here means the full-duplex/continuous dialog architecture. Whether multi-turn is actually used depends on the user switch `duplex_switch` (§6).

### 3.2 Layers of "state"

1. **Engine mode** (`IflytekEngine.mCurrentMode`, volatile; enum `com.tinnove.wecarspeech.speechengine.EngineMode`): `IDLE(0)`, `MVW(1)` = wake-word listening/idle, `SR(2)` = recognizing/listening, `SR_ONLINE(3)`, `ONESHOT(4)`, … (iFlytek maps only MVW/SR/SR_ONLINE). Switching is asynchronous on HandlerThread `"SwitchMode thread"` (`IflytekEngine.switchMode -> switchModeInner`).
   * `switchToSRMode(wakeType,..)` -> SR -> `startAsr(3)` online or `startAsr(2)` offline.
   * `switchToVWMode` -> MVW (stop ASR, start wakeup engine, `DoaUtils.setWakeDirectionDefault(0)`).
2. **Speech-active flag** `AbsSessionMgrInner.o:Z` (`U()Z`). `X(true)` in `F()` and `X(false)` in `G()`/`f0()`. `X` also broadcasts `ISpeechActiveListener.onActive()/onQuiet()` to SDK clients (VPA UI).
3. **Dialog window** `DuplexSessionContainer.l:Z` (mIsInSeriesRecognize). True once a displayable record session was pushed. False on interaction complete. While true, a semantic arriving with no top session creates a new session (wakeType `"duplex"`). Otherwise "drop this semantic".
4. **Per-session HSM** (`DuplexSessionStateMachine`, thread `"duplex_session_state_machine_thread"`):

```
InitState (root: 5 RELEASE->quit OK, 6 INTERRUPT->quit, 7 PROCESS_TIMEOUT->quit NO_SPEECH_TIMEOUT, 9 RESTART->ReStart, 10 START->Start or FirstRoute)
 ├ DispatchableState (11 TTS_START, 12 TTS_END, 16 DISPATCHING_RESULT->Route, 18 SPEECH_START, 22 REJECT, 23 SEMANTIC_TIMEOUT->R())
 │   ├ StartState      (welcome/beep, then startRecord: type1 -> session.o() -> F(); type8 -> SRState)
 │   ├ ReStartState
 │   └ RecordState (3 DISPATCH_FINISH -> Handle)
 │       ├ SRState        <- "listening/recognizing"
 │       └ SeriesSRState
 ├ RouteState (dispatch semantic to client / sc.c dispatcher; 25 s timer)   <- "understanding/executing"
 │   ├ FirstRouteState
 │   └ SeriesRouteState
 ├ HandleState (client handling + TTS; 25 s timer, restarted at TTS_END)    <- "speaking"
 └ EndState
```

Cmd codes (`vframework/session/common/statemachine/Cmd.java`): 1 SR_START, 2 SPEECH_END, 3 DISPATCH_FINISH, 4 HOLD_SESSION, 5 RELEASE_SESSION, 6 INTERRUPT_SESSION, 7 STATE_PROCESS_TIMEOUT, 9 RESTART, 10 START_STATE_MACHINE, 11 TTS_START, 12 TTS_END, 13 SOUND_PLAY_FINISH, 14 SR_TTS_FINISH, 16 DISPATCHING_RESULT, 17 CHECK_ONESHOT, 18 SPEECH_START, 19 SPEECH_PAUSE, 20 DISPATCH_REJECT, 21 DISPATCH_FAILED, 22 DISPATCHING_REJECT_RESULT, 23 SEMANTIC_TIMEOUT, 25 TOUCH_OF_ONESHOT.

Session types (`cd.a.f3461g`, `A()`): 1 = normal SR session (click/key/SDK, and also the wake word on Q05 because `oneShotDisabled=true`), 2 = command without recording (free-wake command words), 4/5 = TTS-then-SR (`TTSSequence`), 8 = oneshot wake session.

Mapping to Q07-like states:

| Q07-ish state | Q05 |
|---|---|
| idle | engine MVW, `U()==false`, container `l==false`, no sessions |
| listening | `F()` called, engine SR, session in Start/SR state |
| recognizing | engine states 200001 VOICE_START / 200016 RECOGNITION_ING, `onSpeechResult` partials |
| understanding | 200003 VOICE_END, then semantic (`duplex/d.H`) -> SemanticQueue -> `container.d` -> RouteState |
| speaking | HandleState + TTS (`cd.h.onTtsStart/onTtsEnd`, InteractionController `d=true`) |
| exit | InteractionController timeout -> `v()` -> `cd.l.a` -> `duplex/d$a.a(SessionError)` (listeners `onInteractionComplete()`) -> `G()` switchToVWMode (engine MVW, `X(false)`, end chime `SoundPoolPlayer.playSoundWhenSpeechEnd`) |

### 3.3 Session start paths (verified chains)

**A. Wake word** (fixed "小安…" / custom word; `comm.cfg mainWakeupWord "小安"`)

```
iFlytek MVW callback -> IflytekEngine.onWakeupResult(type=1001 fixed|1002 custom, word, channel, distribution 2001 in-car|2002 outside, z, s)  [private synchronized]
  -> DoaUtils.setWakeDirectionDefault(channel); setDecodePcmChannel(channel)
  -> handleWakeup(...) -> mWakeupHandler.post(IflytekEngine$d)            [thread "wakeup_thread"]
  -> IEngineListener.onFixWordWakeup(word, DoaUtils.getWakeDirectionInt(), i11, z)   = SessionManager e$a.onFixWordWakeup(Ljava/lang/String;IIZ)V
       (f0() wake interception: SpeechAvailabilityManager / reverse gear / OTA / pet mode)
  -> duplex.d.I -> AbsSessionMgrInner.Q(word, dir, false, false, oneShotDisabled=true, false, i11==2, z)   [SM3 session/b.smali:830]
       requestMvwStart; VoicePlayer.stopAll(1) if app session; d0(...) = startSRFromOneshot:
          Z(): requestSrStart + audio focus; SessionParams(wakeType "speech", needWelcome=!z, w(true))
          W(type 1, ...) -> new DuplexSession + HSM; container.f(W) -> G(push) -> cd.i.c(...) => listeners onRecordSessionStart
       listeners onFixWordWakeup(...) + onRecordStart()
  HSM StartState: Q()=needWelcome -> playWelcome() (GreetArbitration greeting) -> CMD 13 -> startRecord -> DuplexSession.o() -> N() true -> F("speech") -> SR
```

**B. Steering-wheel voice key** (see §7)

```
external app: startService(cmp=com.tinnove.wecarspeech/.app.LaunchService, act="com.tinnove.wecarspeech.Launch", extra_launch_type=7)
LaunchService.onStartCommand (main thread): ICarControlManager isVrDisabled/isCalling/isBackCar -> drop
 -> doLaunch(Landroid/content/Intent;II)V   [SM2 LaunchService.smali:493] case 7:
      canLaunchAsr() (SpeechAvailabilityManager, STT active, reverse gear, OTA, pet mode, power saving, record allowed)
      LaunchParams.Builder(1).setWakeType("sdk").setAsrSoundEnable(true)
 -> IVrAppManager(f8.b).launchVrApp -> (isSpeechVerified) -> f8.e msg 10017 -> f8.d.i -> j(): IVrApp.isInitSuccess()
 -> IVrClient.startSr -> (UI thread? -> ThreadUtils back thread) VrInterfaceImpl.startSr -> IVrLogicService.startSr (local binder)
 -> VrLogic.startSR(LaunchParams, cb)  (d7.a tracking; if on UI thread -> w.f pool)
 -> VFramework.startSR("sdk", true, cb):  if wakeType=="sdk" && engineMode==SR -> stopSR(); VoicePlayer.stopAll(); return   (TOGGLE OFF)
                                          else SessionManager.f -> f0() interception -> duplex.d -> b.f(): SessionParams(wakeType,needWelcome=asrSound) -> c0(1, params)
 -> duplex.d.c0 -> Z() (requestSrStart + RECORD_DUPLEX audio focus) -> B0(): new DuplexSession, container.f(W) (onRecordSessionStart), F("sdk") -> SR
    HSM StartState: needWelcome=true -> greeting via GreetArbitration, then record
```

**C. Screen / icon / launcher click**: `MainActivity` (singleInstance, exported) -> `LaunchService.launch(ctx, LaunchParams(1, "click"))` -> `doLaunch` (EXTRA_LAUNCH_PARAMS) -> `launchVrApp` -> same chain as B with wakeType `"click"` and asrSound false (no greeting, immediate SR). LaunchService type 5 = click with optional `extra_launch_play_welcome`. `"click_right"` selects the passenger seat (`IflytekEngine.prepareSwitchToSrMode`: `"click"`/`"sdk"` -> channel 0, `"click_right"` -> channel 1).

**D. SDK clients** (other apps, e.g. the VPA UI WT_AIAssistant): `WecarService` binder `com/tinnove/wecarspeech/vframework/service/a.java` `startSr(appId, launchParamsJson, cb)` -> `VFramework.startSR(launchParams.getWakeType() or "app", ...)`. `startSR(sessionParamsJson, ...)` / `startSTT(...)` -> SessionManager `s()`/`v()`.

**E. Text**: `VFramework.startAsrByText(String)` -> `SessionManager.x` -> active `d.startAsrByText` -> `lb.e.startAsrByText` -> `IflytekEngine.startAsrByText` -> `mAsrEngine.startAsrByText(str,false)`. **No session is created.** The resulting semantic goes `duplex.d.H` -> SemanticQueue -> `DuplexSessionContainer.d()`. With no top session and `l==false`, it logs `"drop this semantic"` and does nothing. So the mod must make sure a stock session is alive when it injects.

`VFramework.startSrByText(text, LaunchParams, cb)` does it in one call: `b.k()` creates a type-1 session (and `F(...)` -> SR) and sets `i=true`, then `getSemanticByText(text)` (15 s text-semantic timeout, msg 3001).

### 3.4 Session end paths

* InteractionController timeout -> `duplex.a.v(SessionError)` -> back thread -> `cd.l.a` (`duplex/c$a`) -> `duplex/d$a.a(SessionError)`, which:
  * notifies listeners `onInteractionComplete()`
  * starts a pending session if one was queued
  * otherwise calls `G()` (unless STOP_BY_SWITCH_MODE / MVW_EXCLUSIVE)
* `VFramework.stopSR()` -> `SessionManager.stopSR` -> `b.stopSR()` -> `container.e(0)` (interrupt all sessions STOP_BY_REQUEST, `InteractionController.A`) + `G()`.
* `VFramework.stopAllRecordSession(I)` -> `b.b(int)` (type 1 = STOP_BY_SWITCH_MODE, 2 = MIC_ABANDON).
* `VFramework.startSR("sdk",…)` while engine SR (key pressed again).
* LaunchService type 6 (`LaunchParams(11)` -> `f8.d.k`: `IVrClient.stopSr()` + `VrInterfaceImpl.stopAllTts()`), type 8 (`LaunchParams(12)` -> stopSr only), `IVrClient.closeVr()`.
* Engine `SPEECH_END_SR (200015)` (iFlytek SA "执行休眠") -> `G()`. `DUPLEX_SEMANTIC_REJECT_TIMEOUT (300003)` path -> `G()` (see §5).
* Security/availability change: `VFramework.onChange(false)` -> `mSessionMgr.stopSR()`.

---

## 4. "Is awake / session active" (VoiceStateCache.isWakeUp equivalent)

| Check | How | Semantics |
|---|---|---|
| `AbsSessionMgrInner.U()Z` | reflection: `VFramework.mInstance` -> `mSessionMgr` (session.e) -> package field `d:Lcom/tinnove/wecarspeech/vframework/session/d;` -> cast `session.b` -> `U()` (public) | **Best match for isWakeUp.** True from the first `F()` (SR) of a dialog until `G()` (back to MVW). Stays true across TTS and the multi-turn window. |
| `VFramework.isOpenSR()Z` (public) | `mSessionMgr.K()` -> `SessionMgrContainer.n()` -> `engine.getCurrentMode() == SR` | Engine is in SR. Updated asynchronously on "SwitchMode thread" (slight lag after `F`/`G`). |
| `EngineManager.getInstance().getEngine().getCurrentMode()` | public: `Lcom/tinnove/wecarspeech/vframework/EngineManager;->getInstance()`, `->getEngine()Llb/e;`, `Llb/e;->getCurrentMode()Lcom/tinnove/wecarspeech/speechengine/EngineMode;` | same as above |
| `DuplexSessionContainer.l:Z` / `h0()Z` (package-private) | reflection through `duplex.d` field `d` (container) | dialog/series window active |
| Own flag | hook `session/b.X(Z)V` or listener events | recommended (no reflection at query time) |

Not usable: `VrApp.isSpriteActive()` (`notifyAppStateChanged` is never called), `VrAppStatusBroadcastSender` (stubbed, only logs), `f8.d.d` (never reset).

---

## 5. Timeouts (defaults; config files in `resq05/assets/public/cfg/` do not override any of these unless noted)

| Timer | Value | Where | Effect |
|---|---|---|---|
| speechSilenceTimeout (no speech after SR start) | 8000 ms (`speechSilenceTimeout`, engine param 4) | `SessionConfigUtils.getDefaultSpeechSilenceTimeout`, set in `SessionMgrContainer.d0()` at every `G()` | engine `NO_SPEECH_TIMEOUT 200006` -> `duplex.d.w0()` -> top session `m(NO_SPEECH_TIMEOUT)` |
| speechTimeout (max utterance) | 10000 ms (param 3) | `getDefaultSpeechTimeout` | `VOICE_SPEECH_TIMEOUT 200007` -> `D0()` |
| vadEndSilenceTimeout | 460 ms (param 9); onlineVadEndSilenceTimeout 1000 ms (param 12, `enginesdk.cfg isEnableOnlineVad=true`) | | stock end-of-speech -> `VOICE_END 200003` |
| Weak-net / semantic wait after stock VOICE_END | `netReqTimeout`(6)*1000+500 = **6500 ms** | `duplex/b.handleSpeechEnd()` posts CMD 23 when in SR state; `cd/a.R()` -> `duplex.d.A()` -> `L(300003)` + **`G()`** | **Ends listening** if no semantic arrives within 6.5 s of the stock VAD's speech end. Cleared by `handleSpeechStart` (X()) or leaving SR (RouteState.exit removes 23). |
| Per-session process timeout | 25000 ms (CMD 7) in RouteState and HandleState (re-armed at TTS_END) | `DuplexSessionStateMachine` | InitState -> `h0(false, NO_SPEECH_TIMEOUT)` -> session finished |
| SemanticHandler wait per semantic | 25000 ms | `duplex/e.run` | |
| Text semantic (getSemanticByText) | 15000 ms (msg 3001) | `session/b.a0()` | `onTextSemanticTimeout` |
| **Interaction active time** (multi-turn window) | `Settings.Global "tinnove_continuous_conversation_duration"` ∈ {10,20,30} s, default 10 -> 10000 ms (`e9.b.q()`); pref fallback `continuityTalkSmallTime` 15 s; **0 if continuous-dialog switch off**; 30000 in AI mode | `VFSettings.getInteractionActiveTime()` -> `VrSettings$BinderC0172a` (`a8.a.c()` gate) | `duplex.a` MSG 1 on main looper -> `v()` -> interaction complete -> `G()` |
| Extension | +5000 ms once if ASR VAD active at expiry (`e && g`) | `duplex.a.w()` | |
| Beep-end delay | `timeBeepEnd` 300 ms | HSM StartState (`P()` beep) | |
| Oneshot interval | `oneShotDisableTimeInterval` 0 | StartState.playWelcome | |
| Simplex only (unused) | SRState: speechTimeout+5000; Route/Handle 25000 | `SimplexSessionStateMachine` | |

The InteractionController timer (`duplex.a.x()/y(j)`) is (re)armed in these places:
* `m()`: last session removed while in series, from `DuplexSessionContainer.M`
* `n()`: every semantic, via `container.H()` in `duplex.d.H`
* TTS end (`s(..,4|5|7)`)
* `START_BUSINESS_TIMER 200144` / `RESTART_BUSINESS_TIMER 200145`

It is cancelled by `r()` whenever a new session is pushed (`container.f/h`).

**Uncertain:** with pure silence after a wake, a static reading gives 8 s (no-speech) + up to 25 s (RouteState CMD 7, because `cd.a.K()` returns `true` for NO_SPEECH_TIMEOUT without completing the dispatch) + the active-time window. The real UI is probably closed earlier by the external VPA app (calls `stopSr`). To settle it, measure timestamps in logcat of `[AbsSessionMgrInner]switchToSRMode`, `[DuplexSessionManagerInner]NO_SPEECH_TIMEOUT`, `[DuplexSessionStateMachine]quitStateMachine`, `[InteractionController]notifyInteractionComplete`, `[AbsSessionMgrInner]switchToVWMode`.

---

## 6. Multi-turn behaviour

* Continuous dialog switch: `a8.a` (DuplexController).
  * `c()` = `duplex_switch` pref (default = `comm.cfg supportSwitchDuplexDefaultOpen: true`) && `supportSwitchDuplex: true`, so **ON by default**.
  * When off, `getInteractionActiveTime()` returns 0 and the dialog closes right after the first reply's TTS.
* When ON, the engine stays in **SR the whole window**. `G()` is not called between turns, and `duplexAfterTts` (`CONFIG_DUPLEX_SR_AFTER_TTS`) is absent from the config, so false: no explicit re-`F()` after TTS. The iFlytek ASR keeps producing VAD cycles; `duplex.d` counts them in field `n` (`f7246n++` per VOICE_END).
* Each later semantic with no top session and `l==true` creates a new DuplexSession (type 1, wakeType `"duplex"`, `container.F`). That fires `onRecordSessionStart` **after** the stock recognized the utterance, which is too late to be an arm signal.
* **Consequence for the mod:** arm capture at the first `F()`/`onRecordStart` of the dialog and **keep it armed (own VAD segmentation) until `X(false)`/`G()`/`onInteractionComplete`**. Gate on `cd.h.onTtsStart/onTtsEnd` if echo of our Russian TTS is a problem. Q07's per-turn `onSpeechStart` does not exist here.
* TTS state for gating: `DuplexSessionContainer$b` (`IFullVoicePlayStatusListener.onStatusChange(id, status, flag)`): status 1 -> listeners `onTtsStart()`, status 5 -> `onTtsEnd()`. flag==1 means non-dialog TTS, ignored by the timer.

---

## 7. Steering-wheel voice key

* TSpeech has **no KeyEvent/InputManager/car-input listener** for the voice key.
  * `SpeechA11yService` config has no key-event filtering.
  * The `com.tencent.tai.pal.input.*` CabinKey classes are the WeCarFlow PAL SDK, not wired to speech.
  * There is no `com.incall.sdakeyservice` client (Q07's CaKey has no counterpart). `com.incall.serversdk` only lists `ACTION_KEY_SERVICE = "com.incall.HARD_KEY_SERVICE"` in `SvrMngConstant` and has no key API.
* The key is handled by another system app. It is not in the dump: only WT_TSpeech.apk, `android.car.jar` and `car-frameworks-service.jar` were dumped; WT_SpeechMiddleware is listed in listing.txt but not extracted. That app starts **LaunchService with `extra_launch_type=7` (LAUNCH_TYPE_KEYCODE_START_SR)**.

Evidence:
* `LaunchService` constant `LAUNCH_TYPE_KEYCODE_START_SR = 7`.
* `com.tinnove.vrclient.test.LogTestActivity$o` (button `btnStartSr`, text **"模拟方控启动语音"** = "simulate steering-wheel-control voice start") sends exactly `Intent().setClassName("com.tinnove.wecarspeech","com.tinnove.wecarspeech.app.LaunchService").setAction("com.tinnove.wecarspeech.Launch").putExtra("extra_launch_type",7)`.

Yes, it **starts a normal stock session**: wakeType `"sdk"`, greeting played (asrSound=true -> needWelcome), driver seat (channel 0), then `F("sdk")` -> SR. So capture can arm on `F()`. Second press while SR: `VFramework.startSR` sees `"sdk"` + SR, then `stopSR()` + `VoicePlayer.stopAll()` (toggle off).

Hook options for key-specific behaviour (Q07 `onInteraction(2)` analogue):
* `LaunchService.doLaunch(Landroid/content/Intent;II)V` (SM2, private), inspect `intent.getIntExtra("extra_launch_type")==7`.
* Or the top of `VFramework.startSR(Ljava/lang/String;ZLcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V` (SM3 VFramework.smali:6659; `p1` = wakeType, `p2` = asrSound, `p3` = cb). This covers key, click and SDK.

The external sender might instead call the WecarService SDK `startSr(appId, {"wakeType":"sdk"...})`. That also ends in `VFramework.startSR`.

Runtime log to settle it:
* `[LaunchService]doLaunch launchType = 7`
* `LAUNCH_TYPE_KEYCODE_START_SR`
* or `[WecarBinder]startSr appId=...`
* then `[VFramework]wakeupType = sdk,engineMode = MVW`

---

## 8. Programmatic start / stop (for the mod)

1. **Click-wake (public API, recommended for "make sure a session exists before injecting"):**
   ```java
   VFramework.getInstance().startSR("click", false, new IStartResultCallback.Stub() {
       public void onStartSuccess() {}
       public void onStartFailed(int code, String msg) {}
   });
   ```
   * smali: `Lcom/tinnove/wecarspeech/vframework/VFramework;->startSR(Ljava/lang/String;ZLcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V`
   * callback class: `Lcom/tinnove/wecarspeech/vframework/IStartResultCallback$Stub;`
   * Pass a non-null callback; failure paths call it.
   * Call from a non-main thread (VrLogic does the same).
   * `"click_right"` selects the passenger seat.
   * asr=false means no greeting and immediate SR.
   * If a session already exists it is **interrupted and replaced** (`DuplexSessionContainer.G`). Only call when `U()==false`.
2. **Exactly like the voice wake word** (greeting, wake listeners, VPA wake animation), the Q07 `wakeLikeVoice` analogue:
   * reflection: `EngineManager.getInstance().getEngine()` (`lb.b`) -> private field `a` (`IEngineInterface` = `IflytekEngine`)
   * then private `onWakeupResult(ILjava/lang/String;IIZLjava/lang/String;)V` with `(1001, "小安你好", seatChannel(0/1), 2001, false, "")`
   * Same call the engine makes itself (IflytekEngine.java:1567).
   * It runs wake interceptions (STT active, all-wakeup-disabled, VPR register scene).
3. **Like the steering key:** `startService` LaunchService with action `com.tinnove.wecarspeech.Launch`, `extra_launch_type=7`. This goes through `canLaunchAsr()` and the UI controller. It toggles off if already SR.
4. **Start + inject in one step:** `VFramework.startSrByText(text, launchParams, cb)` (§3.3 E).
5. **Stop:** `VFramework.getInstance().stopSR()`. `VFramework.stopAllRecordSession(0)` is softer. LaunchService type 6 also stops TTS.

---

## 9. Sound zone / seat

* `comm.cfg`:
  * `voiceRegion: 2` (two zones)
  * `isVoiceRegionLock: true` (API `VFramework.voiceRegionLock(I)V`)
  * `clickStartSRAsMainSeat: true`
  * `micNumber 2`, `channelNumber 4`, `refChannel 2`
* Engine channel (`onWakeupResult` arg 3, `DoaUtils.getOriginalDirection()`): 0 = driver, 1 = passenger (2/3 rear, unused). It feeds `DoaUtils.setWakeDirectionDefault(ch)` -> `DoaManager.setWakeDirection` -> `convertDoa`, giving 0/-1 -> `DIRECTION_LEFT(2,"主驾")` and 1 -> `DIRECTION_RIGHT(3,"副驾")`. The engine also calls `setDecodePcmChannel(ch)`, so ASR decodes the waking seat's SE channel.
* Current zone: `DoaManager.getInstance().getCurrentDirection()` (`Lcom/tinnove/wecarspeech/vframework/doa/DoaManager;->getCurrentDirection()Lcom/tinnove/wecarspeech/speechcommon/doa/DoaDirectionMode;`). `toIntReal()` gives 2/3. It is also passed to `onRecordSessionStart(..., DoaDirectionMode)` and used as the semantic `channel`.
* MVW resets the direction to 0 (`switchModeInner` MVW branch). `"click"`/`"sdk"` force 0, `"click_right"` forces 1.
* `isDoaEnable` (`writeDoaEnable(true)` at VFramework.init) is required for these updates.
* Q07 zone 1..5 does not exist. For injection, rely on the stock current direction set at wake time (no zone parameter needed).

---

## 10. Threads (who calls what)

| Event | Thread |
|---|---|
| `VrApplication.onCreate`, `VrAppEntry.initVrApp`, LaunchService `onStartCommand/doLaunch`, `f8.e` handler | main |
| VrServerProcess init, `VFramework.init` | `w.d()` pool (bolts executor) |
| `VrApplication.onVrAllInitCompleted` | likely main (VrServerProcess posts with `w.j` = bolts UI executor, then the local binder callback). **Unverified**: log `Thread.currentThread()` in our hook. |
| Wake dispatch (`e$a.onFixWordWakeup` -> `b.Q` -> `onRecordSessionStart`, `onFixWordWakeup`) | `"wakeup_thread"` HandlerThread (IflytekEngine.mWakeupHandler) |
| `VFramework.startSR` via VrClient/VrLogic | ThreadUtils back thread (`"back"` HandlerThread) or a `w.f` pool thread; SDK calls run on binder threads |
| `F()` from the wake path (`DuplexSession.o()`) | `"duplex_session_state_machine_thread"` |
| Engine mode switch / `mCurrentMode` | `"SwitchMode thread"` |
| `onEngineState` / `onSpeechResult` / `onSemantic` | iFlytek SDK callback threads (not pinned down) |
| Semantic processing | `"SemanticHandler"` thread |
| InteractionController timer | main looper; `onInteractionComplete` is delivered via `ThreadUtils.runOnBackThread` |

`cd.h` listener callbacks are invoked synchronously on these threads. Our listener must not block and must be thread-safe. `X(Z)V` is `synchronized` on the manager.

---

## 11. Recommended hook plan (lifecycle part)

Minimal patching:

1. `SM2/com/tinnove/wecarspeech/app/VrAppEntry.smali` `initVrApp(Landroid/content/Context;)V`: after `if-eqz p0, :cond_0` insert `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->init(Landroid/content/Context;)V`. Do not touch VFramework inside it.
2. `SM2/com/tinnove/wecarspeech/app/VrApplication.smali` `onVrAllInitCompleted(ZLjava/lang/String;)V`: first instruction `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onVrReady(Z)V`. There:
   * register `VFramework.getInstance().registerSessionListener(new Q05Listener())`, where `Q05Listener extends Lcd/n;` (public, SM3)
   * override `onRecordStart()V`, `onRecordSessionStart(JZZZLjava/lang/String;Lcom/tinnove/wecarspeech/speechcommon/model/TipsHint;Lcom/tinnove/wecarspeech/speechcommon/doa/DoaDirectionMode;)V`
   * override `onRecordSessionFinish(JZ)V`, `onInteractionComplete()V`, `onEngineState(ILjava/lang/String;)V`
   * override the default methods `onTtsStart()V`/`onTtsEnd()V` (compile with min-api ≥ 24)
   * The listener list is `SessionMgrContainer.A()` (CopyOnWriteArrayList). `registerSessionListener` -> `SessionManager.H` -> `SessionMgrContainer.O(h)`.
3. More robust, Q07-style direct hooks (cover every source, no ordering issues):
   * `SM3/com/tinnove/wecarspeech/vframework/session/b.smali` `F(Ljava/lang/String;)I` (.locals 2; p0=this, p1=wakeType): at top `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onListenStart(Ljava/lang/String;)V`. Arms capture: wake word (`"speech"`), key (`"sdk"`), click, app, re-listen.
   * Same file `G()I` (.locals 4): at top `invoke-static {}, Lcom/stand/q05/Q05Bridge;->onListenStop()V` (dialog over / back to wake word).
   * Or a single hook at the top of `private declared-synchronized X(Z)V` (before `monitor-enter p0`): `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onSpeechActive(Z)V`. true = awake, false = asleep; it may fire repeatedly, so make it idempotent.
   * Optional: `SM3/.../session/duplex/d$a.smali` `a(Lcom/tinnove/wecarspeech/speechcommon/session/SessionError;)V` (onInteractionComplete).
   * Optional: `c(Lcd/e;ZLcom/tinnove/wecarspeech/speechcommon/doa/DoaDirectionMode;)V` (onRecordSessionStart). Inject at the very top: `p3` is overwritten by the first instruction (`const-string p3, ...`).
   * Optional: `SM3/.../VFramework.smali` `startSR(Ljava/lang/String;ZLcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V` to see/redirect key and click starts.
4. Keep the stock session alive while our recognizer works (see risks): neutralize the 6.5 s semantic-wait timer while capturing.
   * hook `Lcd/a;->R()V` (onRequestSemanticTimeout) to return early when the mod is busy
   * or hook `Lcom/tinnove/wecarspeech/vframework/session/duplex/b;->handleSpeechEnd()V`
   * or inject within 6.5 s of the stock `VOICE_END`

---

## 12. Runtime logs that settle open points

Logcat tag is `TSpeech_<versionName>` (set by `q.r(...)` in `VrApp.initLogUtil`). The message is prefixed with `[InnerTag]`. Grep for:

* `[VrAppEntry]` / `VrApplication` -> process and init order. Two `onCreate` lines appear: main and `:intraspeechserver`.
* `[SessionManager]duplexEnabled  = ` and `[VFramework]duplexEnabled:` -> confirms duplex manager.
* `[DuplexController]isDuplexOpen` -> continuous-dialog switch.
* `[InteractionController]refreshInteractionActiveTime, activeTime = ` -> real window length.
* `[LaunchService]doLaunch launchType = 7`, `[VFramework]wakeupType = sdk` -> steering key path.
* `[AbsSessionMgrInner]switchToSRMode, wakeType:` / `switchToVWMode` -> arm/disarm points.
* `[AbsSessionMgrInner]handleMainWakeup` -> wake-word path.
* `[DuplexSessionStateMachine]Session(id = …) : … enter` -> HSM transitions.
* `[DuplexSessionManagerInner]get DUPLEX_SEMANTIC_REJECT_TIMEOUT` -> session killed by the 6.5 s timer.
* `[DoaManager]convertDoa, directionMode:` -> seat.
