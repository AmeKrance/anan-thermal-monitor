' AnAn Thermal Monitor - standalone launcher
' Double-click to run the desktop pet WITHOUT DeepSeek Harness / Bigfish.
' First run will show a UAC prompt (admin rights needed for CPU/RAM temps).
Dim fso, ws, dir, ps
Set fso = CreateObject("Scripting.FileSystemObject")
Set ws = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps = dir & "\assets\desktop-pet.ps1"
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps & """", 0, False
