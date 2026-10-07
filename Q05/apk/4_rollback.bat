@echo off
setlocal
echo Vozvrashchayu shtatnyy golosovoy Q05 (udalyayu mod, vernetsya kopiya iz /system)...
adb wait-for-device
adb uninstall com.tinnove.wecarspeech
adb shell cmd package install-existing com.tinnove.wecarspeech
adb shell "dumpsys package com.tinnove.wecarspeech | grep -m1 versionName"
echo Gotovo. Dolzhen vernutsya shtatnyy (versionName 2.5.3.19_beta).
pause
