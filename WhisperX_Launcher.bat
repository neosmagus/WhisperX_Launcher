@echo off
REM === WhisperX Universal Launcher ===
REM Runs in Silent Mode (VBS) if possible, otherwise falls back to Console Mode
REM Auto-detects whisperx_launcher.ps1 in the same folder

setlocal

:: Get the folder this .bat is in
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%whisperx_launcher.ps1"

:: Temp log file for status messages
set "TEMP_LOG=%TEMP%\whisperx_status.log"
set "HTA_FILE=%TEMP%\whisperx_status.hta"
set "VBS_FILE=%TEMP%\whisperx_temp_launcher.vbs"

:: Check if whisperx_launcher.ps1 exists
if not exist "%PS1_PATH%" (
    echo ERROR: Could not find whisperx_launcher.ps1 in "%SCRIPT_DIR%"
    pause
    exit /b 1
)

:: Test if VBScript is allowed by creating and running a tiny script
> "%TEMP%\vbstest.vbs" echo WScript.Quit 0
cscript //nologo "%TEMP%\vbstest.vbs" >nul 2>&1
if errorlevel 1 (
    set "USE_VBS=0"
) else (
    set "USE_VBS=1"
)
del "%TEMP%\vbstest.vbs" >nul 2>&1

if "%USE_VBS%"=="1" (
    echo VBScript is allowed — launching in Silent Mode...
    goto :LAUNCH_VBS
) else (
    echo VBScript is blocked — launching in Console Mode...
    goto :LAUNCH_CONSOLE
)

:CREATE_HTA
REM Create the HTA file for live status
> "%HTA_FILE%" echo <html><head><title>WhisperX Launcher</title>
>> "%HTA_FILE%" echo ^<HTA:APPLICATION ID="app" BORDER="thin" SCROLL="no" SINGLEINSTANCE="yes" SYSMENU="no" CAPTION="yes" SHOWINTASKBAR="yes" /^>
>> "%HTA_FILE%" echo ^<style^>body{font-family:Segoe UI, sans-serif; font-size:14px; margin:10px; background:#f4f4f4;} #status{font-weight:bold;}^</style^>
>> "%HTA_FILE%" echo ^<script language="VBScript"^>
>> "%HTA_FILE%" echo Sub Window_OnLoad()
>> "%HTA_FILE%" echo   window.resizeTo 400,100
>> "%HTA_FILE%" echo   window.moveTo (screen.availWidth-400)/2, (screen.availHeight-100)/2
>> "%HTA_FILE%" echo   window.setInterval "UpdateStatus", 1000
>> "%HTA_FILE%" echo End Sub
>> "%HTA_FILE%" echo Sub UpdateStatus()
>> "%HTA_FILE%" echo   Dim fso, f, line
>> "%HTA_FILE%" echo   Set fso = CreateObject("Scripting.FileSystemObject")
>> "%HTA_FILE%" echo   If fso.FileExists("%TEMP_LOG%") Then
>> "%HTA_FILE%" echo     Set f = fso.OpenTextFile("%TEMP_LOG%", 1)
>> "%HTA_FILE%" echo     line = ""
>> "%HTA_FILE%" echo     Do Until f.AtEndOfStream
>> "%HTA_FILE%" echo       line = f.ReadLine
>> "%HTA_FILE%" echo     Loop
>> "%HTA_FILE%" echo     f.Close
>> "%HTA_FILE%" echo     document.getElementById("status").innerText = line
>> "%HTA_FILE%" echo   End If
>> "%HTA_FILE%" echo End Sub
>> "%HTA_FILE%" echo ^</script^></head><body>
>> "%HTA_FILE%" echo <div>WhisperX Launcher Status:</div>
>> "%HTA_FILE%" echo <div id="status">Starting...</div>
>> "%HTA_FILE%" echo </body></html>
exit /b

:LAUNCH_VBS
REM Create HTA
call :CREATE_HTA

REM Create temporary VBS launcher
> "%VBS_FILE%" echo Option Explicit
>> "%VBS_FILE%" echo Dim objShell, psScript, tempLog, htaFile, cmd
>> "%VBS_FILE%" echo psScript = "%PS1_PATH%"
>> "%VBS_FILE%" echo tempLog = "%TEMP_LOG%"
>> "%VBS_FILE%" echo htaFile = "%HTA_FILE%"
>> "%VBS_FILE%" echo Set objShell = CreateObject("Wscript.Shell")
>> "%VBS_FILE%" echo objShell.Run "mshta.exe """ & htaFile & """", 1, False
>> "%VBS_FILE%" echo cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & psScript & """ -StatusLog """ & tempLog & """"
>> "%VBS_FILE%" echo objShell.Run cmd, 0, True
>> "%VBS_FILE%" echo On Error Resume Next
>> "%VBS_FILE%" echo CreateObject("Scripting.FileSystemObject").DeleteFile htaFile
>> "%VBS_FILE%" echo CreateObject("Scripting.FileSystemObject").DeleteFile tempLog

REM Run the VBS launcher
cscript //nologo "%VBS_FILE%"
del "%VBS_FILE%" >nul 2>&1
exit /b

:LAUNCH_CONSOLE
REM Create HTA
call :CREATE_HTA

REM Launch HTA
start "" mshta.exe "%HTA_FILE%"

REM Run PowerShell script with status logging (console visible)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%" -StatusLog "%TEMP_LOG%"

REM Cleanup
del "%HTA_FILE%" >nul 2>&1
del "%TEMP_LOG%" >nul 2>&1
pause