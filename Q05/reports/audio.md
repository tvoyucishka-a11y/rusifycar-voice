# Q05 (com.tinnove.wecarspeech, WT_TSpeech 2.5.3.19_beta) – microphone audio pipeline

KEY = audio. Everything below was verified against the jadx sources (`q05x/jx/sources`), the smali
(`q05x/smq05/smali*`), the decoded assets (`q05x/resq05/assets/public/cfg/*.cfg`) and, for the SE
container format, the arm64 disassembly of `lib/arm64-v8a/libissse.so`. I marked anything that is
not statically certain and named the runtime log line that would settle it.

Abbreviations: `S2 = q05x/smq05/smali_classes2`, `S1 = q05x/smq05/smali`, `J = q05x/jx/sources`.
`IE = com.tinnove.wecarspeech.speechengine.engine.engineofiflytek.IflytekEngine`.

---------------------------------------------------------------------------------------------------

## 0. Summary

* **Capture is a plain Java `android.media.AudioRecord`.** It is not native or HAL capture, and the app has no capture service.
  `chj.bind.captureservice` appears only as a `<uses-permission>` in AndroidManifest.xml (line 21). No
  Java/smali class references it, so it is a leftover.
* **Format** (from `assets/public/cfg/comm.cfg`): source 6 (`VOICE_RECOGNITION`), 16000 Hz, PCM 16-bit LE,
  `AudioRecord.Builder().setChannelIndexMask(15)`, which gives **4 interleaved channels `[mic1, mic2, ref1, ref2]`**.
  Each read is 2048 bytes = 256 frames = **16 ms**.
* **iFlytek front end** (Apart mode, the default): raw 4-ch block → `LibISSSE2.process()` (libissse.so → dlopen
  libivSEEngine.so) → a **packed multi-stream SE container** (`"IFLYAUTOISS"` header) in `IE.mSEBuffer`.
  The same packed buffer is passed unchanged to wake-up (libissmvw → libw_ivw) and ASR (libisssr → libw_esr).
  Both native libraries parse the container themselves; each contains the `IFLYAUTOISS` magic string.
* **Clean mono 16 kHz audio** is the **type 2 (`LibISSSE2.TYPE_ASR`) stream inside `mSEBuffer`**. Java can
  read it (container format documented in §4; it is the same format the Q07 mod v10 SeTap reads through
  `PcmConvertor.processPcm(4, …)`, which returns the type-2 stream). The native helper
  `LibISSSE2.extractAudio(...)` also returns it.
* **It flows continuously, including while idle.** The VR recorder starts once the wake-up engine has initialised,
  because `EngineRecordController.c(true, …)` sets `mIsSystemSpeech = true`. The SE runs on every 16 ms frame
  whatever the wake/ASR state. It stops only when the app loses microphone focus (phone call, another recorder,
  power-off, info-security revoke).
* **Best tap** (equivalent of Q07 SeTap/appendData plus SpeechInterfaceImpl.sendSpeechData):
  `Lcom/tinnove/wecarspeech/speechengine/engine/engineofiflytek/IflytekEngine$h;->run()V` ("AppendThread"),
  **directly after** `invoke-interface {v3, v5, v7, v8}, Lcom/iflytek/speech/se2/IISeEngine;->process([B[B[I)I`
  (`S2/.../IflytekEngine$h.smali` line 299). At that point `v5` = raw 4-ch block (2048 B), `v7` = packed SE
  output `mSEBuffer`, and `v8` = `nBufSize` (`int[2]`, where `[0]` = valid bytes in `v7`).

---------------------------------------------------------------------------------------------------

## 1. Recording: who opens the microphone

### 1.1 Recorder selection
* `com.tinnove.fusionadapter.FusionAdapter.init()` reads `fusion.cfg` (`ya.a.c(...)`). Neither assets nor
  the dump contain a `fusion.cfg`, so the defaults apply: `replaceRecorder=true` and
  `replaceReorderClassName="com.tinnove.fusionadapter.fusion.recorder.impl.DefaultRecorder"` (sic). These
  are registered as `hc.a.replaceRecorder` and returned by `EngineContract.getRecorder()`.
* `com.tinnove.vrlogic.service.SpeechRecordManagerImpl.init()` (the only `IAudioRecordManager` implementation)
  calls `getRecorder()` and then `recorder.init(mCommonRecordCallback)`.
* Not used with the shipped config: `OutsideRecorder` (only when `comm.cfg:supportOutsideCarSpeech`, which is
  absent and therefore false), `c5.a` and the Tencent `com.tencent.wecarintraspeech...DefaultRecorder`/`FusionSdkRecorder`,
  and `u6.c` "OboeAudioRecord" (the class `com.tinnove.audio.record.AudioRecord` is not even in the APK).
* `IflytekEngine` is the only `IEngineInterface` implementation (`xb/a.java:15`). There is no other engine.

### 1.2 `t6.a` = "SpeechRecordThread" (`S2/t6/a.smali`, `J/t6/a.java`)
* `Thread` named `"SpeechRecordThread"`, `setPriority(10)`, `Process.setThreadPriority(-19)`.
* Configuration is read in `t6.a.a()` from `comm.cfg` and `AudioChannelParam`:

| key (comm.cfg) | value in APK | meaning |
|---|---|---|
| `voiceSource` | 6 | `MediaRecorder.AudioSource.VOICE_RECOGNITION` |
| `audioFormat` | 2 | `ENCODING_PCM_16BIT` |
| `audioRecordCreateType` | 1 | use `AudioRecord.Builder` |
| `micNumber` / `refChannel` / `channelNumber` | 2 / 2 / 4 | 2 microphones + 2 reference (loop-back) channels |
| `recordChannel` | 15 (0b1111) | used as **channel *index* mask** → 4 channels |
| `buffSize` | 2048 | read size in bytes |
| `voiceRegion` | 2 | two sound zones (driver / front passenger) |
| `noiseReduceMode` | 1 | "hard NR" (doc string); only affects `getTimeOfBuffer` |
| `audioAreaMode` | absent → 0 | so the non-"HighV" keys above apply (`AudioChannelParam.init`, smali verified) |

* `t6.a.b(II)V` (create): `mSetBufferSize = 2048 != -1`, so `this.b = 2048` and `this.d = new byte[2048]`. Because
  `audioRecordCreateType==1`, it calls `new u6.a$a().d(6).h(16000).c(2).i(false).g(15).a()`, which leads to
  `u6.d(SystemAudioRecord)` → `AudioRecord.Builder().setAudioFormat(rate 16000, setChannelIndexMask(15), enc 2)
  .setAudioSource(6).build()`. No explicit buffer size is set; the framework default is used.
* The read loop in `run()` calls `d([F)I`, which calls `u6.b.c(this.d, 0, 2048)`, i.e. `AudioRecord.read(byte[],0,2048)`. Then
  `f(I)I` dispatches the data:

```smali
# S2/t6/a.smali  .method private f(I)I
iget-object v0, p0, Lt6/a;->m:Lt6/a$a;
iget-object v1, p0, Lt6/a;->d:[B
iget p0, p0, Lt6/a;->b:I              # 2048
invoke-interface {v0, v1, p0}, Lt6/a$a;->a([BI)V
```
  It logs `"audio record get 500 buffer"` every 500 reads (that is, every ~8 s when audio flows).
* **Channel layout** is `[mic1, mic2, ref1, ref2]`, interleaved, 8 bytes per frame. Evidence:
  `com.tinnove.vrcommon.utils.a.c(short[],mic,ref,broken)`, which is the broken-microphone down-mix used by the SE
  wrapper, treats `index % (mic+ref) < mic` as microphones (numbered 1..mic) and the rest as references. The SE
  mode strings are all `*