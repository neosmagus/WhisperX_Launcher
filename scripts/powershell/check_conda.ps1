param(
    [switch]$Json
)

# --- Prefer pwsh, fallback to Windows PowerShell ---
if ($PSVersionTable.PSEdition -ne 'Core') {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Write-Host "[INFO] Restarting script in PowerShell Core (pwsh)..." -ForegroundColor Cyan
        & $pwsh.Path @args
        exit $LASTEXITCODE
    }
}

try {
    $ErrorActionPreference = 'Stop'

    Write-Host "=== Conda Installation Check (Miniconda / Anaconda) ===" -ForegroundColor Cyan

    # --- Common install locations ---
    $minicondaLocations = @(
        "$env:USERPROFILE\Miniconda3",
        "$env:LOCALAPPDATA\Miniconda3",
        "$env:ALLUSERSPROFILE\Miniconda3",
        "C:\ProgramData\Miniconda3",
        "C:\Miniconda3"
    )

    $anacondaLocations = @(
        "$env:USERPROFILE\Anaconda3",
        "$env:LOCALAPPDATA\Anaconda3",
        "$env:ALLUSERSPROFILE\Anaconda3",
        "C:\ProgramData\Anaconda3",
        "C:\Anaconda3"
    )

    $results = @()
    $foundValid = $false

    function Test-CondaInstall($loc, $label) {
        $status = "$label Not found"
        $color = "DarkGray"
        $valid = $false

        if (Test-Path $loc) {
            $condaExe = Join-Path $loc "Scripts\conda.exe"
            $condaBat = Join-Path $loc "condabin\conda.bat"
            if ((Test-Path $condaExe) -or (Test-Path $condaBat)) {
                $status = "$label Installed"
                $color = "Green"
                $valid = $true
            } else {
                $status = "$label Partial (folder exists, conda not found)"
                $color = "Yellow"
            }
        }

        Write-Host ("{0,-50} {1}" -f $loc, $status) -ForegroundColor $color
        $results += [PSCustomObject]@{ Path = $loc; Status = $status }

        return $valid
    }

    # --- Check Miniconda ---
    foreach ($loc in $minicondaLocations) {
        if (Test-CondaInstall $loc "Miniconda") { $foundValid = $true }
    }

    # --- Check Anaconda ---
    foreach ($loc in $anacondaLocations) {
        if (Test-CondaInstall $loc "Anaconda") { $foundValid = $true }
    }

    # --- PATH variable check ---
    Write-Host "`n=== PATH Variable Check ===" -ForegroundColor Cyan
    foreach ($scope in @("User", "Machine")) {
        $pathValue = [Environment]::GetEnvironmentVariable("Path", $scope)
        $pathMatches = $pathValue -split ';' | Where-Object { $_ -match "(?i)(Miniconda3|Anaconda3)" }
        if ($pathMatches) {
            Write-Host "$scope PATH contains Conda reference(s):" -ForegroundColor Yellow
            foreach ($m in $pathMatches) { Write-Host "  $m" -ForegroundColor Yellow }
        } else {
            Write-Host "$scope PATH has no Miniconda/Anaconda reference" -ForegroundColor DarkGray
        }
    }

    # --- Summary / Exit code ---
    if (-not $foundValid) {
        Write-Host "`nNo valid Miniconda/Anaconda installation detected." -ForegroundColor Red
    } else {
        Write-Host "`nAt least one valid Miniconda/Anaconda installation detected." -ForegroundColor Green
    }

    if ($Json) {
        $results | ConvertTo-Json -Depth 2
    }

    if ($foundValid) { exit 0 } else { exit 1 }

} catch {
    Write-Host "[ERROR] Check failed: $_" -ForegroundColor Red
    exit 2
}
