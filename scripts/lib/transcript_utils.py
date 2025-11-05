import os
import json
from tkinter import messagebox

def format_json_transcript(json_path):
    """
    Reads a WhisperX JSON transcript and writes a speaker-grouped text file.
    Returns the path to the formatted file, or None on failure.
    """
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
                # Append to the last line for the same speaker
                formatted_lines[-1] += f" {text}"

        formatted_path = os.path.splitext(json_path)[0] + "-formatted.txt"
        with open(formatted_path, "w", encoding="utf-8") as out_f:
            out_f.write("\n".join(formatted_lines))

        return formatted_path

    except Exception as e:
        messagebox.showerror("Formatting Error", f"Failed to format JSON transcript:\n{e}")
        return None