@echo off
setlocal enabledelayedexpansion

REM === WhisperX Launcher ===

set "ROOT_DIR=%~dp0"
set "SCRIPT_PATH=%ROOT_DIR%scripts\whisperx_launcher.ps1"
set "CONFIG_FILE=%ROOT_DIR%whisperx_config.json"
set "UNINSTALL_BAT=%ROOT_DIR%uninstall_whisperx.bat"

echo ============================================================
echo   WhisperX Launcher
echo ------------------------------------------------------------
echo   Preparing the WhisperX environment, installing any
echo   missing dependencies, and launching the GUI.
echo   Please wait while setup runs.
echo ============================================================
echo.

REM --- Check PS1 exists ---
if not exist "%SCRIPT_PATH%" (
    echo [ERROR] Could not find whisperx_launcher.ps1 in "%ROOT_DIR%scripts"
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

REM --- Run launcher ---
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%"
    set "EXITCODE=%ERRORLEVEL%"
    goto check_exit
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -ConfigPath "%CONFIG_FILE%"
set "EXITCODE=%ERRORLEVEL%"
goto check_exit

:check_exit
if "%EXITCODE%"=="0" goto end

echo.
echo ============================================================
echo   WhisperX process failed with exit code %EXITCODE%.
echo ------------------------------------------------------------

REM --- Core launcher exit codes ---
if "%EXITCODE%"=="10" goto err_conda_missing
if "%EXITCODE%"=="11" goto err_conda_install
if "%EXITCODE%"=="20" goto err_env_create
if "%EXITCODE%"=="30" goto err_torch
if "%EXITCODE%"=="31" goto err_whisperx
if "%EXITCODE%"=="40" goto err_ffmpeg
if "%EXITCODE%"=="50" goto err_gui

REM --- Diarization exit codes ---
if "%EXITCODE%"=="60" goto err_diar_no_token
if "%EXITCODE%"=="61" goto err_diar_auth
if "%EXITCODE%"=="62" goto err_diar_download
if "%EXITCODE%"=="63" goto err_diar_dummy

goto err_generic

:err_conda_missing
echo   Conda was not found and InstallConda=false in config.
echo   Enable InstallConda in whisperx_config.json or install
echo   Miniconda manually, then re-run this launcher.
goto offer_uninstall

:err_conda_install
echo   Miniconda installation failed.
echo   Check Chocolatey installation, network connectivity,
echo   or install Miniconda manually.
goto offer_uninstall

:err_env_create
echo   Conda environment creation failed.
echo   Check disk space, permissions, or conda configuration.
goto offer_uninstall

:err_torch
echo   PyTorch installation failed.
echo   Verify CUDA target in config matches your GPU/driver,
echo   or set UseGPU=false to use CPU mode.
goto offer_uninstall

:err_whisperx
echo   WhisperX installation failed.
echo   Check pip connectivity or try upgrading pip/setuptools.
goto offer_uninstall

:err_ffmpeg
echo   ffmpeg setup failed.
echo   Verify FfmpegPath in config or allow auto-install.
goto offer_uninstall

:err_gui
echo   WhisperX GUI failed to launch.
echo   Check Python dependencies or review the log file.
goto end

:err_diar_no_token
echo   Diarization skipped - no Hugging Face token provided.
echo   Provide a valid token in config or via GUI to enable diarization.
goto end

:err_diar_auth
echo   Diarization model access denied.
echo   Accept the model terms at:
echo     https://huggingface.co/pyannote/speaker-diarization-3.1
goto end

:err_diar_download
echo   Diarization model download failed.
echo   Check network connectivity and Hugging Face token validity.
goto end

:err_diar_dummy
echo   Diarization dummy run failed.
echo   Check Pyannote dependencies and ensure audio backend works.
goto end

:err_generic
echo   An unknown error occurred during setup.
goto offer_uninstall

:offer_uninstall
echo.
echo   You can run the uninstall utility to remove all components,
echo   then re-launch this script to reinstall cleanly.
echo   Log file location:
echo     "%ROOT_DIR%%LOG_PATH%"
echo.
if exist "%UNINSTALL_BAT%" (
    set /p RUN_UNINSTALL=Do you want to run the uninstall utility now? (y/n): 
    if /I "!RUN_UNINSTALL!"=="y" goto run_uninstall
)
goto end

:run_uninstall
echo.
echo [INFO] Launching uninstall utility...
call "%UNINSTALL_BAT%"
set "EXITCODE=%ERRORLEVEL%"
goto end

:end
endlocal
exit /b %EXITCODE%