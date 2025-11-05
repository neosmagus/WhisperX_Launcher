import os
import subprocess
from tkinter import messagebox

# Path to the diarization script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DIAR_SCRIPT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', 'whisperx_diarization.py'))

def preflight_diarization_check(hf_token, instructions_widget=None, log_file=None):
    """
    Runs the diarization pre-flight check script with --check-only.
    Updates the instructions widget if provided.
    Returns True if diarization is ready or user chooses to continue without it.
    Returns False if user cancels.
    """
    if not os.path.exists(DIAR_SCRIPT):
        _update_instructions(instructions_widget, "Diarization check skipped - script not found.", is_error=True)
        return True

    cmd = [os.sys.executable, DIAR_SCRIPT, "--check-only"]
    if hf_token:
        cmd.insert(2, hf_token)

    _append_log(f"Running diarization pre-check...\nCommand: {' '.join(cmd)}\n", log_file)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        _append_log(result.stdout, log_file)
        _append_log(result.stderr, log_file)

        code = result.returncode
        if code == 0:
            _update_instructions(instructions_widget, "Diarization model ready.", is_error=False)
            return True
        elif code == 60:
            msg = "Diarization skipped - no Hugging Face token provided."
            _update_instructions(instructions_widget, msg, is_error=True)
            return messagebox.askyesno("Diarization Skipped", msg + "\nContinue without diarization?")
        elif code == 61:
            msg = ("Diarization model access denied.\n"
                   "Accept the model terms at:\n"
                   "https://huggingface.co/pyannote/speaker-diarization-3.1")
            _update_instructions(instructions_widget, msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        elif code == 62:
            msg = "Diarization model download failed.\nCheck network connectivity and Hugging Face token validity."
            _update_instructions(instructions_widget, msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        elif code == 63:
            msg = "Diarization dummy run failed.\nCheck Pyannote dependencies and ensure audio backend works."
            _update_instructions(instructions_widget, msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        else:
            _update_instructions(instructions_widget, f"Unexpected diarization check exit code: {code}", is_error=True)
            return True
    except Exception as e:
        _append_log(f"[ERROR] Diarization pre-check failed: {e}\n", log_file)
        return True


def _update_instructions(widget, message, is_error=False):
    """
    Update the diarization instructions/status box dynamically.
    """
    if widget is None:
        return
    widget.config(state="normal")
    widget.delete("1.0", "end")
    widget.insert("1.0", message)
    if is_error:
        widget.tag_configure("error", foreground="red")
        widget.tag_add("error", "1.0", "end")
    else:
        widget.tag_configure("ok", foreground="green")
        widget.tag_add("ok", "1.0", "end")
    widget.config(state="disabled")


def _append_log(message, log_file=None):
    """
    Append a message to the log file if provided.
    """
    if log_file:
        try:
            with open(log_file, "a", encoding="utf-8") as lf:
                lf.write(message)
                if not message.endswith("\n"):
                    lf.write("\n")
        except Exception:
            pass