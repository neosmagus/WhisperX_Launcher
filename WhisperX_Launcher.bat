@echo off
REM === WhisperX Universal Launcher (Template-based HTA) ===

setlocal

:: Get the folder this .bat is in
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%whisperx_launcher.ps1"
set "HTA_TEMPLATE=%SCRIPT_DIR%status_template.hta"

:: Temp log file for status messages
set "TEMP_LOG=%TEMP%\whisperx_status.log"
set "HTA_FILE=%TEMP%\whisperx_status.hta"
set "VBS_FILE=%TEMP%\whisperx_temp_launcher.vbs"

:: Check for required files
if not exist "%PS1_PATH%" (
    echo ERROR: Could not find whisperx_launcher.ps1 in "%SCRIPT_DIR%"
    pause
    exit /b 1
)
if not exist "%HTA_TEMPLATE%" (
    echo ERROR: Could not find status_template.hta in "%SCRIPT_DIR%"
    pause
    exit /b 1
)

:: Test if VBScript is allowed
> "%TEMP%\vbstest.vbs" echo WScript.Quit 0
cscript //nologo "%TEMP%\vbstest.vbs" >nul 2>&1
if errorlevel 1 (
    set "USE_VBS=0"
) else (
    set "USE_VBS=1"
)
del "%TEMP%\vbstest.vbs" >nul 2>&1

:: Prepare HTA file from template
copy "%HTA_TEMPLATE%" "%HTA_FILE%" >nul
powershell -NoProfile -Command "(Get-Content -Raw '%HTA_FILE%') -replace '\{\{TEMP_LOG\}\}', '%TEMP_LOG%' | Set-Content '%HTA_FILE%'"

if "%USE_VBS%"=="1" (
    echo VBScript is allowed - launching in Silent Mode...
    goto :LAUNCH_VBS
) else (
    echo VBScript is blocked - launching in Console Mode...
    goto :LAUNCH_CONSOLE
)

:LAUNCH_VBS
REM Create temporary VBS launcher
> "%VBS_FILE%" echo Option Explicit
>> "%VBS_FILE%" echo Dim objShell, psScript, tempLog, htaFile, cmd
>> "%VBS_FILE%" echo psScript = "%PS1_PATH%"
>> "%VBS_FILE%" echo tempLog = "%TEMP_LOG%"
>> "%VBS_FILE%" echo htaFile = "%HTA_FILE%"
>> "%VBS_FILE%" echo Set objShell = CreateObject("Wscript.Shell")
>> "%VBS_FILE%" echo objShell.Run "mshta.exe """ ^& htaFile ^& """", 1, True
>> "%VBS_FILE%" echo cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ ^& psScript ^& """ -StatusLog """ ^& tempLog ^& """"
>> "%VBS_FILE%" echo objShell.Run cmd, 0, True
>> "%VBS_FILE%" echo On Error Resume Next
>> "%VBS_FILE%" echo CreateObject("Scripting.FileSystemObject").DeleteFile htaFile
>> "%VBS_FILE%" echo CreateObject("Scripting.FileSystemObject").DeleteFile tempLog

REM Run the VBS launcher
cscript //nologo "%VBS_FILE%"
del "%VBS_FILE%" >nul 2>&1
exit /b

:LAUNCH_CONSOLE
REM Launch HTA and wait for it to close
start /wait "" mshta.exe "%HTA_FILE%"

REM Run PowerShell script with status logging (console visible)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -StatusLog "%TEMP_LOG%"

REM Cleanup
del "%HTA_FILE%" >nul 2>&1
del "%TEMP_LOG%" >nul 2>&1

pause