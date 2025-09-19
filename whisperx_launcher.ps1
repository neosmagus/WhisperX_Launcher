<#
    WhisperX PowerShell Launcher
    - Reads whisperx_config.json
    - If use_console = true → run in console mode
    - Else → run silent mode with HTA + robust VBS
#>

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigFile  = Join-Path $ScriptDir "whisperx_config.json"
$HTATemplate = Join-Path $ScriptDir "status_template.hta"
$HTAFile     = Join-Path $env:TEMP "whisperx_status.hta"
$VBSFile     = Join-Path $env:TEMP "whisperx_launcher.vbs"
$LogFile     = Join-Path $env:TEMP "whisperx_launcher.log"

# --- Read config ---
if (Test-Path $ConfigFile) {
    try {
        $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $UseConsole = $Config.use_console -eq $true
    } catch {
        Write-Warning "Failed to parse config file. Defaulting to silent mode."
        $UseConsole = $false
    }
} else {
    Write-Warning "Config file not found. Defaulting to silent mode."
    $UseConsole = $false
}

if ($UseConsole) {
    Write-Host "[INFO] Console mode forced by config."
    # Activate venv if present
    $VenvActivate = Join-Path $ScriptDir "venv\Scripts\Activate.ps1"
    if (Test-Path $VenvActivate) {
        & $VenvActivate
    }
    python (Join-Path $ScriptDir "whisperx_gui.py")
    exit
}

Write-Host "[INFO] Silent mode (HTA) enabled."

# --- Silent mode logic ---
if (-not (Test-Path $HTATemplate)) {
    Write-Error "HTA template missing: $HTATemplate"
    exit 1
}

# Copy HTA template to temp
Copy-Item -Path $HTATemplate -Destination $HTAFile -Force -ErrorAction Stop

# Replace placeholder in HTA with log path
(Get-Content $HTAFile) -replace '\{\{TEMP_LOG\}\}', [Regex]::Escape($LogFile) |
    Set-Content $HTAFile

# Create robust VBS stealth launcher
$cmdLine = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" internal_run > `"$LogFile`" 2>&1"
$VbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "cmd /c ""$cmdLine""", 0, True
"@
Set-Content $VBSFile -Value $VbsContent -Encoding ASCII

# Launch HTA status window
Start-Process "mshta.exe" $HTAFile

# Launch VBS to run silently
cscript //nologo $VBSFile
exit

# --- Internal run section ---
if ($args -contains "internal_run") {
    $VenvActivate = Join-Path $ScriptDir "venv\Scripts\Activate.ps1"
    if (Test-Path $VenvActivate) {
        & $VenvActivate
    }
    python (Join-Path $ScriptDir "whisperx_gui.py")
}