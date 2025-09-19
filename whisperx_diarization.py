import sys
from pyannote.audio import Pipeline

hf_token = sys.argv[1] if len(sys.argv) > 1 else None

if not hf_token:
    print("No Hugging Face token provided. Skipping diarization model download.")
    sys.exit(0)

print("Downloading diarization model from Hugging Face...")

try:
    pipeline = Pipeline.from_pretrained(
        'pyannote/speaker-diarization-3.1',
        use_auth_token=hf_token
    )
    # Dummy run to force full cache
    import tempfile, soundfile as sf, numpy as np
    dummy_wav = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    sf.write(dummy_wav.name, np.zeros((16000,), dtype=np.float32), 16000)
    _ = pipeline(dummy_wav.name)
    print("Diarization model cached successfully.")
except Exception as e:
    msg = str(e)
    if any(k in msg.lower() for k in ["403", "401", "unauthorized", "forbidden", "not authorized", "access denied"]):
        print("Access denied — please accept the model terms at:")
        print("https://huggingface.co/pyannote/speaker-diarization-3.1")
    else:
        print(f"Error caching diarization model: {msg}")
    sys.exit(1)