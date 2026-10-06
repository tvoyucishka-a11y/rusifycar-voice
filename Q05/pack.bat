@echo off
setlocal
rem Peretashchite na etot fayl papku ili fayl (naprimer v10) - poluchitsya papka <imya>_upload s kuskami po 20 MB.
if "%~1"=="" goto usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pack.ps1" -Path "%~1"
pause
exit /b 0
:usage
echo Peretashchite papku ili fayl na pack.bat
pause
exit /b 1
