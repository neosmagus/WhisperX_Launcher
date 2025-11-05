import tkinter as tk
from lib.config_utils import load_config
from lib.log_utils import init_log_file
from gui.gui_widgets import build_main_window
from gui.gui_handlers import setup_handlers

# --- Load config ---
cfg = load_config()

# --- Init root window ---
root = tk.Tk()
root.title("WhisperX Transcription Tool")

# --- Init log file ---
log_file = init_log_file(cfg, prefix="gui_log")

# --- Build UI ---
widgets = build_main_window(root, cfg)

# --- Wire up handlers ---
setup_handlers(root, widgets, cfg, log_file)

# --- Start loop ---
root.mainloop()