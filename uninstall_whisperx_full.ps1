param(
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# --- Setup logging immediately ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not (Test-Path $ScriptDir)) { $ScriptDir = $PWD }
$LogFile = Join-Path $ScriptDir ("uninstall_log_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
New-Item -Path $LogFile -ItemType File -Force | Out-Null

# Track if any warnings/errors occurred
$global:HadIssues = $false

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    switch ($Level) {
        "WARN"  { Write-Host $line -ForegroundColor Yellow; $global:HadIssues = $true }
        "ERROR" { Write-Host $line -ForegroundColor Red;    $global:HadIssues = $true }
        default { Write-Host $line }
    }

    Add-Content -Path $LogFile -Value $line
}

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-FromPath($pattern, $scope) {
    $pathVar = [Environment]::GetEnvironmentVariable("Path", $scope)
    if ($pathVar) {
        $newPath = ($pathVar -split ';' | Where-Object {$_ -and ($_ -notlike $pattern)}) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
    }
}

try {
    Write-Log "Starting WhisperX uninstall..."

    # --- Remove WhisperX Conda environment ---
    $EnvRoot      = "C:\conda_envs"
    $EnvName      = "WhisperX"
    $FinalEnvPath = Join-Path $EnvRoot $EnvName

    if (Test-Path $FinalEnvPath) {
        Write-Log "Removing WhisperX Conda environment at $FinalEnvPath..."
        try {
            & conda env remove -p $FinalEnvPath -y
            Write-Log "Environment removed successfully."
        } catch {
            Write-Log "Could not remove via conda: $($_.Exception.Message)" "WARN"
            if ($Cleanup) {
                Write-Log "Cleanup mode: deleting folder directly..."
                Remove-Item -Recurse -Force $FinalEnvPath -ErrorAction SilentlyContinue
                if (-not (Test-Path $FinalEnvPath)) {
                    Write-Log "Environment folder deleted in cleanup mode."
                } else {
                    Write-Log "Environment folder still exists after cleanup attempt." "WARN"
                }
            }
        }
    } else {
        Write-Log "No WhisperX environment found."
    }

    # --- Detect and optionally remove Miniconda ---
    $condaPaths = @(
        "$env:USERPROFILE\Miniconda3",
        "$env:LOCALAPPDATA\Miniconda3",
        "$env:ALLUSERSPROFILE\Miniconda3"
    ) | Where-Object { Test-Path $_ }

    if ($condaPaths) {
        $choice = Read-Host "Miniconda found at:`n$($condaPaths -join "`n")`nRemove Miniconda? (y/n)"
        if ($choice -match '^[Yy]') {
            foreach ($path in $condaPaths) {
                $isSystem = $path -like "$env:ALLUSERSPROFILE*"
                if ($isSystem -and -not (Is-Admin)) {
                    Write-Log "Miniconda at ${path} - skipped (requires elevation)." "WARN"
                    continue
                }
                try {
                    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
                        choco uninstall miniconda3 -y -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Log "Chocolatey uninstall step failed for ${path}: $($_.Exception.Message)" "WARN"
                }
                if (Test-Path $path) {
                    if ($Cleanup) {
                        Write-Log "Cleanup mode: force removing ${path}"
                        Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
                    }
                }
                if (-not (Test-Path $path)) {
                    Remove-FromPath "*Miniconda3*" "User"
                    if (Is-Admin) { Remove-FromPath "*Miniconda3*" "Machine" }
                    Write-Log "Miniconda at ${path} - removed successfully."
                } else {
                    Write-Log "Miniconda at ${path} - removal failed or skipped." "WARN"
                }
            }
        } else {
            Write-Log "Skipping Miniconda uninstall."
        }
    } else {
        Write-Log "No Miniconda installation found."
    }

    # --- Detect and optionally remove Chocolatey ---
    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        $choice = Read-Host "Chocolatey detected. Remove Chocolatey? (y/n)"
        if ($choice -match '^[Yy]') {
            if (-not (Is-Admin)) {
                Write-Log "Chocolatey uninstall requires Administrator rights. Skipping." "WARN"
            } else {
                try {
                    choco uninstall all -y
                    Remove-Item -Recurse -Force "$env:ProgramData\chocolatey" -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "Failed to uninstall Chocolatey: $($_.Exception.Message)" "WARN"
                    if ($Cleanup) {
                        Write-Log "Cleanup mode: force removing Chocolatey folder."
                        Remove-Item -Recurse -Force "$env:ProgramData\chocolatey" -ErrorAction SilentlyContinue
                    }
                }
                if (-not (Test-Path "$env:ProgramData\chocolatey")) {
                    Remove-FromPath "*chocolatey*" "User"
                    if (Is-Admin) { Remove-FromPath "*chocolatey*" "Machine" }
                    Write-Log "Chocolatey - removed successfully."
                } else {
                    Write-Log "Chocolatey - removal failed or skipped." "WARN"
                }
            }
        } else {
            Write-Log "Skipping Chocolatey uninstall."
        }
    } else {
        Write-Log "Chocolatey not found."
    }

    Write-Log "Uninstall process complete."
    Write-Log "Log file saved to: $LogFile"

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    $global:HadIssues = $true
} finally {
    if ($global:HadIssues) {
        exit 1
    } else {
        exit 0
    }
}