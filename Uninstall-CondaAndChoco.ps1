<#
.SYNOPSIS
    Removes Miniconda (all common install locations) and Chocolatey from this system.
    Cleans up PATH entries and related environment variables.

.NOTES
    Run in an elevated PowerShell if you want to remove system-wide installs.
    Single-user Miniconda removal does not require elevation.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$msg)
    Write-Host "[INFO] $msg"
}

# --- Remove Miniconda ---
Write-Log "Searching for Miniconda installations..."
$condaPaths = @(
    "$env:USERPROFILE\Miniconda3",
    "$env:LOCALAPPDATA\Miniconda3",
    "$env:ALLUSERSPROFILE\Miniconda3"
) | Where-Object { Test-Path $_ }

if (-not $condaPaths) {
    Write-Log "No Miniconda installation found."
} else {
    foreach ($path in $condaPaths) {
        Write-Log "Removing Miniconda at: $path"
        try {
            # Try Chocolatey uninstall if applicable
            if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
                choco uninstall miniconda3 -y -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log "Chocolatey uninstall step failed or not applicable: $($_.Exception.Message)"
        }

        # Force remove folder if still exists
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
        }
    }
}

# Remove Miniconda from PATH (User + Machine)
foreach ($scope in @("User", "Machine")) {
    try {
        $pathVar = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($pathVar) {
            $newPath = ($pathVar -split ';' | Where-Object {
                ($_ -notmatch "Miniconda3")
            }) -join ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
        }
    } catch {
        Write-Log "Failed to clean PATH for ${scope}: $($_.Exception.Message)"
    }
}

# --- Remove Chocolatey ---
if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    $chocoRoot = $env:ChocolateyInstall
    if (-not $chocoRoot) { $chocoRoot = "C:\ProgramData\chocolatey" }

    Write-Log "Removing Chocolatey from: $chocoRoot"
    try {
        Remove-Item -Recurse -Force $chocoRoot -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Failed to remove Chocolatey folder: $($_.Exception.Message)"
    }

    # Remove Chocolatey env vars
    foreach ($var in "ChocolateyInstall", "ChocolateyToolsLocation", "ChocolateyLastPathUpdate") {
        [Environment]::SetEnvironmentVariable($var, $null, "Machine")
        [Environment]::SetEnvironmentVariable($var, $null, "User")
    }

    # Clean PATH entries
    foreach ($scope in @("User", "Machine")) {
        try {
            $pathVar = [Environment]::GetEnvironmentVariable("Path", $scope)
            if ($pathVar) {
                $newPath = ($pathVar -split ';' | Where-Object {
                    ($_ -notmatch "chocolatey")
                }) -join ';'
                [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
            }
        } catch {
            Write-Log "Failed to clean PATH for ${scope}: $($_.Exception.Message)"
        }
    }
} else {
    Write-Log "Chocolatey not found."
}

Write-Log "Uninstall process complete. You may need to restart your shell or log off/on."