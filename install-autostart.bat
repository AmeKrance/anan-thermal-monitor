@echo off
REM AnAn Thermal Monitor - install auto-start at login (admin rights, no UAC popup)
schtasks /create /tn "AnAnThermalMonitor" /tr "wscript.exe \"%~dp0start-pet.vbs\"" /sc onlogon /rl highest /f
echo.
echo Done! The pet will start automatically at login with admin rights (no UAC prompt).
echo To remove: run uninstall-autostart.bat
pause
