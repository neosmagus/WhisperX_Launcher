# Unified exit codes for WhisperX installer/launcher/uninstaller

$ExitCodes = @{
    # --- General ---
    0  = "Success"
    1  = "Generic/unhandled error"

    # --- Wrapper-level (batch) ---
    2  = "Script not found"
    3  = "Config not found"

    # --- Conda / Miniconda ---
    10 = "Conda missing (enable InstallConda or install manually)"
    11 = "Miniconda install/removal failed"

    # --- Environment ---
    20 = "Environment creation/removal failed"

    # --- Install failures ---
    30 = "PyTorch install failed"
    31 = "WhisperX install failed"
    40 = "ffmpeg-python install failed"

    # --- Verification / GUI ---
    50 = "Environment verification failed (core packages not importable)"
    51 = "GUI launch or runtime failed"

    # --- Hugging Face / diarization ---
    60 = "No Hugging Face token provided"
    61 = "Diarization model access denied (accept model terms on Hugging Face)"
    62 = "Diarization model download failed (check network/token)"
    63 = "Diarization dummy run failed (check Pyannote dependencies/audio backend)"
}

function Get-ExitMessage {
    param([int]$Code)
    if ($ExitCodes.ContainsKey($Code)) {
        return $ExitCodes[$Code]
    } else {
        return "Unknown exit code: $Code"
    }
}
