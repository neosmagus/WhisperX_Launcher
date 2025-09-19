param(
    [string]$StatusLog = ""
)

function Write-Status($msg) {
    if ($StatusLog) {
        Add-Content -Path $StatusLog -Value $msg
    }
}

$settingsFile = "$env:USERPROFILE\.whisperx_launcher_settings.json"

function Save-Settings($envPath, $scriptPath) {
    $settings = @{ envPath = $envPath; scriptPath = $scriptPath }
    $settings | ConvertTo-Json | Set-Content -Path $settingsFile -Encoding UTF8
}

function Load-Settings {
    if (Test-Path $settingsFile) {
        try {
            return Get-Content $settingsFile | ConvertFrom-Json
        } catch { return $null }
    }
    return $null
}

function Install-Conda {
    Write-Status "Installing Miniconda..."
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Status "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    choco install miniconda3 --params="'/AddToPath:1 /InstallationType:JustMe /RegisterPython:1'" -y
    Write-Status "Miniconda installed. Restart shell or run 'refreshenv'."
}

function Create-WhisperXEnv {
    Write-Status "Creating WhisperX environment..."
    $envName = Read-Host "Enter a name for the new conda environment (e.g., whisperx_cpu or whisperx_gpu)"
    $envPath = "C:\conda_envs\$envName"

    $gpuChoice = Read-Host "Do you have an NVIDIA GPU and want GPU acceleration? (y/n)"
    $useGPU = $gpuChoice -match '^[Yy]'

    $versionChoice = Read-Host "Use safe pinned versions (recommended) or latest? (safe/latest)"
    $useSafe = $versionChoice -match '^(safe|s)$'

    conda create -p $envPath python=3.10.18 -y
    conda activate $envPath

    Write-Status "Installing PyTorch..."
    if ($useGPU) {
        if ($useSafe) {
            pip install torch==2.3.1+cu121 torchaudio==2.3.1+cu121 torchvision==0.18.1+cu121 --index-url https://download.pytorch.org/whl/cu121
        } else {
            pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cu121
        }
    } else {
        if ($useSafe) {
            pip install torch==2.3.1+cpu torchaudio==2.3.1+cpu torchvision==0.18.1+cpu --index-url https://download.pytorch.org/whl/cpu
        } else {
            pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cpu
        }
    }

    Write-Status "Installing WhisperX and dependencies..."
    if ($useSafe) {
        pip install whisperx==3.3.0
        pip install pyannote.audio==3.3.2 pyannote.pipeline==3.0.1
        pip install numpy==1.26.4 "pyannote-core<6.0.0" "pyannote-metrics<4.0.0"
    } else {
        pip install whisperx
    }

    pip install matplotlib imageio-ffmpeg

    Write-Status "Configuring ffmpeg..."
    $bin = "$Env:CONDA_PREFIX\Lib\site-packages\imageio_ffmpeg\binaries"
    if (Test-Path "$bin") {
        $ffmpegExe = Get-ChildItem $bin -Filter "ffmpeg-win-*.exe" | Select-Object -First 1
        if ($ffmpegExe -and -not (Test-Path "$bin\ffmpeg.exe")) {
            Copy-Item $ffmpegExe.FullName "$bin\ffmpeg.exe"
        }
    }

    $activateDir = "$Env:CONDA_PREFIX\etc\conda\activate.d"
    New-Item -ItemType Directory -Force -Path $activateDir | Out-Null
    $hookFile = "$activateDir\ffmpeg.ps1"
    @"
# Auto-add imageio-ffmpeg binary folder to PATH
\$bin = `"$Env:CONDA_PREFIX\Lib\site-packages\imageio_ffmpeg\binaries`"
if (Test-Path "\$bin\ffmpeg.exe") {
    if (\$Env:PATH -notlike "\$bin*") {
        \$Env:PATH = "\$bin;" + \$Env:PATH
    }
}
"@ | Set-Content -Path $hookFile -Encoding UTF8

    Write-Status "Downloading diarization models..."
    Write-Host "NOTE: You must have already accepted the model terms in your Hugging Face account."
    $hfToken = Read-Host "Enter your Hugging Face token (leave blank to skip model download)"
    if ($hfToken) {
        python - <<PY
from pyannote.audio import Pipeline
Pipeline.from_pretrained('pyannote/speaker-diarization-3.1', use_auth_token="$hfToken")
print("Diarization model cached successfully.")
PY
        Write-Status "Diarization model cached."
    } else {
        Write-Status "Skipping diarization model download."
    }

    return $envPath
}

# --- MAIN LOGIC ---
Write-Status "Starting WhisperX Launcher..."
$settings = Load-Settings

# Step 1: Check for conda
Write-Status "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    $ans = Read-Host "Conda not found. Install Miniconda now? (y/n)"
    if ($ans -match '^[Yy]') {
        Install-Conda
        Write-Status "Please restart PowerShell and run again."
        exit
    } else {
        Write-Status "Cannot proceed without Conda."
        exit 1
    }
}

# Step 2: Find WhisperX env
Write-Status "Checking for WhisperX environment..."
$envPath = $settings.envPath
if (-not $envPath -or -not (Test-Path $envPath)) {
    $ans = Read-Host "Create a new WhisperX environment now? (y/n)"
    if ($ans -match '^[Yy]') {
        $envPath = Create-WhisperXEnv
    } else {
        Write-Status "Cannot proceed without WhisperX environment."
        exit 1
    }
}

# Step 3: Find GUI script
Write-Status "Locating GUI script..."
$scriptPath = $settings.scriptPath

# Auto-detect in same folder as this .ps1 before prompting
if (-not $scriptPath -or -not (Test-Path $scriptPath)) {
    $ps1Folder = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $autoGuiPath = Join-Path $ps1Folder "whisperx_gui.py"
    if (Test-Path $autoGuiPath) {
        $scriptPath = $autoGuiPath
    } else {
        $defaultPath = Join-Path (Get-Location) "whisperx_gui.py"
        if (Test-Path $defaultPath) {
            $scriptPath = $defaultPath
        } else {
            $scriptPath = Read-Host "Enter full path to whisperx_gui.py"
            if (-not (Test-Path $scriptPath)) {
                Write-Status "GUI script not found."
                exit 1
            }
        }
    }
}

# Save settings for next time
Save-Settings $envPath $scriptPath

# Step 4: Activate env and run GUI
Write-Status "Launching WhisperX GUI..."
conda activate $envPath
python "$scriptPath"

Write-Status "WhisperX GUI closed."