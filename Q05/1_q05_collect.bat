@echo off
setlocal
cd /d "%~dp0"
set PKG=com.tinnove.wecarspeech
set OUT=q05_stock
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%"
echo Zhdu golovnoe ustroystvo Q05 po adb...
adb wait-for-device

echo Sobirayu svedeniya o sisteme...
adb shell getprop > "%OUT%\getprop.txt" 2>&1
adb shell "dumpsys package %PKG%" > "%OUT%\dumpsys_package.txt" 2>&1
adb shell "pm list packages -f" > "%OUT%\packages.txt" 2>&1
adb shell "ls -la /system/lib64 /system/lib /vendor/lib64 /vendor/lib /system_ext/lib64 /product/lib64" > "%OUT%\libs.txt" 2>&1
adb shell "ls -laR /resources" > "%OUT%\resources.txt" 2>&1
adb shell "df -h" > "%OUT%\df.txt" 2>&1

echo Kopiruyu shtatnyy golosovoy (papka prilozheniya celikom, vmeste s lib)...
for /f "delims=" %%d in ('adb shell "p=$(pm path %PKG% | head -n1); dirname ${p#package:}"') do adb pull "%%d" "%OUT%\app"

echo.
echo  SEYCHAS: nazhmite knopku golosovogo na rule, skazhite lyubuyu komandu
echo  i dozhdites otveta. Potom eshche raz. Log pishetsya 40 sekund.
echo.
adb logcat -c
timeout /t 40 /nobreak
adb logcat -d > "%OUT%\logcat.txt" 2>&1

echo.
echo Upakovyvayu i rezhu na kuski po 20 MB...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack.ps1" -Path "%~dp0%OUT%"
if errorlevel 1 goto fail
echo.
echo Gotovo. Zagruzite papku q05_stock_upload na GitHub (sm. README.md).
pause
exit /b 0
:fail
echo OSHIBKA pri upakovke.
pause
exit /b 1
