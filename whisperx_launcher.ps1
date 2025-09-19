param(
    [string]$StatusLog = ""
)

function Write-Status($msg) {
    if ($StatusLog) {
        $sw = [System.IO.StreamWriter]::new($StatusLog, $true, [System.Text.Encoding]::UTF8)
        $sw.WriteLine($msg)
        $sw.Close()
    }
}

$settingsFile = "$env:USERPROFILE\.whisperx_launcher_settings.json"
$configFile   = "$PSScriptRoot\whisperx_config.json"
$diarizationScript = "$PSScriptRoot\whisperx_diarization.py"

function Save-Settings($envPath, $scriptPath) {
    $settings = @{ envPath = $envPath; scriptPath = $scriptPath }
    $settings | ConvertTo-Json | Set-Content -Path $settingsFile -Encoding UTF8
}

function Load-Settings {
    if (Test-Path $settingsFile) {
        try { return Get-Content $settingsFile | ConvertFrom-Json }
        catch { return $null }
    }
    return $null
}

function Load-Config {
    if (-not (Test-Path $configFile)) {
        Write-Status "Creating default config file..."
        $defaultConfig = @{
            UseConfig     = $false
            EnvName       = "whisperx_cpu"
            UseGPU        = $false
            UseSafe       = $true
            HuggingFaceToken = ""
        }
        $defaultConfig | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8
    }
    return Get-Content $configFile | ConvertFrom-Json
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

function Prompt-Input($message, $title, $default) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($message, $title, $default)
}

function Create-WhisperXEnv {
    param($cfg)

    Write-Status "Creating WhisperX environment..."

    if ($cfg.UseConfig) {
        $envName   = $cfg.EnvName
        $useGPU    = [bool]$cfg.UseGPU
        $useSafe   = [bool]$cfg.UseSafe
        $hfToken   = $cfg.HuggingFaceToken
    } else {
        Write-Status "Waiting for input: environment name..."
        $envName = Prompt-Input "Enter a name for the new conda environment (e.g., whisperx_cpu or whisperx_gpu)" "WhisperX Setup" "whisperx_cpu"

        Write-Status "Waiting for input: GPU choice..."
        $gpuChoice = Prompt-Input "Do you have an NVIDIA GPU and want GPU acceleration? (y/n)" "WhisperX Setup" "n"
        $useGPU = $gpuChoice -match '^[Yy]'

        Write-Status "Waiting for input: version choice..."
        $versionChoice = Prompt-Input "Use safe pinned versions (recommended) or latest? (safe/latest)" "WhisperX Setup" "safe"
        $useSafe = $versionChoice -match '^(safe|s)$'

        Write-Status "Waiting for input: Hugging Face token..."
        $hfToken = Prompt-Input "Enter your Hugging Face token (leave blank to skip model download)" "WhisperX Setup" ""
    }

    $envPath = "C:\conda_envs\$envName"

    Write-Status "Creating conda environment at $envPath..."
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
    if ($hfToken) {
        Write-Status "Downloading diarization models..."
        python $diarizationScript $hfToken
        Write-Status "Diarization model cached."
    } else {
        Write-Status "Skipping diarization model download."
    }

    return $envPath
}

# --- MAIN LOGIC ---
Write-Status "Starting WhisperX Launcher..."
$settings = Load-Settings
$config   = Load-Config

# Step 1: Check for conda
Write-Status "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    if ($config.UseConfig -and -not $config.InstallConda) {
        Write-Status "Conda not found and config says not to install. Exiting."
        exit 1
    }
    Write-Status "Waiting for input: install Miniconda?"
    $ans = if ($config.UseConfig) { "y" } else { Prompt-Input "Conda not found. Install Miniconda now? (y/n)" "WhisperX Setup" "y" }
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
    Write-Status "Waiting for input: create new environment?"
    $ans = if ($config.UseConfig) { "y" } else { Prompt-Input "Create a new WhisperX environment now? (y/n)" "WhisperX Setup" "y" }
    if ($ans -match '^[Yy]') {
        $envPath = Create-WhisperXEnv -cfg $config
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
            Write-Status "Waiting for input: GUI script path..."
            $scriptPath = if ($config.UseConfig -and $config.ScriptPath) {
                $config.ScriptPath
            } else {
                Prompt-Input "Enter full path to whisperx_gui.py" "WhisperX Setup" ""
            }
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