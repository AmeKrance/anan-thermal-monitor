@echo off
REM AnAn Thermal Monitor - remove auto-start
schtasks /delete /tn "AnAnThermalMonitor" /f
echo.
echo Auto-start removed.
pause
