# WhisperX Toolchain

A streamlined, GUI‑driven workflow for installing, running, and uninstalling WhisperX with optional speaker diarization.

---

## 📦 Features
- One‑click install & launch via WhisperX_Launcher.bat
- GUI transcription with model/format selection
- Optional diarization with Hugging Face token
- Pre‑flight diarization check with clear status messages
- Config‑driven defaults for model, output dir, and token
- Step‑aware uninstall with cleanup mode
- Persistent logs for troubleshooting

---

## 🚀 Usage

### 1. Install & Launch
1. Ensure dependencies are installed (see Dependencies).
2. Double‑click WhisperX_Launcher.bat.
3. The launcher will:
   - Install Miniconda (if missing and enabled in config)
   - Create the WhisperX environment
   - Install PyTorch, WhisperX, and ffmpeg
   - Launch the GUI

### 2. GUI Basics
- Audio/Video File: Select the file to transcribe.
- Whisper Model: Choose from tiny, base, small, medium, large‑v2.
- Output Format: txt, json, srt, or vtt.
- Output Directory: Optional; defaults to the input file’s folder.
- Hugging Face Token: Required for diarization unless model is already cached.
- Diarization Status: Shows readiness or setup instructions.
- Live Log: Displays real‑time output and errors.

Click Transcribe to start. The GUI remains responsive during processing.

---

## 🗑 Uninstall

Run uninstall_whisperx.bat to remove:
- WhisperX Conda environment
- Miniconda (if installed by the launcher)
- Chocolatey (if installed by the launcher)
- PATH entries and cache folders

Cleanup Mode:
If uninstall fails or leaves remnants, run:
    uninstall_whisperx.bat -Cleanup
This force‑deletes leftover files and PATH entries.

---

## 🛠 Manual / Recovery Instructions

If the launcher fails:
1. Check the exit code in the console or log file.
2. Refer to the error message for targeted recovery:
   - 10 → Conda missing (enable InstallConda or install manually)
   - 11 → Miniconda install failed
   - 20 → Environment creation failed
   - 30 → PyTorch install failed
   - 31 → WhisperX install failed
   - 40 → ffmpeg setup failed
   - 50 → GUI launch failed
   - 60–63 → Diarization issues (see Diarization Setup)
3. Fix the issue and re‑run the launcher.

---

## 📋 Dependencies

- Windows 10/11
- PowerShell 5.1+ or PowerShell Core (pwsh)
- Miniconda (auto‑installed if enabled in config)
- Chocolatey (auto‑installed if needed for Miniconda)
- Python (managed inside Conda env)
- ffmpeg (system or auto‑installed via imageio‑ffmpeg)

---

## 🗣 Diarization Setup

To enable diarization:
1. Create a free Hugging Face account.
2. Accept the terms for:
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
   - https://huggingface.co/pyannote/embedding
3. Generate a READ token: https://huggingface.co/settings/tokens
4. Enter the token in the GUI or save it in Settings.

---

## 🐞 Basic Troubleshooting

- GUI won’t launch → Check LogPath for the latest launcher_log_*.txt.
- Diarization skipped → Provide a valid Hugging Face token.
- Model download fails → Check internet connection and token validity.
- ffmpeg errors → Verify FfmpegPath in config or allow auto‑install.
- Permission errors → Run .bat files as Administrator.

---

## ⚙ Config (whisperx_config.json)

Example:
    {
      "EnvPath": "envs",
      "EnvName": "whisperx",
      "PythonVersion": "3.10",
      "CudaTarget": "cu118",
      "UseGPU": true,
      "UseSystemFfmpeg": false,
      "FfmpegPath": "",
      "InstallConda": true,
      "RetryCount": 3,
      "BackoffSeconds": 5,
      "LogPath": "logs",
      "model": "large-v2",
      "output_dir": "",
      "HuggingFaceToken": ""
    }

Most‑edited fields:
- model → Default Whisper model.
- output_dir → Default output directory.
- HuggingFaceToken → Token for diarization.
- UseGPU → true for GPU, false for CPU.
- CudaTarget → Match your GPU/CUDA version.
- InstallConda → Auto‑install Miniconda if missing.

---

## 📄 License

This toolchain wraps WhisperX (MIT License) and Pyannote.audio (various licenses).
See their repositories for license details.
All batch/PowerShell/GUI scripts in this repo are released under the MIT License.