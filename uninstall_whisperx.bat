@echo off
setlocal enabledelayedexpansion

REM === WhisperX Uninstall Utility ===

set "ROOT_DIR=%~dp0"
set "SCRIPT_PATH=%ROOT_DIR%scripts\uninstall_whisperx_full.ps1"
set "CONFIG_FILE=%ROOT_DIR%whisperx_config.json"

echo ============================================================
echo   WhisperX Uninstall Utility
echo ------------------------------------------------------------
echo   Removing WhisperX environment and related components...
echo   Please wait while the process completes.
echo ============================================================
echo.

REM --- Check PS1 exists ---
if not exist "%SCRIPT_PATH%" (
    echo [ERROR] Could not find uninstall_whisperx_full.ps1 in "%ROOT_DIR%scripts"
    pause
    exit /b 1
)

REM --- Check config exists ---
if not exist "%CONFIG_FILE%" (
    echo [ERROR] Could not find config file: "%CONFIG_FILE%"
    pause
    exit /b 1
)

REM --- Read LogPath from config ---
for /f "usebackq tokens=* delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "(Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json).LogPath"`) do (
    set "LOG_PATH=%%~A"
)
if not defined LOG_PATH set "LOG_PATH=logs"
if not exist "%ROOT_DIR%%LOG_PATH%" mkdir "%ROOT_DIR%%LOG_PATH%"

REM --- Check for -Cleanup argument ---
set "CLEANUP_FLAG="
for %%A in (%*) do (
    if /I "%%~A"=="-Cleanup" set "CLEANUP_FLAG=-Cleanup"
)
if defined CLEANUP_FLAG goto run_cleanup

REM --- Run normal uninstall ---
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%"
    set "EXITCODE=%ERRORLEVEL%"
    goto check_exit
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%"
set "EXITCODE=%ERRORLEVEL%"
goto check_exit

:run_cleanup
echo [INFO] Running in cleanup mode...
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%" -Cleanup
    set "EXITCODE=%ERRORLEVEL%"
    goto check_exit
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%" -Cleanup
set "EXITCODE=%ERRORLEVEL%"
goto check_exit

:check_exit
if "%EXITCODE%"=="0" goto end

echo.
echo ============================================================
echo   Uninstall encountered issues. Exit code: %EXITCODE%
echo ------------------------------------------------------------

if "%EXITCODE%"=="10" goto err_env_remove
if "%EXITCODE%"=="11" goto err_miniconda_remove
if "%EXITCODE%"=="12" goto err_choco_remove
if "%EXITCODE%"=="20" goto err_path_cleanup
if "%EXITCODE%"=="30" goto err_file_cleanup
goto err_generic

:err_env_remove
echo   Failed to remove WhisperX Conda environment.
echo   Check if the environment is in use or locked.
goto offer_cleanup

:err_miniconda_remove
echo   Failed to uninstall Miniconda.
echo   Ensure no other Conda environments are active.
goto offer_cleanup

:err_choco_remove
echo   Failed to uninstall Chocolatey.
echo   You may need to remove it manually via Control Panel or scripts.
goto offer_cleanup

:err_path_cleanup
echo   Failed to clean PATH environment variables.
echo   You may need to edit PATH manually to remove WhisperX/Conda entries.
goto offer_cleanup

:err_file_cleanup
echo   Failed to delete leftover files/folders.
echo   They may be locked by another process.
goto offer_cleanup

:err_generic
echo   An unknown error occurred during uninstall.
goto offer_cleanup

:offer_cleanup
echo.
echo   You can try running in CLEANUP MODE to:
echo     - Force-delete leftover folders/files.
echo     - Remove PATH entries even if uninstall failed.
echo     - Purge partial Miniconda/Chocolatey installs.
echo.
echo   WARNING: Cleanup mode is aggressive and cannot be undone.
echo   To run cleanup directly in future, pass the -Cleanup argument:
echo     uninstall_whisperx.bat -Cleanup
echo.
set /p RUN_CLEANUP=Do you want to run cleanup mode now? (y/n): 
if /I "!RUN_CLEANUP!"=="y" goto run_cleanup
goto end

:end
endlocal
exit /b %EXITCODE%