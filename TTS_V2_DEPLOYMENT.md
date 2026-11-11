# Kokoro TTS v2.0 部署指南

## 问题诊断

旧版 `kokoro_tts_service.py` 是没有语音模型的测试模拟器，不是真正的 Kokoro 推理服务。v2 使用 Edge-TTS，Edge-TTS 失败时尝试 gTTS；两者都失败会返回错误，不再保存伪造的白噪声音频。

日志中出现 `Edge-TTS ... 403` 表示 Edge-TTS 请求被服务端拒绝。旧逻辑会把该错误吞掉，再用 `random.randint()` 生成白噪声；同时生成的 WAV 数据可能被命名为 MP3。请运行更新后的 v2 服务，并在日志中确认 gTTS 回退是否成功。

注意：此服务当前调用 Edge-TTS、gTTS 或 Google TTS，并未加载 Kokoro ONNX 模型。

## 解决方案对比

| 方案 | 优点 | 缺点 | 成本 |
|------|------|------|------|
| **Google TTS** ✅ 推荐 | 高质量日语、多种人声、情感控制 | 需API密钥、需要网络连接 | $0-$50/月 |
| **gTTS** | 开源轻量、无需API密钥 | 质量一般、受限于Google免费配额 | 免费(有限) |
| **Voicevox** | 完全开源、无需API密钥 | 设置复杂、需要额外依赖 | 免费(自托管) |

## 快速部署 (推荐方案: Google TTS)

### 步骤 1: 获取 Google Cloud 认证

```bash
# 方式 A: 使用服务账户密钥 (推荐用于服务器)
# 1. 访问 https://console.cloud.google.com/
# 2. 创建新项目或选择现有项目
# 3. 启用 Text-to-Speech API: https://console.cloud.google.com/apis/library/texttospeech.googleapis.com
# 4. 创建服务账户:
#    - 导航到 IAM & Admin > Service Accounts
#    - 创建新服务账户
#    - 赋予 Editor 权限
#    - 创建 JSON 密钥 → 下载为 google-creds.json

# 方式 B: 使用本地应用默认凭证 (开发环境)
# 运行: gcloud auth application-default login
```

### 步骤 2: 安装依赖

```bash
cd backend/scripts

# 安装 Google TTS
pip install google-cloud-texttospeech uvicorn fastapi pydantic

# 或安装 gTTS 作为备选
pip install gtts

# 推荐: 同时安装两个
pip install google-cloud-texttospeech gtts uvicorn fastapi pydantic
```

### 步骤 3: 配置环境变量

```bash
# Linux/Mac
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/google-creds.json"
export KOKORO_PORT=8010
export KOKORO_HOST=0.0.0.0

# Windows (PowerShell)
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\google-creds.json"
$env:KOKORO_PORT=8010
$env:KOKORO_HOST=0.0.0.0
```

### 步骤 4: 停止旧服务并启动新服务

```bash
# 停止旧的Kokoro服务
pm2 stop kokoro-tts
pm2 delete kokoro-tts

# 或通过PID杀死 (示例)
# kill -9 138149

# 启动新的 v2 服务
cd /home/japanese-learn/kokoro-tts  # 或你的项目路径

# 方法 A: 直接运行 (用于测试)
python kokoro_tts_service_v2.py

# 方法 B: 使用 PM2 管理 (生产环境)
pm2 start kokoro_tts_service_v2.py --name kokoro-tts -i 1

# 方法 C: 使用 systemd (Linux)
# 参见下方 systemd 配置示例
```

### 步骤 5: 验证服务

```bash
# 检查健康状态
curl http://127.0.0.1:8010/health

# 列出可用人声
curl http://127.0.0.1:8010/api/v1/tts/voices

# 测试合成 (返回一个播放URL)
curl -X POST http://127.0.0.1:8010/api/v1/tts/kokoro \
  -H "Content-Type: application/json" \
  -d '{"text": "こんにちは", "voice": "a", "emotion": "neutral", "speed": 1.0}'

# 播放返回的音频 URL
# 响应示例: {"audio_url": "/api/v1/tts/kokoro/audio/kokoro_abc123.wav", ...}
```

## 快速部署 (备选方案: gTTS)

如果无法使用 Google TTS (如API成本考虑)，可以改用轻量级 gTTS:

```bash
pip install gtts uvicorn fastapi pydantic

# 将 gTTS 设为默认引擎 (无需API密钥)
export TTS_ENGINE=gtts
python kokoro_tts_service_v2.py
```

默认引擎仍是 Edge-TTS；若 Edge-TTS 失败，服务会尝试使用 gTTS。gTTS 质量较低，且可能有请求限制。

## PM2 配置 (生产部署)

### 方案 1: ecosystem.config.js

```javascript
module.exports = {
  apps: [
    {
      name: 'kokoro-tts',
      script: 'backend/scripts/kokoro_tts_service_v2.py',
      interpreter: 'python',
      instances: 1,
      env: {
        GOOGLE_APPLICATION_CREDENTIALS: '/path/to/google-creds.json',
        KOKORO_PORT: 8010,
        KOKORO_HOST: '0.0.0.0',
      },
      error_file: './logs/kokoro-tts.log',
      out_file: './logs/kokoro-tts.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      restart_delay: 4000,
      max_restarts: 30,
    },
  ],
};
```

启动:
```bash
pm2 start ecosystem.config.js --only kokoro-tts
pm2 logs kokoro-tts  # 查看日志
```

### 方案 2: Systemd Service (Linux)

创建 `/etc/systemd/system/kokoro-tts.service`:

```ini
[Unit]
Description=Kokoro TTS Service v2
After=network.target

[Service]
Type=simple
User=japanese-learn
WorkingDirectory=/home/japanese-learn/kokoro-tts
ExecStart=/usr/bin/python3 kokoro_tts_service_v2.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="GOOGLE_APPLICATION_CREDENTIALS=/home/japanese-learn/.config/google-creds.json"
Environment="KOKORO_PORT=8010"
Environment="KOKORO_HOST=0.0.0.0"

[Install]
WantedBy=multi-user.target
```

启动:
```bash
sudo systemctl daemon-reload
sudo systemctl enable kokoro-tts
sudo systemctl start kokoro-tts
sudo systemctl status kokoro-tts
```

## 性能优化

### 并发请求处理

v2.0 支持异步处理多个TTS请求:

```bash
# 使用 Gunicorn + Uvicorn (多进程)
# 注意: 需要修改启动命令
# gunicorn kokoro_tts_service_v2:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8010
```

### 缓存和清理

- 临时音频文件保存在 `/tmp/kokoro_tts/` (Linux) 或 `%TEMP%/kokoro_tts` (Windows)
- 文件自动在1小时后清理
- 可在 `RealTTS._synthesize_*()` 方法中调整缓存策略

## 故障排除

### Issue 1: "google-cloud-texttospeech not installed"

```bash
pip install google-cloud-texttospeech
```

### Issue 2: "GOOGLE_APPLICATION_CREDENTIALS not set"

```bash
# 检查环境变量
echo $GOOGLE_APPLICATION_CREDENTIALS  # Linux/Mac
$env:GOOGLE_APPLICATION_CREDENTIALS   # Windows PowerShell

# 设置正确路径
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/google-creds.json"
```

### Issue 3: "Failed to initialize Google TTS"

```log
[!] Failed to initialize Google TTS: 401 Unauthorized
```

- ✅ 确保 `google-creds.json` 正确且有效
- ✅ 验证 Text-to-Speech API 已启用
- ✅ 检查服务账户有适当权限

### Issue 4: 仍然生成白噪声

**可能原因**:
1. 运行的仍是旧版 `kokoro_tts_service.py` 模拟器
2. v2 文件或 Python 服务进程尚未更新
3. 其他服务或旧数据中仍有此前生成的白噪声音频

**解决**:
```bash
# 仅重启 Kokoro TTS 服务，然后确认启动日志显示 TTS Engine
pm2 restart kokoro-tts
pm2 logs kokoro-tts --lines 50
```

若 Edge-TTS 返回 403，查看后续日志中的 gTTS 回退结果；若回退也失败，接口会返回错误，不会生成音频文件。确认部署了更新后的 v2 脚本且安装了 gTTS。

### Issue 5: 连接被拒绝

```
Connection refused: 127.0.0.1:8010
```

```bash
# 检查端口是否开放
netstat -an | grep 8010  # Linux/Mac
netstat -ano | findstr :8010  # Windows

# 检查防火墙
sudo ufw allow 8010  # Linux
```

## 回滚计划 (如需恢复到v1)

```bash
  
pm2 stop kokoro-tts
pm2 delete kokoro-tts

# 恢复旧文件
cp backend/scripts/kokoro_tts_service.py.backup backend/scripts/kokoro_tts_service.py

# 重新启动
pm2 start ecosystem.config.js --only kokoro-tts
```

## 成本估算 (Google TTS)

- **免费额度**: 100万字符/月
- **超额费用**: $16 per 100万字符
- **建议**: 设置配额提醒

## 后续改进

1. **添加文音号自动检测** (当输入多音字时)
2. **集成Voicevox** (作为Google TTS的备选降级方案)
3. **实现本地ONNX模型** (如果需要完全离线)
4. **添加音频质量评分** (防止低质量音频被存储)

---

**文件对照表**:

| 文件 | 位置 | 版本 | 状态 |
|------|------|------|------|
| `kokoro_tts_service.py` | `backend/scripts/` | v1 (旧) | ❌ 无语音模型；现已拒绝生成占位音频 |
| `kokoro_tts_service_v2.py` | `backend/scripts/` | v2 (新) | ✅ Edge-TTS，失败时回退 gTTS |

**推荐升级**: ✅ 立即升级到 v2.0
