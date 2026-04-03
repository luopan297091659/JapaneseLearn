#!/bin/bash
# Kokoro TTS v2.0 快速升级脚本
# 使用方式: bash upgrade_kokoro_tts.sh

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Kokoro TTS v2.0 升级脚本 (白噪声 → 真实语音)       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_SCRIPTS="$PROJECT_ROOT/backend/scripts"

echo "📁 项目路径: $PROJECT_ROOT"
echo ""

# 步骤 1: 备份旧文件
echo "📦 步骤 1: 备份旧服务文件..."
if [ -f "$BACKEND_SCRIPTS/kokoro_tts_service.py" ]; then
    mv "$BACKEND_SCRIPTS/kokoro_tts_service.py" "$BACKEND_SCRIPTS/kokoro_tts_service.py.backup-$(date +%Y%m%d-%H%M%S)"
    echo -e "${GREEN}✓${NC} 旧文件已备份"
else
    echo -e "${YELLOW}⚠${NC} 未找到旧服务文件"
fi

# 步骤 2: 复制新文件
echo ""
echo "📝 步骤 2: 部署新服务文件..."
cp "$BACKEND_SCRIPTS/kokoro_tts_service_v2.py" "$BACKEND_SCRIPTS/kokoro_tts_service.py"
echo -e "${GREEN}✓${NC} 新服务文件已部署"

# 步骤 3: 安装依赖
echo ""
echo "📚 步骤 3: 安装Python依赖..."
echo "   选项 A: Google TTS (推荐，需要API密钥)"
echo "   选项 B: gTTS (免费，质量一般)"
echo ""
read -p "请选择 [A/B] (默认: A): " tts_choice
tts_choice=${tts_choice:-A}

if [[ "$tts_choice" == "A" || "$tts_choice" == "a" ]]; then
    pip install google-cloud-texttospeech uvicorn fastapi pydantic gtts
    echo -e "${GREEN}✓${NC} Google TTS + gTTS 备选已安装"
    echo ""
    echo "⚠️  重要: 需要设置 Google 认证密钥"
    echo "   https://console.cloud.google.com/ → 创建服务账户 → 下载 JSON 密钥"
    echo "   然后设置环境变量:"
    echo "   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/google-creds.json"
else
    pip install gtts uvicorn fastapi pydantic
    echo -e "${GREEN}✓${NC} gTTS 已安装 (使用免费配额)"
fi

# 步骤 4: 询问是否启动服务
echo ""
echo "🚀 步骤 4: 启动新服务..."
read -p "是否现在启动 Kokoro TTS v2 服务? [y/n] (默认: y): " start_choice
start_choice=${start_choice:-y}

if [[ "$start_choice" == "y" || "$start_choice" == "Y" ]]; then
    # 停止旧服务
    echo "   正在停止旧服务..."
    pm2 stop kokoro-tts 2>/dev/null || true
    pm2 delete kokoro-tts 2>/dev/null || true
    
    # 或杀死直接运行的进程
    pkill -f "kokoro_tts_service.py" 2>/dev/null || true
    
    sleep 2
    
    # 启动新服务
    cd "$BACKEND_SCRIPTS"
    
    echo "   启动 Kokoro TTS v2..."
    if command -v pm2 &> /dev/null; then
        pm2 start kokoro_tts_service.py --name kokoro-tts -i 1 --interpreter python
        pm2 logs kokoro-tts
    else
        echo -e "${YELLOW}⚠${NC} PM2 未安装，使用直接运行模式"
        python kokoro_tts_service.py
    fi
else
    echo "   跳过启动，稍后手动启动"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    升级完成! ✨                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 后续步骤:"
echo "   1. 测试服务: curl http://127.0.0.1:8010/health"
echo "   2. 检查日志: pm2 logs kokoro-tts"
echo "   3. 生成音频: 在管理员面板点击 🎵 按钮"
echo ""
echo "❓ 需要帮助?"
echo "   - 查看完整文档: TTS_V2_DEPLOYMENT.md"
echo "   - 常见问题: TTS_V2_DEPLOYMENT.md#故障排除"
echo ""
