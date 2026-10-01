@echo off
setlocal
cd /d "%~dp0"
echo Pishu log. Nazhmite knopku na rule, govorite komandy. Zakroyte okno (Ctrl+C) kogda zakonchite.
echo Fayl: q07_log.txt
adb logcat -s Q07Bridge:V Q07Fix:V GigaAsr:V TeraTts:V Q07PiperCaTts:V Q07CaKey:V Q07AppLaunch:V Q07CarSettings:V BusinessController:V UiService:V > q07_log.txt
