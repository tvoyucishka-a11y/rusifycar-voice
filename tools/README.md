# Сборка мода (для следующих сессий)

Код мода (`com.stand.*`) одинаковый во всех трёх версиях (v2, 1.6.0, 1.7.0) — это один dex
(`classes35.dex` в v2, `classes7.dex` в 1.6.0, `classes2.dex` в 1.7.0). Правки делаются один раз.

Порядок сборки v5:
1. Склеить базовую APK из `*.part*`, наложить `v4/update.q7patch` → `v4.apk` (`q7patch_apply.py`).
2. Достать dex мода, разобрать: мини-APK (`AndroidManifest.xml` + dex) → `apktool d -r`.
3. В `smali_classes2/com/stand`: `python3 patch_smali.py`; заменить `q07/CaKey*.smali` и добавить `q07/Fix*.smali`
   (компиляция `mod-src/java` → `javac --release 8` со стабами `mod-src/stubs` + android.jar → `dx --min-sdk-version=26` → baksmali).
4. `apktool b` → новый dex.
5. `repack.py old.apk unsigned.apk <имя dex> new.dex` — копирует все записи байт-в-байт, выравнивание 4/4096.
6. `Sign.java` (apksig из uber-apk-signer) — подпись AOSP platform test-key (сертификат sha256 `c8a2e9bc…2ab8`).
7. `check.py` — проверить, что изменились только dex и META-INF, выравнивание 0 ошибок.
8. `mkpatch.py base.apk new.apk update.q7patch` — патч для `vN/1_update.bat`.
