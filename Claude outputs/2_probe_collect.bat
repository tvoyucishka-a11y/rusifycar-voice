@echo off
setlocal
cd /d "%~dp0"
if not exist probe_result mkdir probe_result
adb logcat -d > probe_result\logcat_full.txt
adb logcat -d -s Q07Probe > probe_result\probe.txt
adb pull /sdcard/Android/data/com.stand.q07probe/files probe_result\files
adb shell "dumpsys package com.incall.apps.speechassistant | grep -E 'versionName|versionCode'" > probe_result\stock_version.txt
adb shell cat /resources/iflytek/version.json >> probe_result\stock_version.txt
echo.
echo Gotovo: papka probe_result - zaarhiviruyte i prishlite.
pause
