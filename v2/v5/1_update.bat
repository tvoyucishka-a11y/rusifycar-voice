@echo off
setlocal
cd /d "%~dp0"
echo Sobirayu novuyu versiyu moda: staryy APK (papkoy vyshe) + malenkiy patch...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply.ps1" -Old "%~dp0..\SpeechAssistant-q07-ru.apk" -Patch "%~dp0update.q7patch" -Out "%~dp0SpeechAssistant-q07-ru.apk"
if errorlevel 1 goto fail
echo.
echo Gotovo. Dalshe 2_install.bat
pause
exit /b 0
:fail
echo.
echo OSHIBKA: staryy APK ne sovpal. Napishite Claude - prishlyu APK tselikom.
pause
exit /b 1
