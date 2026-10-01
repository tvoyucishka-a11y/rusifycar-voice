@echo off
setlocal
cd /d "%~dp0"
echo Zhdu golovnoe ustroystvo po adb...
adb wait-for-device
rem flagi dlya proverki Vecentek (na mashinah bez nee nichego ne delayut)
adb shell setprop vecentek.model 1
adb shell setprop debug.ro.debuggable 1
echo.
echo Shtatnyy golosovoy na mashine (dolzhen byt RODNOY, ne nash mod - versionCode ne 2000000000):
adb shell "dumpsys package com.incall.apps.speechassistant | grep -m1 versionCode"
echo.
adb install -r -g -t Q07Probe.apk
adb shell cmd package install-existing com.stand.q07probe
adb logcat -c
adb shell am start -n com.stand.q07probe/.MainActivity
echo.
echo Q07 Probe otkryt na ekrane mashiny. Posle testov zapustite 2_probe_collect.bat
pause
