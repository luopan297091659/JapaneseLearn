#!/bin/bash

# 测试Kokoro TTS服务

echo "=== 测试 Kokoro TTS 服务 ==="

# 检查Kokoro Python服务是否运行
echo ""
echo "[1] 检查 Kokoro 服务健康状况 (端口 8010)..."
curl -s http://139.196.44.6:8010/health | jq . || echo "无响应"

# 获取可用人声列表
echo ""
echo "[2] 获取可用人声列表..."
curl -s http://139.196.44.6:8010/api/v1/tts/voices | jq . || echo "获取失败"

# 测试Kokoro合成
echo ""
echo "[3] 测试 Kokoro 合成 (日文文本)..."
curl -s -X POST http://139.196.44.6:8010/api/v1/tts/kokoro \
  -H "Content-Type: application/json" \
  -d '{"text":"こんにちは","voice":"a","emotion":"neutral","speed":1.0}' | jq .

# 测试后端代理节点
echo ""
echo "[4] 测试后端 Node.js 代理 (端口 8002)..."
curl -s -k https://139.196.44.6:8002/api/v1/tts/health | jq .

# 测试后端合成端点
echo ""
echo "[5] 测试后端 Kokoro-speak 端点..."
curl -s -k -X POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak \
  -H "Content-Type: application/json" \
  -d '{"text":"ありがとうございます","voice":"a","emotion":"neutral","speed":1.0}' | jq .

# 测试admin配置端点
echo ""
echo "[6] 测试管理员 Kokoro 配置端点..."
curl -s -k https://139.196.44.6:8002/api/v1/admin/settings/kokoro \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" | jq .

echo ""
echo "=== 测试完成 ==="
