@echo off
setlocal
rem Peretashchite na etot fayl papku s dampom Q05 (naprimer D:\Q05\q05 sys\q05 sys).
if "%~1"=="" goto usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dump_pack.ps1" -Dump "%~1"
if errorlevel 1 goto fail
echo.
echo Gotovo. Zagruzite papku q05_dump_upload na GitHub (sm. README.md).
pause
exit /b 0
:fail
echo OSHIBKA - prishlite tekst iz etogo okna.
pause
exit /b 1
:usage
echo Peretashchite papku s dampom Q05 na 2_q05_dump_pack.bat
pause
exit /b 1
