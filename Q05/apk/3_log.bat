@echo off
setlocal
cd /d "%~dp0"
echo Pishu log. Nazhmite knopku na rule, govorite komandy. Zakroyte okno (Ctrl+C) kogda zakonchite.
echo Fayl: q05_log.txt
adb logcat -s Q05Bridge:V Q07Bridge:V GigaAsr:V Q07PiperCaTts:V IflytekTTSEngine:V TSpeech_2.5.3.19_beta:V > q05_log.txt
