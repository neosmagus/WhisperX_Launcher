import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk
import subprocess
import os
import sys
import json
import argparse
import threading
import datetime

# --- Load config ---
CONFIG_PATH = os.path.join(os.path.dirname(__file__), '..', 'whisperx_config.json')
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
else:
    cfg = {}

# --- Resolve log directory ---
script_dir = os.path.dirname(os.path.abspath(__file__))
log_dir = os.path.abspath(os.path.join(script_dir, cfg.get("LogPath", "./logs")))
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, f"gui_log_{datetime.datetime.now():%Y%m%d_%H%M%S}.txt")

def append_log(message):
    with open(log_file, "a", encoding="utf-8") as lf:
        lf.write(message)
    log_box.configure(state="normal")
    log_box.insert(tk.END, message)
    log_box.configure(state="disabled")
    log_box.see(tk.END)

# --- Constants ---
WHISPER_MODELS = ["tiny", "base", "small", "medium", "large-v2"]
OUTPUT_FORMATS = ["txt", "json", "srt", "vtt"]

HF_INSTRUCTIONS = """\
To use diarization, you must:
1. Log into Hugging Face in your browser.
2. Accept the terms for these models:
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - https://huggingface.co/pyannote/embedding
3. Create a READ token at:
   https://huggingface.co/settings/tokens
4. Paste the token into the box below.
"""

# --- CLI arg parsing ---
parser = argparse.ArgumentParser(description="WhisperX GUI")
parser.add_argument("--default-model", type=str, help="Default Whisper model to pre-select")
parser.add_argument("--output-dir", type=str, help="Default output directory")
parser.add_argument("--hf-token", type=str, help="Default Hugging Face token")
args, unknown = parser.parse_known_args()

default_model_arg = args.default_model if args.default_model in WHISPER_MODELS else cfg.get("model", "large-v2")
default_output_dir_arg = args.output_dir if args.output_dir else cfg.get("output_dir", "")
default_hf_token_arg = args.hf_token if args.hf_token else os.environ.get("HUGGINGFACE_TOKEN", cfg.get("HuggingFaceToken", ""))

# --- GUI setup ---
root = tk.Tk()
root.title("WhisperX Transcription Tool")

# --- Settings persistence ---
def save_settings():
    cfg["model"] = model_var.get()
    cfg["output_dir"] = entry_output_dir.get().strip()
    cfg["HuggingFaceToken"] = entry_token.get().strip()
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2)
    messagebox.showinfo("Settings Saved", "Settings have been saved to config.")

def open_settings():
    settings_win = tk.Toplevel(root)
    settings_win.title("Settings")
    tk.Label(settings_win, text="Default Whisper Model:").grid(row=0, column=0, sticky="e", padx=5, pady=5)
    model_entry = ttk.Combobox(settings_win, values=WHISPER_MODELS)
    model_entry.set(cfg.get("model", default_model_arg))
    model_entry.grid(row=0, column=1, padx=5, pady=5)

    tk.Label(settings_win, text="Default Output Directory:").grid(row=1, column=0, sticky="e", padx=5, pady=5)
    out_dir_entry = tk.Entry(settings_win, width=40)
    out_dir_entry.insert(0, cfg.get("output_dir", default_output_dir_arg))
    out_dir_entry.grid(row=1, column=1, padx=5, pady=5)

    tk.Label(settings_win, text="Hugging Face Token:").grid(row=2, column=0, sticky="e", padx=5, pady=5)
    token_entry = tk.Entry(settings_win, width=40, show="*")
    token_entry.insert(0, cfg.get("HuggingFaceToken", default_hf_token_arg))
    token_entry.grid(row=2, column=1, padx=5, pady=5)

    def save_and_close():
        cfg["model"] = model_entry.get()
        cfg["output_dir"] = out_dir_entry.get().strip()
        cfg["HuggingFaceToken"] = token_entry.get().strip()
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
        settings_win.destroy()
        messagebox.showinfo("Settings Saved", "Settings have been saved to config.")

    tk.Button(settings_win, text="Save", command=save_and_close).grid(row=3, column=0, columnspan=2, pady=10)

menubar = tk.Menu(root)
settings_menu = tk.Menu(menubar, tearoff=0)
settings_menu.add_command(label="Open Settings", command=open_settings)
settings_menu.add_command(label="Save Settings Now", command=save_settings)
menubar.add_cascade(label="Settings", menu=settings_menu)
root.config(menu=menubar)

# --- File selection ---
tk.Label(root, text="Audio/Video File:").grid(row=0, column=0, sticky="e", padx=5, pady=5)
entry_file = tk.Entry(root, width=50)
entry_file.grid(row=0, column=1, padx=5, pady=5)
tk.Button(root, text="Browse...", command=lambda: select_file(entry_file)).grid(row=0, column=2, padx=5, pady=5)

def select_file(entry_widget):
    file_path = filedialog.askopenfilename(
        title="Select audio/video file",
        filetypes=[("Audio/Video Files", "*.mp3 *.wav *.m4a *.mp4 *.flac *.ogg *.wma *.aac"), ("All Files", "*.*")]
    )
    if file_path:
        entry_widget.delete(0, tk.END)
        entry_widget.insert(0, file_path)

# --- Model selection ---
tk.Label(root, text="Whisper Model:").grid(row=1, column=0, sticky="e", padx=5, pady=5)
model_var = tk.StringVar(value=default_model_arg)
tk.OptionMenu(root, model_var, *WHISPER_MODELS).grid(row=1, column=1, sticky="w", padx=5, pady=5)

# --- Output format ---
tk.Label(root, text="Output Format:").grid(row=2, column=0, sticky="e", padx=5, pady=5)
format_var = tk.StringVar(value="json")
tk.OptionMenu(root, format_var, *OUTPUT_FORMATS).grid(row=2, column=1, sticky="w", padx=5, pady=5)

# --- Output directory ---
tk.Label(root, text="Output Directory (optional):").grid(row=3, column=0, sticky="e", padx=5, pady=5)
entry_output_dir = tk.Entry(root, width=50)
entry_output_dir.grid(row=3, column=1, padx=5, pady=5)
if default_output_dir_arg:
    entry_output_dir.insert(0, default_output_dir_arg)
tk.Button(root, text="Browse...", command=lambda: browse_dir(entry_output_dir)).grid(row=3, column=2, padx=5, pady=5)

def browse_dir(entry_widget):
    folder_path = filedialog.askdirectory(title="Select output directory")
    if folder_path:
        entry_widget.delete(0, tk.END)
        entry_widget.insert(0, folder_path)

# --- Hugging Face token ---
tk.Label(root, text="Hugging Face Token (optional):").grid(row=4, column=0, sticky="e", padx=5, pady=5)
entry_token = tk.Entry(root, width=50, show="*")
entry_token.grid(row=4, column=1, padx=5, pady=5)
if default_hf_token_arg:
    entry_token.insert(0, default_hf_token_arg)

# --- Instructions / status box ---
txt_instructions = scrolledtext.ScrolledText(root, width=60, height=8, wrap="word")
txt_instructions.insert("1.0", HF_INSTRUCTIONS)
txt_instructions.config(state="disabled")
txt_instructions.grid(row=5, column=1, columnspan=2, padx=5, pady=5)

def update_instructions(message, is_error=False):
    """Update the diarization instructions/status box dynamically."""
    txt_instructions.config(state="normal")
    txt_instructions.delete("1.0", tk.END)
    txt_instructions.insert("1.0", message)
    if is_error:
        txt_instructions.tag_configure("error", foreground="red")
        txt_instructions.tag_add("error", "1.0", "end")
    else:
        txt_instructions.tag_configure("ok", foreground="green")
        txt_instructions.tag_add("ok", "1.0", "end")
    txt_instructions.config(state="disabled")

# --- Pre-flight diarization check ---
DIAR_SCRIPT = os.path.join(script_dir, "whisperx_diarization.py")

def preflight_diarization_check(hf_token):
    if not os.path.exists(DIAR_SCRIPT):
        append_log("[WARN] Diarization check skipped - script not found.\n")
        return True
    cmd = [sys.executable, DIAR_SCRIPT, "--check-only"]
    if hf_token:
        cmd.insert(2, hf_token)  # token goes before the flag
    append_log("Running diarization pre-check...\n")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        append_log(result.stdout)
        append_log(result.stderr)
        code = result.returncode
        if code == 0:
            update_instructions("Diarization model ready.", is_error=False)
            return True
        elif code == 60:
            msg = "Diarization skipped - no Hugging Face token provided."
            update_instructions(msg, is_error=True)
            return messagebox.askyesno("Diarization Skipped", msg + "\nContinue without diarization?")
        elif code == 61:
            msg = ("Diarization model access denied.\n"
                   "Accept the model terms at:\n"
                   "https://huggingface.co/pyannote/speaker-diarization-3.1")
            update_instructions(msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        elif code == 62:
            msg = "Diarization model download failed.\nCheck network connectivity and Hugging Face token validity."
            update_instructions(msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        elif code == 63:
            msg = "Diarization dummy run failed.\nCheck Pyannote dependencies and ensure audio backend works."
            update_instructions(msg, is_error=True)
            return messagebox.askyesno("Diarization Error", msg + "\nContinue without diarization?")
        else:
            update_instructions(f"Unexpected diarization check exit code: {code}", is_error=True)
            return True
    except Exception as e:
        append_log(f"[ERROR] Diarization pre-check failed: {e}\n")
        return True

# --- JSON transcript formatting ---
def format_json_transcript(json_path):
    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        segments = data.get("segments", [])
        if not segments:
            return None
        formatted_lines = []
        last_speaker = None
        for seg in segments:
            speaker = seg.get("speaker", "UNKNOWN")
            text = seg.get("text", "").strip()
            if speaker != last_speaker:
                if last_speaker is not None:
                    formatted_lines.append("")
                formatted_lines.append(f"{speaker}: {text}")
                last_speaker = speaker
            else:
                formatted_lines[-1] += f" {text}"
        formatted_path = os.path.splitext(json_path)[0] + "-formatted.txt"
        with open(formatted_path, "w", encoding="utf-8") as out_f:
            out_f.write("\n".join(formatted_lines))
        return formatted_path
    except Exception as e:
        messagebox.showerror("Formatting Error", f"Failed to format JSON transcript:\n{e}")
        return None

# --- Transcription logic ---
def run_transcription_thread():
    file_path = entry_file.get().strip()
    model = model_var.get()
    output_format = format_var.get()
    hf_token = entry_token.get().strip()
    output_dir = entry_output_dir.get().strip()

    if not file_path:
        messagebox.showerror("Error", "Please select a file to transcribe.")
        return
    if not os.path.exists(file_path):
        messagebox.showerror("Error", "Selected file does not exist.")
        return

    if not preflight_diarization_check(hf_token):
        append_log("Transcription cancelled by user after diarization check.\n")
        return

    diarize_flag = "--diarize" if hf_token else ""
    base_name = os.path.splitext(os.path.basename(file_path))[0]
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        output_path = os.path.join(output_dir, f"{base_name}.{output_format}")
    else:
        output_path = f"{os.path.splitext(file_path)[0]}.{output_format}"

    cmd = [
        sys.executable, "-m", "whisperx",
        file_path,
        "--model", model,
        "--output_format", output_format,
        "--output_dir", output_dir if output_dir else os.path.dirname(file_path)
    ]
    if diarize_flag:
        cmd.append("--diarize")
    if hf_token:
        cmd.extend(["--hf_token", hf_token])

    safe_cmd = [c if not (hf_token and hf_token in c) else "***TOKEN***" for c in cmd]
    append_log(f"Starting transcription...\nCommand: {' '.join(safe_cmd)}\n\n")

    btn_transcribe.config(state="disabled")
    try:
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            append_log(line)
        process.wait()

        exit_code = process.returncode
        if exit_code == 0:
            msg = f"\nTranscription complete.\nOutput saved to:\n{output_path}"
            if output_format == "json" and os.path.exists(output_path):
                formatted_path = format_json_transcript(output_path)
                if formatted_path:
                    msg += f"\nFormatted transcript saved to:\n{formatted_path}"
            append_log(msg + "\n")
            messagebox.showinfo("Done", msg)
        elif exit_code in (60, 61, 62, 63):
            if exit_code == 60:
                diag_msg = "Diarization skipped - no Hugging Face token provided."
            elif exit_code == 61:
                diag_msg = ("Diarization model access denied.\n"
                            "Accept the model terms at:\n"
                            "https://huggingface.co/pyannote/speaker-diarization-3.1")
            elif exit_code == 62:
                diag_msg = "Diarization model download failed.\nCheck network connectivity and token validity."
            elif exit_code == 63:
                diag_msg = "Diarization dummy run failed.\nCheck Pyannote dependencies and audio backend."
            append_log(f"\n[DIARIZATION WARNING] {diag_msg}\n")
            messagebox.showerror("Diarization Issue", diag_msg)
        else:
            append_log(f"\nWhisperX failed with exit code {exit_code}\n")
            messagebox.showerror("Error", f"WhisperX failed. See log for details.")
    except Exception as e:
        append_log(f"\nError running WhisperX: {e}\n")
        messagebox.showerror("Error", f"Error running WhisperX:\n{e}")
    finally:
        btn_transcribe.config(state="normal")

def run_transcription():
    threading.Thread(target=run_transcription_thread, daemon=True).start()

# --- Transcribe button ---
btn_transcribe = tk.Button(root, text="Transcribe", command=run_transcription, bg="green", fg="white")
btn_transcribe.grid(row=6, column=0, columnspan=3, pady=10)

# --- Live log output box ---
tk.Label(root, text="Live Log:").grid(row=7, column=0, sticky="ne", padx=5, pady=5)
log_box = scrolledtext.ScrolledText(root, width=80, height=15, wrap="word", state="disabled")
log_box.grid(row=7, column=1, columnspan=2, padx=5, pady=5)

root.mainloop()