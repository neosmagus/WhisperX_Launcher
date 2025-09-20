param(
    [string]$ConfigPath = "$(Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\whisperx_config.json')",
    [switch]$Cleanup
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
$LogFile = Join-Path $LogDir ("uninstall_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

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

Write-Log "=== WhisperX Uninstall Started ==="

# --- Remove WhisperX Conda environment ---
try {
    if ($config.EnvPath -and $config.EnvName) {
        $envPath = Join-Path $config.EnvPath $config.EnvName
        if (Test-Path $envPath) {
            Write-Log "Removing WhisperX Conda environment at $envPath..."
            & conda env remove -p $envPath -y
            if (Test-Path $envPath) {
                Write-Log "Environment folder still exists after removal attempt." "ERROR"
                exit 10
            }
            Write-Log "Environment removed successfully." "OK"
        } else {
            Write-Log "No WhisperX environment found at $envPath"
        }
    }
} catch {
    Write-Log "Error removing Conda environment: $($_.Exception.Message)" "ERROR"
    exit 10
}

# --- Uninstall Miniconda ---
try {
    $minicondaRoot = "$env:USERPROFILE\Miniconda3"
    if (Test-Path $minicondaRoot) {
        Write-Log "Uninstalling Miniconda..."
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            choco uninstall miniconda3 -y
        } else {
            Write-Log "Chocolatey not found - manual Miniconda uninstall required." "WARN"
        }
        if (Test-Path $minicondaRoot) {
            if (-not $Cleanup) {
                Write-Log "Miniconda folder still exists after uninstall attempt." "ERROR"
                exit 11
            } else {
                Write-Log "Cleanup mode: force-deleting Miniconda folder..."
                Remove-Item -Recurse -Force $minicondaRoot -ErrorAction SilentlyContinue
            }
        }
        Write-Log "Miniconda uninstalled successfully." "OK"
    }
} catch {
    Write-Log "Error uninstalling Miniconda: $($_.Exception.Message)" "ERROR"
    exit 11
}

# --- Uninstall Chocolatey ---
try {
    $chocoPath = "$env:ProgramData\chocolatey"
    if (Test-Path $chocoPath) {
        Write-Log "Uninstalling Chocolatey..."
        Remove-Item -Recurse -Force $chocoPath -ErrorAction SilentlyContinue
        if (Test-Path $chocoPath) {
            if (-not $Cleanup) {
                Write-Log "Chocolatey folder still exists after uninstall attempt." "ERROR"
                exit 12
            } else {
                Write-Log "Cleanup mode: force-deleting Chocolatey folder..."
                Remove-Item -Recurse -Force $chocoPath -ErrorAction SilentlyContinue
            }
        }
        Write-Log "Chocolatey uninstalled successfully." "OK"
    }
} catch {
    Write-Log "Error uninstalling Chocolatey: $($_.Exception.Message)" "ERROR"
    exit 12
}

# --- Clean PATH entries ---
try {
    Write-Log "Cleaning PATH environment variables..."
    $scopes = @("User", "Machine")
    foreach ($scope in $scopes) {
        $pathValue = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($pathValue) {
            $newPath = ($pathValue -split ';' | Where-Object {$_ -notmatch "(?i)whisperx|miniconda"}) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
        }
    }
    Write-Log "PATH variables cleaned." "OK"
} catch {
    Write-Log "Error cleaning PATH variables: $($_.Exception.Message)" "ERROR"
    exit 20
}

# --- Delete leftover files/folders ---
try {
    $targets = @(
        "$env:USERPROFILE\.cache\whisperx",
        "$env:USERPROFILE\.cache\torch",
        "$env:USERPROFILE\.cache\huggingface"
    )
    foreach ($t in $targets) {
        if (Test-Path $t) {
            if ($Cleanup) {
                Write-Log "Cleanup mode: force-deleting $t"
                Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
            } else {
                Write-Log "Leftover folder found: $t" "WARN"
                exit 30
            }
        }
    }
    Write-Log "Leftover files/folders removed." "OK"
} catch {
    Write-Log "Error deleting leftover files/folders: $($_.Exception.Message)" "ERROR"
    exit 30
}

Write-Log "=== WhisperX Uninstall Completed Successfully ===" "OK"
exit 0