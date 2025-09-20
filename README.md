# WhisperX One‑Click Transcription Tool (Console‑Only)

A portable, self‑contained setup for running WhisperX with optional speaker diarization.  
Includes a universal batch launcher that always runs in console mode and reads all runtime options from a JSON config file.

## 🚀 Quick Start

1. **Download & Extract**
   - Get the release ZIP and extract to `C:\WhisperX\`

2. **Edit Config**
   - Open `whisperx_config.json`
   - Minimal working example:
     ```json
     {
       "UseConfig": true,
       "model": "base",
       "input_file": "input_audio.wav",
       "output_format": "srt",
       "output_dir": "output",
       "diarize": false,
       "InstallConda": true
     }
     ```

3. **Run**
   - Double‑click `WhisperX_Launcher.bat`
   - Or run in PowerShell:
     ```powershell
     .\whisperx_launcher.ps1 -ConfigPath "whisperx_config.json"
     ```

## Installation

1. Download the release ZIP (or clone this repo).
2. Extract everything into a folder, e.g.: C:\WhisperX\
3. You should see:
- `WhisperX_Launcher.bat`
- `whisperx_launcher.ps1`
- `whisperx_config.json`
- (Optional) `icon\` for shortcuts

Optional: Create a desktop shortcut
- Right‑click `WhisperX_Launcher.bat` → **Send to → Desktop (create shortcut)**
- Right‑click the shortcut → **Properties → Change Icon…** → choose an `.ico` from `.\icon`
- Name it: **WhisperX – Console Launcher**

## Running the tool

### Option 1 — Recommended: `.bat` universal launcher
- Double‑click `WhisperX_Launcher.bat`.
- Behavior:
  - Always runs `whisperx_launcher.ps1` in console mode.
  - Reads all runtime options from the JSON config file.
  - Sets up Miniconda and the WhisperX environment if needed.
  - Runs WhisperX transcription directly in the console.

### Option 2 — Run the `.ps1` launcher directly
1. Open PowerShell.
2. `cd "C:\WhisperX"`
3. Run:
   ```powershell
   .\whisperx_launcher.ps1 -ConfigPath "whisperx_config.json"
4. 	If you get an execution policy error (first run on some systems):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

## Configuration via `whisperx_config.json`

The launcher reads settings from `whisperx_config.json` in the same folder (or from a path you pass to the `.bat` or `.ps1`).  
If `UseConfig = true`, the launcher runs unattended and never prompts; missing critical values cause a clear failure.

### Config schema (console‑only version)

| Key              | Type    | Default       | Description                                           |
| ---------------- | ------- | ------------- | ----------------------------------------------------- |
| UseConfig        | bool    | true          | Unattended mode toggle                                |
| EnvPath          | string  | C:\conda_envs | Root folder for Conda envs                            |
| EnvName          | string  | WhisperX      | Environment name                                      |
| PythonVersion    | string  | 3.10.18       | Python version to install                             |
| CudaTarget       | string  | ""            | PyTorch CUDA target (e.g. cu118)                      |
| UseGPU           | bool    | false         | Install GPU PyTorch                                   |
| model            | string  | base          | WhisperX model to use (`tiny`…`large-v2`)             |
| input_file       | string  | *(none)*      | Path to audio/video file to transcribe (**required**) |
| output_format    | string  | srt           | Output format: txt, json, srt, vtt                    |
| output_dir       | string  | output        | Output directory                                      |
| diarize          | bool    | false         | Enable speaker diarization                            |
| extra_args       | array   | []            | Additional CLI args (e.g. `["--language","en"]`)      |
| HuggingFaceToken | string  | ""            | Token for diarization models                          |
| DiarizeOnFirstRun| bool    | false         | Cache diarization model at setup                      |
| UseSafe          | bool    | true          | Avoid pre-release packages                            |
| UseSystemFfmpeg  | bool    | false         | Use system ffmpeg                                     |
| FfmpegPath       | string  | ""            | Path to system ffmpeg binary                          |
| RetryCount       | int     | 3             | Network retry attempts                                |
| BackoffSeconds   | int     | 5             | Delay between retries                                 |
| LogTimestamps    | bool    | true          | Prefix log lines with timestamps                      |
| ScriptPath       | string  | ""            | Path to whisperx_gui.py (unused in console-only mode) |
| InstallConda     | bool    | true          | Install Miniconda if missing                          |

### Diarization setup
Tokens and model terms acceptance are required on Hugging Face for diarization.

1. Log in to Hugging Face:  
   https://huggingface.co/
2. Accept model terms:  
   - https://huggingface.co/pyannote/speaker-diarization-3.1  
   - https://huggingface.co/pyannote/segmentation-3.0  
   - https://huggingface.co/pyannote/embedding
3. Create a READ access token:  
   https://huggingface.co/settings/tokens → New token → “Read”
4. Add your token to `HuggingFaceToken` in the config.

If you skip these steps:
- Diarization will be disabled unless models are already cached locally.
- Transcription still works; text won’t be split by speaker.

## What’s included

- **WhisperX_Launcher.bat**  
  - One‑file universal launcher  
  - Always runs in console mode  
  - Passes config path to PowerShell script
- **whisperx_launcher.ps1**  
  - Reads config JSON  
  - Sets up Conda env (GPU or CPU)  
  - Installs PyTorch and WhisperX  
  - Installs diarization dependencies (optional)  
  - Runs WhisperX transcription with retries
- **whisperx_config.json**  
  - Stores all runtime options

## Tools and dependencies

- WhisperX — transcription with word‑level timestamps
- PyTorch — model runtime (CPU or CUDA)
- PyAnnote — speaker diarization pipeline
- Miniconda — environment manager for isolated Python setup
- Chocolatey — Windows package manager to install Miniconda if missing
- imageio‑ffmpeg — bundled ffmpeg binaries for media decoding

## Manual install (if you don’t want the launchers)

1. Install Miniconda:  
   https://docs.conda.io/en/latest/miniconda.html
2. Create and activate an environment:  
   ```powershell
   conda create -n whisperx python=3.10
   conda activate whisperx
3. Install PyTorch (choose one):
   - GPU (CUDA 12.1):
   pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cu121
   - CPU only:
   pip install torch torchaudio torchvision --index-url https://download.pytorch.org/whl/cpu
4. Install WhisperX:
   pip install whisperx
5. Optional diarization deps:
   pip install pyannote.audio pyannote.pipeline
6. Utilities:
   pip install imageio-ffmpeg matplotlib
   Optional: ffmpeg on PATH (if you prefer system ffmpeg)
   https://ffmpeg.org/download.html
   Add ffmpeg\bin to your PATH

## Running WhisperX from the command line

If you prefer not to use the launcher:

1. Activate the Conda environment: conda activate whisperx
2. Basic transcription: whisperx "path\to\audio.mp3" --model large-v2 --output_format json
3. With diarization: whisperx "path\to\audio.mp3" --model large-v2 --output_format json --diarize --hf_token YOUR_HF_READ_TOKEN

### Common flags
- `--model`: `tiny` | `base` | `small` | `medium` | `large-v2`
- `--output_format`: `txt` | `json` | `srt` | `vtt`
- `--diarize`: enable speaker diarization (requires accepted models + token unless cached)
- `--hf_token`: your Hugging Face READ token

### Output
- Files are saved next to your audio/video (e.g., `.json`, `.srt`, `.vtt`, `.txt`)
- If you specify `--output_dir`, files are saved there instead
- JSON output contains word‑level timestamps; SRT/VTT are subtitle‑ready
- If diarization is enabled, output is segmented by speaker

## Troubleshooting

- **First run is slow:**  
  Models and dependencies are downloading/caching. Subsequent runs are faster.

- **Execution policy blocks `.ps1`:**  
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
- **CUDA mismatch:
  If GPU install fails, check driver/CUDA runtime compatibility.
- **Change or reset saved paths:
  Delete %userprofile%\.whisperx_launcher_settings.json (only relevant if you later add GUI mode back).

## License

This project automates setup and usage for WhisperX and related tools.  
See upstream projects for their licenses and terms.