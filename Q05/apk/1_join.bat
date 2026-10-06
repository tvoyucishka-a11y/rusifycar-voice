@echo off
setlocal
cd /d "%~dp0"
echo Sobirayu SpeechAssistant-q05-ru.apk iz chastey...
if exist SpeechAssistant-q05-ru.apk del SpeechAssistant-q05-ru.apk
copy /b parts\SpeechAssistant-q05-ru.apk.part* SpeechAssistant-q05-ru.apk >nul
for %%A in (SpeechAssistant-q05-ru.apk) do echo Gotovo: %%~zA bayt  (dolzhno byt 816677073)
echo.
echo Dalshe zapustite 2_install.bat
pause
