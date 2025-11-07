param(
    [string]$ConfigDir,
    [switch]$Cleanup,
    [switch]$Debug
)

$global:ScriptContext = "uninstall"

. "$PSScriptRoot\exit_codes.ps1"
. "$PSScriptRoot\whisperx_shared.ps1"
. "$PSScriptRoot\whisperx_uninstall_tasks.ps1"

$cfg = if ($ConfigDir) { Get-Config $ConfigDir } else { @{} }

Write-Log "Starting WhisperX uninstall..."

$Summary = @{
    CondaEnvRemoved  = $false
    ShortcutRemoved  = $false
    MinicondaRemoved = $false
    ExtraInstalls    = @()
    RemainingConda   = $false
    InstallPolicy    = "Unknown"
    VerifiedRemoved  = $false
}

$stages = @(
    @{ Name = "Check Conda Environment"; Action = { Test-CondaEnvironment $cfg } },
    @{ Name = "Run Conda Environment Removal"; Action = { Remove-CondaEnvironment $cfg; $Summary.CondaEnvRemoved = $true } },
    @{ Name = "Manual Folder Cleanup"; Action = { Remove-EnvironmentFolder } },
    @{ Name = "Remove Desktop Shortcut"; Action = { Remove-Shortcut; $Summary.ShortcutRemoved = $true } },
    @{ Name = "Remove Miniconda (optional)"; Action = { Remove-Miniconda $cfg; $Summary.MinicondaRemoved = $true } },
    @{ Name = "Cleanup Extra Conda Installs"; Action = { Remove-CondaInstalls $Cleanup } },
    @{ Name = "Final Verification"; Action = { Test-UninstallVerification $cfg; $Summary.VerifiedRemoved = $true } }
)

# --- Run stages with progress ---
for ($i = 0; $i -lt $stages.Count; $i++) {
    $pct = [int](($i / $stages.Count) * 100)
    Write-Progress -Activity "WhisperX Uninstallation" -Status $stages[$i].Name -PercentComplete $pct
    try {
        & $stages[$i].Action | Out-Null
    } catch {
        Write-Log "Stage '$($stages[$i].Name)' encountered an error: $_" "WARN"
    }
}
Write-Progress -Activity "WhisperX Uninstallation" -Completed
Write-Log "Uninstall complete." "OK"

# --- Human-readable summary ---
Write-Host "`n========== UNINSTALL SUMMARY ==========" -ForegroundColor Cyan
Write-Host ("Conda Environment Removed : {0}" -f $Summary.CondaEnvRemoved)
Write-Host ("Desktop Shortcut Removed  : {0}" -f $Summary.ShortcutRemoved)
Write-Host ("Default Miniconda Removed : {0}" -f $Summary.MinicondaRemoved)
if ($Summary.ExtraInstalls.Count -gt 0) {
    Write-Host "Extra Conda Installs Removed:" -ForegroundColor Green
    $Summary.ExtraInstalls | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "Extra Conda Installs Removed : None"
}
Write-Host ("Install Policy            : {0}" -f $Summary.InstallPolicy)
Write-Host ("Remaining Conda Present   : {0}" -f $Summary.RemainingConda)
Write-Host ("Verified Removed          : {0}" -f $Summary.VerifiedRemoved)
Write-Host "=======================================" -ForegroundColor Cyan

# --- Machine-readable summary for batch wrapper ---
$summaryLine = "SUMMARY=" +
"CondaEnvRemoved=$($Summary.CondaEnvRemoved);" +
"ShortcutRemoved=$($Summary.ShortcutRemoved);" +
"MinicondaRemoved=$($Summary.MinicondaRemoved);" +
"ExtraInstalls=$([string]::Join(',', $Summary.ExtraInstalls));" +
"RemainingConda=$($Summary.RemainingConda);" +
"InstallPolicy=$($Summary.InstallPolicy);" +
"VerifiedRemoved=$($Summary.VerifiedRemoved)"
Write-Output $summaryLine

# --- Exit code logic ---
if ($global:EnvExists -and -not $Summary.CondaEnvRemoved) {
    Write-Log "Environment removal failed." "ERROR"
    exit 20   # Environment creation/removal failed
}
if ($cfg.InstallConda -and (Test-Path (Join-Path $env:USERPROFILE "Miniconda3")) -and -not $Summary.MinicondaRemoved) {
    Write-Log "Miniconda removal failed." "ERROR"
    exit 11   # Miniconda install/removal failed
}
if (-not $Summary.VerifiedRemoved) {
    Write-Log "Final verification failed." "ERROR"
    exit 50   # Environment verification failed
}

# If we reach here, uninstall succeeded
exit 0
