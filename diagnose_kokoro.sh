#!/bin/bash
# Kokoro TTS 诊断脚本

echo "=== Kokoro TTS 服务诊断 ==="
echo ""

# 1. 检查 Python 服务是否运行
echo "[1] 检查 Python Kokoro 服务 (port 8010)..."
curl -s http://localhost:8010/health | jq . && echo "✅ Kokoro Python 服务正常" || echo "❌ Kokoro Python 服务异常"

echo ""

# 2. 检查 Node.js 代理是否运行
echo "[2] 检查 Node.js 后端 (port 8002)..."
curl -s http://localhost:8002/api/v1/tts/health | jq . && echo "✅ Node.js 后端正常" || echo "❌ Node.js 后端异常"

echo ""

# 3. 测试完整的 TTS 流程（通过 Node 代理）
echo "[3] 测试完整 TTS 合成流程..."
RESPONSE=$(curl -s -X POST http://localhost:8002/api/v1/tts/kokoro-speak \
  -H "Content-Type: application/json" \
  -d '{
    "text": "こんにちは",
    "voice": "a",
    "emotion": "neutral",
    "speed": 1.0
  }')

echo "响应: $RESPONSE"
AUDIO_URL=$(echo $RESPONSE | jq -r '.audio_url // empty')

if [ -z "$AUDIO_URL" ]; then
  echo "❌ 没有获得 audio_url，TTS 合成失败"
else
  echo "✅ 获得 audio_url: $AUDIO_URL"
  
  # 4. 测试音频文件是否存在
  echo ""
  echo "[4] 检查音频文件..."
  curl -s -I "$AUDIO_URL" | head -5
fi

echo ""
echo "[5] 实时监控 Node.js 日志..."
pm2 logs japanese-learn --lines 20
