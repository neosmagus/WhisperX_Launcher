# whisperx_uninstall_tasks.ps1
# Task functions for WhisperX uninstallation

function Test-CondaEnvironment($cfg) {
    $envName = if ($cfg.EnvName) { $cfg.EnvName } else { "whisperx" }
    $envRoot = if ($cfg.EnvPath) { $cfg.EnvPath } else { (Join-Path $PSScriptRoot "..\envs") }
    $envPath = Join-Path $envRoot $envName
    $global:EnvPath = $envPath
    $global:EnvExists = $false

    if (Get-Command conda -ErrorAction SilentlyContinue) {
        try {
            $envList = conda env list --json | ConvertFrom-Json
            if ($envList.envs -contains $envPath) {
                $global:EnvExists = $true
                Write-Log "Conda environment $envName found at $envPath"
            } else {
                Write-Log "Conda environment $envName not found." "INFO"
            }
        } catch {
            Write-Log "Failed to query Conda environments: $_" "WARN"
        }
    } elseif (Test-Path $envPath) {
        $global:EnvExists = $true
        Write-Log "Environment folder exists at $envPath"
    }
}

function Remove-CondaEnvironment($cfg) {
    if ($global:EnvExists -and (Get-Command conda -ErrorAction SilentlyContinue)) {
        if (-not (Invoke-WithRetry -Command @("conda", "env", "remove", "-n", $cfg.EnvName, "-y") `
                    -MaxRetries ($cfg.RetryCount ? $cfg.RetryCount : 3) `
                    -BackoffSeconds ($cfg.BackoffSeconds ? $cfg.BackoffSeconds : 5) `
                    -Description "Remove Conda environment ($($cfg.EnvName))")) {
            Write-Log "Could not remove Conda environment $($cfg.EnvName). Skipping." "WARN"
        } else {
            $Summary.CondaEnvRemoved = $true
        }
    }
}

function Remove-EnvironmentFolder() {
    if ($global:EnvExists -and (Test-Path $global:EnvPath)) {
        try {
            Remove-Item -Recurse -Force $global:EnvPath
            Write-Log "Manually removed environment folder at $global:EnvPath" "OK"
            $Summary.CondaEnvRemoved = $true
        } catch {
            Write-Log "Failed to manually remove environment folder: $_" "WARN"
        }
    }
}

function Remove-Shortcut() {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath "WhisperX.lnk"
    if (Test-Path $shortcutPath) {
        try {
            Remove-Item $shortcutPath -Force
            Write-Log "Removed desktop shortcut at $shortcutPath" "OK"
            $Summary.ShortcutRemoved = $true
        } catch {
            Write-Log "Failed to remove desktop shortcut: $_" "WARN"
        }
    } else {
        Write-Log "No desktop shortcut found." "INFO"
    }
}

function Remove-Miniconda($cfg) {
    if ($cfg.InstallConda) {
        $minicondaUser = Join-Path $env:USERPROFILE "Miniconda3"
        if (Test-Path $minicondaUser) {
            if (Get-Prompt-Response "Remove default Miniconda at '$minicondaUser'?") {
                try {
                    Remove-Item -Recurse -Force $minicondaUser
                    Write-Log "Removed Miniconda folder at $minicondaUser" "OK"
                    $Summary.MinicondaRemoved = $true
                } catch {
                    Write-Log "Failed to remove Miniconda folder: $_" "WARN"
                }
            } else {
                Write-Log "User chose not to remove Miniconda at $minicondaUser" "INFO"
            }
        } else {
            Write-Log "No Miniconda installation found at $minicondaUser." "INFO"
        }
    } else {
        Write-Log "Config does not request Miniconda removal." "INFO"
    }
}

function Cleanup-CondaInstalls($Cleanup) {
    if ($Cleanup) {
        while ($true) {
            $condaCmd = Get-Command conda -ErrorAction SilentlyContinue
            if (-not $condaCmd) { break }
            $exePath = $condaCmd.Source
            $condaRoot = (Get-Item $exePath).Directory.Parent.FullName
            Write-Log "Detected extra conda installation at $condaRoot" "WARN"
            if (Get-Prompt-Response "Remove additional conda installation at '$condaRoot'?") {
                try {
                    Remove-Item -Recurse -Force $condaRoot
                    Write-Log "Removed conda installation at $condaRoot" "OK"
                    $Summary.ExtraInstalls += $condaRoot
                } catch {
                    Write-Log "Failed to remove conda installation at ${condaRoot}: $_" "WARN"
                }
            } else {
                Write-Log "User chose not to remove extra conda installation at $condaRoot" "INFO"
            }
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
        }
    } else {
        Write-Log "Skipping removal of extra conda installs." "INFO"
    }
}

function Test-UninstallVerification($cfg) {
    $envPath = $global:EnvPath
    $pythonExe = Join-Path $envPath "python.exe"
    $pipExe = Join-Path $envPath "Scripts\pip.exe"

    Write-Log "Performing final verification..."

    if (-not (Test-Path $envPath) -and -not (Test-Path $pythonExe) -and -not (Test-Path $pipExe)) {
        Write-Log "Environment $($cfg.EnvName) successfully removed." "OK"
        $Summary.VerifiedRemoved = $true
    } else {
        Write-Log "Environment $($cfg.EnvName) still present. Manual cleanup may be required." "WARN"
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Log "WARNING: 'conda' is still available after uninstall." "WARN"
        $Summary.RemainingConda = $true
    } else {
        Write-Log "Verified: 'conda' no longer found on PATH." "OK"
    }
}
