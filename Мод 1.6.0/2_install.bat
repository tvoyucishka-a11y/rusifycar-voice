@echo off
setlocal
cd /d "%~dp0"
set PKG=com.incall.apps.speechassistant
set APK=SpeechAssistant-q07-ru.apk
if not exist "%APK%" goto noapk
echo Zhdu golovnoe ustroystvo po adb...
adb wait-for-device
rem flagi na sluchay proverki Vecentek (bez nee nichego ne delayut)
adb shell setprop vecentek.model 1
adb shell setprop debug.ro.debuggable 1
echo Stavlyu novuyu versiyu moda...
adb install -r -d -g -t "%APK%"
rem obyazatelno: vklyuchit paket dlya polzovatelya 0 (inache "not found" i nol reakcii)
adb shell cmd package install-existing %PKG%
adb shell "dumpsys package %PKG% | grep -m1 'User 0'"
adb logcat -c
adb shell am force-stop %PKG%
echo.
echo  Gotovo. Nazhmite knopku na rule i govorite. Assistent zapustitsya sam.
echo  Chtoby snyat log dlya proverki - zapustite 3_log.bat
pause
