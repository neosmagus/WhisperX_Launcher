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
. "$PSScriptRoot\whisperx_install_tasks.ps1"

# --- Load config ---
$cfg = if ($ConfigDir) { Get-Config $ConfigDir } else { @{} }

Write-Log "Starting WhisperX installation..."

# --- Summary tracking ---
$Summary = @{
    CondaInstalled    = $false
    EnvCreated        = $false
    PipInstalled      = $false
    PyTorchInstalled  = $false
    WhisperXInstalled = $false
    FfmpegInstalled   = $false
    Verified          = $false
    ShortcutCreated   = $false
}

# Define stages
$stages = @(
    @{ Name = "Check Conda"; Action = { Test-CondaPresence $cfg } },
    @{ Name = "Download Miniconda"; Action = { Get-MinicondaInstaller $cfg } },
    @{ Name = "Run Miniconda Installer"; Action = { Install-Miniconda $cfg; $Summary.CondaInstalled = $true } },
    @{ Name = "Configure Conda Channels"; Action = { Set-CondaChannels $cfg } },
    @{ Name = "Update Conda"; Action = { Update-Conda $cfg } },
    @{ Name = "Create Environment"; Action = { Install-CondaEnvironment $cfg; $Summary.EnvCreated = $true } },
    @{ Name = "Install Pip"; Action = { Install-Pip $cfg; $Summary.PipInstalled = $true } },

    # Core scientific stack
    @{ Name = "Install Numpy"; Action = { Install-Numpy $cfg } },

    # PyTorch stack
    @{ Name = "Install PyTorch"; Action = { Install-PyTorch $cfg; $Summary.PyTorchInstalled = $true } },

    # HuggingFace stack
    @{ Name = "Install Transformers"; Action = { Install-Transformers $cfg } },
    @{ Name = "Install Tokenizers"; Action = { Install-Tokenizers $cfg } },
    @{ Name = "Install Huggingface Hub"; Action = { Install-HuggingfaceHub $cfg } },
    @{ Name = "Install Safetensors"; Action = { Install-Safetensors $cfg } },
    @{ Name = "Install Nltk"; Action = { Install-Nltk $cfg } },

    # WhisperX itself (no deps)
    @{ Name = "Install WhisperX"; Action = { Install-WhisperX $cfg; $Summary.WhisperXInstalled = $true } },

    # Pyannote stack
    @{ Name = "Install Pyannote Audio"; Action = { Install-PyannoteAudio $cfg } },
    @{ Name = "Install Pyannote Pipeline"; Action = { Install-PyannotePipeline $cfg } },
    @{ Name = "Install Pyannote Metrics"; Action = { Install-PyannoteMetrics $cfg } },
    @{ Name = "Install Pyannote Core"; Action = { Install-PyannoteCore $cfg } },

    # ffmpeg-python
    @{ Name = "Install ffmpeg-python"; Action = { Install-FFmpegPython $cfg; $Summary.FfmpegInstalled = $true } },

    # Final checks
    @{ Name = "Verify Environment"; Action = { Test-Environment $cfg; $Summary.Verified = $true } },
    @{ Name = "Create Shortcut"; Action = { New-Shortcut $cfg; $Summary.ShortcutCreated = $true } }
)

# --- Run stages with progress ---
for ($i = 0; $i -lt $stages.Count; $i++) {
    $pct = [int](($i / $stages.Count) * 100)
    Write-Progress -Activity "WhisperX Installation" -Status $stages[$i].Name -PercentComplete $pct
    try {
        & $stages[$i].Action | Out-Null
    } catch {
        Write-Log "Stage '$($stages[$i].Name)' failed: $_" "ERROR"
        if ($Debug) { Pause }
        exit 1
    }
}

Write-Progress -Activity "WhisperX Installation" -Completed
Write-Log "Installation complete." "OK"

# --- Human-readable summary ---
Write-Host "`n========== INSTALL SUMMARY ==========" -ForegroundColor Cyan
Write-Host ("Conda Installed         : {0}" -f $Summary.CondaInstalled)
Write-Host ("Environment Created     : {0}" -f $Summary.EnvCreated)
Write-Host ("Pip Installed           : {0}" -f $Summary.PipInstalled)
Write-Host ("PyTorch Installed       : {0}" -f $Summary.PyTorchInstalled)
Write-Host ("WhisperX Installed      : {0}" -f $Summary.WhisperXInstalled)
Write-Host ("ffmpeg-python Installed : {0}" -f $Summary.FfmpegInstalled)
Write-Host ("Environment Verified    : {0}" -f $Summary.Verified)
Write-Host ("Shortcut Created        : {0}" -f $Summary.ShortcutCreated)
Write-Host "=====================================" -ForegroundColor Cyan

# --- Machine-readable summary for batch wrapper ---
$condaVersion = conda --version
$summaryLine = "SUMMARY=" +
"CondaInstalled=$($Summary.CondaInstalled);" +
"EnvCreated=$($Summary.EnvCreated);" +
"PipInstalled=$($Summary.PipInstalled);" +
"PyTorchInstalled=$($Summary.PyTorchInstalled);" +
"WhisperXInstalled=$($Summary.WhisperXInstalled);" +
"FfmpegInstalled=$($Summary.FfmpegInstalled);" +
"Verified=$($Summary.Verified);" +
"ShortcutCreated=$($Summary.ShortcutCreated);" +
"CondaVersion=$condaVersion;" +
"PythonVersion=$($cfg.PythonVersion);" +
"CudaTarget=$($cfg.CudaTarget)"
Write-Output $summaryLine

if ($Debug) {
    Write-Log "Debug mode active - press any key to close..."
    Pause
}
exit 0
