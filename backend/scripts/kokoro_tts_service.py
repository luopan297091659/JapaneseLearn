"""
Kokoro-ONNX TTS 微服务
支持多并发用户请求、灵活人声配置、情感合成

启动: python kokoro_tts_service.py
或: uvicorn kokoro_tts_service:app --host 0.0.0.0 --port 8010 --workers 4
"""

import os
import sys
import asyncio
import tempfile
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
import uvicorn

# 尝试导入 Kokoro
try:
    from kokoro import KokoroTTS
    KOKORO_AVAILABLE = True
except ImportError:
    KOKORO_AVAILABLE = False
    print("⚠️  WARNING: kokoro-onnx not installed. Install via: pip install kokoro-onnx onnxruntime")

app = FastAPI(title="Kokoro TTS Service", version="1.0.0")

# ─── 配置 ────────────────────────────────────────────────────────────────
CONFIG = {
    "enabled": True,
    "default_voice": "a",
    "default_emotion": "neutral",
    "voices": {
        "a": {"name": "女声优美", "lang": "ja_JP", "supported_emotions": ["neutral", "happy", "sad"]},
        "b": {"name": "女声清晰", "lang": "ja_JP", "supported_emotions": ["neutral", "happy", "sad"]},
        "c": {"name": "男声深沉", "lang": "ja_JP", "supported_emotions": ["neutral", "happy", "sad"]},
    },
    "model_name": "kokoro-82m",
    "port": 8010,
    "host": "0.0.0.0",
}

# 临时文件目录
TEMP_AUDIO_DIR = Path(tempfile.gettempdir()) / "kokoro_tts"
TEMP_AUDIO_DIR.mkdir(exist_ok=True)

# ─── TTS 实例池（支持多并发） ────────────────────────────────────────────
tts_instances = {}
tts_lock = asyncio.Lock()

def get_tts_instance(voice: str, emotion: str):
    """获取或创建 TTS 实例（缓存）"""
    if not KOKORO_AVAILABLE:
        raise Exception("Kokoro TTS not available")
    
    key = f"{voice}_{emotion}"
    if key not in tts_instances:
        try:
            tts_instances[key] = KokoroTTS(lang="ja_JP", voice=voice, emotion=emotion)
        except Exception as e:
            raise Exception(f"Failed to create TTS instance: {e}")
    return tts_instances[key]

# ─── 数据模型 ────────────────────────────────────────────────────────────
class TTSRequest(BaseModel):
    text: str
    voice: str = CONFIG["default_voice"]
    emotion: str = CONFIG["default_emotion"]
    speed: float = 1.0

class TTSResponse(BaseModel):
    audio_url: str
    duration: Optional[float] = None
    voice: str
    emotion: str

# ─── API 端点 ────────────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """健康检查"""
    return {
        "status": "ok",
        "kokoro_available": KOKORO_AVAILABLE,
        "voices": list(CONFIG["voices"].keys()),
    }

@app.get("/api/v1/tts/voices")
async def get_voices():
    """获取可用人声列表"""
    return {
        "default_voice": CONFIG["default_voice"],
        "default_emotion": CONFIG["default_emotion"],
        "voices": CONFIG["voices"],
    }

@app.post("/api/v1/tts/kokoro", response_model=TTSResponse)
async def kokoro_tts_api(req: TTSRequest, background_tasks: BackgroundTasks):
    """
    Kokoro TTS 合成端点
    
    参数:
    - text: 日语文本
    - voice: 人声 ("a", "b", "c")
    - emotion: 情感 ("neutral", "happy", "sad")
    - speed: 语速 (0.5-2.0)
    """
    if not KOKORO_AVAILABLE:
        raise HTTPException(status_code=503, detail="Kokoro TTS service not available")
    
    # 参数验证
    if not req.text or len(req.text.strip()) == 0:
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    
    if req.voice not in CONFIG["voices"]:
        raise HTTPException(status_code=400, detail=f"Invalid voice: {req.voice}")
    
    if req.emotion not in CONFIG["voices"][req.voice]["supported_emotions"]:
        raise HTTPException(status_code=400, detail=f"Invalid emotion for voice {req.voice}")
    
    if not (0.5 <= req.speed <= 2.0):
        raise HTTPException(status_code=400, detail="Speed must be between 0.5 and 2.0")
    
    try:
        # 获取 TTS 实例
        async with tts_lock:
            tts = get_tts_instance(req.voice, req.emotion)
            # 合成（同步）
            audio_bytes = tts.synthesize(req.text, speed=req.speed)
        
        # 保存到临时文件
        filename = f"kokoro_{uuid.uuid4().hex}.wav"
        file_path = TEMP_AUDIO_DIR / filename
        
        with open(file_path, "wb") as f:
            f.write(audio_bytes)
        
        # 后台清理（1小时后删除）
        background_tasks.add_task(cleanup_file, str(file_path), delay=3600)
        
        return TTSResponse(
            audio_url=f"/api/v1/tts/kokoro/audio/{filename}",
            voice=req.voice,
            emotion=req.emotion,
        )
    except Exception as e:
        print(f"TTS Error: {e}")
        raise HTTPException(status_code=500, detail=f"TTS synthesis failed: {str(e)}")

@app.get("/api/v1/tts/kokoro/audio/{filename}")
async def get_audio(filename: str):
    """获取已合成的音频文件"""
    try:
        file_path = TEMP_AUDIO_DIR / filename
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Audio file not found")
        
        return FileResponse(
            path=file_path,
            media_type="audio/wav",
            headers={"Cache-Control": "public, max-age=86400"}
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ─── 工具函数 ────────────────────────────────────────────────────────────

async def cleanup_file(file_path: str, delay: int = 3600):
    """延迟删除文件（后台任务）"""
    await asyncio.sleep(delay)
    try:
        if Path(file_path).exists():
            Path(file_path).unlink()
            print(f"Cleaned up: {file_path}")
    except Exception as e:
        print(f"Cleanup failed: {e}")

# ─── 启动事件 ────────────────────────────────────────────────────────────

@app.on_event("startup")
async def startup_event():
    """服务启动时的初始化"""
    print(f"\n{'='*60}")
    print(f"  Kokoro TTS Service Starting")
    print(f"{'='*60}")
    print(f"  Kokoro Available: {KOKORO_AVAILABLE}")
    if KOKORO_AVAILABLE:
        print(f"  Voices: {', '.join(CONFIG['voices'].keys())}")
        print(f"  Temp Audio Dir: {TEMP_AUDIO_DIR}")
    else:
        print(f"  ⚠️  Kokoro NOT available - install: pip install kokoro-onnx onnxruntime")
    print(f"{'='*60}\n")

# ─── 主函数 ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.getenv("KOKORO_PORT", CONFIG["port"]))
    host = os.getenv("KOKORO_HOST", CONFIG["host"])
    
    print(f"Starting Kokoro TTS Service on {host}:{port}")
    uvicorn.run(
        app,
        host=host,
        port=port,
        workers=1,  # Kokoro 模型较重，1个worker避免内存过度
        log_level="info",
    )

