# Q05 (com.tinnove.wecarspeech, WT_TSpeech 2.5.3.19_beta) – TTS pipeline

KEY = tts. I checked everything against the jadx sources (`q05x/jx/sources`), the smali (`q05x/smq05/smali*`), the
decoded assets (`q05x/resq05/assets/public/cfg/*.cfg`), the resources (`res/raw`, `res/values/public.xml`) and the
native exports of `lib/arm64-v8a/libissxtts40.so`. Anything that is not statically certain is marked, together with the
runtime log that would settle it.

Abbreviations: `S1 = q05x/smq05/smali`, `S2 = q05x/smq05/smali_classes2`, `S3 = q05x/smq05/smali_classes3`,
`J = q05x/jx/sources`.

---------------------------------------------------------------------------------------------------

## 0. Summary

* **Stack (top to bottom):** dialog/session/SDK code → `VoicePlayer.getInstance()` (= singleton
  `com.tinnove.speechtts.impl.PlayerImpl`, which handles the queue, priorities, audio focus and callbacks) → engine
  abstraction `k7.b` ("BaseTTSPlayer"), implemented by `l7.a` ("IflytekPlayer") → `l7.b` ("IflytekTTSEngine"; it owns
  the **AudioTrack and the write thread**) → JNI `com.iflytek.speech.libisstts` (`libissxtts40.so` → `libxtts.so`).
  The previous claim "TTS synthesis is in l7.b" is **correct**. `VFramework.startAsrByText` is the text→NLU path and
  has nothing to do with TTS.
* **Playback** (for the shipped config `comm.cfg`: `ttsStream=9`, `forceRequestUserAndroidO=true`):
  `new AudioTrack(AudioAttributes{usage=11 USAGE_ASSISTANCE_ACCESSIBILITY, contentType=1 CONTENT_TYPE_SPEECH},
  AudioFormat{CHANNEL_OUT_MONO(4), ENCODING_PCM_16BIT(2), 24000 Hz}, bufferSize=AudioTrack.getMinBufferSize(24000,4,2),
  MODE_STREAM(1), sessionId=0)`. jadx decompiles `l7.b.s(I)` wrongly and gives contentType 0. The smali shows
  **contentType = 1 (SPEECH)** for stream 9.
* **Focus:** `AudioManager.requestAudioFocus(AudioFocusRequest(AUDIOFOCUS_GAIN_TRANSIENT=2, same attributes
  usage 11 / content 1, willPauseWhenDucked=true, acceptsDelayed=false))`, requested by PlayerImpl before each item.
  It is auto-abandoned after 2000 ms unless "play start" arrives, and abandoned when the item ends.
* **The state machine depends on** `IVoicePlayerCallback.onStatusChange(status, flag)`: 1 START, 2 COMPLETED, 3
  INTERRUPT, 4 ERROR, 5 END. In `cd.a$a` (AbsSession), 1 → HSM CMD 11 TTS_START and 5 → CMD 12 TTS_END. There is also
  `IFullVoicePlayStatusListener` (DuplexSessionContainer, IPC clients). All of these are derived from the 4 engine
  callbacks in `k7.b$a`: `a(id)` start, `b(id)` completed, `c(id,err)` error, `d(id,reason)` interrupted.
* **Q05 has no `module_config.txt`-style TTS engine registry.** `l7.a` is hard-coded in `PlayerImpl.init`. There are
  three dormant reflective slots (`com.tinnove.speechtts.impl.taes.TaesPlayer`, `...aispeech.AISpeechPlayer`,
  `...larklite.LarklitePlayer`). None of these classes exists in the APK, and nothing calls `VoicePlayer.setEngine`.
* **Recommended substitution (option a, the Q05 equivalent of Q07 PiperCaTts):** keep PlayerImpl, l7.a, l7.b, the
  AudioTrack, the write thread, focus and callbacks 100 % stock, and **replace only the JNI engine**. Retarget the
  `invoke-static Lcom/iflytek/speech/libisstts;->…` call sites in **`S2/l7/b.smali`** (it is the only class in the APK
  that calls libisstts) to a mod class `Lcom/stand/q05/RuIssTts;` with identical static signatures. RuIssTts receives
  the Chinese text in `start()`/`appendText()`, translates it, synthesizes 24 kHz mono s16 PCM with TeraTTS, and
  returns it from `getAudioData()`. The stock write thread then plays it through the stock AudioTrack. RuIssTts fires
  `ITtsListener.onTtsMsgProc(20000,…)` and returns `ISS_ERROR_TTS_COMPLETED=10004` at the end. Everything else
  (start/complete/interrupt callbacks, fade-out on barge-in, focus, AEC reference, stream switching) then behaves
  exactly as for stock Chinese TTS.
* **Earcons:** the stock wake response on Q05 (Duplex) is a **spoken TTS greeting**
  (`GreetArbitration.i` → `SoundPoolPlayer.playSoundWithTTS` → `PlayerImpl.playWelcomeTTS`), not a ding. It goes through
  the same TTS pipeline, so RuIssTts catches it. The SoundPool "dingdang" earcons only play when `comm.cfg:play_earcon`
  is set. It is absent, so it defaults to false and they are silent. The startup prompts `speech_starting.wav` /
  `speech_comming.wav` play through a separate SoundPool (`g8.d`) with the same usage 11 / content 1.

---------------------------------------------------------------------------------------------------

## 1. Class map (obfuscated ↔ readable ↔ smali)

| obfuscated | readable (from `compiled from:` / log tags) | smali |
|---|---|---|
| `com.tinnove.wecarspeech.vframework.voiceplayer.VoicePlayer` | facade, `getInstance()` returns `PlayerImpl.getInstance()` | `S3/com/tinnove/wecarspeech/vframework/voiceplayer/VoicePlayer.smali` |
| `com.tinnove.speechtts.impl.PlayerImpl` | PlayerImpl (implements `IVoicePlayer`), log tag "PlayerImpl" | `S2/com/tinnove/speechtts/impl/PlayerImpl.smali` |
| `PlayerImpl$k` | `k7.b.a` impl = engine callback sink (`S` field) | `S2/.../PlayerImpl$k.smali` |
| `PlayerImpl$j` | `k7.a.InterfaceC0318a` impl = raw-audio player callback sink (`R` field) | `S2/.../PlayerImpl$j.smali` |
| `PlayerImpl$c` | "startPlayInner" runnable (focus request + `C.m(...)`) | `S2/.../PlayerImpl$c.smali` |
| `PlayerImpl$o` / `$m` / `$n` | enqueue TTS / audio file / raw audio (`Q(item)`) | |
| `PlayerImpl$p`, `$d`, `$a` | stop(id), stopPlayInner, stopAll runnables | |
| `com.tinnove.speechtts.impl.c` | VoiceItem | `S2/com/tinnove/speechtts/impl/c.smali` |
| `com.tinnove.speechtts.impl.a` | AudioFocus (requestAutoAbandon / cancelAutoAbandon / abandon) | `S2/com/tinnove/speechtts/impl/a.smali` |
| `k7.b` (+`k7.b$a`) | BaseTTSPlayer (+ its callback interface) | `S2/k7/b.smali`, `S2/k7/b$a.smali` |
| `k7.a` (+`k7.a$a`) | BaseAudioPlayer (raw/audio-file player) | `S2/k7/a.smali` |
| `k7.d`, `k7.c` | MockTTSPlayser / MockAudioPlayer (test mode only, `setTest(true)`) | |
| `l7.a` (+`l7.a$a`) | IflytekPlayer (extends `k7.b`), log tag "IflytekPlayer"; `l7.a$a` = `l7.c` impl that forwards to `k7.b$a` | `S2/l7/a.smali`, `S2/l7/a$a.smali` |
| `l7.b` | **IflytekTTSEngine** (implements `com.iflytek.speech.tts.ITtsListener`), log tag "IflytekTTSEngine" | `S2/l7/b.smali` |
| `l7.b$b` | AudioWriteWorking runnable (the write thread) | `S2/l7/b$b.smali` |
| `l7.c` | IflytekTTSListener (engine → player callbacks) | `S2/l7/c.smali` |
| `com.iflytek.speech.libisstts` | JNI, `System.loadLibrary("issxtts40")`, `("issauth")` | `S1/com/iflytek/speech/libisstts.smali` |
| `com.iflytek.speech.NativeHandle` | `{public int err_ret; public long native_point}` | `S1/com/iflytek/speech/NativeHandle.smali` |
| `j7.a` | AudioPlayer ("AudioPlayer_raw"), extends `k7.a`; plays raw PCM resources | `S2/j7/a.smali` |
| `z8.b` / `z8.a` | VrAudioFocusManager / AndroidFocusManager | `S2/z8/b.smali`, `S2/z8/a.smali` |
| `ad.b` / `com.tinnove.wecarspeech.vframework.resource.audiofocus.a` | ResourceManager / AudioFocusManagerProxy | `S3/ad/b.smali`, `S3/com/tinnove/wecarspeech/vframework/resource/audiofocus/a.smali` |
| `cd.a` (+`cd.a$a`) | AbsSession and its TTS callback wrapper | `S3/cd/a.smali`, `S3/cd/a$a.smali` |
| `com.tinnove.wecarspeech.vframework.session.common.sound.SoundPoolPlayer` | earcon SoundPool | `S3/.../session/common/sound/SoundPoolPlayer.smali` |
| `com.tinnove.wecarspeech.vframework.session.common.GreetArbitration` | wake greeting selector | `S3/.../session/common/GreetArbitration.smali` |
| `g8.d` | WtSoundPoolPlayer ("voice is starting" prompts) | `S2/g8/d.smali` |

Native libraries: `libissxtts40.so` exports `Java_com_iflytek_speech_libisstts_{appendText,create,destroy,getAudioData,
getSpeakerList,getVersion,initRes,prepare,retrieveCacheLog,setLogCfgParam,setMachineCode,setParam,setParamEx,start,stop,
unInitRes}` and calls back `onTtsMsgProc(IILjava/lang/String;)V` and `onProgress(II)V`. NEEDED: libissauth, **libxtts**,
libwebsockets, libzmq, libidas, libopencc, liblesl, libgnustl_shared … `libxtts.so` (24 MB) is the xTTS 4.0 core.
Voice resources: `TTSDataManager.TTS_PATH + "iflytek/xTTS40Res"` (`comm.cfg:iflytekXTTSVersion=4`; with 3 it would be
`xTTS30Res`). `TTS_PATH = h.k() + "tts/"`, which is probably the `inlineDataRootPath` `/resources/appdata/tinnove/WT_TSpeech/`.
`l7.b.A()` may override it with `v8.b.a().f()`. Log line to confirm: `IflytekTTSEngine … init resource,path is:`.

---------------------------------------------------------------------------------------------------

## 2. Call chain and threads

```
(any caller) VoicePlayer.getInstance().playTTS(...) / playWelcomeTTS / playMultiTTS / startTtsSynthesize
  callers: cd.a.playTTS (AbsSession, dialog replies), session.b.j (closure TTS), session.e (system prompts:
           "倒车中，请专心停车" …), SpeechAvailabilityManager, vframework.service.a (WecarBinder / SDK clients:
           skills, applets, A11), vrlogic.server.a (IPC), SoundPoolPlayer$b (greeting)
  -> PlayerImpl.playTTS(IILjava/lang/String;IZLjava/lang/Integer;IZIIJLcom/tinnove/speechtts/IVoicePlayerCallback;)I
       [declared-synchronized; every TTS overload ends here; caller thread]
       builds VoiceItem c(id=W(), type=1).F(text).z(priority).v(cb).w(completeDelay).G(emotion).I(stream).B(requestFocus)
                .x(mode).D(soundEffect).y(multiIntention).H(speed).E(taskId).t(appendState)
       l0(new PlayerImpl$o(item))          -> posts to HandlerThread "ThreadVoice"
  -> [ThreadVoice] PlayerImpl.Q(item) (queue/priority, may stop current item with reason 0 or 21)
       -> R(item)/S() -> n0(item) -> l0(new PlayerImpl$c(item))
  -> [ThreadVoice] PlayerImpl$c.run():
       focusOk = AudioFocus.c(item.stream, vrStream(-997), 2000L, focusType(4))   (if requestFocus && appendState∉{2,3})
       C.m(text, id, emotion, stream, mode, soundEffect, focusOk, speed, appendState)
  -> l7.a.m(Ljava/lang/String;IIIIIZII)V   [ThreadVoice]
       !focusOk -> k7.b$a.c(id,-5) (error) ; stream != current -> l7.b.K(stream) (rebuild AudioTrack)
       text2 = "[d][e"+soundEffect+"][s"+speed+"]" + ( "[em"+emotion+"]" if 0<emotion<14 ) + text
       l7.b.Q(mode); l7.b.O(appendState==0?0:1)   (only for appendState 0/1)
       l7.b.S(text2, appendState)
  -> l7.b.S(Ljava/lang/String;I)I [ThreadVoice]
       appendState 0/1: W(22)  (interrupt the item that is currently playing, with fade-out)
       e.set(false)  (data-ready flag)
       T(text) [appendState 0]  or  U(text, appendState) [1/2/3]   -> libisstts.start / appendText
       error -> ISynthesizerListener.onErrorRet + l7.c.e(err)
       appendState 2/3 -> return 0 (already playing)
       AudioTrack.play(); k.set(1); l.notifyAll()
  -> [native iFlytek thread] l7.b.onTtsMsgProc(20000 local | 20001 cloud | 20005 cache, …)
       e.set(true); l.notifyAll(); l7.c.a(isCloud) (data ready); l7.c.b() (onTTSPlayBegin)
  -> [write thread "b" (initial) or "reset_tts_<stream>", Process.setThreadPriority(-16)] l7.b$b.run():
       loop while k==1 && e==true:
         ret = l7.b.t(buf, minBuf, outLen)  == libisstts.getAudioData(handle, buf, minBuf, outLen); ret := handle.err_ret
         0 / 10024 with outLen>0 -> (fade if interrupt flag) AudioTrack.write(buf,0,outLen)  or ISynthesizerListener.onDataRet
         0 with outLen==0         -> l.wait(20 ms)
         10004 (TTS_COMPLETED)    -> k=0; X() (libisstts.stop); pause(); flush(); l7.c.c()  (onTTSPlayCompleted)
         10613                    -> continue (no wait)
         10003 (TTS_STOPPED)      -> busy retry up to 500 times, then error path
         other                    -> error: k=0; X(); pause(); flush(); l7.c.e(0)
  -> l7.a$a (l7.c) -> k7.b$a == PlayerImpl$k:
       b() -> a(id) onPlayStart  -> PlayerImpl.j0: cancel focus auto-abandon; d0(id, 1 START)
       c() -> b(id) onPlayCompleted -> PlayerImpl.f0: postDelayed(completeDelay or 0) -> c0(id,2 COMPLETED) + g0 -> abandon focus, d0(id,5 END), next item
       d(r)-> d(id,r) onPlayInterrupted -> PlayerImpl.i0: d0(id,3 INTERRUPT,r) + g0 -> 5 END
       e(c)-> c(id,c) onPlayError -> PlayerImpl.h0: d0(id,4 ERROR,c) + g0 -> 5 END
       onProgress(a,b) -> f(id,a,b) -> IVoicePlayerCallback.onProgress(a,b)
  -> PlayerImpl.d0/e0: IVoicePlayerCallback.onStatusChange(status, flag) on the single-thread executor f6325i;
       IFullVoicePlayStatusListener.onStatusChange(id,status,flag) (+ onTtsTextChange(text, flag) on START)
```

Threads:
* the caller thread for `playTTS` (synchronized);
* **"ThreadVoice"** (HandlerThread in `PlayerImpl.init`), which runs queue logic, focus requests, `l7.a.m`,
  `l7.b.S/T/U` (so `libisstts.start/appendText` run here) and `stop` (`PlayerImpl$p` → `l7.a.w` → `l7.b.W` → `X()`
  → `libisstts.stop`);
* the **write thread** `l7.b$b`, named `"b"` (from `getClass().getSimpleName()`), or `"reset_tts_<stream>"` after
  `J()`/`K()`. Priority -16. It calls `getAudioData`, `AudioTrack.write` and `l7.c.c()/e()`, and also `X()` on
  completion and error;
* the iFlytek native callback thread, for `onTtsMsgProc` / `onProgress`;
* the PlayerImpl single-thread executor, for `IVoicePlayerCallback` / `IFullVoicePlayStatusListener` dispatch;
* the main looper, for the focus auto-abandon timer (`impl.a`).

---------------------------------------------------------------------------------------------------

## 3. Where the reply TEXT is available (signatures, registers)

| level | signature | text register | notes |
|---|---|---|---|
| master entry (all TTS) | `Lcom/tinnove/speechtts/impl/PlayerImpl;->playTTS(IILjava/lang/String;IZLjava/lang/Integer;IZIIJLcom/tinnove/speechtts/IVoicePlayerCallback;)I` (S2 PlayerImpl.smali:4099, `.locals 16`) | **p3** (v19). p1 emotion, p2 streamType, p4 priority, p5 requestFocus, p6 completeDelay(Integer), p7 mode, p8 multiIntention, p9 speed, p10 appendState, p11:p12 taskId (J), p13 callback | Caller thread. The first instruction copies p3 into v4. To rewrite the text, insert before `move-object/from16 v4, p3`: `invoke-static/range {p3 .. p3}, L…;->x(Ljava/lang/String;)Ljava/lang/String;` + `move-result-object p3`. A /range invoke is needed because p3 > v15. The item text also feeds `IFullVoicePlayStatusListener.onTtsTextChange` (UI subtitle in DuplexSessionContainer) and the cloud upload. |
| greeting | `Lcom/tinnove/speechtts/impl/PlayerImpl;->playWelcomeTTS(Ljava/lang/String;I)I` (S2:5204, `.locals 14`) | **p1** (v15). p2 = 1 inner speaker, else outside stream | Calls master playTTS with taskId **1L**, priority 2, emotion 5 for 早上好/中午好/下午好/晚上好, otherwise 0. If `!MachineCode.isAuthorization()` the text is replaced by `MachineCode.getTTSNoAuthorization()`. |
| engine-player entry | `Ll7/a;->m(Ljava/lang/String;IIIIIZII)V` (S2/l7/a.smali:581, `.locals 2`) | **p1** raw text. p2 item id, p3 emotion, p4 streamType, p5 mode(ttsMode), p6 soundEffect, p7 focusOk(Z), p8 speed, p9 appendState | ThreadVoice. This is the last point that still knows the item id. |
| engine | `Ll7/b;->S(Ljava/lang/String;I)I` (S2/l7/b.smali:3424) | p1 = `"[d][e<fx>][s<speed>]"`(+`"[em<n>]"`)+text, p2 appendState | ThreadVoice |
| JNI boundary | `Lcom/iflytek/speech/libisstts;->start(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;)I`, `->appendText(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;I)I` | string arg | Final text. In streaming mode U() adds "。" for appendState 1 and maps `"!@#%^"` to "。" for appendState 3. |

`appendState` (VoiceItem `a()`) is 0 = whole text, 1 = first chunk of a streamed (LLM) answer, 2 = middle chunk,
3 = last chunk. Mapping in `l7.b.U`:
* state 1 → `start(h,"")` + `appendText(h,text,0)`
* state 2 → `appendText(h,text,1)`
* state 3 → `appendText(h,text,2)`

In `l7.b.T` (state 0) with `enginesdk.cfg:isUseMultiStyle=false` (shipped) the call is just `start(h,text)`. With
true it would be `start(h,"")` + `appendText(h,text,2)`.

---------------------------------------------------------------------------------------------------

## 4. Synthesis and playback internals (l7.b)

* Init: `l7.a.l(Context,k7.b$a,int stream,String resPath,String deviceId,boolean)` → `l7.a.B()` → `new l7.b()` →
  `l7.b.A(stream, deviceId)`. The steps in `A` are `setMachineCode`, `initRes(path,1)`, `create(handle, this)`,
  `setParam(1289 mode)`, `setParam(1537 cache)` (`ttsCacheEnabled=true`), and `setParam(24580 emotion scale -9)`.
  `A` then creates the AudioTrack with `I(stream, minBuf)` and starts the write thread. After that `P(new l7.a$a())`
  sets the l7.c listener, and `k7.b$a.onInit()` sets `PlayerImpl.f6332p` (mIsTTSPlayerInit). `PlayerImpl.playTTS`
  refuses text (status 4 then 5, flag -1) until this flag is set.
* AudioTrack factory `Ll7/b;->I(II)Landroid/media/AudioTrack;` (b.smali:528):
  * if `comm.cfg:forceRequestUserAndroidO` (true in APK):
    `new AudioTrack(s(stream), new AudioFormat.Builder().setChannelMask(4).setEncoding(2).setSampleRate(B=24000).build(), minBuf, 1, 0)`;
  * else `new AudioTrack(stream, 24000, 4, 2, minBuf, 1)`.
  * `minBuf = AudioTrack.getMinBufferSize(24000, 4, 2)` (field `l7.b.i`).
* `Ll7/b;->s(I)Landroid/media/AudioAttributes;` (b.smali:1150), mapping verified from the smali (jadx is wrong for
  9/10/0):

| stream | usage | contentType |
|---|---|---|
| 0 | 2 VOICE_COMMUNICATION | 1 SPEECH |
| 3 | 1 MEDIA | 2 MUSIC |
| 5 | 11 ASSISTANCE_ACCESSIBILITY (or 10 NOTIFICATION_EVENT if `outsideVoiceTTSScheme==2`) | 0 UNKNOWN (1 if scheme 2) |
| **9 (shipped `ttsStream`)** | **11 USAGE_ASSISTANCE_ACCESSIBILITY** | **1 CONTENT_TYPE_SPEECH** |
| 10 | 12 ASSISTANCE_NAVIGATION_GUIDANCE | 1 SPEECH |
| 13 | 16 ASSISTANT | 3 MOVIE |
| other | -1 → Builder falls back to UNKNOWN | -1 → UNKNOWN |

* The stream value comes from `SessionConfigUtils.getTtsStreamType()`, which returns `comm.cfg:ttsStream` = **9**
  (because `useAndroidAudioFocus=true`; `usageType` is also 9). The value travels through `VFramework` (line ~1890) →
  `VoicePlayer.init(...)` → `IConfig.getTTSStreamType()` → `PlayerImpl.f6327k`. It can later be changed by
  `VrAudioFocusManager.setAudioFocusManager` → `PlayerImpl.setStream(vr, tts, useAttr)`, but `z8.a.getAudioType`
  returns the same configured value. Per-item streams: an outside-car session uses
  `comm.cfg:outsideCarTtsStream`, which is absent, so -1, so the default stream is used. An A11 call that passes
  stream 5 or 9 makes `l7.b.K(stream)` rebuild the AudioTrack and its write thread.
* Completion detail that matters for injected PCM: when getAudioData returns 10004 the write thread calls
  `AudioTrack.pause(); flush()` **immediately** (b$b.smali:296-330). Anything still in the AudioTrack buffer, about
  `minBuf` bytes plus HAL latency, is **discarded**. iFlytek output evidently ends with silence. **Injected PCM must be
  padded with about 250-300 ms of zeros before signalling 10004**, otherwise the last syllable is clipped.
* Interrupt: `Ll7/b;->W(I)I` (b.smali:4237) sets fade flag `z=true` and waits up to 300 ms on `A`. The write thread
  fades the next chunk linearly (`q([B)[B`), sets `k=0` and notifies. `W` then calls `X()` (stop), `pause()+flush()`,
  `l7.c.d(reason)`. `l7.a.w(II)V` additionally calls `k7.b$a.d(id, reason)`, so interrupt can be reported twice; that
  is stock behaviour and harmless. Reasons seen: 0 = stop/stopAll, 20 = `VoicePlayer.STOP_REASON_SPEECH_START`
  (barge-in), 21 = replaced by a same-stream item (focus kept), 22 = new speak().
* Synthesize-only mode (`startTtsSynthesize` → `l7.b.V`): if `t==true && u!=null` the PCM goes to
  `ISynthesizerListener.onDataRet(byte[],isFirst,isLast)` instead of the AudioTrack. It is used by `hb.a` /
  `vrlogic.server.a` (IPC `startTtsSynthesize`). The same getAudioData source feeds it.
* `onProgress(II)` comes from native and is forwarded to `IVoicePlayerCallback.onProgress`. Nothing in the
  session/state machine depends on it.

---------------------------------------------------------------------------------------------------

## 5. Audio focus

* Request: `PlayerImpl$c.run` → `com.tinnove.speechtts.impl.a.c(stream=9, vrStream=-997, 2000L, focusType=4)` →
  `VoicePlayer$c.requestAudioFocus` → `ad.b` (ResourceManager) → `resource.audiofocus.a` (proxy with usage
  ref-count) → `z8.b.h` (counts `vrTtsFocusCount`; first acquire → `VFramework.setSpeechState(7,22)`) →
  `z8.a.requestAudioFocus(9,-997,AUDIO,4)`. Because `forceRequestUserAndroidO=true` this is
  **`AudioManager.requestAudioFocus(new AudioFocusRequest.Builder(2 /*AUDIOFOCUS_GAIN_TRANSIENT*/)
  .setOnAudioFocusChangeListener(z8.a$a).setAcceptsDelayedFocusGain(false).setAudioAttributes(usage 11, content 1)
  .setWillPauseWhenDucked(true).build())`**. `focusType=4` (`comm.cfg:audioFocusType`) is only used on the legacy path.
* Auto-abandon: `impl.a.c` posts an abandon after **2000 ms** on the main looper. It is cancelled only when the engine
  reports play start (`PlayerImpl.j0` → `impl.a.b()`). **Consequence for the mod: "play begin"
  (`onTtsMsgProc(20000)`) must fire well before 2 s, even if the first Russian sentence is still synthesizing.**
* Abandon at end: `PlayerImpl.g0` → `impl.a.a()` unless the reason is 21 or the item has `isNeedSaveFocus` →
  `abandonAudioFocusRequest`. The ref-count then reaches 0 and `setSpeechState(7,23)` is set.
* Focus loss −1/−2 → `z8.a$a.onAudioFocusChange` → `VoicePlayer.getInstance().stopAll()`.
* If focus is refused, `l7.a.m` reports error −5 (status 4 then 5) and nothing is played.
* `comm.cfg` `audioFocusViaSSA` / `newAudioFocusViaSSA` are defined as constants but never read. The IPC focus
  manager (`vrlogic.server.a$e`, `VrClientAudioManager`) is registered but nobody calls `setAudioFocusManager` on it,
  so `z8.a` is what runs.

---------------------------------------------------------------------------------------------------

## 6. Callbacks the dialog state machine depends on

* `cd.a.playTTS(String,int,long,IVoicePlayerCallback)` (AbsSession) wraps the caller's callback in `cd.a$a`:
  * status **1** → `f3473s=true; Y(11)` (HSM CMD 11 TTS_START);
  * status **5** → `f3473s=false; Y(12)` (CMD 12 TTS_END; it restarts the 25 s HandleState timer), `f3476v=-1`,
    `VFramework.setSpeechState(4,18)`;
  * all statuses are passed on to the original callback.
* `session.b.j` (closure session) acts on `onPlayCompleted` (status 2) → `F(...)` (next step).
* `DuplexSessionContainer$b` (IFullVoicePlayStatusListener): status → `InteractionController.s(id,status,flag)` plus
  `onTtsStart`/`onTtsEnd` to session listeners. `onTtsTextChange(text, flag!=1)` → `h.onTtsText(0,text)`, which is
  the **on-screen TTS text**.
* `vrlogic.server.a` (IPC) → `IpcTtsCallback.onTtsBegin/onTtsEnd` on statuses 1 and 5.
* Every one of these is produced inside PlayerImpl from the four engine callbacks
  (`Lk7/b$a;->a(I)V`, `->b(I)V`, `->c(II)V`, `->d(II)V`). Keeping l7.b's own logic (option a) means they keep coming
  in the stock order: START at data-ready, COMPLETED then END after the last write, INTERRUPT then END on stop,
  ERROR then END.

---------------------------------------------------------------------------------------------------

## 7. Pluggability (compared with the Q07 module_config.txt + ICaStreamTts)

* Q05 has no `assets/module_config.txt` and no `ICaStreamTts`-style interface for TTS.
* `PlayerImpl.init` hard-codes `const-class p2, Ll7/a;` + `newInstance()` (PlayerImpl.smali:3365). On exception it
  falls back to `U()` → `Class.forName("com.tinnove.speechtts.impl.taes.TaesPlayer")` (PlayerImpl.smali:1337).
* `PlayerImpl.setTTSEngine(TTSEngineType)` (PlayerImpl.smali:5739) can switch at runtime to
  `"com.tinnove.speechtts.impl.larklite.LarklitePlayer"` (:5811) or `"…aispeech.AISpeechPlayer"` (:5853) by reflection.
  None of the three classes exists in the APK and nothing calls `VoicePlayer.setEngine`. These are dormant plugin
  slots. A `k7.b` subclass placed under one of these names and activated with `VoicePlayer.setEngine(LARKLITE)` would
  plug in with no stock smali patch. It would then have to own the AudioTrack itself (see option b).
* The real "engine boundary" in Q05 is the static JNI class `libisstts`. **It is referenced only from `S2/l7/b.smali`
  (26 call sites, all `invoke-static`; no field refs, because the constants are inlined).** That makes it the
  cleanest substitution point.

---------------------------------------------------------------------------------------------------

## 8. RECOMMENDED: option (a) – fake JNI engine, stock player/callback path

### 8.1 Patch

In `S2/l7/b.smali` only, retarget libisstts calls to `Lcom/stand/q05/RuIssTts;` (same method names and descriptors).

Minimal set:

| line | instruction | in method |
|---|---|---|
| 878 | `invoke-static {v0}, Lcom/iflytek/speech/libisstts;->stop(Lcom/iflytek/speech/NativeHandle;)I` | `X()I` |
| 1296 | `invoke-static {v0, p1, p2, p3}, …->getAudioData(Lcom/iflytek/speech/NativeHandle;[BI[I)I` | `t([BI[I)I` (write thread) |
| 2018 | `invoke-static {p2, p0}, …->create(Lcom/iflytek/speech/NativeHandle;Lcom/iflytek/speech/tts/ITtsListener;)I` | `A(ILjava/lang/String;)I` (to capture the listener = the `l7.b` instance) |
| 4023, 4038 | `…->start(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;)I` | `T(Ljava/lang/String;)I` |
| 4030 | `…->appendText(Lcom/iflytek/speech/NativeHandle;Ljava/lang/String;I)I` | `T` (multi-style branch) |
| 4163 | `…->start(…)` | `U(Ljava/lang/String;I)I` |
| 4170, 4182, 4211 | `…->appendText(…)` | `U` |

Simplest variant: `sed 's#Lcom/iflytek/speech/libisstts;->#Lcom/stand/q05/RuIssTts;->#g'` over the whole file. It
also covers `setParam`/`setParamEx`/`initRes`/`setMachineCode`/`destroy`/`unInitRes`/`setLogCfgParam` (lines 249,
287, 442, 484, 487, 1894, 1959, 2882, 2937, 3298, 3352, 4806-4827). RuIssTts passes those straight through to the
real `libisstts`. This keeps a single switch: when the mod is disabled or unlicensed, every method delegates to
libisstts and the stock Chinese TTS works unchanged.

Optional: a "kill native" variant, where RuIssTts stubs `initRes`/`create`/`setMachineCode` and sets
`h.native_point=1` and `err_ret=0`. libissxtts40 is then never loaded, and TTS no longer depends on the iFlytek TTS
licence or resources. **Phase 2 only**; `T()` checks `native_point != 0`.

No other stock file needs touching for TTS audio.

### 8.2 RuIssTts contract

l7.b reads `handle.err_ret`, not the return value. **Every fake must set `h.err_ret`.**

* `create(NativeHandle h, ITtsListener l)`: `r = libisstts.create(h,l); listener = l; return r;`
* `start(h, text)` (ThreadVoice), and `appendText(h, text, mode)` with mode 0 = first, 1 = middle, 2 = last:
  * strip the tags `\[(d|e\d+|s\d+|em\d+|[a-zA-Z]{1,2}\d*)\]`;
  * a non-empty `start` text is a complete utterance; `start(h,"")` opens a streaming job; `appendText(…,2)` closes it;
  * the `"。"` that U() appends and the `"!@#%^"`→`"。"` substitution are harmless.
  * Cancel any previous job, create a new job (generation counter), set `h.err_ret=0`, return 0.
  * On a worker thread, **first** call `listener.onTtsMsgProc(20000, 0, "")` (ISS_TTS_MSG_LocalResult). This sets
    l7.b's data-ready flag `e`, wakes the write thread, and fires `l7.c.a(false)` + `l7.c.b()` → STATUS_START → cancels
    the 2-second focus auto-abandon.
  * Do not call it synchronously inside `start()`. Stock calls it asynchronously from native, and `S()` clears `e`
    *before* calling `T/U`, so any later call is safe.
  * Then translate (`ttsTextToRu` port of Q07Bridge), apply `Replies.vary`, split into sentences
    (`TeraTts.sentences`), call `TeraTts.synthPcm16(sentence, 24000)` (AudioTrack rate is 24000, the same RATE as Q07
    PiperCaTts) and append to a byte FIFO.
  * At the end, append **≥300 ms of zeros (14400 bytes)**, then mark the job DRAINING.
  * For streaming jobs (mode 0/1), either accumulate until mode 2 (needed for whole-phrase translation), or
    synthesize each sentence as soon as a 。！？ terminator arrives.
* `getAudioData(h, buf, len, outLen)` (write thread; must be non-blocking or briefly blocking):
  * copy `n = min(available, len & ~1)` bytes, set `outLen[0]=n`, `h.err_ret=0`, return 0.
  * If nothing is available yet: `outLen[0]=0`, `err_ret=0`. The stock thread then waits 20 ms.
    **Never return 10003**: that path busy-loops without waiting.
  * Only when the current job is DRAINING and the FIFO is empty: `err_ret = 10004` (ISS_ERROR_TTS_COMPLETED), once.
    The stock thread then pauses and flushes the AudioTrack and fires `onTTSPlayCompleted` → STATUS_COMPLETED + END.
  * After `stop()` (IDLE job) return 0/0, **not** 10004. Otherwise a stale 10004 racing with a new `S()` could report
    completion for the next item id.
  * Empty translation, or a deliberately dropped phrase: still fire `onTtsMsgProc(20000)` and complete with a short
    silence. The state machine then sees a normal START → END.
* `stop(h)`: cancel the job (generation++), clear the FIFO, `h.err_ret=0`. It is idempotent and called from
  ThreadVoice (`W`, `N`) and from the write thread (after 10004 or an error). Optionally also call the real
  `libisstts.stop(h)`; it is harmless while the native engine is idle.
* PCM format: signed 16-bit little-endian, mono, 24000 Hz, even byte counts. Normalize the level to match stock
  (iFlytek volume param 1284 = 0 "normal"; Q07 used `Fix.norm`). Check by ear or with `dumpsys media.audio_flinger`.
* Greeting detection: `l7.b` only sees text. Either text-match the GreetArbitration words, as Q07 does with
  `isWakeGreeting`, or mark greetings at the source by inserting at the top of `PlayerImpl.playWelcomeTTS`
  (`.locals 14`, so p1 = v15 and a 35c invoke is legal):
  `invoke-static {p1}, Lcom/stand/q05/RuIssTts;->markWelcome(Ljava/lang/String;)V`.
  The greeting words are:
  * 在 / 我在 / 在呢 / 来啦 / 来了来了 / 唉 / 啥事 / 请说 / 听着呢 / 我在听 / 咋了 / 咋了呀 / 你说 / 你讲
  * 嗨 / 请讲 / 早上好 / 中午好 / 下午好 / 晚上好
  * 副驾请讲 / 副驾请说 / 嗨、副驾 / 左后排请讲 / … / `<appellation>你好` …

  For a greeting, push `WakeChime.pcm16(ctx, 24000)` mixed with the Russian greeting, as Q07 PiperCaTts does.

### 8.3 Why this is the right layer

* Stock owns the routing: the identical AudioTrack (usage 11 / content SPEECH / 24 kHz mono), per-item stream
  switching (`K()`), focus (GAIN_TRANSIENT, auto-abandon logic), the queue and priorities, fade-out on barge-in,
  `ISynthesizerListener` clients, and every callback the HSM, InteractionController, UI and IPC clients rely on.
* Playback stays on the exact output the iFlytek AEC uses as reference. In Duplex, recording starts about 100 ms after
  the greeting begins (`DuplexSessionStateMachine$StartState.playWelcome` sends CMD 13 after 100 ms or
  `oneShotTimeInterval`), so the Russian greeting must be in the echo reference just like the stock one.
* It is three to ten mechanical call-site retargets in one obfuscated file, with no control-flow edits.

### 8.4 Mod-originated speech (no stock text to replace)

Examples are the Q07-style confirmations, `Fix.doneTone`, and a chime on click-wake (stock Q05 click wake has no
greeting: `asrSound=false`). Do **not** create a private `AudioTrack(STREAM_MUSIC…)` as Q07 `TeraTts.runQuiet` does.
Call the stock player with a marker string that RuIssTts recognizes as "already Russian" or "chime":
`invoke-interface {...}, Lcom/tinnove/speechtts/IVoicePlayer;->playTTS(Ljava/lang/String;IJLcom/tinnove/speechtts/IVoicePlayerCallback;)I`
(text, priority, taskId 0, callback or null), obtained from `VoicePlayer.getInstance()`. Focus, AEC reference and
callbacks are then stock.

Caveats:
* `IFullVoicePlayStatusListener.onTtsTextChange` shows the text on screen, so the UI hook should strip the marker,
  for example by using an invisible prefix such as U+2063.
* START/END are counted by `DuplexSessionContainer`'s InteractionController, which re-arms the dialog window. This is
  normally what you want while a dialog is active.

---------------------------------------------------------------------------------------------------

## 9. Option (b) – suppress stock synthesis and play our own AudioTrack

If option (a) proves impossible (for example a native init failure), there are two ways:

1. Hook `Ll7/a;->m(Ljava/lang/String;IIIIIZII)V` at its entry:
   `invoke-static/range {p0 .. p9}, Lcom/stand/q05/RuTts;->speak(Ll7/a;Ljava/lang/String;IIIIIZII)Z` → `if-eqz` →
   `return-void`.
2. Ship `com.tinnove.speechtts.impl.larklite.LarklitePlayer extends Lk7/b;` and call
   `VoicePlayer.setEngine(TTSEngineType.LARKLITE)` once PlayerImpl is initialized. `setTTSEngine` releases l7.a/l7.b
   and calls our `l(...)` with the `k7.b$a` sink.

Either way the mod must reproduce exactly:
* `new AudioTrack(new AudioAttributes.Builder().setUsage(11).setContentType(1).build(),
  new AudioFormat.Builder().setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
  .setSampleRate(24000).build(), AudioTrack.getMinBufferSize(24000,4,2), AudioTrack.MODE_STREAM, 0)`.
  If the item's stream (`m` p4) is not 9, use the `s(int)` table in §4.
* Callbacks through `Lk7/b$a;`, with the item id = `m` p2:
  * `a(I)V` at first audio, and in any case < 2 s after `m()` because of focus auto-abandon;
  * `b(I)V` after the last sample has played (wait for `getPlaybackHeadPosition`, no flush);
  * `d(II)V` on `w(id,reason)`, the stop request (stop and flush quickly, ideally with a short fade);
  * `c(II)V` on failure.
* The sink is reachable as l7.a private field `b:Lk7/b$a;` (package-private accessor `l7.a.z(Ll7/a;)Lk7/b$a;`, so a
  helper class in package `l7` would be needed) or via PlayerImpl private field `S:Lk7/b$a;`.
* Do not request focus yourself; PlayerImpl already did. Respect `m` p7 (focusOk false → error −5).
* Handle `appendState` 1/2/3 (the streaming chunks arrive as separate `m()` calls with the same item id).

Drawbacks: it duplicates the write thread, fade, interrupt and synthesize-only logic; it is easy to get the
COMPLETED/INTERRUPT ordering wrong (double callbacks, stale ids); and with variant 2 the voice-settings speaker list
also has to be emulated (`e()`, `j()`, `k()`). This is why (a) is preferred.

---------------------------------------------------------------------------------------------------

## 10. Prompt and earcon sounds

| sound | player | trigger | attributes | status on Q05 |
|---|---|---|---|---|
| **Wake response** | TTS pipeline | `DuplexSessionStateMachine$StartState.playWelcome()` → `GreetArbitration.i(wakeType)` → (`useLocalRaw` absent → false) `SoundPoolPlayer.playSoundWithTTS(d(type))` → `ThreadUtils` → `PlayerImpl.playWelcomeTTS(text, type)` | TTS AudioTrack (§4) | **Active.** Spoken Chinese greeting; caught by RuIssTts (§8.2 greeting). Only for wakes with needWelcome (voice wake / SDK). Screen click has no greeting (see lifecycle report). |
| raw greeting PCM `res/raw/lingxiaoqi_*.pcm` (24 kHz mono s16 raw) | `j7.a` AudioPlayer via `PlayerImpl.playRawAudio(resId,text,2,true,null)` | `GreetArbitration.i` only if `enginesdk:useLocalRaw==true` and speaker == 软萌少女 | `j7.a.m(II)`: same mapping, stream 9 → usage 11, content 1, 24 kHz mono | Inactive (`useLocalRaw` not in cfg). |
| `dingdang_wake` / `dingdang_quit` / `dingdang_result` / `click` (wav) | `SoundPoolPlayer` (`new SoundPool(3, streamType=9, 0)`; the `mUseAudioAttributes` path is false because `z8.a.shouldUseAudioAttributes()` returns false) | `playSoundBeforeSpeech` (start of SR), `playSoundWhenSpeechEnd` (end of dialog), `playSoundWhenSemanticResult` | legacy stream 9 = ACCESSIBILITY (framework maps it to usage 11 / content SPEECH) | **Silent**: guarded by `comm.cfg:play_earcon`, which is absent, so false. `requestAudioWhenEndSound` is also absent, so false. |
| `click.wav` | SoundPoolPlayer | `ISpeechService.playClickEffect` (SDK) → `playClickEffect()` | stream 9 | Plays when an SDK client asks. |
| `speech_starting.wav` / `speech_comming.wav` (48 kHz mono s16 WAV, Chinese voice prompts) | `g8.d` WtSoundPoolPlayer: `SoundPool.Builder().setMaxStreams(2).setAudioAttributes(usage 11, content 1)` | `f8.d.b()` (VrAppManagerHandler) when the user tries to launch before init is complete (starting = wake-up not ready yet, coming = wake-up ready) | usage 11 / content 1 | Active at boot. To russify, replace the two files in `res/raw` with Russian WAVs of the same name and format. |
| `yinli_sound.pcm` | j7.a via `playRawAudio(...,"A11Sound",0,false)` | A11 multi-speech client | stream 9 | Non-verbal; leave as is. |

There is no separate AudioTrack anywhere else in the app: `new AudioTrack` appears only in `l7.b` and `j7.a`. `q4.c`
(PlayerMgr, MediaPlayer) is a file player, not involved in prompts.

---------------------------------------------------------------------------------------------------

## 11. Q07 ↔ Q05 mapping (TTS)

| Q07 mod | Q05 equivalent |
|---|---|
| `PiperCaTts implements ICaStreamTts`, registered in `assets/module_config.txt` | `com.stand.q05.RuIssTts` with libisstts-identical static methods; call sites in `S2/l7/b.smali` retargeted |
| `sendText(str)` | `start(NativeHandle,String)` / `appendText(NativeHandle,String,int)` |
| `ICaTtsCallback.onMessage(1,"")` (begin) | `ITtsListener.onTtsMsgProc(20000, 0, "")` on the l7.b instance captured in `create()` |
| `ICaTtsCallback.onAudioData(pcm,len)` (push) | pull: `getAudioData(h, buf, len, outLen)` → `outLen[0]=n; h.err_ret=0` |
| `onMessage(2,"")` (end) | `h.err_ret = 10004` from getAudioData once the FIFO is drained (pad ≥300 ms of silence first) |
| `stop()` | `stop(NativeHandle)` (called via `l7.b.X()`) |
| RATE 24000 | AudioTrack rate 24000 (`l7.b.B`); no resampling needed |
| `Q07Bridge.isWakeGreeting` / `WakeChime` | greeting via `PlayerImpl.playWelcomeTTS` (taskId 1) → optional `markWelcome` hook |

---------------------------------------------------------------------------------------------------

## 12. Risks and open points (with the runtime evidence that settles them)

The logger is `com.tinnove.wecarspeechtools.q`. It writes to logcat under tag `TSpeech_2.5.3.19_beta`, with the
class tag inside the message, and to `/data/remotelog/common/tinnovespeechclient/` when `logEnabled` is set.

1. **Effective stream and attributes.** Statically, stream 9 → usage 11 / content 1. Configs can be overlaid from
   external config dirs (`ConfigManager.loadConfig`: two directories plus assets). Confirm with:
   * `IflytekPlayer stream:9|deviceId:…`
   * `IflytekTTSEngine requireAudioTrack() requestAndroidOAudio :true`
   * `PlayerImpl playTTS text:…,stream type is:9`
   * `adb shell dumpsys audio`: the focus stack shows `USAGE_ASSISTANCE_ACCESSIBILITY`, and the playback config list
     shows an AudioTrack with `u/c 11/1` from uid 1000 at sr 24000.
2. **Tail clipping.** The size of `getMinBufferSize(24000,MONO,16)` on this HAL is unknown. Log it from RuIssTts on
   first use and size the silence pad (≥ 2× minBuf + 100 ms).
3. **libisstts.stop on an idle native handle.** If the minimal patch keeps the real `create` but never calls the real
   `start`, `X()` → real `stop` may return non-zero. That is harmless because l7.b only logs it
   (`stop synthetic <ret>`). The `RuIssTts.stop` described above skips the native call anyway.
4. **First-audio latency.** TeraTTS on this SoC (8675 per `comm.cfg:cpuPlatform`) may need >500 ms for the first
   sentence. That is why `onTtsMsgProc(20000)` must fire immediately (2 s focus auto-abandon). Watch for
   `AudioFocus audio abandon` in the log before speech starts.
5. **Long Russian replies.** HandleState has a 25 s process timeout that is re-armed only at TTS_END. A reply longer
   than about 25 s might be cut by `interruptSession` → `VoicePlayer.stop(id)`. Keep replies short. Check with the
   `AbsSession interruptSession` / `stop tts : id =` log.
6. **On-screen TTS text.** The pipeline shows the *Chinese* text unless the UI hook translates it
   (`DuplexSessionContainer$b.onTtsTextChange` → `h.onTtsText`). Alternatively, translate once at
   `PlayerImpl.playTTS` p3 and let RuIssTts treat Cyrillic input as already translated.
7. **iFlytek TTS licence.** If `MachineCode`/`setMachineCode`/`initRes` fail, PlayerImpl never becomes "inited" and
   no TTS reaches l7.b, whether Chinese or Russian. Logs: `IflytekTTSEngine init machine code failed` /
   `init res failed` / `PlayerImpl TTS Player error:`. The fallback is the Phase-2 "kill native" variant of RuIssTts.
8. **Streaming answers (appendState 1/2/3).** These come from cloud/LLM chat. Whole-phrase dictionary translation only
   works after mode 2 (last chunk). Decide per product whether to speak them, translate online, or replace them with
   a canned Russian sentence.
