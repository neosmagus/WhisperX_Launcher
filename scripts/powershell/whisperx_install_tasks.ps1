# whisperx_install_tasks.ps1
# Task functions for WhisperX installation with pinned versions and full bootstrap

function Test-CondaPresence($cfg) {
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Log "Conda already present."
        $Summary.CondaInstalled = $true   # mark only if found
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
        if (-not (Invoke-WithRetry -Command @("conda", "create", "-y", "-p", $envPath,
                    "python=$($cfg.PythonVersion)", "--quiet", "--no-default-packages") `
                    -Description "Creating Conda environment ($envPath)" `
                    -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
            Write-Log "Failed to create environment at $envPath." "ERROR"
            exit 20
        }
    }
    Write-Log "Environment $($cfg.EnvName) ready at $envPath." "OK"
}

function Install-Pip($cfg) {
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $cfg.EnvName

    if (-not (Invoke-WithRetry -Command @("conda", "install", "-p", $envPath, "-y", "pip") `
                -Description "Installing pip into environment ($envPath)" `
                -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds)) {
        Write-Log "Failed to install pip into environment at $envPath." "ERROR"
        exit 32
    }
    Write-Log "pip installed successfully in environment at $envPath." "OK"
}

function Install-WithPip {
    param(
        [Parameter(Mandatory = $true)] [string]$PythonExe,
        [Parameter(Mandatory = $true)] [hashtable]$Dep,   # pass the dependency object from config
        [hashtable]$Cfg                                 # full config for global flags
    )

    $package = $Dep.Name
    $version = $Dep.Version
    $description = "Installing $package"

    # --- Build package spec ---
    if ($version) {
        if ($version.StartsWith("<") -or $version.StartsWith(">")) {
            # inequality specifiers: don't prepend ==
            $pkgSpec = "$package$version"
        } else {
            if ($Dep.UseGpuFlag) {
                if ($Cfg.UseGPU) {
                    $pkgSpec = "$package==$version+$($Cfg.CudaTarget)"
                    $indexUrl = "https://download.pytorch.org/whl/$($Cfg.CudaTarget)"
                } else {
                    $pkgSpec = "$package==$version+cpu"
                    $indexUrl = "https://download.pytorch.org/whl/cpu"
                }
            } else {
                $pkgSpec = "$package==$version"
                $indexUrl = "https://pypi.org/simple"
            }
        }
    } else {
        $pkgSpec = $package
        $indexUrl = "https://pypi.org/simple"
    }

    # --- Build pip args ---
    $pipArgs = @($PythonExe, "-m", "pip", "install", $pkgSpec)

    if ($Dep.NoDeps) { $pipArgs += "--no-deps" }
    if ($Dep.PreferBinary -ne $false) { $pipArgs += "--prefer-binary" }
    if ($Dep.NoBuildIsolation -ne $false) { $pipArgs += "--no-build-isolation" }
    if ($Dep.OnlyIfNeeded -ne $false) { $pipArgs += @("--upgrade-strategy", "only-if-needed") }

    $pipArgs += @("--index-url", $indexUrl, "--disable-pip-version-check", "--no-input")

    # --- Timeouts ---
    $timeoutSeconds = if ($Dep.TimeoutSeconds) { $Dep.TimeoutSeconds } else { 900 }
    $inactivitySeconds = if ($Dep.InactivitySeconds) { $Dep.InactivitySeconds } else { 300 }

    Invoke-WithRetry -Command $pipArgs `
        -Description $description `
        -MaxRetries $Cfg.RetryCount `
        -BackoffSeconds $Cfg.BackoffSeconds `
        -TimeoutSeconds $timeoutSeconds `
        -InactivitySeconds $inactivitySeconds `
        -NoProgressDuringRun
}

function Install-Dependencies($cfg) {
    $pythonExe = Join-Path (Join-Path $cfg.EnvPath $cfg.EnvName) "python.exe"

    foreach ($dep in $cfg.Dependencies) {
        Install-WithPip -PythonExe $pythonExe -Dep $dep -Cfg $cfg
    }
}

function Test-Environment($cfg) {
    $envPath = Join-Path (if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }) $cfg.EnvName
    $pythonExe = Join-Path $envPath "python.exe"

    if (-not (Test-Path $pythonExe)) {
        Write-Log "python.exe not found in environment $($cfg.EnvName)." "ERROR"
        exit 50
    }

    Write-Log "Verifying WhisperX environment integrity..."

    $code = @'
modules = [
    "torch","torchaudio","torchvision","numpy","transformers","tokenizers",
    "huggingface_hub","safetensors","whisperx",
    "pyannote.audio","pyannote.pipeline","pyannote.core","pyannote.metrics","ffmpeg"
]
for m in modules:
    try:
        __import__(m)
        print(f"{m} OK")
    except Exception as e:
        print(f"{m} FAILED: {e}")
'@

    $tempFile = [System.IO.Path]::GetTempFileName() + ".py"
    Set-Content -Path $tempFile -Value $code -Encoding UTF8

    $result = Invoke-WithRetry -Command @($pythonExe, $tempFile) `
        -Description "Environment verification" `
        -MaxRetries $cfg.RetryCount -BackoffSeconds $cfg.BackoffSeconds `
        -TimeoutSeconds 120 -InactivitySeconds 30 -NoProgressDuringRun

    Remove-Item $tempFile -Force

    if (-not $result) {
        Write-Log "Environment verification failed." "ERROR"
        exit 51
    }

    Write-Log "Environment verification succeeded. All core packages are importable." "OK"
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
