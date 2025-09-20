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
        [int]$DelaySeconds = 5
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            & $Script
            return
        }
        catch {
            Write-Warn "Attempt $i failed: $($_.Exception.Message)"
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

# --- Check for Conda ---
Write-Info "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    Write-Warn "Conda not found"
    if ($config.InstallConda -eq $true) {
        Write-Info "Installing Conda as per config..."
        # Add Conda install logic here if desired
    }
}

# --- Check for CUDA ---
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

# --- Check for ffmpeg ---
Write-Info "Checking for ffmpeg..."
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warn "ffmpeg not found — some features may be unavailable."
}

# --- Build WhisperX command from config ---
$cmdArgs = @()

if ($config.model) { $cmdArgs += @("--model", $config.model) }
if ($config.diarize -eq $true) { $cmdArgs += "--diarize" }
if ($config.output_format) { $cmdArgs += @("--output_format", $config.output_format) }
if ($config.output_dir) { $cmdArgs += @("--output_dir", $config.output_dir) }
if ($config.extra_args) { $cmdArgs += $config.extra_args }

if (-not $config.input_file) {
    Write-ErrorMsg "No input_file specified in config."
    exit 1
}
$cmdArgs += $config.input_file

# --- Run WhisperX ---
try {
    Write-Info "Starting WhisperX transcription..."
    Retry-Command {
        & conda run -n whisperx python -m whisperx.transcribe @cmdArgs
    } -MaxRetries 2 -DelaySeconds 10
    Write-Info "WhisperX transcription completed."
}
catch {
    Write-ErrorMsg "WhisperX encountered an error: $($_.Exception.Message)"
    exit 1
}

Write-Info "All tasks completed successfully."
exit 0