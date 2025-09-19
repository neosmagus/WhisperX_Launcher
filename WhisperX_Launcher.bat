@echo on
setlocal enabledelayedexpansion

REM ============================================================
REM WhisperX Launcher — Config toggle + robust VBS silent mode
REM ============================================================

REM --- Paths ---
set "SCRIPT_DIR=%~dp0"
set "CONFIG_FILE=%SCRIPT_DIR%whisperx_config.json"
set "HTA_TEMPLATE=%SCRIPT_DIR%status_template.hta"
set "HTA_FILE=%TEMP%\whisperx_status.hta"
set "VBS_FILE=%TEMP%\whisperx_launcher.vbs"
set "LOG_FILE=%TEMP%\whisperx_launcher.log"

REM --- Read use_console from JSON ---
for /f "usebackq tokens=*" %%A in (
    `powershell -NoProfile -Command "(Get-Content '%CONFIG_FILE%' | ConvertFrom-Json).use_console -replace '\s+$',''"`
) do set "USE_CONSOLE=%%A"

set "USE_CONSOLE=%USE_CONSOLE: =%"
echo USE_CONSOLE=[%USE_CONSOLE%]

REM --- Branch based on config ---
if /i "%USE_CONSOLE%"=="True" (
    echo [INFO] Console mode forced by config.
    goto :RUN_CONSOLE
)

echo [INFO] Silent mode (HTA) enabled.
goto :RUN_SILENT

:RUN_CONSOLE
REM ============================================================
REM Console Mode — No HTA, no VBS, direct Python execution
REM ============================================================
echo [INFO] Starting WhisperX in console mode...
if exist "%SCRIPT_DIR%venv\Scripts\activate.bat" (
    call "%SCRIPT_DIR%venv\Scripts\activate.bat"
)
python "%SCRIPT_DIR%whisperx_gui.py"
goto :EOF

:RUN_SILENT
REM ============================================================
REM Silent Mode — HTA + robust VBS stealth launcher
REM ============================================================

REM --- Verify HTA template exists ---
if not exist "%HTA_TEMPLATE%" (
    echo [ERROR] HTA template missing: %HTA_TEMPLATE%
    pause
    goto :EOF
)

REM --- Copy HTA template to temp ---
copy /Y "%HTA_TEMPLATE%" "%HTA_FILE%" >nul || (
    echo [ERROR] Failed to copy HTA file.
    pause
    goto :EOF
)

REM --- Replace placeholder in HTA with log path ---
powershell -NoProfile -Command ^
    "(Get-Content '%HTA_FILE%') -replace '\{\{TEMP_LOG\}\}', '%LOG_FILE%' | Set-Content '%HTA_FILE%'"

REM --- Create robust VBS stealth launcher ---
REM This version handles spaces, quotes, and passes args safely
(
    echo Set objShell = CreateObject("WScript.Shell")
    echo cmdLine = "cmd /c """"%~f0"" internal_run > ""%LOG_FILE%"" 2^>^&1"""
    echo objShell.Run cmdLine, 0, True
) > "%VBS_FILE%"

REM --- Launch HTA status window ---
start "" mshta.exe "%HTA_FILE%"

REM --- Launch VBS to run batch silently ---
cscript //nologo "%VBS_FILE%"
goto :EOF

:internal_run
REM ============================================================
REM This section runs the actual WhisperX process silently
REM ============================================================

if exist "%SCRIPT_DIR%venv\Scripts\activate.bat" (
    call "%SCRIPT_DIR%venv\Scripts\activate.bat"
)

python "%SCRIPT_DIR%whisperx_gui.py"
goto :EOF