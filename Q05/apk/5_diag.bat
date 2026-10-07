@echo off
setlocal
cd /d "%~dp0"
set PKG=com.tinnove.wecarspeech
echo Zhdu golovnoe ustroystvo po adb...
adb wait-for-device

echo. > q05_diag.txt
echo ===== PACKAGE INFO ===== >> q05_diag.txt
adb shell "dumpsys package %PKG% | grep -E 'versionName|versionCode|codePath|lastUpdateTime|primaryCpuAbi'" >> q05_diag.txt 2>&1
echo. >> q05_diag.txt
echo ===== APK v nashem li /data ili shtatnyy /system ===== >> q05_diag.txt
adb shell "pm path %PKG%" >> q05_diag.txt 2>&1
echo. >> q05_diag.txt
echo ===== est li nash klass v rabote (poisk Q05Bridge) ===== >> q05_diag.txt
adb shell "ls -la /data/app/*/com.tinnove.wecarspeech*/ 2>/dev/null; ls -la /data/app/com.tinnove.wecarspeech* 2>/dev/null" >> q05_diag.txt 2>&1

echo.
echo Perezapuskayu assistenta i pishu POLNYY log (vse tegi, vklyuchaya padeniya)...
adb logcat -c
adb shell am force-stop %PKG%
start /b "" cmd /c "adb logcat -v time -b main -b crash -b system *:V > q05_full.txt 2>&1"
adb shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1 >nul 2>&1
echo.
echo  SEYCHAS: podozhdite ~15 sek (zapusk), potom nazhmite knopku golosa na rule
echo  i skazhite po-russki "otkroy okno voditelya". Log pishetsya 45 sekund.
echo.
timeout /t 45 /nobreak
echo Ostanavlivayu log...
adb kill-server >nul 2>&1
echo.
echo Gotovo. Prishlite DVA fayla: q05_diag.txt i q05_full.txt (lezhat ryadom s batnikom)
pause
