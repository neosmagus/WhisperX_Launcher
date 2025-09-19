# whisperx_launcher.ps1
# PowerShell orchestrator for WhisperX Launcher
# Implements robust env handling, retries, timestamps, CUDA/ffmpeg logic, diarization hints

param(
    [string]$StatusLog = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load config ---
$ConfigPath = Join-Path $PSScriptRoot 'whisperx_config.json'
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}
$Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

# --- Resolve config values with defaults ---
$UseConfig         = $Config.UseConfig
$UseConsole        = $Config.use_console
$EnvRoot           = if ($Config.EnvPath) { $Config.EnvPath } else { "C:\conda_envs" }
$EnvName           = if ($Config.EnvName) { $Config.EnvName } else { "WhisperX" }
$FinalEnvPath      = Join-Path $EnvRoot $EnvName
$PythonVersion     = if ($Config.PythonVersion) { $Config.PythonVersion } else { "3.10.18" }
$CudaTarget        = if ($Config.CudaTarget) { $Config.CudaTarget } else { "" }
$UseGPU            = [bool]$Config.UseGPU
$DefaultModel      = if ($Config.DefaultModel) { $Config.DefaultModel } else { "base" }
$OutputDir         = $Config.OutputDir
$HfToken           = $Config.HuggingFaceToken
$DiarizeOnFirstRun = [bool]$Config.DiarizeOnFirstRun
$UseSafe           = [bool]$Config.UseSafe
$UseSystemFfmpeg   = [bool]$Config.UseSystemFfmpeg
$FfmpegPath        = $Config.FfmpegPath
$RetryCount        = if ($Config.RetryCount) { [int]$Config.RetryCount } else { 3 }
$BackoffSeconds    = if ($Config.BackoffSeconds) { [int]$Config.BackoffSeconds } else { 5 }
$LogTimestamps     = if ($null -ne $Config.LogTimestamps) { [bool]$Config.LogTimestamps } else { $true }
$ScriptPath        = if ($Config.ScriptPath) { $Config.ScriptPath } else { $PSScriptRoot }
$InstallConda      = [bool]$Config.InstallConda

# --- Status logging helpers ---
$script:LastStatus = $null
function Write-Status {
    param([string]$Message)
    $ts = if ($LogTimestamps) { "[{0:yyyy-MM-dd HH:mm:ss}] " -f (Get-Date) } else { "" }
    $line = "$ts$Message"

    if ($script:LastStatus -ne $line) {
        $script:LastStatus = $line

        if ($StatusLog) {
            # Read existing log (if any), remove any previous occurrence of this message
            $content = ""
            if (Test-Path $StatusLog) {
                $content = Get-Content -Raw -Path $StatusLog -ErrorAction SilentlyContinue
                $content = ($content -split "`r?`n" | Where-Object { $_ -and ($_ -ne $line) }) -join "`r`n"
            }
            # Write updated log with the new status at the end
            "$content`r`n$line" | Out-File -FilePath $StatusLog -Encoding UTF8
        }

        Write-Host $line
    }
}
function Set-Phase { param([string]$Phase) ; Write-Status $Phase }

# --- Retry wrapper ---
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$Retries = $RetryCount,
        [int]$Backoff = $BackoffSeconds,
        [string]$What = "operation"
    )
    $attempt = 0
    while ($true) {
        try {
            & $ScriptBlock
            return
        } catch {
            $attempt++
            if ($attempt -gt $Retries) {
                Write-Status "Failed $What after $Retries retries: $($_.Exception.Message)"
                throw
            } else {
                Write-Status "Error during $What (attempt $attempt/$Retries): $($_.Exception.Message). Retrying in $Backoff seconds..."
                Start-Sleep -Seconds $Backoff
            }
        }
    }
}

# --- Quote helper ---
function Q { param([string]$p) if ($p -match '\s') { return '"' + $p + '"' } else { return $p } }

# --- Conda bootstrap ---
Set-Phase "Checking for Conda"
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    if ($InstallConda) {
        Invoke-WithRetry -What "Miniconda install" -ScriptBlock {
            Write-Status "Installing Miniconda..."
            choco install miniconda3 -y
        }
        $env:PATH = "$env:ALLUSERSPROFILE\Miniconda3\Scripts;$env:ALLUSERSPROFILE\Miniconda3;$env:PATH"
    } else {
        throw "Conda not found and InstallConda=false."
    }
}

# --- Environment creation ---
Set-Phase "Ensuring environment at $FinalEnvPath"
if (-not (Test-Path $FinalEnvPath)) {
    Invoke-WithRetry -What "conda env creation" -ScriptBlock {
        & conda create -y -p $FinalEnvPath python=$PythonVersion
    }
} else {
    Write-Status "Using existing environment at $(Q $FinalEnvPath)"
}

# --- CUDA preflight ---
function Get-CudaInfo {
    try {
        $nvidiaSmi = (Get-Command nvidia-smi -ErrorAction Stop).Source
    } catch { return @{ HasGPU = $false; Driver = "" } }
    $info = & $nvidiaSmi --query-gpu=driver_version --format=csv,noheader 2>$null
    return @{ HasGPU = $true; Driver = ($info | Select-Object -First 1) }
}
$cuda = Get-CudaInfo
if ($UseGPU) {
    if (-not $cuda.HasGPU) {
        $msg = "No NVIDIA GPU/driver detected."
        if ($UseConfig) { throw "$msg Aborting because UseGPU=true under UseConfig." }
        else {
            Write-Status "$msg Falling back to CPU."
            $UseGPU = $false
        }
    }
}

# --- PyTorch install ---
Set-Phase "Installing PyTorch"
$torchIndex = ""
if ($UseGPU -and $CudaTarget) { $torchIndex = "https://download.pytorch.org/whl/$CudaTarget" }
elseif (-not $UseGPU) { $torchIndex = "https://download.pytorch.org/whl/cpu" }

function Pip-Install {
    param([string[]]$Args, [string]$What = "pip install")
    Invoke-WithRetry -What $What -ScriptBlock {
        & conda run -p $FinalEnvPath python -m pip install @Args
    }
}
if ($torchIndex) {
    Pip-Install -What "PyTorch" -Args @("--index-url", $torchIndex, "torch", "torchaudio")
}

# --- WhisperX + deps ---
Set-Phase "Installing WhisperX"
Pip-Install -What "WhisperX" -Args @("whisperx")
if (-not $UseSystemFfmpeg) {
    Pip-Install -What "imageio-ffmpeg" -Args @("imageio-ffmpeg")
}

# --- ffmpeg handling ---
Set-Phase "ffmpeg setup"
if ($UseSystemFfmpeg -and $FfmpegPath) {
    if (Test-Path $FfmpegPath) {
        $ffDir = Split-Path -Parent $FfmpegPath
        $env:PATH = "$ffDir;$($env:PATH)"
        Write-Status "Using system ffmpeg at $(Q $FfmpegPath)"
    } else {
        Write-Status "FfmpegPath not found: $(Q $FfmpegPath). Falling back to imageio-ffmpeg."
    }
}

# --- Diarization pre-cache ---
if ($DiarizeOnFirstRun -and $HfToken) {
    Set-Phase "Caching diarization model"
    try {
        Invoke-WithRetry -What "Diarization cache" -ScriptBlock {
            & conda run -p $FinalEnvPath python (Join-Path $PSScriptRoot "whisperx_diarization.py") $HfToken
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "403|401|Unauthorized|Forbidden|not authorized|access") {
            Write-Status "Hugging Face access denied. Accept model terms and verify token."
        }
        throw
    }
}

# --- Launch GUI ---
Set-Phase "Launching GUI"

$guiPath = Join-Path $PSScriptRoot "whisperx_gui.py"
$guiArgs = @()

# Pass default model and output dir if configured
if ($DefaultModel) { $guiArgs += @("--default-model", $DefaultModel) }
if ($OutputDir)    { $guiArgs += @("--output-dir", $OutputDir) }

# Pass Hugging Face token via environment if present
if ($HfToken) { $env:HUGGINGFACE_TOKEN = $HfToken }

# Run the GUI inside the environment using conda run
try {
    & conda run -p $FinalEnvPath python $guiPath @guiArgs
} catch {
    Write-Status "Error launching GUI: $($_.Exception.Message)"
    throw
}

Set-Phase "WhisperX session complete"
Write-Status "All tasks finished successfully."