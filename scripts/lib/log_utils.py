import os
import datetime
import tkinter as tk

def init_log_file(cfg, prefix):
    """
    Create a timestamped log file in the configured LogPath.
    Returns the absolute path to the log file.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_dir = os.path.abspath(os.path.join(script_dir, cfg.get("LogPath", "./logs")))
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(
        log_dir,
        f"{prefix}_{datetime.datetime.now():%Y%m%d_%H%M%S}.txt"
    )
    return log_file

def append_log(message, log_widget=None, log_file=None):
    """
    Append a message to the GUI log widget (if provided) and to the log file (if provided).
    """
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {message}"

    # Append to GUI log box
    if log_widget is not None:
        log_widget.config(state="normal")
        log_widget.insert(tk.END, line)
        if not line.endswith("\n"):
            log_widget.insert(tk.END, "\n")
        log_widget.see(tk.END)
        log_widget.config(state="disabled")

    # Append to file
    if log_file:
        try:
            with open(log_file, "a", encoding="utf-8") as lf:
                lf.write(line)
                if not line.endswith("\n"):
                    lf.write("\n")
        except Exception as e:
            # If logging to file fails, still allow GUI to work
            if log_widget is not None:
                log_widget.config(state="normal")
                log_widget.insert(tk.END, f"[LOG ERROR] {e}\n")
                log_widget.config(state="disabled")