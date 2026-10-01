@echo off
REM Установка русского голосового на Changan Q07 через ADB.
REM Головное устройство должно быть подключено по ADB (USB или Wi-Fi: adb connect IP:PORT).
setlocal
cd /d "%~dp0"

set ADB=adb
if exist "%~dp0adb.exe" set ADB="%~dp0adb.exe"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

if not exist SpeechAssistant-q07-ru.apk (
  echo Сначала запустите 1_join.bat — файл SpeechAssistant-q07-ru.apk не найден.
  pause & exit /b 1
)

echo Проверяю подключение...
%ADB% devices
echo.
echo Устанавливаю (обновление системного приложения, root не нужен)...
%ADB% install -r -d -g -t SpeechAssistant-q07-ru.apk
if errorlevel 1 (
  echo.
  echo Если ошибка INSTALL_FAILED_VERSION_DOWNGRADE — выполните:
  echo   %ADB% install -r -d SpeechAssistant-q07-ru.apk
  pause & exit /b 1
)
echo.
echo Перезапускаю ассистента...
%ADB% shell am force-stop com.incall.apps.speechassistant
echo.
echo Готово. Первый запуск ~1 минуту (распаковка моделей).
echo Нажмите кнопку голосового на руле ОДИН раз, дождитесь звука, скажите команду и замолчите.
pause
