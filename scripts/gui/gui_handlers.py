import threading
import subprocess, os, sys
from tkinter import messagebox
from lib.diarization_utils import preflight_diarization_check
from lib.transcript_utils import format_json_transcript
from lib.log_utils import append_log

def setup_handlers(root, widgets, cfg, log_file):
    def run_transcription():
        threading.Thread(target=run_transcription_thread, daemon=True).start()

    def run_transcription_thread():
        file_path = widgets['entry_file'].get().strip()
        model = widgets['model_var'].get()
        output_format = widgets['format_var'].get()
        hf_token = widgets['entry_token'].get().strip()
        output_dir = widgets['entry_output_dir'].get().strip()

        if not file_path or not os.path.exists(file_path):
            messagebox.showerror("Error", "Please select a valid file.")
            return

        if not preflight_diarization_check(hf_token, widgets['txt_instructions'], log_file):
            append_log("Transcription cancelled after diarization check.\n", widgets['log_box'], log_file)
            return

        cmd = [
            sys.executable, "-m", "whisperx",
            file_path,
            "--model", model,
            "--output_format", output_format,
            "--output_dir", output_dir if output_dir else os.path.dirname(file_path)
        ]
        if hf_token:
            cmd.extend(["--hf_token", hf_token])
            cmd.append("--diarize")

        append_log(f"Starting transcription...\nCommand: {' '.join(cmd)}\n\n", widgets['log_box'], log_file)
        widgets['btn_transcribe'].config(state="disabled")

        try:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                append_log(line, widgets['log_box'], log_file)
            process.wait()

            if process.returncode == 0:
                msg = f"Transcription complete."
                append_log(msg + "\n", widgets['log_box'], log_file)
                messagebox.showinfo("Done", msg)
            else:
                append_log(f"WhisperX failed with exit code {process.returncode}\n", widgets['log_box'], log_file)
                messagebox.showerror("Error", "WhisperX failed. See log for details.")
        finally:
            widgets['btn_transcribe'].config(state="normal")

    widgets['btn_transcribe'].config(command=run_transcription)