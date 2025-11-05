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
            if ($line.Trim()) { Write-Log "[$Description][OUT] $line" }
        }
    }
    if ($Stderr) {
        foreach ($line in $Stderr -split "`r?`n") {
            if ($line.Trim()) { Write-Log "[$Description][ERR] $line" "WARN" }
        }
    }
}

function Invoke-WithRetry {
    param(
        [string[]]$Command,
        [int]$MaxRetries = 3,
        [int]$BackoffSeconds = 5,
        [int]$TimeoutSeconds = 600,   # default 10 minutes
        [string]$Description = "External command"
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Log "[$Description] Attempt $attempt of $MaxRetries..."

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Command[0]
        $psi.Arguments = ($Command[1..($Command.Length - 1)] -join " ")
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()

        if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
            # Completed within timeout
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            Add-LogOutput $stdout $stderr $Description

            if ($proc.ExitCode -eq 0) {
                Write-Log "[$Description] succeeded." "OK"
                return $true
            } else {
                Write-Log "[$Description] failed with exit code $($proc.ExitCode)" "WARN"
            }
        } else {
            # Timeout
            try { $proc.Kill() } catch {}
            Write-Log "[$Description] timed out after $TimeoutSeconds seconds." "ERROR"
        }

        Start-Sleep -Seconds $BackoffSeconds
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
