# whisperx_shared.ps1
# Common functions for WhisperX scripts

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    # Guard against missing config
    $logDir = if ($null -ne $cfg -and $cfg.LogPath) { $cfg.LogPath } else { Join-Path $PSScriptRoot "..\logs" }
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

    $stamp = Get-Date -Format "yyyyMMdd"
    $logFile = Join-Path $logDir "$global:ScriptContext-$stamp.log"

    Add-Content -Path $logFile -Value $line

    # Optional: echo to console in debug mode
    if ($Debug) { Write-Host $line }
}

function Add-LogOutput {
    param(
        [string]$Stdout,
        [string]$Stderr,
        [string]$Description
    )

    if ($Stdout) {
        foreach ($line in $Stdout -split "`r?`n") {
            if ($line.Trim()) {
                Write-Log "[$Description][OUT] $line"
                if ($Debug) { Write-Host "[$Description][OUT] $line" -ForegroundColor Gray }
            }
        }
    }
    if ($Stderr) {
        foreach ($line in $Stderr -split "`r?`n") {
            if ($line.Trim()) {
                Write-Log "[$Description][ERR] $line" "WARN"
                if ($Debug) { Write-Host "[$Description][ERR] $line" -ForegroundColor Yellow }
            }
        }
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Command,
        [string]$Description = "",
        [int]$MaxRetries = 3,
        [int]$BackoffSeconds = 5,
        [int]$TimeoutSeconds = 1800,
        [int]$InactivitySeconds = 600,
        [switch]$NoProgressDuringRun  # optional: temporarily suppress Write-Progress
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Log "[$Description] Attempt $attempt of $MaxRetries..."

        $oldProgressPref = $Global:ProgressPreference
        if ($NoProgressDuringRun) { $Global:ProgressPreference = 'SilentlyContinue' }

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Command[0]
            $psi.Arguments = ($Command[1..($Command.Length - 1)] -join " ")
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardInput = $true   # allow us to close stdin
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            # Close stdin to prevent child from waiting on input
            try { $proc.StandardInput.Close() } catch {}

            $startTime = Get-Date
            $lastOutput = Get-Date

            while (-not $proc.HasExited) {
                while ($proc.StandardOutput.Peek() -ne -1) {
                    $lineOut = $proc.StandardOutput.ReadLine()
                    if ($lineOut) {
                        $lastOutput = Get-Date
                        Write-Log "[$Description][OUT] $lineOut" "INFO"
                        if ($Debug) { Write-Host "[DEBUG][OUT] $lineOut" -ForegroundColor Yellow }
                    }
                }
                while ($proc.StandardError.Peek() -ne -1) {
                    $lineErr = $proc.StandardError.ReadLine()
                    if ($lineErr) {
                        $lastOutput = Get-Date
                        Write-Log "[$Description][ERR] $lineErr" "WARN"
                        if ($Debug) { Write-Host "[DEBUG][ERR] $lineErr" -ForegroundColor Red }
                    }
                }

                $idle = (Get-Date) - $lastOutput
                if ($idle.TotalSeconds -ge $InactivitySeconds) {
                    Write-Log "[$Description] No output for $InactivitySeconds seconds — killing process." "ERROR"
                    try { $proc.Kill() } catch {}
                    break
                }

                $elapsed = (Get-Date) - $startTime
                if ($elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    Write-Log "[$Description] Timed out after $TimeoutSeconds seconds — killing process." "ERROR"
                    try { $proc.Kill() } catch {}
                    break
                }

                Start-Sleep -Milliseconds 200
            }

            $proc.WaitForExit(5000) | Out-Null

            if ($proc.ExitCode -eq 0) {
                if ($NoProgressDuringRun) { $Global:ProgressPreference = $oldProgressPref }
                return $true
            } else {
                Write-Log "[$Description] failed with exit code $($proc.ExitCode)" "WARN"
            }
        } catch {
            Write-Log "[$Description] exception: $_" "ERROR"
        } finally {
            if ($NoProgressDuringRun) { $Global:ProgressPreference = $oldProgressPref }
        }

        if ($attempt -lt $MaxRetries) {
            Start-Sleep -Seconds $BackoffSeconds
        }
    }

    return $false
}

function Get-Config {
    param([string]$ConfigDir)

    $baseConfigPath = Join-Path $ConfigDir "config.json"
    $localConfigPath = Join-Path $ConfigDir "config.local.json"

    if (-not (Test-Path $baseConfigPath)) {
        Write-Host "[ERROR] Base config not found: $baseConfigPath" -ForegroundColor Red
        exit 2
    }

    try {
        $cfg = Get-Content $baseConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "[ERROR] Failed to parse base config: $_" -ForegroundColor Red
        exit 2
    }

    if (Test-Path $localConfigPath) {
        Write-Log "Applying local overrides from $localConfigPath"
        try {
            $localCfg = Get-Content $localConfigPath -Raw | ConvertFrom-Json
            foreach ($prop in $localCfg.PSObject.Properties) {
                if ($null -ne $prop.Value -and $prop.Value -ne "") {
                    $cfg | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
        } catch {
            Write-Host "[WARN] Failed to parse local overrides: $_" -ForegroundColor Yellow
        }
    }

    return $cfg
}

function Get-Prompt-Response($message) {
    $response = Read-Host "$message (y/N)"
    return $response -match '^[Yy]$'
}
