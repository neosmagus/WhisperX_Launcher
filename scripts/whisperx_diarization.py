import sys
import os
import json
import datetime
import tempfile
import soundfile as sf
import numpy as np
from pyannote.audio import Pipeline
import argparse

# --- Load config ---
CONFIG_PATH = os.path.join(os.path.dirname(__file__), '..', 'whisperx_config.json')
with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
    cfg = json.load(f)

# --- Resolve log directory ---
script_dir = os.path.dirname(os.path.abspath(__file__))
log_dir = os.path.abspath(os.path.join(script_dir, cfg.get("LogPath", "./logs")))
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, f"diarization_log_{datetime.datetime.now():%Y%m%d_%H%M%S}.txt")

def log(message, level="INFO", always=True):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [{level}] {message}"
    if always:
        print(line)
        with open(log_file, "a", encoding="utf-8") as lf:
            lf.write(line + "\n")

parser = argparse.ArgumentParser(description="WhisperX diarization setup/check")
parser.add_argument("hf_token", nargs="?", help="Hugging Face token")
parser.add_argument("--check-only", action="store_true", help="Only check model/token readiness, no diarization run")
args = parser.parse_args()

try:
    hf_token = args.hf_token

    if not hf_token:
        log("No Hugging Face token provided. Skipping diarization model download.", "WARN")
        sys.exit(60)

    log("Checking diarization model access...")

    try:
        pipeline = Pipeline.from_pretrained(
            'pyannote/speaker-diarization-3.1',
            token=hf_token
        )
    except Exception as e:
        msg = str(e)
        if any(k in msg.lower() for k in ["403", "401", "unauthorized", "forbidden", "not authorized", "access denied"]):
            log("Access denied - please accept the model terms at:", "ERROR")
            log("https://huggingface.co/pyannote/speaker-diarization-3.1", "ERROR")
            sys.exit(61)
        else:
            log(f"Error downloading diarization model: {msg}", "ERROR")
            sys.exit(62)

    if args.check_only:
        log("Diarization model accessible and cached check passed.", "OK")
        sys.exit(0)

    # Dummy run to force full cache
    dummy_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    try:
        sf.write(dummy_wav.name, np.zeros((16000,), dtype=np.float32), 16000)
        try:
            _ = pipeline(dummy_wav.name)
        except Exception as e:
            log(f"Error running dummy diarization: {e}", "ERROR")
            sys.exit(63)
        log("Diarization model cached successfully.", "OK")
    finally:
        try:
            os.unlink(dummy_wav.name)
        except OSError:
            pass

    sys.exit(0)

except SystemExit:
    raise
except Exception as e:
    log(f"Unhandled error in diarization script: {e}", "ERROR")
    sys.exit(1)