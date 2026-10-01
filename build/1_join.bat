@echo off
setlocal
cd /d "%~dp0"
echo Sobirayu SpeechAssistant-q07-ru.apk iz chastey...
if exist SpeechAssistant-q07-ru.apk del SpeechAssistant-q07-ru.apk
copy /b SpeechAssistant-q07-ru.apk.part* SpeechAssistant-q07-ru.apk >nul
for %%A in (SpeechAssistant-q07-ru.apk) do echo Gotovo: %%~zA bayt  (dolzhno byt 836172674)
echo.
echo Dalshe zapustite 2_install.bat
pause
