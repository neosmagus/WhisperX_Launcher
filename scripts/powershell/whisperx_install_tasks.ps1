# whisperx_install_tasks.ps1
# Task functions for WhisperX installation

function Test-CondaPresence($cfg) {
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Log "Conda already present."
    } elseif (-not $cfg.InstallConda) {
        Write-Log "Conda not found and InstallConda=false." "ERROR"
        exit 10
    }
}

function Get-MinicondaInstaller($cfg) {
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        $installerUrl = if ($cfg.CondaInstallerUrl) { $cfg.CondaInstallerUrl } else {
            "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
        }
        $installerPath = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
        if (-not (Invoke-WithRetry -Command @("powershell", "-Command",
                    "Invoke-WebRequest -Uri $installerUrl -OutFile `"$installerPath`" -UseBasicParsing") `
                    -Description "Downloading Miniconda installer" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
            Write-Log "Failed to download Miniconda installer." "ERROR"
            exit 11
        }
    }
}

function Install-Miniconda($cfg) {
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        $installerPath = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
        if (-not (Invoke-WithRetry -Command @($installerPath, "/InstallationType=JustMe", "/AddToPath=1", "/RegisterPython=1", "/S", "/D=$env:USERPROFILE\Miniconda3") `
                    -Description "Installing Miniconda" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
            Write-Log "Miniconda installer failed." "ERROR"
            exit 11
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
            Write-Log "Miniconda installed but 'conda' not found." "ERROR"
            exit 14
        }
        Write-Log "Miniconda installed successfully. Detected $(conda --version)" "OK"
    }
}

function Set-CondaChannels($cfg) {
    if ($cfg.AcceptAnacondaTOS) {
        Write-Log "Accepting Anaconda Terms of Service for default channels..."
        Invoke-WithRetry -Command @("conda", "tos", "accept", "--override-channels", "--channel", "https://repo.anaconda.com/pkgs/main") -Description "Accept TOS main"
        Invoke-WithRetry -Command @("conda", "tos", "accept", "--override-channels", "--channel", "https://repo.anaconda.com/pkgs/r") -Description "Accept TOS r"
        Invoke-WithRetry -Command @("conda", "tos", "accept", "--override-channels", "--channel", "https://repo.anaconda.com/pkgs/msys2") -Description "Accept TOS msys2"
    } else {
        Write-Log "Config set to not accept Anaconda ToS. Switching to conda-forge..."
        Invoke-WithRetry -Command @("conda", "config", "--remove", "channels", "defaults") -Description "Remove defaults channel"
        Invoke-WithRetry -Command @("conda", "config", "--add", "channels", "conda-forge") -Description "Add conda-forge channel"
        Invoke-WithRetry -Command @("conda", "config", "--set", "channel_priority", "strict") -Description "Set channel priority strict"
    }

    # Record install policy marker
    $policyFile = Join-Path "$env:USERPROFILE\Miniconda3" "install_policy.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = if ($cfg.AcceptAnacondaTOS) {
        "Policy=AnacondaTOSAccepted; Installed=$timestamp"
    } else {
        "Policy=CondaForge; Installed=$timestamp"
    }
    Set-Content -Path $policyFile -Value $content
    Write-Log "Recorded install policy: $content"
}

function Update-Conda($cfg) {
    if (-not (Invoke-WithRetry -Command @("conda", "update", "-n", "base", "-y", "conda") `
                -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds -Description "Conda update")) {
        Write-Log "Continuing with installed version." "WARN"
    } else {
        Write-Log "Conda successfully updated. Now running $(conda --version)" "OK"
    }
}

function Install-CondaEnvironment($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName

    if (-not (Test-Path $envPath)) {
        if (-not (Invoke-WithRetry -Command @("conda", "create", "-y", "-n", $cfg.EnvName,
                    "python=$($cfg.PythonVersion)", "--quiet", "--no-default-packages") `
                    -Description "Creating Conda environment ($($cfg.EnvName))" `
                    -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
            Write-Log "Failed to create environment $($cfg.EnvName)." "ERROR"
            exit 20
        }
    }
    Write-Log "Environment $($cfg.EnvName) ready." "OK"
}

function Install-Pip($cfg) {
    if (-not (Invoke-WithRetry -Command @("conda", "install", "-n", $cfg.EnvName, "-y", "pip") `
                -Description "Installing pip into environment" `
                -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
        Write-Log "Failed to install pip into environment $($cfg.EnvName)." "ERROR"
        exit 32
    }
    Write-Log "pip installed successfully in environment $($cfg.EnvName)." "OK"
}

function Install-PyTorch($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName
    $pipExe = Join-Path $envPath "Scripts\pip.exe"

    if (-not (Test-Path $pipExe)) {
        Write-Log "pip.exe not found in environment $($cfg.EnvName)." "ERROR"
        exit 30
    }

    Invoke-WithRetry -Command @($pipExe, "install",
        "torch", "torchvision", "torchaudio",
        "--index-url", "https://download.pytorch.org/whl/$($cfg.CudaTarget)") `
        -Description "Installing PyTorch stack" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Write-Log "PyTorch stack installed." "OK"
}

function Install-WhisperX($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName
    $pipExe = Join-Path $envPath "Scripts\pip.exe"

    if (-not (Test-Path $pipExe)) {
        Write-Log "pip.exe not found in environment $($cfg.EnvName)." "ERROR"
        exit 31
    }

    Write-Log "Installing WhisperX (this may take a few minutes to download and install)..."
    Invoke-WithRetry -Command @($pipExe, "install", "git+https://github.com/m-bain/whisperx.git") `
        -Description "Installing WhisperX" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Write-Log "WhisperX installed." "OK"
}

function Install-FFmpegPython($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName
    $pipExe = Join-Path $envPath "Scripts\pip.exe"

    if (-not (Test-Path $pipExe)) {
        Write-Log "pip.exe not found in environment $($cfg.EnvName)." "ERROR"
        exit 40
    }

    Invoke-WithRetry -Command @($pipExe, "install", "ffmpeg-python") `
        -Description "Installing ffmpeg-python" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Write-Log "ffmpeg-python installed." "OK"
}

function Test-Environment($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName
    $pythonExe = Join-Path $envPath "python.exe"

    if (-not (Test-Path $pythonExe)) {
        Write-Log "python.exe not found in environment $($cfg.EnvName)." "ERROR"
        exit 50
    }

    Write-Log "Verifying WhisperX environment integrity..."
    if (-not (Invoke-WithRetry -Command @($pythonExe, "-c",
                "import torch, whisperx, ffmpeg; print('Environment OK')") `
                -Description "Environment verification" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
        Write-Log "Environment verification failed." "ERROR"
        exit 50
    }

    Write-Log "Environment verification succeeded. Core packages are importable." "OK"
}

function New-Shortcut($cfg) {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath "WhisperX.lnk"
    $targetPath = Join-Path $PSScriptRoot "..\..\run_whisperx.bat"
    $iconPath = Join-Path $PSScriptRoot "..\..\icons\WhisperX_Launcher.ico"

    if ((Test-Path $targetPath) -and (Test-Path $iconPath)) {
        Write-Log "Creating desktop shortcut..."
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.WorkingDirectory = (Split-Path $targetPath)
        $shortcut.IconLocation = $iconPath
        $shortcut.Save()
        Write-Log "Desktop shortcut created: $shortcutPath" "OK"
        Write-Output "SHORTCUT_PATH=$shortcutPath"
    } else {
        Write-Log "Shortcut not created - missing target or icon." "WARN"
    }
}
