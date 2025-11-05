param(
    [string]$ConfigDir,
    [switch]$Debug
)

# --- Context for logging ---
$global:ScriptContext = "install"

# --- Prefer pwsh, fallback to powershell ---
if ($PSVersionTable.PSEdition -ne 'Core') {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Write-Host "[INFO] Restarting script in PowerShell Core (pwsh)..." -ForegroundColor Cyan
        & $pwsh.Path @args
        exit $LASTEXITCODE
    }
}

. "$PSScriptRoot\exit_codes.ps1"
. "$PSScriptRoot\whisperx_shared.ps1"

function Install-Miniconda {
    param([string]$InstallerUrl, $cfg)

    $installerPath = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"

    # Download installer with retry + spinner
    Invoke-WithRetry -Command @("powershell", "-Command", "Invoke-WebRequest -Uri $InstallerUrl -OutFile `"$installerPath`" -UseBasicParsing") `
        -Description "Downloading Miniconda installer" `
        -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    # Run installer silently
    Invoke-WithRetry -Command @($installerPath, "/InstallationType=JustMe", "/AddToPath=1", "/RegisterPython=1", "/S", "/D=$env:USERPROFILE\Miniconda3") `
        -Description "Installing Miniconda" `
        -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        Write-Log "Miniconda installed but 'conda' not found." "ERROR"
        exit 14
    }

    $condaVersion = conda --version
    Write-Log "Miniconda installed successfully. Detected $condaVersion" "OK"

    # Handle Anaconda ToS or switch to conda-forge
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

    # Update conda itself
    if (-not (Invoke-WithRetry -Command @("conda", "update", "-n", "base", "-y", "conda") `
                -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds -Description "Conda update")) {
        Write-Log "Continuing with installed version." "WARN"
    } else {
        $newVersion = conda --version
        Write-Log "Conda successfully updated. Now running $newVersion" "OK"
    }
}

try {
    # --- Load config ---
    $cfg = if ($ConfigDir) { Get-Config $ConfigDir } else { @{} }

    Write-Log "Starting WhisperX installation..."

    # Install Miniconda if missing
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        Write-Log "Conda not found"
        if ($cfg.InstallConda) {
            $installerUrl = if ($cfg.CondaInstallerUrl) { $cfg.CondaInstallerUrl } else {
                "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
            }
            Install-Miniconda -InstallerUrl $installerUrl -cfg $cfg
        } else {
            Write-Log "Conda not found and InstallConda=false." "ERROR"
            exit 10
        }
    }

    # Create environment if missing
    $envPath = Join-Path $PSScriptRoot "..\envs\whisperx"
    if (-not (Test-Path $envPath)) {
        Invoke-WithRetry -Command @("conda", "create", "-y", "-n", "whisperx", "python=$($cfg.PythonVersion)", "--quiet", "--no-default-packages") `
            -Description "Creating Conda environment (whisperx)" `
            -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds
    }

    # Install dependencies
    Invoke-WithRetry -Command @("conda", "run", "-n", "whisperx", "pip", "install", "torch", "torchvision", "torchaudio", "--index-url", "https://download.pytorch.org/whl/$($cfg.CudaTarget)") `
        -Description "Installing PyTorch stack" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Invoke-WithRetry -Command @("conda", "run", "-n", "whisperx", "pip", "install", "git+https://github.com/m-bain/whisperx.git") `
        -Description "Installing WhisperX" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Invoke-WithRetry -Command @("conda", "run", "-n", "whisperx", "pip", "install", "ffmpeg-python") `
        -Description "Installing ffmpeg-python" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    # Verify environment
    Write-Log "Verifying WhisperX environment integrity..."
    Invoke-WithRetry -Command @("conda", "run", "-n", "whisperx", "python", "-c", "import torch, whisperx, ffmpeg; print('OK')") `
        -Description "Environment verification" -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds

    Write-Log "Environment verification succeeded. Core packages are importable." "OK"
    Write-Log "Installation complete." "OK"

    # Create desktop shortcut
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath "WhisperX.lnk"
    $targetPath = Join-Path $PSScriptRoot "..\..\run_whisperx.bat"
    $iconPath = Join-Path $PSScriptRoot "..\..\icons\WhisperX_Launcher.ico"

    $shortcutCreated = $false
    if ((Test-Path $targetPath) -and (Test-Path $iconPath)) {
        Write-Log "Creating desktop shortcut..."
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.WorkingDirectory = Split-Path $targetPath
        $shortcut.IconLocation = $iconPath
        $shortcut.Save()
        Write-Log "Desktop shortcut created: $shortcutPath"
        $shortcutCreated = $true
        Write-Output "SHORTCUT_PATH=$shortcutPath"
    } else {
        Write-Log "Shortcut not created - missing target or icon." "WARN"
    }

    # --- Emit machine-readable summary ---
    $condaVersion = conda --version
    $summaryLine = "SUMMARY=" +
    "InstallComplete=True;" +
    "ShortcutCreated=$shortcutCreated;" +
    "ShortcutPath=$shortcutPath;" +
    "CondaVersion=$condaVersion;" +
    "PythonVersion=$($cfg.PythonVersion);" +
    "CudaTarget=$($cfg.CudaTarget)"
    Write-Output $summaryLine

    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }

    exit 0
} catch {
    Write-Log "Unexpected install error: $_" "ERROR"
    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }
    exit 1
}
