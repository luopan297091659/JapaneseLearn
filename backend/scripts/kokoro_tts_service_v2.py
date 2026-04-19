
"""Kokoro-ONNX TTS 微服务 (改进版 - 集成 Microsoft Edge-TTS)
支持实时音频合成和多并发请求
在中国大陆可直接访问

启动: python kokoro_tts_service_v2.py
或: uvicorn kokoro_tts_service_v2:app --host 0.0.0.0 --port 8010 --workers 1

依赖: pip install fastapi uvicorn pydantic edge-tts
"""

import os
import sys
import asyncio
import tempfile
import uuid
from pathlib import Path
from typing import Optional

try:
    from fastapi import FastAPI, HTTPException, BackgroundTasks
    from fastapi.responses import FileResponse, JSONResponse
    from pydantic import BaseModel
    import uvicorn
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install fastapi uvicorn pydantic")
    sys.exit(1)

# 尝试导入Edge-TTS
try:
    import edge_tts
    HAS_EDGE_TTS = True
except ImportError:
    HAS_EDGE_TTS = False
    print("[WARNING] edge-tts not installed")
    print("         Install with: pip install edge-tts")

# 尝试导入gTTS
try:
    from gtts import gTTS
    HAS_GTTS = True
except ImportError:
    HAS_GTTS = False
    print("[WARNING] gtts not installed")
    print("         Install with: pip install gtts")

# 尝试导入Google TTS
try:
    from google.cloud import texttospeech
    HAS_GOOGLE_TTS = True
except ImportError:
    HAS_GOOGLE_TTS = False
    print("[WARNING] google-cloud-texttospeech not installed")
    print("         Install with: pip install google-cloud-texttospeech")

app = FastAPI(title="Kokoro TTS Service", version="2.0.0")

# ─── 配置 ────────────────────────────────────────────────────────────────
CONFIG = {
    "enabled": True,
    "default_voice": "a",
    "default_emotion": "neutral",
    "tts_engine": os.getenv("TTS_ENGINE", "edge-tts"),  # 可配置: edge-tts, gtts, google-tts, white-noise
    "audio_format": os.getenv("AUDIO_FORMAT", "mp3"),  # 输出格式: mp3(默认,兼容性最好) 或 wav
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

# TTS 可用性标志
KOKORO_AVAILABLE = True

# Google TTS 客户端
google_tts_client = None
if HAS_GOOGLE_TTS:
    try:
        # 需要设置 GOOGLE_APPLICATION_CREDENTIALS 环境变量指向JSON密钥文件
        google_tts_client = texttospeech.TextToSpeechClient()
        print("[✓] Google TTS client initialized")
    except Exception as e:
        print(f"[!] Failed to initialize Google TTS: {e}")
        HAS_GOOGLE_TTS = False

# ─── 真实 TTS 实现 ────────────────────────────────────────────────────────
class RealTTS:

    def __init__(self, voice: str, emotion: str, engine: str = None):
        self.voice = voice
        self.emotion = emotion
        self.engine = engine or CONFIG.get("tts_engine", "edge-tts")
        
        # 映射Kokoro人声到各个TTS引擎
        self.edge_voice_map = {
            "a": "ja-JP-NanamiNeural",      # 女声
            "b": "ja-JP-NanamiNeural",      # 女声
            "c": "ja-JP-KeitaNeural",       # 男声
        }
        self.google_voice_map = {
            "a": "ja-JP-Neural2-A",  # 女声
            "b": "ja-JP-Neural2-B",  # 女声
            "c": "ja-JP-Neural2-C",  # 男声
        }
        
        self.edge_voice = self.edge_voice_map.get(voice, "ja-JP-NanamiNeural")
        self.google_voice = self.google_voice_map.get(voice, "ja-JP-Neural2-A")
        
        print(f"RealTTS instance created: voice={voice}, emotion={emotion}, engine={self.engine}")
    
    def synthesize(self, text: str, speed: float = 1.0) -> bytes:
        """根据配置的TTS引擎合成音频"""
        
        # 根据引擎选择合成方法
        if self.engine == "edge-tts":
            try:
                return self._synthesize_edge(text, speed)
            except Exception as e:
                print(f"[!] Edge-TTS failed: {e}")
        elif self.engine == "gtts":
            try:
                return self._synthesize_gtts(text, speed)
            except Exception as e:
                print(f"[!] gTTS failed: {e}")
        elif self.engine == "google-tts":
            try:
                return self._synthesize_google(text, speed)
            except Exception as e:
                print(f"[!] Google TTS failed: {e}")
        elif self.engine == "white-noise":
            print(f"[*] Using configured white-noise fallback")
            return self._synthesize_fallback(text, speed)
        
        # 默认fallback
        print("[WARNING] Unsupported engine, falling back to white noise")
        return self._synthesize_fallback(text, speed)
    
    def _synthesize_edge(self, text: str, speed: float) -> bytes:
        """使用Microsoft Edge-TTS 异步调用"""
        try:
            import edge_tts
            import asyncio
            
            print(f"[*] Using Edge-TTS to synthesize: text_len={len(text)}, speed={speed}")
            
            # 创建异步任务
            async def get_audio():
                # Edge-TTS的速度参数是+/-50%范围
                # speed 0.5 -> rate=-50%, speed 2.0 -> rate=+100%
                rate = int((speed - 1.0) * 100)  # 转换为百分比
                rate = max(-50, min(100, rate))  # 限制在-50%到+100%
                
                print(f"[DEBUG] Creating Edge-TTS communicate object, voice={self.edge_voice}, rate={rate}%")
                
                communicate = edge_tts.Communicate(
                    text=text,
                    voice=self.edge_voice,
                    rate=f"{rate:+d}%"
                )
                
                audio_data = b''
                async for chunk in communicate.stream():
                    if chunk['type'] == 'audio':
                        audio_data += chunk['data']
                return audio_data
            
            # 运行异步函数 - 确保在新event loop中运行（通常在线程中调用）
            try:
                loop = asyncio.get_running_loop()
                # 不应该在这里有running loop，如果有说明被错误地调用了
                raise Exception("Cannot run in existing event loop context")
            except RuntimeError:
                # 正常情况：没有running loop，创建新的
                pass
            
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                audio_bytes = loop.run_until_complete(get_audio())
            finally:
                loop.close()
            
            print(f"[✓] Edge-TTS synthesis successful: {len(audio_bytes)} bytes")
            return audio_bytes
        except ImportError as e:
            raise Exception(f"edge-tts not installed: {e}")
        except Exception as e:
            raise Exception(f"Edge-TTS synthesis failed: {str(e)}")
    
    def _synthesize_gtts(self, text: str, speed: float) -> bytes:
        """使用gTTS库 轻量级Google TTS"""
        try:
            from gtts import gTTS
            import io
            
            print(f"[*] Using gTTS to synthesize: text_len={len(text)}, speed={speed}")
            
            slow_mode = speed < 0.8
            tts = gTTS(text=text, lang='ja', slow=slow_mode, tld='com')
            
            fp = io.BytesIO()
            tts.write_to_fp(fp)
            fp.seek(0)
            audio_bytes = fp.read()
            
            print(f"[✓] gTTS synthesis successful: {len(audio_bytes)} bytes")
            return audio_bytes
        except ImportError:
            raise Exception("gTTS not installed. Install with: pip install gtts")
        except Exception as e:
            raise Exception(f"gTTS synthesis failed: {str(e)}")
    
    def _synthesize_google(self, text: str, speed: float) -> bytes:
        """使用Google Cloud TTS(需要密钥)"""
        try:
            from google.cloud import texttospeech
            
            if not HAS_GOOGLE_TTS:
                raise Exception("Google TTS not initialized")
            
            print(f"[*] Using Google TTS to synthesize: text_len={len(text)}, speed={speed}")
            
            synthesis_input = texttospeech.SynthesisInput(text=text)
            voice = texttospeech.VoiceSelectionParams(
                language_code="ja-JP",
                name=self.google_voice,
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.LINEAR16,
                speaking_rate=speed,
                pitch=0.0,
            )
            
            response = google_tts_client.synthesize_speech(
                input=synthesis_input,
                voice=voice,
                audio_config=audio_config,
            )
            
            print(f"[✓] Google TTS synthesis successful: {len(response.audio_content)} bytes")
            return response.audio_content
        except ImportError:
            raise Exception("google-cloud-texttospeech not installed")
        except Exception as e:
            raise Exception(f"Google TTS synthesis failed: {str(e)}")
    
    def _synthesize_fallback(self, text: str, speed: float) -> bytes:
        """降级方案:白噪声(当没有TTS引擎时)"""
        import struct
        import random
        
        sample_rate = 24000
        duration_ms = int(len(text) * 50 / speed)
        num_samples = int(sample_rate * duration_ms / 1000)
        
        # WAV文件头
        wav_header = bytearray()
        wav_header.extend(b'RIFF')
        wav_header.extend(struct.pack('<I', 36 + num_samples * 2))
        wav_header.extend(b'WAVE')
        wav_header.extend(b'fmt ')
        wav_header.extend(struct.pack('<I', 16))
        wav_header.extend(struct.pack('<HHIIHH', 1, 1, sample_rate, sample_rate * 2, 2, 16))
        wav_header.extend(b'data')
        wav_header.extend(struct.pack('<I', num_samples * 2))
        
        # 白噪声
        audio_data = bytearray()
        for _ in range(num_samples):
            sample = random.randint(-100, 100)
            audio_data.extend(struct.pack('<h', sample))
        
        return bytes(wav_header) + bytes(audio_data)

# ─── TTS 实例池 ────────────────────────────────────────────────────────────
tts_instances = {}
tts_lock = asyncio.Lock()

def get_tts_instance(voice: str, emotion: str, engine: str = None):
    """获取或创建 TTS 实例"""
    engine = engine or CONFIG.get("tts_engine", "edge-tts")
    key = f"{voice}_{emotion}_{engine}"
    if key not in tts_instances:
        try:
            tts_instances[key] = RealTTS(voice, emotion, engine=engine)
        except Exception as e:
            raise Exception(f"Failed to create TTS instance: {e}")
    return tts_instances[key]

# ─── 数据模型 ────────────────────────────────────────────────────────────
class TTSRequest(BaseModel):
    text: str
    voice: str = CONFIG["default_voice"]
    emotion: str = CONFIG["default_emotion"]
    speed: float = 1.0
    engine: str = None  # 可选:指定TTS引擎(edge-tts, gtts, google-tts, white-noise)

class TTSResponse(BaseModel):
    audio_url: str
    voice: str
    emotion: str

class BatchTTSRequest(BaseModel):
    texts: list
    voice: str = CONFIG["default_voice"]
    emotion: str = CONFIG["default_emotion"]
    speed: float = 1.0
    engine: str = None  # 可选:指定TTS引擎

class BatchTTSResult(BaseModel):
    text: str
    success: bool
    audio_url: str = None
    error: str = None

class BatchTTSResponse(BaseModel):
    results: list
    summary: dict  # {total, success, failed}

# ─── API 端点 ────────────────────────────────────────────────────────────

@app.get("/health")
async def health_check():

    return {
        "status": "ok",
        "service": "Kokoro TTS v2",
        "voices": list(CONFIG["voices"].keys()),
        "available_engines": ["edge-tts", "gtts", "google-tts", "white-noise"],
        "configured_engine": CONFIG.get("tts_engine", "edge-tts"),
        "audio_format": CONFIG.get("audio_format", "mp3"),
        "note": "Engine can be customized per request or via TTS_ENGINE env var",
    }

@app.get("/api/v1/tts/voices")
async def get_voices():

    return {
        "default_voice": CONFIG["default_voice"],
        "default_emotion": CONFIG["default_emotion"],
        "voices": CONFIG["voices"],
        "available_engines": ["edge-tts", "gtts", "google-tts", "white-noise"],
        "configured_engine": CONFIG.get("tts_engine", "edge-tts"),
        "note": "Specify 'engine' parameter in /api/v1/tts/kokoro request to override",
    }

@app.post("/api/v1/tts/kokoro", response_model=TTSResponse)
async def kokoro_tts_api(req: TTSRequest, background_tasks: BackgroundTasks):

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
        # 在线程池中运行合成，避免blocking FastAPI的async event loop
        def synthesize_sync():
            tts = get_tts_instance(req.voice, req.emotion, engine=req.engine)
            return tts.synthesize(req.text, speed=req.speed)
        
        # 使用asyncio.to_thread在线程池中运行，避免event loop冲突
        audio_bytes = await asyncio.to_thread(synthesize_sync)
        
        # 保存到临时文件（根据配置决定格式）
        audio_fmt = CONFIG.get("audio_format", "mp3")
        filename = f"kokoro_{uuid.uuid4().hex}.{audio_fmt}"
        file_path = TEMP_AUDIO_DIR / filename
        
        with open(file_path, "wb") as f:
            f.write(audio_bytes)
        
        # 后台清理(1小时后删除)
        background_tasks.add_task(cleanup_file, str(file_path), delay=3600)
        
        return TTSResponse(
            audio_url=f"/api/v1/tts/kokoro/audio/{filename}",
            voice=req.voice,
            emotion=req.emotion,
        )
    except Exception as e:
        print(f"TTS Error: {e}")
        raise HTTPException(status_code=500, detail=f"TTS synthesis failed: {str(e)}")

async def synthesize_single(text: str, voice: str, emotion: str, engine: str, speed: float, background_tasks: BackgroundTasks) -> BatchTTSResult:
    """异步合成单个文本 (带超时保护)"""
    if not text or len(text.strip()) == 0:
        return BatchTTSResult(
            text=text,
            success=False,
            error="Text cannot be empty"
        )
    
    try:
        # 在线程池中运行合成（IO密集型），单个文本超时设为15秒
        def synthesize_sync():
            tts = get_tts_instance(voice, emotion, engine=engine)
            return tts.synthesize(text, speed=speed)
        
        # 单个文本的超时: 15秒
        audio_bytes = await asyncio.wait_for(
            asyncio.to_thread(synthesize_sync),
            timeout=15.0
        )
        
        # 保存到临时文件（根据配置决定格式）
        audio_fmt = CONFIG.get("audio_format", "mp3")
        filename = f"kokoro_{uuid.uuid4().hex}.{audio_fmt}"
        file_path = TEMP_AUDIO_DIR / filename
        
        with open(file_path, "wb") as f:
            f.write(audio_bytes)
        
        # 后台清理(1小时后删除)
        background_tasks.add_task(cleanup_file, str(file_path), delay=3600)
        
        return BatchTTSResult(
            text=text,
            success=True,
            audio_url=f"/api/v1/tts/kokoro/audio/{filename}"
        )
        
    except asyncio.TimeoutError:
        print(f"[!] TTS timeout for text '{text[:50]}...'")
        return BatchTTSResult(
            text=text,
            success=False,
            error="Synthesis timeout (15s exceeded)"
        )
    except Exception as e:
        print(f"[!] Batch TTS Error for text '{text[:50]}...': {e}")
        return BatchTTSResult(
            text=text,
            success=False,
            error=str(e)
        )

@app.post("/api/v1/tts/batch-generate", response_model=BatchTTSResponse)
async def batch_tts_api(req: BatchTTSRequest, background_tasks: BackgroundTasks):
    """批量生成TTS音频 (并发处理，启用超时保护)"""
    if not KOKORO_AVAILABLE:
        raise HTTPException(status_code=503, detail="Kokoro TTS service not available")
    
    # 参数验证
    if not req.texts or len(req.texts) == 0:
        raise HTTPException(status_code=400, detail="Texts list cannot be empty")
    
    if req.voice not in CONFIG["voices"]:
        raise HTTPException(status_code=400, detail=f"Invalid voice: {req.voice}")
    
    if req.emotion not in CONFIG["voices"][req.voice]["supported_emotions"]:
        raise HTTPException(status_code=400, detail=f"Invalid emotion for voice {req.voice}")
    
    if not (0.5 <= req.speed <= 2.0):
        raise HTTPException(status_code=400, detail="Speed must be between 0.5 and 2.0")
    
    print(f"[*] Batch TTS: Starting to synthesize {len(req.texts)} texts (concurrent)")
    
    # 使用 asyncio.gather 并发处理所有文本 (最多同时3个)
    # 这避免了顺序处理的低效，提速显著
    semaphore = asyncio.Semaphore(3)  # 最多同时合成3个文本
    
    # 计算整体超时: 每个文本约需5秒 (含网络开销), 加上20秒的buffer
    total_timeout = max(30, len(req.texts) * 5 + 20)
    
    async def bounded_synthesize(text):
        async with semaphore:
            return await synthesize_single(text, req.voice, req.emotion, req.engine, req.speed, background_tasks)
    
    try:
        # 并发运行所有合成任务，且加上总体超时保护
        tasks = [bounded_synthesize(text) for text in req.texts]
        results = await asyncio.wait_for(
            asyncio.gather(*tasks),
            timeout=total_timeout
        )
    except asyncio.TimeoutError:
        print(f"[!] Batch TTS timeout after {total_timeout}s")
        # 返回已完成的结果（可能不完整）
        raise HTTPException(
            status_code=504, 
            detail=f"Batch generation timeout: {total_timeout}s exceeded for {len(req.texts)} texts"
        )
    
    # 统计结果
    success_count = sum(1 for r in results if r.success)
    failed_count = len(results) - success_count
    
    print(f"[✓] Batch TTS: Synthesized {success_count}/{len(req.texts)} successfully, {failed_count} failed")
    
    return BatchTTSResponse(
        results=results,
        summary={
            "total": len(req.texts),
            "success": success_count,
            "failed": failed_count
        }
    )

@app.get("/api/v1/tts/kokoro/audio/{filename}")
async def get_audio(filename: str):
    try:
        file_path = TEMP_AUDIO_DIR / filename
        if not file_path.exists():
            raise HTTPException(status_code=404, detail="Audio file not found")
        
        # 根据文件扩展名返回正确的Content-Type
        media_type = "audio/mpeg" if filename.endswith(".mp3") else "audio/wav"
        return FileResponse(
            path=file_path,
            media_type=media_type,
            headers={"Cache-Control": "public, max-age=86400"}
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ─── 工具函数 ────────────────────────────────────────────────────────────

async def cleanup_file(file_path: str, delay: int = 3600):

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

    print(f"\n{'='*60}")
    print(f"  Kokoro TTS Service v2.0.0 Starting")
    print(f"{'='*60}")
    print(f"  TTS Engine: Microsoft Edge-TTS (Primary)")
    print(f"  Region: Works in China Mainland (No proxy needed)")
    print(f"  Voices: {', '.join(CONFIG['voices'].keys())}")
    print(f"  Temp Audio Dir: {TEMP_AUDIO_DIR}")
    print(f"{'='*60}\n")

# ─── 主函数 ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.getenv("KOKORO_PORT", CONFIG["port"]))
    host = os.getenv("KOKORO_HOST", CONFIG["host"])
    
    print(f"Starting Kokoro TTS Service v2.0.0 on {host}:{port}")
    print(f"TTS Engine: Microsoft Edge-TTS (Primary) - Works in China Mainland\n")
    
    uvicorn.run(
        app,
        host=host,
        port=port,
        workers=1,
        log_level="info",
    )
