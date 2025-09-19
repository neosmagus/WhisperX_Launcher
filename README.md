# WhisperX One‑Click Transcription Tool

A portable, self‑contained setup for running WhisperX with a simple GUI and optional speaker diarization.  
Includes a universal launcher that runs silently (no console) when possible, or falls back to console mode — both with a live status window.

---

## Installation

1. Download the release ZIP (or clone this repo).
2. Extract everything into a folder, e.g.:
   - C:\WhisperX\
3. You should see:
   - WhisperX_Launcher.bat
   - whisperx_launcher.ps1
   - whisperx_gui.py
   - icons\ (optional icons for shortcuts)

Optional: Create a desktop shortcut
- Right‑click WhisperX_Launcher.bat → Send to → Desktop (create shortcut)
- Right‑click the shortcut → Properties → Change Icon… → choose an .ico from .\icon
- Name it: WhisperX – Auto Launcher

---

## Running the tool

### Option 1 — Recommended: .bat universal launcher
- Double‑click WhisperX_Launcher.bat.
- Behavior:
  - If VBScript is allowed → Silent Mode (hidden PowerShell + live status window)
  - If VBScript is blocked → Console Mode (visible PowerShell + live status window)
- It auto‑detects whisperx_launcher.ps1 and whisperx_gui.py in the same folder.
- It sets up Miniconda and the WhisperX environment if needed.
- It launches the GUI.

Note: If Miniconda is not installed, right‑click → Run as administrator to allow Chocolatey to install it.

### Option 2 — Run the .ps1 launcher directly
1. Open PowerShell.
2. cd "C:\WhisperX"
3. Run:
   - .\whisperx_launcher.ps1
4. If you get an execution policy error (first run on some systems):
   - Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

---

## Configuration via whisperx_config.json

The launcher reads settings from `whisperx_config.json` in the same folder.  
If `UseConfig = true`, the launcher runs unattended and never prompts; missing critical values cause a clear failure.  
If `UseConfig = false`, missing values are prompted for (GUI or console).

A separate file `%USERPROFILE%\.whisperx_launcher_settings.json` stores last‑used environment and GUI paths.

### Config schema

| Key | Type | Default | Description |
| --- | ---- | ------- | ----------- |
| UseConfig | bool | true | Unattended mode toggle |
| use_console | bool | false | Force console mode |
| EnvPath | string | C:\conda_envs | Root folder for Conda envs |
| EnvName | string | WhisperX | Environment name |
| PythonVersion | string | 3.10.18 | Python version to install |
| CudaTarget | string | "" | PyTorch CUDA target (e.g. cu118) |
| UseGPU | bool | false | Install GPU PyTorch |
| DefaultModel | string | base | Default Whisper model in GUI |
| OutputDir | string | "" | Default output directory |
| HuggingFaceToken | string | "" | Token for diarization models |
| DiarizeOnFirstRun | bool | false | Cache diarization model at setup |
| UseSafe | bool | true | Avoid pre‑release packages |
| UseSystemFfmpeg | bool | false | Use system ffmpeg |
| FfmpegPath | string | "" | Path to system ffmpeg binary |
| RetryCount | int | 3 | Network retry attempts |
| BackoffSeconds | int | 5 | Delay between retries |
| LogTimestamps | bool | true | Prefix log lines with timestamps |
| ScriptPath | string | "" | Path to whisperx_gui.py |
| InstallConda | bool | true | Install Miniconda if missing |

### Silent mode prompts
When `UseConfig = false` and no console is visible, GUI dialogs are shown for inputs.

### Diarization setup
Tokens and model terms acceptance are required on Hugging Face for diarization.

### Resetting
Delete `%USERPROFILE%\.whisperx_launcher_settings.json` to clear saved paths.

### Offline installs
Use local wheels/conda packages and set `UseConfig = true` to avoid network prompts.

### Troubleshooting
- **CMD parser pitfalls:** Escape parentheses in `.bat` scripts; avoid em dashes.
- **CUDA mismatch:** If GPU install fails, check driver/CUDA runtime compatibility.
- **Chocolatey permissions:** Run `.bat` as admin if Miniconda install fails.

---

## Hugging Face setup for diarization (speaker labeling)

Diarization is optional. Without it, you still get transcription (no speaker labels).  
To enable diarization on first use:

1. Log in to Hugging Face:
   - https://huggingface.co/
2. Accept model terms (required to download models):
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - https://huggingface.co/pyannote/embedding
3. Create a READ access token:
   - https://huggingface.co/settings/tokens → New token → “Read”
4. When prompted by the GUI or PowerShell script, paste your token.

If you skip these steps:
- Diarization will be disabled unless models are already cached locally.
- Transcription still works; text won’t be split by speaker.

---

## What’s included

- WhisperX_Launcher.bat
  - One‑file universal launcher
  - Auto‑detects whether Silent Mode (VBS) is available; otherwise uses Console Mode
  - Shows live status window in both modes
- whisperx_launcher.ps1
  - Sets up Conda env (GPU or CPU)
  - Installs PyTorch and WhisperX (safe pinned or latest)
  - Installs diarization dependencies (optional)
  - Auto‑configures ffmpeg via imageio‑ffmpeg
  - Auto‑detects whisperx_gui.py in the same folder
  - Launches the GUI
- whisperx_gui.py
  - Simple Tkinter GUI to select an audio/video file, model, output format
  - Optional Hugging Face token for diarization
  - Automatically formats JSON output into a -formatted.txt, grouped by speaker

---

## Tools and dependencies

- WhisperX — transcription with word‑level timestamps
- PyTorch — model runtime (CPU or CUDA)
- PyAnnote — speaker diarization pipeline
- Miniconda — environment manager for isolated Python setup
- Chocolatey — Windows package manager to install Miniconda if missing
- imageio‑ffmpeg — bundled ffmpeg binaries for media decoding
- Tkinter — GUI framework included with Python

---

## Manual install (if you don’t want the launchers)

1. Install Miniconda:
   - https://docs.conda.io/en/latest/miniconda.html
2. Create and activate an environment:
   - conda create -n whisperx python=3.10
   - conda activate whisperx
3. Install PyTorch (choose one):
   - GPU (CUDA 12.1):
     - pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cu121
   - CPU only:
     - pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cpu
4. Install WhisperX:
   - pip install whisperx
5. Optional diarization deps:
   - pip install pyannote.audio pyannote.pipeline
6. Utilities:
   - pip install imageio-ffmpeg matplotlib

Optional: ffmpeg on PATH (if you prefer system ffmpeg)
- https://ffmpeg.org/download.html
- Add ffmpeg\bin to your PATH

---

## Running WhisperX from the command line

If you prefer not to use the GUI:

1. conda activate whisperx
2. Basic transcription:
   - whisperx "path\to\audio.mp3" --model large-v2 --output_format json
3. With diarization:
   - whisperx "path\to\audio.mp3" --model large-v2 --output_format json --diarize --hf_token YOUR_HF_READ_TOKEN

Common flags:
- --model: tiny | base | small | medium | large-v2
- --output_format: txt | json | srt | vtt
- --diarize: enable speaker diarization (requires accepted models + token unless cached)
- --hf_token: your Hugging Face READ token

Output:
- Files saved next to your audio/video (e.g., .json, .srt, .vtt, .txt)
- If you use the GUI and choose JSON, it also generates a -formatted.txt grouped by speaker

---

## Troubleshooting

- First run is slow:
  - Models and dependencies are downloading/caching. Subsequent runs are faster.
- Execution policy blocks .ps1:
  - Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
- Conda not found:
  - Run the .bat as administrator so Chocolatey can install Miniconda.
- Change or reset saved paths:
  - Delete %USERPROFILE%\.whisperx_launcher_settings.json

---

## License

This project automates setup and usage for WhisperX and related tools.  
See upstream projects for their licenses and terms.

