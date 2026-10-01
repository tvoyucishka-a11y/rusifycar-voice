@echo off
setlocal
cd /d "%~dp0"
set PKG=com.incall.apps.speechassistant
set APK=SpeechAssistant-q07-ru.apk
set BK=backup
if not exist "%APK%" goto noapk
if not exist "%BK%" mkdir "%BK%"
set INFO=%BK%\info.txt

echo Zhdu golovnoe ustroystvo po adb...
adb wait-for-device

echo === props === > "%INFO%"
adb shell getprop ro.build.display.id >> "%INFO%" 2>&1
adb shell getprop ro.build.fingerprint >> "%INFO%" 2>&1
adb shell getprop ro.derive.product.sda >> "%INFO%" 2>&1
adb shell getprop persist.sys.speechassistant.config >> "%INFO%" 2>&1
echo === vecentek === >> "%INFO%"
adb shell "getprop | grep -i -E 'vecentek|ro.debuggable'" >> "%INFO%" 2>&1
echo === resources === >> "%INFO%"
adb shell cat /resources/iflytek/version.json >> "%INFO%" 2>&1
adb shell df -h /data /resources >> "%INFO%" 2>&1
echo === package BEFORE === >> "%INFO%"
adb shell "dumpsys package %PKG% | grep -E 'versionName|versionCode|codePath|User 0'" >> "%INFO%" 2>&1

rem --- kopiya shtatnogo: sistemnaya papka, esli est; inache iz /data, esli moda eshche net ---
if exist "%BK%\stock_system" goto dataCopy
for /f "tokens=2 delims==" %%d in ('adb shell "dumpsys package %PKG% | grep codePath= | grep -v /data/app"') do adb pull %%d "%BK%\stock_system"
:dataCopy
adb shell "dumpsys package %PKG% | grep -m1 versionCode" | findstr 2000000000 >nul
if not errorlevel 1 goto install
if exist "%BK%\stock_SpeechAssistant.apk" goto install
for /f "tokens=2 delims=:" %%p in ('adb shell pm path %PKG%') do adb pull %%p "%BK%\stock_SpeechAssistant.apk"

:install
echo Stavlyu mod...
echo === install === >> "%INFO%"
adb install -r -d -g -t "%APK%" >> "%INFO%" 2>&1
rem --- paket dolzhen byt ustanovlen dlya polzovatelya 0 (na 1.6.0 on okazalsya installed=false) ---
adb shell cmd package install-existing %PKG% >> "%INFO%" 2>&1
type "%INFO%" | findstr /i "Success Failure INSTALL_ Vecentek installed.for"
echo === package AFTER === >> "%INFO%"
adb shell "dumpsys package %PKG% | grep -E 'versionName|versionCode|codePath|User 0'" >> "%INFO%" 2>&1

rem --- 90 sekund loga posle perezapuska ---
adb logcat -c
adb shell am force-stop %PKG%
echo.
echo  SEYCHAS: nazhmite knopku golosovogo na rule, skazhite "nihao nihao" i komandu.
echo  Log pishetsya 90 sekund.
echo.
timeout /t 90 /nobreak
adb logcat -d > "%BK%\log.txt" 2>&1
echo.
echo  Gotovo. Esli golosovoy ne zarabotal - prishlite papku %BK% celikom.
pause
exit /b 0

:noapk
echo Net %APK% - snachala zapustite 1_join.bat
pause
exit /b 1
