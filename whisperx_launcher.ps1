param(
    [string]$StatusLog = ""
)

# --- Clear log at start to avoid duplicates from previous runs ---
if ($StatusLog) {
    Clear-Content -Path $StatusLog -ErrorAction SilentlyContinue
}

# --- Helper: Write status with de-dupe ---
function Write-Status($msg) {
    if ($StatusLog) {
        $last = if (Test-Path $StatusLog) { Get-Content $StatusLog -Tail 1 } else { "" }
        if ($last -ne $msg) {
            Add-Content -Path $StatusLog -Value $msg
        }
    }
}

# --- Helper: Detect hidden console ---
function In-SilentMode {
    return ($Host.UI.RawUI.WindowTitle -eq "")
}

# --- Helper: Prompt Yes/No with GUI fallback ---
function Prompt-YesNo($message, $title = "WhisperX") {
    if (In-SilentMode) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $result = [Microsoft.VisualBasic.Interaction]::MsgBox($message, 4 + 32, $title)
        return ($result -eq "Yes")
    } else {
        $ans = Read-Host "$message (y/n)"
        return ($ans -match '^[Yy]')
    }
}

# --- Helper: Prompt text input with GUI fallback ---
function Prompt-Input($message, $title = "WhisperX", $default = "") {
    if (In-SilentMode) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        return [Microsoft.VisualBasic.Interaction]::InputBox($message, $title, $default)
    } else {
        return Read-Host $message
    }
}

$settingsFile = "$env:USERPROFILE\.whisperx_launcher_settings.json"
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configFile   = Join-Path $ScriptDir "whisperx_config.json"

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

    if ($UseConfig) {
        $envName  = $Config.envName
        $useGPU   = $Config.useGPU
        $useSafe  = $Config.useSafe
    } else {
        $envName = Prompt-Input "Enter a name for the new conda environment (e.g., whisperx_cpu or whisperx_gpu)"
        $useGPU  = Prompt-YesNo "Do you have an NVIDIA GPU and want GPU acceleration?"
        $useSafe = (Prompt-Input "Use safe pinned versions (recommended) or latest? (safe/latest)" -match '^(safe|s)$')
    }

    $envPath = "C:\conda_envs\$envName"

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
    $hfToken = if ($UseConfig) { $Config.hfToken } else { Prompt-Input "Enter your Hugging Face token (leave blank to skip model download)" }
    if ($hfToken) {
        $diarScript = Join-Path $ScriptDir "whisperx_diarization.py"
        if (Test-Path $diarScript) {
            python "$diarScript" "$hfToken"
        } else {
            Write-Warning "Diarization script not found: $diarScript"
        }
    } else {
        Write-Status "Skipping diarization model download."
    }

    return $envPath
}

# --- MAIN LOGIC ---
Write-Status "Starting WhisperX Launcher..."

# Load config if present
$Config = $null
$UseConfig = $false
if (Test-Path $configFile) {
    try {
        $Config = Get-Content $configFile -Raw | ConvertFrom-Json
        $UseConfig = $Config.UseConfig -eq $true
    } catch {
        Write-Warning "Failed to parse config file."
    }
}

$settings = Load-Settings

# Step 1: Check for conda
Write-Status "Checking for Conda..."
if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    if ($UseConfig) {
        if ($Config.installConda) {
            Install-Conda
            Write-Status "Please restart PowerShell and run again."
            exit
        } else {
            Write-Status "Cannot proceed without Conda."
            exit 1
        }
    } else {
        if (Prompt-YesNo "Conda not found. Install Miniconda now?") {
            Install-Conda
            Write-Status "Please restart PowerShell and run again."
            exit
        } else {
            Write-Status "Cannot proceed without Conda."
            exit 1
        }
    }
}

# Step 2: Find WhisperX env
Write-Status "Checking for WhisperX environment..."
$envPath = $settings.envPath

if (-not $envPath -or -not (Test-Path $envPath)) {
    if ($UseConfig -and $Config.envPath) {
        if (Test-Path $Config.envPath) {
            $envPath = $Config.envPath
        } else {
            Write-Status "Configured environment path not found: $($Config.envPath)"
            $envPath = Create-WhisperXEnv
        }
    } else {
        if (Prompt-YesNo "Create a new WhisperX environment now?") {
            $envPath = Create-WhisperXEnv
        } else {
            Write-Status "Cannot proceed without WhisperX environment."
            exit 1
        }
    }
}

# Step 3: Find GUI script
Write-Status "Locating GUI script..."
$scriptPath = $settings.scriptPath

if (-not $scriptPath -or -not (Test-Path $scriptPath)) {
    if ($UseConfig -and $Config.scriptPath) {
        if (Test-Path $Config.scriptPath) {
            $scriptPath = $Config.scriptPath
        } else {
            Write-Status "Configured GUI script not found: $($Config.scriptPath)"
            $scriptPath = Prompt-Input "Enter full path to whisperx_gui.py"
        }
    } else {
        # Auto-detect in same folder as this .ps1 before prompting
        $ps1Folder = Split-Path -Parent $MyInvocation.MyCommand.Definition
        $autoGuiPath = Join-Path $ps1Folder "whisperx_gui.py"
        if (Test-Path $autoGuiPath) {
            $scriptPath = $autoGuiPath
        } else {
            $defaultPath = Join-Path (Get-Location) "whisperx_gui.py"
            if (Test-Path $defaultPath) {
                $scriptPath = $defaultPath
            } else {
                $scriptPath = Prompt-Input "Enter full path to whisperx_gui.py"
                if (-not (Test-Path $scriptPath)) {
                    Write-Status "GUI script not found."
                    exit 1
                }
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