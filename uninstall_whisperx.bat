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

set "LOGFILE=uninstall_output.txt"

if defined DEBUG_FLAG (
    rem Debug mode: run directly, see live output
    %PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigDir "%CONFIG_PATH%" %DEBUG_FLAG% %CLEANUP_FLAG%
    set "EXITCODE=%ERRORLEVEL%"
) else (
    rem Normal mode: run, log, then parse summary
    %PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigDir "%CONFIG_PATH%" %CLEANUP_FLAG% > "%LOGFILE%" 2>&1
    set "EXITCODE=%ERRORLEVEL%"

    type "%LOGFILE%"
    for /f "tokens=*" %%L in (%LOGFILE%) do (
        echo %%L | findstr /B "SUMMARY=" >nul
        if not errorlevel 1 set "SUMMARY_LINE=%%L"
    )
)

if %EXITCODE% NEQ 0 (
    echo [ERROR] Uninstall failed with exit code %EXITCODE%.
    goto :end
)

echo [INFO] Uninstall completed successfully.
if defined SUMMARY_LINE (
    set "SUMMARY_LINE=%SUMMARY_LINE:SUMMARY=%=%"
    echo [INFO] Parsed uninstall summary:
    for %%S in (%SUMMARY_LINE:;= %) do (
        for /f "tokens=1,2 delims==" %%K in ("%%~S") do (
            set "KEY=%%K"
            set "VAL=%%L"
            call :PrintSummaryLine
        )
    )
)

goto :end

:PrintSummaryLine
set "PADKEY=!KEY!                    "
set "PADKEY=!PADKEY:~0,20!"
echo    !PADKEY! : !VAL!
exit /b

:end
endlocal
exit /b %EXITCODE%
