@echo off
setlocal
cd /d "%~dp0"
set PKG=com.tinnove.wecarspeech
set APK=SpeechAssistant-q05-ru.apk
if not exist "%APK%" goto noapk
echo Zhdu golovnoe ustroystvo Q05 po adb...
adb wait-for-device
rem --- razblokirovka verifikacii Vecentek (kak pri ustanovke moda Q07) ---
echo Otklyuchayu verifikaciyu (Vecentek)...
echo adb36987| adb shell disable-verify 1
adb shell setprop vecentek.model 1
adb shell setprop debug.ro.debuggable 1
echo Stavlyu russkiy golosovoy (obnovlenie sistemnogo prilozheniya, root ne nuzhen)...
adb install -r -d -g "%APK%"
if errorlevel 1 (
  echo.
  echo Esli oshibka podpisi/verifikacii - snachala vypolnite vashu razblokirovku
  echo (disable-verify / AppControl), potom zapustite 2_install.bat zanovo.
)
rem vklyuchit paket dlya polzovatelya 0 (inache "not found")
adb shell cmd package install-existing %PKG%
adb shell "dumpsys package %PKG% | grep -m1 versionName"
adb logcat -c
adb shell am force-stop %PKG%
echo.
echo  Gotovo. Nazhmite knopku golosa na rule (ili skazhite shtatnoe slovo probuzhdeniya)
echo  i govorite po-russki. Pervyy zapusk ~1 minutu (raspakovka modeley GigaAM/TeraTTS).
echo  Chtoby snyat log dlya proverki - zapustite 3_log.bat
pause
exit /b 0
:noapk
echo Net %APK% - snachala zapustite 1_join.bat
pause
exit /b 1
