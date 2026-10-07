# Перенос русского голосового Q07 → Q05 (WT_TSpeech) — техническая спецификация

Цель: тот же русский стек, что в моде Q07 v10 — **GigaAM** (распознавание), **TeraTTS** (озвучка),
**Ru2Zh** (перевод команд на китайский) — работает поверх штатного голосового Q05.

- Штатный Q05: `com.tinnove.wecarspeech`, приложение `WT_TSpeech`, версия `2.5.3.19_beta`.
- `sharedUserId=android.uid.system`, Application `com.tinnove.wecarspeech.app.VrApplication`.
- Подпись — **тот же AOSP platform test-key**, что и мод Q07 (sha256 `c8a2e9bc…2ab8`). Пересобранный
  APK подписывается этим же ключом — замена системного приложения проходит без отключения проверки.
- 3 dex (classes.dex…classes3.dex), arm64-v8a, **onnxruntime 1.14.0** внутри.
- Движок один: iFlytek (`IflytekEngine` + `IflytekApartEngine` + `IflytekAsrEngine`), сессии — Tencent
  WeCar `VFramework`, диспетчер сессий — **duplex** (`vframework/session/duplex/d`).

Принцип тот же, что на Q07: мод сам слышит звук, сам распознаёт русский через GigaAM, переводит фразу
в китайскую команду и отдаёт её штатному движку на исполнение; штатное распознавание русского глушится.
iFlytek на Q05 используется только для **исполнения** команды — распознавание русского делает GigaAM.

---

## Таблица перехватов (что и где патчить в smali Q05)

Все пути — относительно `q05x/smq05/` (apktool). SM2 = `smali_classes2`, SM3 = `smali_classes3`,
SM1 = `smali`. Класс адаптера мода — `com/stand/q05/Q05Bridge`.

| # | Назначение | Файл / метод Q05 | Что вставить |
|---|---|---|---|
| 1 | Инициализация мода (1 раз, главный процесс) | SM2 `com/tinnove/wecarspeech/app/VrAppEntry.smali` → `initVrApp(Landroid/content/Context;)V`, сразу после `if-eqz p0, :cond_0` | `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->init(Landroid/content/Context;)V` |
| 2 | VFramework готов (регистрация слушателя сессий) | SM2 `com/tinnove/wecarspeech/app/VrApplication.smali` → `onVrAllInitCompleted(ZLjava/lang/String;)V`, первой инструкцией | `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onVrReady(Z)V` |
| 3 | Перехват чистого звука (моно 16 кГц после шумоподавления) | SM2 `…/speechengine/engine/engineofiflytek/IflytekEngine$h.smali` → `run()V`, **сразу после** `invoke-interface {…}, Lcom/iflytek/speech/se2/IISeEngine;->process([B[B[I)I` | подать `mSEBuffer` (v7) и `nBufSize[0]` в `Q05Bridge.feedSE([BI)V` |
| 4 | Начало прослушивания (взвести запись) | SM3 `…/vframework/session/b.smali` → `F(Ljava/lang/String;)I`, в начале | `invoke-static {p1}, Lcom/stand/q05/Q05Bridge;->onListen(Ljava/lang/String;)V` |
| 5 | Конец диалога (сон) | SM3 `…/vframework/session/b.smali` → `G()I`, в начале | `invoke-static {}, Lcom/stand/q05/Q05Bridge;->onSleep()V` |
| 6 | Глушить штатное распознавание русского | SM2 `…/ability/IflytekAsrEngine.smali` → `onFinalResult(ILjava/lang/String;ZZZZLjava/lang/String;)V` и `onTmpResult(ILjava/lang/String;ZZLjava/lang/String;ZI)V`, в начале | если голосовой результат (не наш текст, `p6==false`) и мод активен → `return-void` |
| 7 | Озвучка/экран по-русски (v2) | ответный текст в `l7/b.smali` (`IflytekTTSEngine`) или `VoicePlayer` | `Q05Bridge.tts(str)` → если вернул русский, синтез TeraTTS + проигрывание, callback'и состояния |

### Инъекция команды (вызывается из кода мода, патч не нужен)
`VFramework.getInstance().startSrByText(zh, new LaunchParams.Builder(0).build(), null)`
- smali: `Lcom/tinnove/wecarspeech/vframework/VFramework;->startSrByText(Ljava/lang/String;Lcom/tinnove/vrcommon/app/LaunchParams;Lcom/tinnove/wecarspeech/vframework/IStartResultCallback;)V`
- сам открывает сессию (не нужна живая), прогоняет китайский текст через штатный NLU, исполняет,
  показывает текст и произносит ответ. Это аналог `injectZh` из Q07.
- альтернатива без новой сессии: `getSemanticByText(zh, new lb.a[0], null)`.

### Звук: как достать чистое моно
В точке #3 `mSEBuffer` — многопотоковый контейнер iFlytek (`IFLYAUTOISS`). Чистое моно для ASR —
поток типа 2 (`LibISSSE2.TYPE_ASR`). Доставать штатным нативным методом, без ручного разбора:
```
int[] io = new int[2]; byte[] out = new byte[len];
if (com.iflytek.speech.LibISSSE2.extractAudio(se, len, 2, out, len, io) == 0) feedPcm(out, io[0]);
```
(ровно так делает штатный `IflytekApartEngine.notifyAudioData`). Поток идёт постоянно, в т.ч. в простое —
поэтому предзапись (pre-roll) перед фразой работает как на Q07.

### Ловушка сессии
`startAsrByText`/инъекция требует живую сессию, а после конца речи штатная сессия закрывается через
~6.5 c (таймаут семантики) и по таймауту без речи (8 c). `startSrByText` открывает сессию сам —
это снимает проблему. Если удерживать дольше — глушить таймер `cd/a;->R()V` пока мод занят.

### Руль
Отдельного перехвата не нужно: кнопку руля обрабатывает внешнее системное приложение, оно шлёт
`LaunchService` (`extra_launch_type=7`) → штатная сессия `startSR("sdk")` → срабатывает перехват #4.

---

## Библиотеки и коллизии

- Обе стороны содержат `lib/arm64-v8a/libonnxruntime.so`: у Q05 — **1.14.0** (нужен его `librecommendation.so`),
  у мода — **1.17.1** (нужен `libsherpa-onnx-jni.so`, `libsherpa-onnx-c-api.so`, `libonnxruntime4j_jni.so`).
  Нельзя просто перезаписать 1.14 → 1.17 (может сломать штатные либы). Решение: **переименовать ORT мода**
  — в `libsherpa-onnx*.so`, `libonnxruntime4j_jni.so` и в java-привязке `ai.onnxruntime` поменять
  `DT_NEEDED`/`System.loadLibrary` с `onnxruntime` на `onnxruntime_stand`, положить мод-ORT как
  `libonnxruntime_stand.so`. Тогда 1.14 Q05 и 1.17 мода сосуществуют.
- `libc++_shared.so`: у мода 1.29 МБ, у Q05 1.06 МБ — оставить версию мода (новее, совместима назад),
  либо переименовать по той же схеме, если штатные либы капризничают (проверяется логом).
- Классы `ai.onnxruntime.*`, `com.k2fsa.sherpa.*` есть только в dex мода — коллизий классов нет
  (у Q05 своя java-привязка отсутствует, ORT вызывается нативно из iFlytek-либ).
- dex: у Q05 3 dex, у мода — свой `classes7.dex` с `com.stand.*`, `ai.onnxruntime.*`, `com.k2fsa.*`.
  Добавляется отдельным `classes4.dex` — лимитов это не нарушает.

## Модели (ассеты мода, кладутся без сжатия)
`assets/gigaam/model.int8.onnx` (225 МБ), `assets/tera/models/*` (389 МБ: sampler 256, vocoder 101,
text_encoder 28, duration 1.5), `assets/tera/ruaccent.bin` (2 МБ), `assets/tera/*` словари,
`assets/q07/*.pcm` (звуки), `assets/stand/wake_chime.wav`. Загружаются из assets → распаковка в
`filesDir` при первом старте (как на Q07). Итоговый APK ≈ 199 МБ (Q05) + ~620 МБ (мод) ≈ 820 МБ.

---

## Что ещё специфично для Q07 в коде мода и требует адаптации
- `Q07Bridge`: все вызовы хоста — через `Class.forName("com.incall.apps.speechassistant.*")` в try/catch;
  на Q05 они просто не найдутся (no-op). Нужен `Q05Bridge`, перенаправляющий инъекцию/пробуждение/экран
  на `VFramework`.
- `Fix`: `norm()` (нормализация громкости) и проигрывание — переносятся; `awake()`/`wakeLikeVoice` — на Q05.
- `PiperCaTts` (ICaStreamTts) — на Q05 нет такого подключаемого TTS; озвучка через патч `l7.b`/`VoicePlayer`.
- `CaKey`, `SeTap` — не нужны (руль и звук на Q05 устроены иначе, см. выше).
- `CarSettings` (пакет `com.incall.apps.vehiclesetting`) — у Q05 другой пакет настроек, перепроверить.
- **Лицензия** (`ru.q07.overlays`, `License.ok()`): по решению пользователя для сборки Q05 — **отключить**
  (`Extra.TEST`/флаг), голосовой работает без проверки.

## Этапность (как на Q07: v1 → логи → итерации)
- **v1**: перехваты #1–#6 — GigaAM слышит, распознаёт, Ru2Zh переводит, команда исполняется. Проверка
  логом с машины (`feedSE … rms=…`, `ASR: […]`, `injectZh …`). Озвучка ответа пока китайская (штатная).
- **v2**: перехват #7 — русская озвучка (TeraTTS) и русский текст на экране.
- Дальше — донастройка команд (таблица `commands_map.tsv`) и формата звука по логам.

Отладочный лог Q05 — тег `TSpeech_2.5.3.19_beta`, плюс наши строки с тегом `Q05Bridge`.
