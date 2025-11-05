"""
exit_codes.py
Central definition of WhisperX toolchain exit codes and their meanings.
"""

EXIT_CODES = {
    # General success
    0:  "Success",

    # Launcher / install errors
    10: "Conda missing (enable InstallConda or install manually)",
    11: "Miniconda install failed",
    20: "Environment creation failed",
    30: "PyTorch install failed",
    31: "WhisperX install failed",
    40: "ffmpeg setup failed",
    50: "GUI launch failed",

    # Diarization-specific errors
    60: "No Hugging Face token provided",
    61: "Diarization model access denied (accept model terms on Hugging Face)",
    62: "Diarization model download failed (check network/token)",
    63: "Diarization dummy run failed (check Pyannote dependencies/audio backend)"
}

def get_exit_message(code):
    """
    Return the human-readable message for a given exit code.
    If the code is unknown, return a generic message.
    """
    return EXIT_CODES.get(code, f"Unknown exit code: {code}")