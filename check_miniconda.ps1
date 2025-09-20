$ErrorActionPreference = 'Stop'

Write-Host "=== Miniconda Installation Check ===" -ForegroundColor Cyan

# Common Miniconda install locations
$locations = @(
    "$env:USERPROFILE\Miniconda3",         # Single-user default
    "$env:LOCALAPPDATA\Miniconda3",        # Single-user local app data
    "$env:ALLUSERSPROFILE\Miniconda3",     # System-wide (all users)
    "C:\ProgramData\Miniconda3",           # Alternate system-wide
    "C:\Miniconda3"                         # Legacy/manual installs
)

# Track results
$results = @()

foreach ($loc in $locations) {
    if (Test-Path $loc) {
        $condaExe = Join-Path $loc "Scripts\conda.exe"
        if (Test-Path $condaExe) {
            $status = "Installed"
            $color = "Green"
        } else {
            $status = "Partial (folder exists, conda.exe missing)"
            $color = "Yellow"
        }
    } else {
        $status = "Not found"
        $color = "DarkGray"
    }

    Write-Host ("{0,-50} {1}" -f $loc, $status) -ForegroundColor $color
    $results += [PSCustomObject]@{
        Path   = $loc
        Status = $status
    }
}

# Check PATH environment variables for Miniconda references
Write-Host "`n=== PATH Variable Check ===" -ForegroundColor Cyan
$pathVars = @(
    [Environment]::GetEnvironmentVariable("Path", "User"),
    [Environment]::GetEnvironmentVariable("Path", "Machine")
)

$foundInPath = $false
foreach ($scope in @("User", "Machine")) {
    $pathValue = [Environment]::GetEnvironmentVariable("Path", $scope)
    if ($pathValue -match "Miniconda3") {
        Write-Host "$scope PATH contains Miniconda reference" -ForegroundColor Yellow
        $foundInPath = $true
    } else {
        Write-Host "$scope PATH has no Miniconda reference" -ForegroundColor DarkGray
    }
}

if (-not $foundInPath) {
    Write-Host "No Miniconda references found in PATH." -ForegroundColor Green
}

Write-Host "`nCheck complete."