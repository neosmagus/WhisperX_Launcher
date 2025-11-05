@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0scripts\powershell"
set "SCRIPT_PATH=%SCRIPT_DIR%\run_whisperx.ps1"
set "CONFIG_PATH=%~dp0config"
set "DEBUG_FLAG="

for %%A in (%*) do (
    if /I "%%~A"=="-debug" set "DEBUG_FLAG=-Debug"
    if /I "%%~A"=="/debug" set "DEBUG_FLAG=-Debug"
    if /I "%%~A"=="/d" set "DEBUG_FLAG=-Debug"
)

where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (set "PS_CMD=pwsh") else (set "PS_CMD=powershell")

set "LOGFILE=run_output.txt"

if defined DEBUG_FLAG (
    %PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigDir "%CONFIG_PATH%" %DEBUG_FLAG%
    set "EXITCODE=%ERRORLEVEL%"
) else (
    %PS_CMD% -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigDir "%CONFIG_PATH%" > "%LOGFILE%" 2>&1
    set "EXITCODE=%ERRORLEVEL%"
    type "%LOGFILE%"
    for /f "tokens=*" %%L in (%LOGFILE%) do (
        echo %%L | findstr /B "SUMMARY=" >nul
        if not errorlevel 1 set "SUMMARY_LINE=%%L"
    )
)

if %EXITCODE% NEQ 0 (
    echo [ERROR] Run failed with exit code %EXITCODE%.
    goto :end
)

echo [INFO] Run completed successfully.
if defined SUMMARY_LINE (
    set "SUMMARY_LINE=%SUMMARY_LINE:SUMMARY=%=%"
    echo [INFO] Parsed run summary:
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
