#!/usr/bin/env python
"""
whisperx_diarization.py
Runs a diarization readiness check or a full dummy diarization run.
Exit codes are defined in lib/exit_codes.py.
"""

import sys
import argparse
from lib.config_utils import load_config
from lib.log_utils import init_log_file, append_log
from lib.diarization_utils import preflight_diarization_check
from lib.exit_codes import get_exit_message

def main():
    parser = argparse.ArgumentParser(description="WhisperX diarization setup/check")
    parser.add_argument("hf_token", nargs="?", help="Hugging Face token")
    parser.add_argument("--check-only", action="store_true", help="Only check model/token readiness")
    args = parser.parse_args()

    # Load config
    cfg = load_config()

    # Init log file
    log_file = init_log_file(cfg, prefix="diarization_log")

    # Use token from CLI if provided, else from config
    hf_token = args.hf_token or cfg.get("HuggingFaceToken", "").strip()

    append_log("=== WhisperX Diarization Script ===\n", log_file)
    append_log(f"Mode: {'Check-only' if args.check_only else 'Full dummy run'}", log_file)

    # Run preflight check
    ready = preflight_diarization_check(
        hf_token=hf_token,
        instructions_widget=None,  # Not using GUI here
        log_file=log_file
    )

    # In CLI mode, preflight_diarization_check() returns True/False, not exit codes
    # So we map True to 0, False to 60 (no token) unless we want to expand
    if ready:
        append_log("Diarization check passed.", log_file)
        sys.exit(0)
    else:
        # If no token, use 60; otherwise generic failure
        code = 60 if not hf_token else 63
        append_log(f"Diarization check failed: {get_exit_message(code)}", log_file)
        sys.exit(code)

if __name__ == "__main__":
    main()