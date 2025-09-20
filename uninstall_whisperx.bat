@echo off
setlocal

set "SCRIPT_PATH=%~dp0uninstall_whisperx_full.ps1"

echo ============================================================
echo WhisperX Uninstall Utility
echo ------------------------------------------------------------
echo This tool will:
echo   - Remove the WhisperX Conda environment.
echo   - Detect Miniconda and Chocolatey installations.
echo   - Ask if you want to uninstall each one.
echo   - Only remove PATH entries if uninstall succeeds.
echo.
echo CLEANUP MODE:
echo   If enabled, the script will force-delete leftover folders
echo   and files from failed or partial uninstalls.
echo   Use this if a previous uninstall failed or left remnants.
echo   WARNING: This is more aggressive and cannot be undone.
echo ============================================================
echo.

:: Prompt for cleanup mode
set "CLEANUP_FLAG="
set /p CLEANUP_CHOICE=Run in cleanup mode? (y/n): 
if /I "%CLEANUP_CHOICE%"=="y" set "CLEANUP_FLAG=-Cleanup"

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting elevation...
    powershell -NoProfile -Command ^
        "$argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT_PATH%');" ^
        "if ('%CLEANUP_FLAG%' -ne '') { $argsList += '%CLEANUP_FLAG%' };" ^
        "Start-Process 'powershell.exe' -ArgumentList $argsList -Verb RunAs -Wait"
    set "EXITCODE=%ERRORLEVEL%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %CLEANUP_FLAG%
    set "EXITCODE=%ERRORLEVEL%"
)

:: After PowerShell finishes, try to open the latest log file
set "LOGFILE_FOUND="
for /f "delims=" %%L in ('dir /b /a:-d /o:-d "%~dp0uninstall_log_*.txt" 2^>nul') do (
    start notepad "%~dp0%%L"
    set "LOGFILE_FOUND=1"
    goto afterlog
)

:afterlog
:: Default to error if EXITCODE is blank
if "%EXITCODE%"=="" set "EXITCODE=1"

:: Pause only if there was an error
if not "%EXITCODE%"=="0" (
    echo.
    echo One or more warnings or errors occurred during uninstall.
    if defined LOGFILE_FOUND (
        echo Review the log file that just opened for details.
    ) else (
        echo No log file found - check script output above.
    )
    echo.
    pause
)

endlocal