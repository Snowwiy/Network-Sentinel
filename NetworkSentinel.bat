@echo off
setlocal
set "WD=%~dp0"
if not exist "%WD%NetworkSentinel.ps1" goto missing
if exist "%WD%NetworkSentinel.vbs" goto runvbs
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WD%NetworkSentinel.ps1"
exit /b 0
:runvbs
wscript.exe //nologo "%WD%NetworkSentinel.vbs"
exit /b 0
:missing
echo [Network Sentinel] Falta NetworkSentinel.ps1 en esta carpeta.
pause
exit /b 1
