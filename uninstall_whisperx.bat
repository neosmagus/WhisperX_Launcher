@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0scripts\powershell"
set "SCRIPT_PATH=%SCRIPT_DIR%\uninstall_whisperx.ps1"
set "CONFIG_PATH=%~dp0config"

set "DEBUG_FLAG="
set "CLEANUP_FLAG="

for %%A in (%*) do (
    if /I "%%~A"=="-debug"   set "DEBUG_FLAG=-Debug"
    if /I "%%~A"=="/debug"   set "DEBUG_FLAG=-Debug"
    if /I "%%~A"=="/d"       set "DEBUG_FLAG=-Debug"
    if /I "%%~A"=="-cleanup" set "CLEANUP_FLAG=-Cleanup"
    if /I "%%~A"=="/cleanup" set "CLEANUP_FLAG=-Cleanup"
)

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (set "PS_CMD=pwsh") else (set "PS_CMD=powershell")

%PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigDir "%CONFIG_PATH%" %DEBUG_FLAG% %CLEANUP_FLAG%
set "EXITCODE=%ERRORLEVEL%"

if %EXITCODE% NEQ 0 (
    echo [ERROR] Uninstall failed with exit code %EXITCODE%.
    goto :end
)

echo [INFO] Uninstall completed successfully.

:end
endlocal
exit /b %EXITCODE%
