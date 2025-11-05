import os, json

def load_config():
    config_path = os.path.join(os.path.dirname(__file__), '..', 'whisperx_config.json')
    with open(config_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_config(cfg):
    config_path = os.path.join(os.path.dirname(__file__), '..', 'whisperx_config.json')
    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2)