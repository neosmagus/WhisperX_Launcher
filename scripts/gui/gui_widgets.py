import tkinter as tk
from tkinter import filedialog, scrolledtext

def build_main_window(root, cfg):
    widgets = {}

    # File selection
    tk.Label(root, text="Audio/Video File:").grid(row=0, column=0, sticky="e", padx=5, pady=5)
    widgets['entry_file'] = tk.Entry(root, width=50)
    widgets['entry_file'].grid(row=0, column=1, padx=5, pady=5)
    tk.Button(root, text="Browse...", command=lambda: browse_file(widgets['entry_file'])).grid(row=0, column=2, padx=5, pady=5)

    # Model selection
    tk.Label(root, text="Whisper Model:").grid(row=1, column=0, sticky="e", padx=5, pady=5)
    widgets['model_var'] = tk.StringVar(value=cfg.get("model", "large-v2"))
    tk.OptionMenu(root, widgets['model_var'], "tiny", "base", "small", "medium", "large-v2").grid(row=1, column=1, sticky="w", padx=5, pady=5)

    # Output format
    tk.Label(root, text="Output Format:").grid(row=2, column=0, sticky="e", padx=5, pady=5)
    widgets['format_var'] = tk.StringVar(value="json")
    tk.OptionMenu(root, widgets['format_var'], "txt", "json", "srt", "vtt").grid(row=2, column=1, sticky="w", padx=5, pady=5)

    # Output directory
    tk.Label(root, text="Output Directory (optional):").grid(row=3, column=0, sticky="e", padx=5, pady=5)
    widgets['entry_output_dir'] = tk.Entry(root, width=50)
    widgets['entry_output_dir'].grid(row=3, column=1, padx=5, pady=5)
    tk.Button(root, text="Browse...", command=lambda: browse_dir(widgets['entry_output_dir'])).grid(row=3, column=2, padx=5, pady=5)

    # Hugging Face token
    tk.Label(root, text="Hugging Face Token (optional):").grid(row=4, column=0, sticky="e", padx=5, pady=5)
    widgets['entry_token'] = tk.Entry(root, width=50, show="*")
    widgets['entry_token'].grid(row=4, column=1, padx=5, pady=5)

    # Diarization status
    tk.Label(root, text="Diarization Status / Instructions:").grid(row=5, column=0, sticky="ne", padx=5, pady=5)
    widgets['txt_instructions'] = scrolledtext.ScrolledText(root, width=60, height=8, wrap="word", state="disabled")
    widgets['txt_instructions'].grid(row=5, column=1, columnspan=2, padx=5, pady=5)

    # Transcribe button
    widgets['btn_transcribe'] = tk.Button(root, text="Transcribe", bg="green", fg="white")
    widgets['btn_transcribe'].grid(row=6, column=0, columnspan=3, pady=10)

    # Live log
    tk.Label(root, text="Live Log:").grid(row=7, column=0, sticky="ne", padx=5, pady=5)
    widgets['log_box'] = scrolledtext.ScrolledText(root, width=80, height=15, wrap="word", state="disabled")
    widgets['log_box'].grid(row=7, column=1, columnspan=2, padx=5, pady=5)

    return widgets

def browse_file(entry_widget):
    path = filedialog.askopenfilename(
        title="Select audio/video file",
        filetypes=[("Audio/Video Files", "*.mp3 *.wav *.m4a *.mp4 *.flac *.ogg *.wma *.aac"), ("All Files", "*.*")]
    )
    if path:
        entry_widget.delete(0, tk.END)
        entry_widget.insert(0, path)

def browse_dir(entry_widget):
    folder = filedialog.askdirectory(title="Select output directory")
    if folder:
        entry_widget.delete(0, tk.END)
        entry_widget.insert(0, folder)