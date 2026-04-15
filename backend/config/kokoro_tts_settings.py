# Kokoro-ONNX TTS 服务配置 (Python)
KOKORO_TTS = {
    "enabled": True,
    "default_voice": "a",
    "default_emotion": "neutral",
    "voices": {
        "a": {"name": "女声优美", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"]},
        "b": {"name": "女声清晰", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"]},
        "c": {"name": "男声深沉", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"]},
    },
    "model_name": "kokoro-82m",  # 可使用量化版本 "kokoro-82m-q5" 加快速度
    "port": 8010,
    "host": "0.0.0.0",
}
