# Как собран мод Q05 (воспроизведение)

Вход: штатный `WT_TSpeech.apk` (Q05, из дампа) и `v10/1.6.0/SpeechAssistant-q07-ru.apk` (мод Q07).

1. Распаковать dex обоих, разобрать в smali (apktool `d -r`). Мод: `com.stand.*` + `ai.onnxruntime` +
   `com.k2fsa.sherpa` лежат в `classes7.dex`.
2. Добавить в дерево мода `src/Q05Bridge.smali` и `src/RuIssTts.smali`.
3. `tools/patch_q05.py <дерево_мода_smali> <дерево_Q05_smali>` — применяет 7 перехватов (см. PORT.md)
   и перенаправляет `injectZh` мода на `Q05Bridge.inject`; в `l7/b.smali` заменяет все вызовы
   `com.iflytek.speech.libisstts` на `com.stand.q05.RuIssTts`.
4. Собрать 4 dex из smali: `tools/Assemble.java` (API 29) —
   Q05 `smali`→classes.dex, `smali_classes2`→classes2.dex, `smali_classes3`→classes3.dex,
   мод `smali_classes7`→classes4.dex.
5. `tools/merge_apk.py WT_TSpeech.apk unsigned.apk spec.json` — берёт штатный APK, заменяет 3 dex,
   добавляет classes4.dex, заменяет `libonnxruntime.so` на 1.17 от мода, добавляет
   `libonnxruntime4j_jni.so`/`libsherpa-onnx-jni.so`/`libsherpa-onnx-c-api.so` и ассеты
   `assets/{gigaam,tera,q07,stand}`; выравнивание 4/4096, сброс старой подписи.
6. Подпись: `tools/Sign.java` (apksig, platform test‑key `platform.pk8`/`platform.x509.pem`).
7. Проверка: `tools/check.py` (изменились только dex/so/META‑INF, 0 невыровненных) + `Sign verify`
   (cert sha256 `c8a2e9bc…2ab8`, совпадает со штатным Q05).

Итог: `SpeechAssistant-q05-ru.apk` (816 677 073 байта).
