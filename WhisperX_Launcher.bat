@echo off
REM === WhisperX Hybrid Launcher (No VBS) ===
REM - Console mode: no HTA, direct PS1 call
REM - Silent mode: copy static HTA template, run PS1 directly
REM - Config override via whisperx_config.json

setlocal enabledelayedexpansion

:: --- Paths ---
set "SCRIPT_DIR=%~dp0"
set "CONFIG_FILE=%SCRIPT_DIR%whisperx_config.json"
set "PS1_PATH=%SCRIPT_DIR%whisperx_launcher.ps1"
set "HTA_TEMPLATE=%SCRIPT_DIR%status_template.hta"
set "TEMP_LOG=%TEMP%\whisperx_status.log"
set "HTA_FILE=%TEMP%\whisperx_status.hta"

:: --- Config override check ---
if exist "%CONFIG_FILE%" (
    for /F "usebackq tokens=*" %%A in (
        `powershell -NoProfile -Command "(Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json).use_console -replace '\s+$',''"`
    ) do set "USE_CONSOLE=%%A"
)

if /I "!USE_CONSOLE!"=="True" (
    echo [INFO] Console mode forced by config.
    goto :LAUNCH_CONSOLE
)

:: --- Check PS1 exists ---
if not exist "%PS1_PATH%" (
    echo [ERROR] Could not find whisperx_launcher.ps1 in "%SCRIPT_DIR%"
    pause
    exit /b 1
)

:: --- VBScript capability check ---
> "%TEMP%\vbstest.vbs" echo WScript.Quit 0
cscript //nologo "%TEMP%\vbstest.vbs" >nul 2>&1

if errorlevel 1 set "USE_VBS=0"
if not errorlevel 1 set "USE_VBS=1"

del "%TEMP%\vbstest.vbs" >nul 2>&1

:: Clean the variable to strip any stray CR/LF or spaces
for /f "delims=" %%V in ("!USE_VBS!") do set "USE_VBS=%%V"

if "!USE_VBS!"=="1" (
    echo [INFO] VBScript allowed - launching in Silent Mode ^(no VBS wrapper^)... 
    goto :LAUNCH_SILENT
)

echo [INFO] VBScript blocked - launching in Console Mode...
goto :LAUNCH_CONSOLE

:: --- Prepare HTA from template ---
:PREPARE_HTA
if not exist "%HTA_TEMPLATE%" (
    echo [ERROR] HTA template missing: %HTA_TEMPLATE%
    pause
    exit /b 1
)
copy /Y "%HTA_TEMPLATE%" "%HTA_FILE%" >nul
powershell -NoProfile -Command ^
    "(Get-Content '%HTA_FILE%' -Raw) -replace '\{\{TEMP_LOG\}\}', '%TEMP_LOG%' | Set-Content '%HTA_FILE%'"
exit /b

:: --- Silent mode (no VBS) ---
:LAUNCH_SILENT
call :PREPARE_HTA
start "" mshta.exe "%HTA_FILE%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -StatusLog "%TEMP_LOG%"
del "%HTA_FILE%" >nul 2>&1
del "%TEMP_LOG%" >nul 2>&1
exit /b

:: --- Console mode ---
:LAUNCH_CONSOLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
exit /b