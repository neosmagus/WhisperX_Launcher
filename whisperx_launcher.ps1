param(
    [string]$ConfigPath = "$(Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\whisperx_config.json')"
)

$ErrorActionPreference = 'Stop'

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "[ERROR] Failed to parse config file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Resolve log directory ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir = if ($config.LogPath) { Resolve-Path (Join-Path $ScriptDir $config.LogPath) } else { Join-Path $ScriptDir '..\logs' }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# --- Create log file ---
$LogFile = Join-Path $LogDir ("launcher_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
    Add-Content -Path $LogFile -Value $line
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
            return $true
        }
        catch {
            Write-Log "Attempt $i failed during $What: $($_.Exception.Message)" "WARN"
            if ($i -lt $MaxRetries) {
                Write-Log "Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    return $false
}

function Install-Conda {
    Write-Log "Installing Miniconda..."
    try {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Log "Chocolatey not found - installing..."
            $chocoInstallCmd = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
'@
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-Command", $chocoInstallCmd -Wait
        }
        choco install miniconda3 --params="'/AddToPath:1 /InstallationType:JustMe /RegisterPython:1'" -y
        $condaRoot = "$env:USERPROFILE\Miniconda3"
        $env:PATH = "$condaRoot;$condaRoot\Scripts;$condaRoot\condabin;$condaRoot\Library\bin;$env:PATH"
        if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
            Write-Log "Miniconda installation completed but 'conda' not found." "ERROR"
            exit 11
        }
    } catch {
        Write-Log "Miniconda installation failed: $($_.Exception.Message)" "ERROR"
        exit 11
    }
}

Write-Log "Launcher started with config: $ConfigPath"

$EnvRoot        = $config.EnvPath
$EnvName        = $config.EnvName
$FinalEnvPath   = Join-Path $EnvRoot $EnvName
$PythonVersion  = $config.PythonVersion
$CudaTarget     = $config.CudaTarget
$UseGPU         = [bool]$config.UseGPU
$UseSystemFfmpeg= [bool]$config.UseSystemFfmpeg
$FfmpegPath     = $config.FfmpegPath
$InstallConda   = [bool]$config.InstallConda

# --- Conda bootstrap ---
Write-Log "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    Write-Log "Conda not found"
    if ($InstallConda) {
        Install-Conda
    } else {
        Write-Log "Conda not found and InstallConda=false." "ERROR"
        exit 10
    }
}

# --- Environment creation ---
Write-Log "Ensuring environment at $FinalEnvPath"
if (-not (Test-Path $FinalEnvPath)) {
    if (-not (Retry-Command -What "conda env creation" -MaxRetries $config.RetryCount -DelaySeconds $config.BackoffSeconds -Script {
        & conda create -y -p $FinalEnvPath python=$PythonVersion
    })) {
        Write-Log "Failed to create Conda environment." "ERROR"
        exit 20
    }
}

# --- PyTorch install ---
Write-Log "Installing PyTorch..."
$torchIndex = ""
if ($UseGPU -and $CudaTarget) { $torchIndex = "https://download.pytorch.org/whl/$CudaTarget" }
elseif (-not $UseGPU) { $torchIndex = "https://download.pytorch.org/whl/cpu" }

if ($torchIndex) {
    if (-not (Retry-Command -What "PyTorch install" -MaxRetries $config.RetryCount -DelaySeconds $config.BackoffSeconds -Script {
        & conda run -p $FinalEnvPath python -m pip install --upgrade --index-url $torchIndex torch torchaudio
    })) {
        Write-Log "PyTorch installation failed." "ERROR"
        exit 30
    }
}

# --- WhisperX install ---
Write-Log "Installing WhisperX..."
if (-not (Retry-Command -What "WhisperX install" -MaxRetries $config.RetryCount -DelaySeconds $config.BackoffSeconds -Script {
    & conda run -p $FinalEnvPath python -m pip install whisperx
})) {
    Write-Log "WhisperX installation failed." "ERROR"
    exit 31
}

# --- ffmpeg handling ---
Write-Log "Checking for ffmpeg..."
try {
    if ($UseSystemFfmpeg -and $FfmpegPath) {
        if (Test-Path $FfmpegPath) {
            $ffDir = Split-Path -Parent $FfmpegPath
            $env:PATH = "$ffDir;$($env:PATH)"
            Write-Log "Using system ffmpeg at $FfmpegPath"
        } else {
            Write-Log "FfmpegPath not found: $FfmpegPath" "ERROR"
            exit 40
        }
    } elseif (-not $UseSystemFfmpeg) {
        if (-not (Retry-Command -What "imageio-ffmpeg install" -MaxRetries $config.RetryCount -DelaySeconds $config.BackoffSeconds -Script {
            & conda run -p $FinalEnvPath python -m pip install --upgrade imageio-ffmpeg
        })) {
            Write-Log "imageio-ffmpeg installation failed." "ERROR"
            exit 40
        }
    }
} catch {
    Write-Log "ffmpeg setup failed: $($_.Exception.Message)" "ERROR"
    exit 40
}

# --- Launch WhisperX GUI ---
$guiPath = Join-Path $ScriptDir "whisperx_gui.py"
if (-not (Test-Path $guiPath)) {
    Write-Log "GUI script not found: $guiPath" "ERROR"
    exit 50
}

try {
    Write-Log "Launching WhisperX GUI..."
    & conda run -p $FinalEnvPath python $guiPath
    $guiExit = $LASTEXITCODE
    if ($guiExit -ne 0) {
        Write-Log "WhisperX GUI exited with code $guiExit" "ERROR"
        exit 50
    }
    Write-Log "WhisperX GUI closed successfully." "OK"
} catch {
    Write-Log "Error launching GUI: $($_.Exception.Message)" "ERROR"
    exit 50
}

Write-Log "All tasks completed successfully." "OK"
exit 0