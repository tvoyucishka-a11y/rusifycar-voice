@echo off
setlocal
echo Vozvrashchayu shtatnyy golosovoy (udalyayu mod, vernetsya kopiya iz /system)...
adb wait-for-device
adb uninstall com.incall.apps.speechassistant
adb shell cmd package install-existing com.incall.apps.speechassistant
adb shell "dumpsys package com.incall.apps.speechassistant | grep -m1 versionCode"
echo Gotovo. versionCode dolzhen byt 20260318.
pause
