import tkinter as tk
from tkinter import filedialog, messagebox
import subprocess
import os
import sys
import json
import argparse

# List of available Whisper models
WHISPER_MODELS = [
    "tiny", "base", "small", "medium", "large-v2"
]

# Output formats
OUTPUT_FORMATS = [
    "txt", "json", "srt", "vtt"
]

# Instructions for Hugging Face model access
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

default_model_arg = args.default_model if args.default_model in WHISPER_MODELS else "large-v2"
default_output_dir_arg = args.output_dir if args.output_dir else ""
default_hf_token_arg = args.hf_token if args.hf_token else os.environ.get("HUGGINGFACE_TOKEN", "")

# --- GUI callbacks ---
def browse_file():
    file_path = filedialog.askopenfilename(
        title="Select audio/video file",
        filetypes=[("Audio/Video Files", "*.mp3 *.wav *.m4a *.mp4 *.flac *.ogg *.wma *.aac"), ("All Files", "*.*")]
    )
    if file_path:
        entry_file.delete(0, tk.END)
        entry_file.insert(0, file_path)

def browse_output_dir():
    folder_path = filedialog.askdirectory(
        title="Select output directory"
    )
    if folder_path:
        entry_output_dir.delete(0, tk.END)
        entry_output_dir.insert(0, folder_path)

def format_json_transcript(json_path):
    """Reads WhisperX JSON and writes a -formatted.txt with speaker-by-speaker transcript."""
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
                    formatted_lines.append("")  # blank line between speakers
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

def run_transcription():
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

    diarize_flag = "--diarize"
    if not hf_token:
        # Warn but allow
        if messagebox.askyesno("No Hugging Face Token",
                               "No Hugging Face token provided.\n"
                               "Diarization will fail unless the model is already cached.\n"
                               "Do you want to continue without diarization?"):
            diarize_flag = ""  # skip diarization
        else:
            return

    # Build output path
    base_name = os.path.splitext(os.path.basename(file_path))[0]
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        output_path = os.path.join(output_dir, f"{base_name}.{output_format}")
    else:
        output_path = f"{os.path.splitext(file_path)[0]}.{output_format}"

    # Build command
    cmd = [
        sys.executable, "-m", "whisperx",
        file_path,
        "--model", model,
        "--output_format", output_format
    ]
    if diarize_flag:
        cmd.append("--diarize")
    if hf_token:
        cmd.extend(["--hf_token", hf_token])

    # Run WhisperX
    try:
        messagebox.showinfo("Transcription Started", "Transcription has started. This may take a while...")
        subprocess.run(cmd, check=True)
        msg = f"Transcription complete.\nOutput saved to:\n{output_path}"

        # If JSON, auto-format
        if output_format == "json" and os.path.exists(output_path):
            formatted_path = format_json_transcript(output_path)
            if formatted_path:
                msg += f"\nFormatted transcript saved to:\n{formatted_path}"

        messagebox.showinfo("Done", msg)
    except subprocess.CalledProcessError as e:
        err_msg = str(e)
        if any(keyword in err_msg.lower() for keyword in ["403", "401", "unauthorized", "forbidden", "not authorized", "access denied"]):
            err_msg += "\n\nHint: You may need to accept the model terms on Hugging Face."
        messagebox.showerror("Error", f"WhisperX failed:\n{err_msg}")

# --- GUI setup ---
root = tk.Tk()
root.title("WhisperX Transcription Tool")

# File selection
tk.Label(root, text="Audio/Video File:").grid(row=0, column=0, sticky="e", padx=5, pady=5)
entry_file = tk.Entry(root, width=50)
entry_file.grid(row=0, column=1, padx=5, pady=5)
tk.Button(root, text="Browse...", command=browse_file).grid(row=0, column=2, padx=5, pady=5)

# Model selection
tk.Label(root, text="Whisper Model:").grid(row=1, column=0, sticky="e", padx=5, pady=5)
model_var = tk.StringVar(value=default_model_arg)
tk.OptionMenu(root, model_var, *WHISPER_MODELS).grid(row=1, column=1, sticky="w", padx=5, pady=5)

# Output format
tk.Label(root, text="Output Format:").grid(row=2, column=0, sticky="e", padx=5, pady=5)
format_var = tk.StringVar(value="json")
tk.OptionMenu(root, format_var, *OUTPUT_FORMATS).grid(row=2, column=1, sticky="w", padx=5, pady=5)

# Output directory
tk.Label(root, text="Output Directory (optional):").grid(row=3, column=0, sticky="e", padx=5, pady=5)
entry_output_dir = tk.Entry(root, width=50)
entry_output_dir.grid(row=3, column=1, padx=5, pady=5)
if default_output_dir_arg:
    entry_output_dir.insert(0, default_output_dir_arg)
tk.Button(root, text="Browse...", command=browse_output_dir).grid(row=3, column=2, padx=5, pady=5)

# Hugging Face token
tk.Label(root, text="Hugging Face Token (optional):").grid(row=4, column=0, sticky="e", padx=5, pady=5)
entry_token = tk.Entry(root, width=50, show="*")
entry_token.grid(row=4, column=1, padx=5, pady=5)
if default_hf_token_arg:
    entry_token.insert(0, default_hf_token_arg)

# Instructions
tk.Label(root, text="Instructions for diarization access:").grid(row=5, column=0, sticky="ne", padx=5, pady=5)
txt_instructions = tk.Text(root, width=60, height=8, wrap="word")
txt_instructions.insert("1.0", HF_INSTRUCTIONS)
txt_instructions.config(state="disabled")
txt_instructions.grid(row=5, column=1, columnspan=2, padx=5, pady=5)

# Transcribe button
tk.Button(
    root,
    text="Transcribe",
    command=run_transcription,
    bg="green",
    fg="white"
).grid(row=6, column=0, columnspan=3, pady=10)

root.mainloop()