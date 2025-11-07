@echo off
setlocal

set "SCRIPT_DIR=%~dp0scripts\powershell"
set "SCRIPT_PATH=%SCRIPT_DIR%\check_miniconda.ps1"

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (set "PS_CMD=pwsh") else (set "PS_CMD=powershell")

%PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
set "EXITCODE=%ERRORLEVEL%"

endlocal
exit /b %EXITCODE%
