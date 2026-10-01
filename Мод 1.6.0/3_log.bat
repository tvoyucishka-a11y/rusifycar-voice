@echo off
setlocal
cd /d "%~dp0"
echo Pishu log. Govorite komandy. Zakroyte okno (Ctrl+C) kogda zakonchite.
echo Fayl: q07_log.txt
adb logcat -s Q07Bridge:V GigaAsr:V Q07PiperCaTts:V Q07CaKey:V > q07_log.txt
