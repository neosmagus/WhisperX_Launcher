import sys
from pyannote.audio import Pipeline

# Expect Hugging Face token as first argument
hf_token = sys.argv[1] if len(sys.argv) > 1 else None

if not hf_token:
    print("No Hugging Face token provided. Skipping diarization model download.")
    sys.exit(0)

print("Downloading diarization model from Hugging Face...")

# Load the diarization pipeline
pipeline = Pipeline.from_pretrained(
    'pyannote/speaker-diarization-3.1',
    use_auth_token=hf_token
)

# Force model download by running a dummy diarization
# (Replace 'dummy.wav' with a small bundled audio file if you want to pre-cache)
# Example:
# diarization = pipeline("dummy.wav")

print("Diarization model cached successfully.")