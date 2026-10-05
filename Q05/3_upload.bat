@echo off
setlocal
rem Peretashchite na etot fayl papku (naprimer v10) ili zapustite: 3_upload.bat "put\k\papke"
rem Papka budet narezana na kuski po 20 MB i zagruzhena na GitHub v vetku upload-<imya papki>.
rem Mozhno zapuskat povtorno - zagruzka prodolzhitsya s mesta obryva.
if "%~1"=="" goto usage
where git >nul 2>&1
if errorlevel 1 goto nogit
if exist "%~1_upload\*.sha256" goto upload
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack.ps1" -Path "%~1"
if errorlevel 1 goto fail
:upload
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1" -Parts "%~1_upload" -Repo "%~dp0..\repo"
if errorlevel 1 goto fail
echo.
echo Gotovo. Napishite Claude, chto zagruzka zakonchena.
pause
exit /b 0
:fail
echo.
echo OSHIBKA - prishlite tekst iz etogo okna. Povtornyy zapusk prodolzhit zagruzku.
pause
exit /b 1
:nogit
echo Ne nayden git. Ustanovite: https://git-scm.com/download/win
pause
exit /b 1
:usage
echo Peretashchite papku (naprimer v10) na 3_upload.bat
pause
exit /b 1
