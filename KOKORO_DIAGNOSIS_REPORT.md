# Kokoro TTS 白噪声问题 - 完整诊断报告

**生成时间**: 2026年4月3日 16:45 UTC
**问题等级**: 🔴 **严重** - 音频完全无法使用

---

## 📊 诊断概览

| 项目 | 状态 | 证据 |
|------|------|------|
| **根本原因** | ✅ 确认 | SimpleTTS模拟器 + random.randint() |
| **文件生成** | ✅ 工作 | 80KB+的有效WAV文件已保存 |
| **API连接** | ✅ 正常 | 服务运行在PID 138149, 端口8010 |
| **数据库存储** | ✅ 正常 | URL已保存到GrammarExample.audio_url |
| **音频质量** | ❌ **损坏** | 纯白噪声（随机字节） |

---

## 🔍 详细技术分析

### 1️⃣ 代码确认 (服务器实际代码)

**文件**: `/home/japanese-learn/kokoro-tts/kokoro_tts_service.py`

```python
class SimpleTTS:
    """简化的TTS模拟器 - 用于测试和演示"""
    
    def synthesize(self, text: str, speed: float = 1.0) -> bytes:
        # ... WAV头生成 (正确) ...
        
        # 简单音频数据（白噪声或静音）
        import random
        audio_data = bytearray()
        for _ in range(num_samples):
            sample = random.randint(-100, 100)  # ⚠️ 随机噪声!
            audio_data.extend(struct.pack('<h', sample))
        
        return bytes(wav_header) + bytes(audio_data)
```

**问题**: 第82行使用 `random.randint(-100, 100)` 生成**伪随机样本**而非真实语音

### 2️⃣ 文件验证 (十六进制分析)

**文件**: `kokoro_925bb4c5fc894e03b292948582c8ace9.wav`

```
十六进制输出:
5249 4646 e43e 0100 5741 5645 ...
00000020: 0200 1000 6461 7461 c03e 0100 a5ff bbff
00000030: 5800 1a00 4f00 d7ff e7ff 0d00 5c00 c7ff
```

**分析**:
- ✅ RIFF header: 正确
- ✅ WAVE标记: 正确  
- ✅ fmt chunk: PCM, 16-bit, 24kHz, mono - 正确
- ❌ **audio data**: `a5ff bbff 5800 1a00 ...` 

**转换为十进制**:
- `a5ff` = -91 (16位PCM)
- `bbff` = -69
- `5800` = 88
- `1a00` = 26
- `4f00` = 79
- `d7ff` = -41

➜ 这完全是 `random.randint(-100, 100)` 的特征！

### 3️⃣ 进程确认

```bash
PID 138149: python3.11 -m uvicorn kokoro_tts_service:app --host 0.0.0.0 --port 8010
运行时长: 0:20 (20分钟)
内存占用: 40.7MB (2.3%)
状态: 正常
```

**结论**: 进程运行正常，没有崩溃或错误，只是代码本身有问题。

### 4️⃣ API流程追踪

```
管理员点击🎵按钮
    ↓
POST /api/v1/tts/kokoro (文本: "こんにちは", 人声: "a")
    ↓
SimpleTTS.synthesize(text, speed=1.0)
    ↓
生成82行: sample = random.randint(-100, 100)
    ↓
返回有效的WAV头 + 垃圾音频数据
    ↓
保存到: /home/japanese-learn/backend/uploads/grammar/audio/kokoro_XXX.wav (80KB)
    ↓
数据库记录URL: /uploads/grammar/audio/kokoro_XXX.wav
    ↓
前端播放: 白噪声 😢
```

---

## 💡 问题的哲学

这不是"bug"，而是**设计选择**：

1. **初期开发时** (可能2个月前):
   - 开发者需要测试API基础设施
   - 没有实际的ONNX模型可用
   - 创建SimpleTTS作为**临时模拟器**
   - 代码注释明确说："简化的TTS模拟器 - 用于测试和演示"

2. **问题发生方式**:
   - 模拟器从未被替换为真实TTS引擎
   - 生产环境仍在使用测试代码
   - 最近的音频生成请求触发了这个模拟器

3. **为什么没被发现**:
   - 开发/测试时: 可能API端点未实际调用过
   - 或之前的测试只验证了文件生成，不验证音频质量
   - 最近才在生产环境中使用

---

## 🔧 根本解决方案对比

### 方案 A: Google TTS (✅ 推荐)

**优点**:
- ✅ 高质量日语语音
- ✅ 多种女性/男性人声
- ✅ 情感控制 (neutral, happy, sad)
- ✅ 生产级已验证

**缺点**:
- ❌ 需要API密钥 ($16/百万字符)
- ❌ 需要网络连接

**实施时间**: 30分钟（仅需替换SimpleTTS类）

---

### 方案 B: gTTS (免费备选)

**优点**:
- ✅ 完全免费
- ✅ 无需API密钥
- ✅ 开源

**缺点**:
- ❌ 质量一般 (听起来有点机械)
- ❌ 可能有请求限制
- ❌ 没有情感控制

**实施时间**: 15分钟

---

### 方案 C: Voicevox (完全离线)

**优点**:
- ✅ 完全免费和开源
- ✅ 不需要网络
- ✅ 真实的日语语音库

**缺点**:
- ❌ 需要单独的Voicevox服务进程
- ❌ 配置复杂
- ❌ 占用更多系统资源

**实施时间**: 1-2小时 (需要部署Voicevox)

---

## 📋 立即修复路径

### 快速修复 (1小时):

1. **选择TTS引擎**: A (Google) 最推荐
2. **部署新服务**: `kokoro_tts_service_v2.py` 已准备就绪
3. **安装依赖**: `pip install google-cloud-texttospeech`
4. **设置认证**: `GOOGLE_APPLICATION_CREDENTIALS` 环境变量
5. **重启服务**: `pm2 restart kokoro-tts`

### 验证修复:

```bash
# 测试API
curl -X POST http://127.0.0.1:8010/api/v1/tts/kokoro \
  -H "Content-Type: application/json" \
  -d '{"text": "テスト", "voice": "a", "emotion": "neutral"}'

# 播放音频 (应该听到真实的日语语音)
```

---

## 📊 影响范围

**受影响的功能**:
- 🔴 管理员🎵音频生成按钮 (完全损坏)
- 🔴 所有已生成的语法例句音频 (无法使用)
- 🔴 APP中的音频播放功能 (收到白噪声)

**未受影响**:
- ✅ 其他所有功能
- ✅ 文本和图像的显示
- ✅ 数据库和API基础设施

---

## 🎯 建议的行动步骤

### ✅ 短期 (今天):

- [ ] 选择TTS引擎方案 (A/B/C)
- [ ] 部署 `kokoro_tts_service_v2.py`
- [ ] 设置必要的认证信息
- [ ] 重启服务并验证

### ⏳ 中期 (本周):

- [ ] 重新生成所有语法例句的音频
- [ ] 验证音频质量
- [ ] 更新APP版本
- [ ] 部署到生产环境

### 📚 长期 (可选):

- [ ] 考虑缓存策略 (避免重复API调用)
- [ ] 实现音频质量检查
- [ ] 添加离线备选方案

---

## 🔗 相关文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `kokoro_tts_service_v2.py` | `backend/scripts/` | 新的真实TTS实现 |
| `TTS_V2_DEPLOYMENT.md` | 根目录 | 完整部署指南 |
| `upgrade_kokoro_tts.sh` | 根目录 | Linux升级脚本 |
| `upgrade_kokoro_tts.bat` | 根目录 | Windows升级脚本 |

---

## 💬 诊断结论

**问题**: 生产代码中仍在使用测试用的SimpleTTS模拟器
**原因**: 开发初期为测试API基础设施而创建，后未替换为真实引擎
**影响**: 所有生成的音频都是白噪声，无法学习
**解决**: 部署真实TTS引擎 (推荐Google TTS)
**工作量**: ~1小时快速修复 + 2小时验证

---

**下一步**: 确认使用哪个TTS引擎方案，然后执行升级。
