param(
    [string]$ConfigDir,
    [switch]$Debug
)

# --- Context for logging ---
$global:ScriptContext = "run"

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

try {
    $ErrorActionPreference = 'Stop'

    # --- Load config safely ---
    $cfg = if ($ConfigDir) { Get-Config $ConfigDir } else { @{} }

    Write-Log "Launching WhisperX GUI..."

    # --- Write merged config to a temporary file ---
    $tempConfigPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfigPath -Encoding UTF8
    Write-Log "Wrote merged config to $tempConfigPath"

    # --- Locate Python in the whisperx environment ---
    $envPath = Join-Path $PSScriptRoot "..\envs\whisperx"
    $pythonExe = Join-Path $envPath "python.exe"

    if (-not (Test-Path $pythonExe)) {
        Write-Log "Python executable not found in WhisperX environment." "ERROR"
        exit 51   # GUI launch failed (refined exit code map)
    }

    # --- Launch the GUI with the merged config ---
    $cmd = @($pythonExe, (Join-Path $PSScriptRoot "..\gui\whisperx_gui.py"), "--config", $tempConfigPath)

    if (-not (Invoke-WithRetry -Command $cmd `
                -MaxRetries ($cfg.RetryCount ? $cfg.RetryCount : 1) `
                -BackoffSeconds ($cfg.BackoffSeconds ? $cfg.BackoffSeconds : 2) `
                -Description "Running WhisperX GUI")) {
        Write-Log "WhisperX GUI failed to launch." "ERROR"
        exit 51   # GUI launch/runtime failed
    } else {
        Write-Log "WhisperX GUI closed successfully." "OK"
    }

    # --- Cleanup temp config ---
    if (Test-Path $tempConfigPath) {
        Remove-Item $tempConfigPath -Force
        Write-Log "Cleaned up temporary config file."
    }

    # --- Emit machine-readable summary ---
    $summaryLine = "SUMMARY=" +
    "RunComplete=True;" +
    "ConfigPath=$tempConfigPath"
    Write-Output $summaryLine

    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }

    exit 0
} catch {
    Write-Log "Run failed: $_" "ERROR"
    if ($Debug) {
        Write-Log "Debug mode active - press any key to close..."
        Pause
    }
    exit 51   # GUI launch/runtime failed
}


