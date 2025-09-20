param(
    [string]$ConfigPath = "$(Join-Path $PSScriptRoot 'whisperx_config.json')"
)

$ErrorActionPreference = 'Stop'

function Write-Info($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [INFO] $Message"
}

function Write-Warn($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg($Message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [ERROR] $Message" -ForegroundColor Red
}

function Retry-Command {
    param(
        [scriptblock]$Script,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5,
        [string]$What = "operation"
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            & $Script
            return
        }
        catch {
            Write-Warn "Attempt $i failed during ${What}: $($_.Exception.Message)"
            if ($i -lt $MaxRetries) {
                Write-Info "Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw
            }
        }
    }
}

function Install-Conda {
    Write-Info "Installing Miniconda..."

    # Install Chocolatey if missing (elevated)
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Chocolatey not found — requesting elevation to install..."
        $chocoInstallCmd = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
'@
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-Command", $chocoInstallCmd -Wait
    }

    # Install Miniconda in JustMe mode (no elevation)
    $minicondaParams = "'/AddToPath:1 /InstallationType:JustMe /RegisterPython:1'"
    Write-Info "Installing Miniconda (JustMe mode, no elevation)..."
    choco install miniconda3 --params=$minicondaParams -y

    # Temp PATH update for current session
    $condaRoot = "$env:USERPROFILE\Miniconda3"
    $env:PATH = "$condaRoot;$condaRoot\Scripts;$condaRoot\Library\bin;$env:PATH"

    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Info "Miniconda installed and PATH updated for this session."
    }
    else {
        Write-ErrorMsg "Miniconda installation completed but 'conda' not found."
        exit 1
    }
}

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-ErrorMsg "Config file not found: $ConfigPath"
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-ErrorMsg "Failed to parse config file: $($_.Exception.Message)"
    exit 1
}

Write-Info "Launcher started with config: $ConfigPath"

# --- Resolve key config values ---
$EnvRoot        = if ($config.EnvPath) { $config.EnvPath } else { "C:\conda_envs" }
$EnvName        = if ($config.EnvName) { $config.EnvName } else { "WhisperX" }
$FinalEnvPath   = Join-Path $EnvRoot $EnvName
$PythonVersion  = if ($config.PythonVersion) { $config.PythonVersion } else { "3.10.18" }
$CudaTarget     = if ($config.CudaTarget) { $config.CudaTarget } else { "" }
$UseGPU         = [bool]$config.UseGPU
$UseSystemFfmpeg= [bool]$config.UseSystemFfmpeg
$FfmpegPath     = $config.FfmpegPath
$InstallConda   = [bool]$config.InstallConda

# --- Conda bootstrap ---
Write-Info "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    Write-Warn "Conda not found"
    if ($InstallConda) {
        Install-Conda
    }
    else {
        Write-ErrorMsg "Conda not found and InstallConda=false."
        exit 1
    }
}

# --- Environment creation ---
Write-Info "Ensuring environment at $FinalEnvPath"
if (-not (Test-Path $FinalEnvPath)) {
    Retry-Command -What "conda env creation" -Script {
        & conda create -y -p $FinalEnvPath python=$PythonVersion
    }
}
else {
    Write-Info "Using existing environment at $FinalEnvPath"
}

# --- CUDA check ---
Write-Info "Checking for CUDA..."
try {
    $cudaVersion = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null
    if ($cudaVersion) {
        Write-Info "CUDA driver version detected: $cudaVersion"
    }
    else {
        Write-Warn "No NVIDIA GPU detected or nvidia-smi not available."
    }
}
catch {
    Write-Warn "Unable to query CUDA: $($_.Exception.Message)"
}

# --- PyTorch install ---
Write-Info "Installing PyTorch..."
$torchIndex = ""
if ($UseGPU -and $CudaTarget) { $torchIndex = "https://download.pytorch.org/whl/$CudaTarget" }
elseif (-not $UseGPU) { $torchIndex = "https://download.pytorch.org/whl/cpu" }

if ($torchIndex) {
    Retry-Command -What "PyTorch install" -Script {
        & conda run -p $FinalEnvPath python -m pip install --upgrade --index-url $torchIndex torch torchaudio
    }
}

# --- WhisperX install ---
Write-Info "Installing WhisperX..."
Retry-Command -What "WhisperX install" -Script {
    & conda run -p $FinalEnvPath python -m pip install whisperx
}

# --- ffmpeg handling ---
Write-Info "Checking for ffmpeg..."
if ($UseSystemFfmpeg -and $FfmpegPath) {
    if (Test-Path $FfmpegPath) {
        $ffDir = Split-Path -Parent $FfmpegPath
        $env:PATH = "$ffDir;$($env:PATH)"
        Write-Info "Using system ffmpeg at $FfmpegPath"
    }
    else {
        Write-Warn "FfmpegPath not found: $FfmpegPath. Please verify path or set UseSystemFfmpeg=false to auto-install."
    }
}
elseif (-not $UseSystemFfmpeg) {
    Write-Info "Installing imageio-ffmpeg into environment..."
    Retry-Command -What "imageio-ffmpeg install" -Script {
        & conda run -p $FinalEnvPath python -m pip install --upgrade imageio-ffmpeg
    }
    Write-Info "imageio-ffmpeg installed. WhisperX will use its bundled ffmpeg binary."
}

# --- Launch WhisperX GUI ---
$guiPath = if ($config.ScriptPath) { $config.ScriptPath } else { Join-Path $PSScriptRoot "whisperx_gui.py" }

if (-not (Test-Path $guiPath)) {
    Write-ErrorMsg "GUI script not found: $guiPath"
    exit 1
}

$guiArgs = @()
if ($config.model)       { $guiArgs += @("--default-model", $config.model) }
if ($config.output_dir)  { $guiArgs += @("--output-dir", $config.output_dir) }
if ($config.HuggingFaceToken) { $env:HUGGINGFACE_TOKEN = $config.HuggingFaceToken }

try {
    Write-Info "Launching WhisperX GUI..."
    & conda run -p $FinalEnvPath python $guiPath @guiArgs
    Write-Info "WhisperX GUI closed."
}
catch {
    Write-ErrorMsg "Error launching GUI: $($_.Exception.Message)"
    exit 1
}

Write-Info "All tasks completed successfully."
exit 0
