param(
    [switch]$Json,
    [string]$ConfigPath = "$(Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\whisperx_config.json')"
)

$ErrorActionPreference = 'Stop'

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Config file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# --- Resolve log directory ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir = if ($config.LogPath) { Resolve-Path (Join-Path $ScriptDir $config.LogPath) } else { Join-Path $ScriptDir '..\logs' }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# --- Create log file ---
$LogFile = Join-Path $LogDir ("check_miniconda_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line -ForegroundColor Gray }
    }
    Add-Content -Path $LogFile -Value $line
}

Write-Log "=== Miniconda Installation Check ===" "INFO"

# Common Miniconda install locations
$locations = @(
    "$env:USERPROFILE\Miniconda3",
    "$env:LOCALAPPDATA\Miniconda3",
    "$env:ALLUSERSPROFILE\Miniconda3",
    "C:\ProgramData\Miniconda3",
    "C:\Miniconda3"
)

$results = @()
$foundValid = $false

foreach ($loc in $locations) {
    if (Test-Path $loc) {
        $condaExe = Join-Path $loc "Scripts\conda.exe"
        $condaBat = Join-Path $loc "condabin\conda.bat"
        if (Test-Path $condaExe -or Test-Path $condaBat) {
            $status = "Installed"
            $color = "OK"
            $foundValid = $true
        } else {
            $status = "Partial (folder exists, conda not found)"
            $color = "WARN"
        }
    } else {
        $status = "Not found"
        $color = "INFO"
    }
    Write-Log ("{0,-50} {1}" -f $loc, $status) $color
    $results += [PSCustomObject]@{ Path = $loc; Status = $status }
}

# PATH variable check
Write-Log "=== PATH Variable Check ===" "INFO"
foreach ($scope in @("User", "Machine")) {
    $pathValue = [Environment]::GetEnvironmentVariable("Path", $scope)
    $matches = $pathValue -split ';' | Where-Object {$_ -match "(?i)Miniconda3"}
    if ($matches) {
        Write-Log "$scope PATH contains Miniconda reference(s):" "WARN"
        foreach ($m in $matches) { Write-Log "  $m" "WARN" }
    } else {
        Write-Log "$scope PATH has no Miniconda reference" "INFO"
    }
}

if (-not $foundValid) {
    Write-Log "No valid Miniconda installation detected." "ERROR"
}

if ($Json) {
    $results | ConvertTo-Json -Depth 2
}

# Exit code: 0 if found valid install, 1 otherwise
if ($foundValid) { exit 0 } else { exit 1 }