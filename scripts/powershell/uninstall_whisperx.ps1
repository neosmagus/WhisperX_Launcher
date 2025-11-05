param(
    [string]$ConfigDir,
    [switch]$Cleanup,
    [switch]$Debug
)

# --- Context for logging ---
$global:ScriptContext = "uninstall"

# --- Prefer pwsh, fallback to powershell ---
if ($PSVersionTable.PSEdition -ne 'Core') {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        Write-Host "[INFO] Restarting script in PowerShell Core (pwsh)..." -ForegroundColor Cyan
        & $pwsh.Path @args
        exit $LASTEXITCODE
    }
}

. "$PSScriptRoot\exit_codes.ps1"
. "$PSScriptRoot\whisperx_shared.ps1"

function Remove-FromPath {
    param([string]$PathToRemove, [switch]$System)
    try {
        $regPath = if ($System) { "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" } else { "HKCU:\Environment" }
        $currentPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction SilentlyContinue).Path
        if ($currentPath -and $currentPath -like "*$PathToRemove*") {
            $newPath = ($currentPath -split ';' | Where-Object { $_ -and ($_ -ne $PathToRemove) -and ($_ -notlike "$PathToRemove\*") }) -join ';'
            Set-ItemProperty -Path $regPath -Name Path -Value $newPath
            Write-Log "Removed '$PathToRemove' from PATH ($($System ? 'System' : 'User'))."
        }
    } catch {
        Write-Log ("Failed to update PATH for {0}: {1}" -f $PathToRemove, $_) "WARN"
    }
}

$ErrorActionPreference = 'Stop'

# --- Tracking summary ---
$Summary = @{
    CondaEnvRemoved  = $false
    ShortcutRemoved  = $false
    MinicondaRemoved = $false
    ExtraInstalls    = @()
    RemainingConda   = $false
    InstallPolicy    = "Unknown"
}

try {
    Write-Log "Starting WhisperX uninstall..."

    # --- Load config safely ---
    $cfg = if ($ConfigDir) { Get-Config $ConfigDir } else { @{} }

    # --- Resolve environment path from config ---
    $envName = if ($cfg.EnvName) { $cfg.EnvName } else { "whisperx" }
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $envName

    # --- Remove Conda environment if possible ---
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        if (-not (Invoke-WithRetry -Command @("conda", "env", "remove", "-n", $envName, "-y") `
                    -MaxRetries ($cfg.RetryCount ? $cfg.RetryCount : 3) `
                    -BackoffSeconds ($cfg.BackoffSeconds ? $cfg.BackoffSeconds : 5) `
                    -Description "Remove Conda environment ($envName)")) {
            Write-Log "Failed to remove Conda environment $envName" "WARN"
            exit 20
        } else {
            $Summary.CondaEnvRemoved = $true
        }
    } elseif (Test-Path $envPath) {
        Write-Log "Conda not found, but environment folder exists at $envPath" "WARN"
        try {
            Remove-Item -Recurse -Force $envPath
            Write-Log "Manually removed environment folder at $envPath" "OK"
            $Summary.CondaEnvRemoved = $true
        } catch {
            Write-Log "Failed to manually remove environment folder: $_" "ERROR"
            exit 20
        }
    } else {
        if ($cfg.InstallConda) {
            Write-Log "Conda missing but InstallConda=true and no env folder found" "ERROR"
            exit 10
        } else {
            Write-Log "No Conda and no environment folder found — skipping environment removal." "INFO"
        }
    }

    # --- Remove desktop shortcut ---
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath "WhisperX.lnk"
    if (Test-Path $shortcutPath) {
        Remove-Item $shortcutPath -Force
        Write-Log "Removed desktop shortcut at $shortcutPath"
        $Summary.ShortcutRemoved = $true
        Write-Output "SHORTCUT_REMOVED=$shortcutPath"
    }

    # --- Reverse ToS acceptance if set ---
    if ($cfg.AcceptAnacondaTOS -and (Get-Command conda -ErrorAction SilentlyContinue)) {
        Write-Log "Reversing Anaconda Terms of Service acceptance..."
        Invoke-WithRetry -Command @("conda", "tos", "reject", "--channel", "https://repo.anaconda.com/pkgs/main") -Description "Reject TOS main"
        Invoke-WithRetry -Command @("conda", "tos", "reject", "--channel", "https://repo.anaconda.com/pkgs/r") -Description "Reject TOS r"
        Invoke-WithRetry -Command @("conda", "tos", "reject", "--channel", "https://repo.anaconda.com/pkgs/msys2") -Description "Reject TOS msys2"
        $Summary.InstallPolicy = "AnacondaTOSRejected"
    }

    # --- Remove default per-user Miniconda if config says so ---
    if ($cfg.InstallConda) {
        $minicondaUser = "$env:USERPROFILE\Miniconda3"
        if (Test-Path $minicondaUser) {
            if (Get-Prompt-Response "Remove default Miniconda at $minicondaUser?") {
                try {
                    Remove-Item -Recurse -Force $minicondaUser
                    Write-Log "Removed Miniconda folder at $minicondaUser" "OK"
                    $Summary.MinicondaRemoved = $true
                } catch {
                    Write-Log ("Failed to remove Miniconda folder at {0}: {1}" -f $minicondaUser, $_) "ERROR"
                    exit 11
                }
                Remove-FromPath $minicondaUser -System:$false
                Remove-FromPath (Join-Path $minicondaUser "Scripts") -System:$false
                Remove-FromPath (Join-Path $minicondaUser "condabin") -System:$false
                Remove-FromPath (Join-Path $minicondaUser "Library\bin") -System:$false
            } else {
                Write-Log "User chose not to remove Miniconda at $minicondaUser" "INFO"
            }
        }
    }

    # --- Remove additional conda installs only if -Cleanup is passed ---
    if ($Cleanup) {
        while ($true) {
            $condaCmd = Get-Command conda -ErrorAction SilentlyContinue
            if (-not $condaCmd) { break }

            $exePath = $condaCmd.Source
            $condaRoot = (Get-Item $exePath).Directory.Parent.FullName
            Write-Log "Detected extra conda installation at $condaRoot" "WARN"

            if (Get-Prompt-Response "Remove additional conda installation at $condaRoot?") {
                try {
                    Remove-Item -Recurse -Force $condaRoot
                    Write-Log "Removed conda installation at $condaRoot" "OK"
                    $Summary.ExtraInstalls += $condaRoot
                } catch {
                    Write-Log ("Failed to remove conda installation at {0}: {1}" -f $condaRoot, $_) "WARN"
                }

                Remove-FromPath $condaRoot -System:$false
                Remove-FromPath (Join-Path $condaRoot "Scripts") -System:$false
                Remove-FromPath (Join-Path $condaRoot "condabin") -System:$false
                Remove-FromPath (Join-Path $condaRoot "Library\bin") -System:$false
            } else {
                Write-Log "User chose not to remove extra conda installation at $condaRoot" "INFO"
            }

            # Refresh PATH so next Get-Command conda finds the next install (if any)
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
        }
    } else {
        Write-Log "Skipping removal of extra conda installs (use -Cleanup to remove all)." "INFO"
    }

    # --- Refresh PATH ---
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Final verification ---
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Log "WARNING: 'conda' is still available after uninstall. Manual cleanup may be required." "WARN"
        $Summary.RemainingConda = $true
    } else {
        Write-Log "Verified: 'conda' no longer found on PATH." "OK"
    }

    # --- Summary Report (console) ---
    Write-Host "`n========== UNINSTALL SUMMARY ==========" -ForegroundColor Cyan
    Write-Host ("Conda environment removed: {0}" -f ($Summary.CondaEnvRemoved ? "Yes" : "No"))
    Write-Host ("Desktop shortcut removed: {0}" -f ($Summary.ShortcutRemoved ? "Yes" : "No"))
    Write-Host ("Default Miniconda removed: {0}" -f ($Summary.MinicondaRemoved ? "Yes" : "No"))
    if ($Summary.ExtraInstalls.Count -gt 0) {
        Write-Host "Extra conda installs removed:" -ForegroundColor Green
        $Summary.ExtraInstalls | ForEach-Object { Write-Host " - $_" }
    }
    Write-Host ("Install policy: {0}" -f $Summary.InstallPolicy)
    if ($Summary.RemainingConda) {
        Write-Host "WARNING: Conda is still available on PATH after uninstall." -ForegroundColor Yellow
    } else {
        Write-Host "No conda installations remain on PATH." -ForegroundColor Green
    }
    Write-Host "=======================================" -ForegroundColor Cyan

    Write-Log "Uninstall complete." "OK"

    # --- Emit machine-readable summary for batch wrapper ---
    $summaryLine = "SUMMARY=" +
    "CondaEnvRemoved=$($Summary.CondaEnvRemoved);" +
    "ShortcutRemoved=$($Summary.ShortcutRemoved);" +
    "MinicondaRemoved=$($Summary.MinicondaRemoved);" +
    "ExtraInstalls=$([string]::Join(',', $Summary.ExtraInstalls));" +
    "RemainingConda=$($Summary.RemainingConda);" +
    "InstallPolicy=$($Summary.InstallPolicy)"
    Write-Output $summaryLine

    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }

    exit 0
} catch {
    Write-Log "Uninstall failed: $_" "ERROR"
    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }
    exit 1
}
