@echo off
setlocal enabledelayedexpansion

REM === WhisperX Launcher (Console Only, Config Path Aware) ===

:: --- Paths ---
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%whisperx_launcher.ps1"

:: --- Config path from argument or default ---
if "%~1"=="" (
    set "CONFIG_FILE=%SCRIPT_DIR%whisperx_config.json"
) else (
    set "CONFIG_FILE=%~1"
)

:: --- Check PS1 exists ---
if not exist "%PS1_PATH%" (
    echo [ERROR] Could not find whisperx_launcher.ps1 in "%SCRIPT_DIR%"
    pause
    exit /b 1
)

:: --- Check config exists ---
if not exist "%CONFIG_FILE%" (
    echo [ERROR] Could not find config file: %CONFIG_FILE%
    pause
    exit /b 1
)

:: --- Always run in console mode ---
echo [INFO] Launching WhisperX with config: "%CONFIG_FILE%"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -ConfigPath "%CONFIG_FILE%"
exit /b