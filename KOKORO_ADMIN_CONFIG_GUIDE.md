# Kokoro TTS 管理员配置指南

**日期**: 2026-04-03  
**目标**: 让管理员通过web端配置Kokoro TTS的合成参数

---

## 📋 功能总览

管理员可以在后台面板通过图形界面配置以下Kokoro TTS参数：

| 参数 | 选项 | 默认值 | 说明 |
|------|------|--------|------|
| **启用状态** | 开/关 | 开（✅） | 是否启用Kokoro TTS功能 |
| **人声选择** | a / b / c | a | 👩女优美 / 👩女清晰 / 👨男深沉 |
| **情感合成** | neutral / happy / sad | neutral | 😐自然 / 😊高兴 / 😢伤心 |
| **语速倍数** | 0.5x - 2.0x | 1.0x | 调整朗读速度 |
| **服务URL** | 文本输入 | http://127.0.0.1:8010 | Kokoro Python服务地址 |

---

## 🎯 使用流程

### 第一步：访问管理后台

1. 打开 `https://139.196.44.6:8002/admin`
2. 使用超级管理员账号登录
3. 在左侧菜单"系统"栏目中找到 **🎤 Kokoro TTS** 菜单项

### 第二步：配置参数

#### ✅ 启用/禁用

在顶部找到"启用 Kokoro TTS"开关：
- **开启** ✅ → APP用户播放语法例句时可使用后端合成
- **关闭** ❌ → APP降级使用设备系统TTS或失败提示

#### 🎤 选择人声

三个高度差异化的人声：

```
👩 女优美 (a)
   - 音阶较高，清晰优美
   - 适合日常学习场景
   - 推荐新手使用

👩 女清晰 (b)  
   - 中等音阶，清晰有力
   - 适合听力训练
   - 推荐正式讲述场景

👨 男深沉 (c)
   - 音阶较低，稳重有力
   - 适合对话练习
   - 推荐商务场景
```

#### 😊 选择情感

影响朗读的语气色彩：

```
😐 自然（neutral）
   - 平稳，无特殊感情色彩
   - 最常用，推荐默认选择

😊 高兴（happy）
   - 声调上扬，语速稍快
   - 用于积极上进的内容

😢 伤心（sad）
   - 声调下沉，语速稍慢
   - 用于悲伤或严肃的内容
```

#### ⚡ 调整语速

使用滑块调整朗读速度：

```
0.5x ====|==================== 2.0x
        1.0x (默认标准速度)

推荐值：
- 初学者：0.7x（较慢，便于理解）
- 标准：1.0x（自然速度）
- 快速听力训练：1.3-1.5x
```

---

## 🔧 后端实现详解

### 配置存储方式

配置保存到数据库 `AppConfig` 表：

```javascript
// Key: 'kokoro_tts_settings'
// Value: JSON格式
{
  "enabled": true,
  "default_voice": "a",
  "default_emotion": "neutral",
  "default_speed": 1.0,
  "speed_range": { "min": 0.5, "max": 2.0 },
  "service_url": "http://127.0.0.1:8010"
}
```

### API端点

**获取配置**：
```
GET /api/v1/admin/settings/kokoro
Authorization: Bearer <token>

响应：
{
  "kokoro_tts": {
    "enabled": true,
    "default_voice": "a",
    "default_emotion": "neutral",
    "default_speed": 1.0,
    "voices": {
      "a": { "name": "女声优美", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"] },
      "b": { "name": "女声清晰", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"] },
      "c": { "name": "男声深沉", "lang": "ja_JP", "emotions": ["neutral", "happy", "sad"] }
    },
    "emotions": ["neutral", "happy", "sad"],
    "speed_range": { "min": 0.5, "max": 2.0 }
  },
  "service_url": "http://127.0.0.1:8010"
}
```

**保存配置**：
```
POST /api/v1/admin/settings/kokoro
Authorization: Bearer <token>
Content-Type: application/json

请求体：
{
  "enabled": true,
  "default_voice": "a",
  "default_emotion": "neutral",
  "default_speed": 1.0,
  "service_url": "http://127.0.0.1:8010"
}

响应：
{
  "success": true,
  "settings": { ... }
}
```

### 后端控制器实现

**文件**: `backend/src/controllers/adminController.js`

```javascript
async function getKokoroSettings(req, res) {
  // 1. 设置默认参数
  let kokoroConfig = {
    enabled: true,
    default_voice: 'a',
    default_emotion: 'neutral',
    default_speed: 1.0,
    voices: { a: {...}, b: {...}, c: {...} },
    emotions: ['neutral', 'happy', 'sad'],
  };
  
  // 2. 尝试从数据库读取用户保存的设置
  const kv = await sequelize.models.AppConfig.findOne({
    where: { key: 'kokoro_tts_settings' }
  });
  if (kv && kv.value) {
    const userSettings = JSON.parse(kv.value);
    kokoroConfig = { ...kokoroConfig, ...userSettings };
  }
  
  // 3. 返回配置
  res.json({ kokoro_tts: kokoroConfig, service_url: process.env.KOKORO_SERVICE_URL });
}

async function saveKokoroSettings(req, res) {
  const { enabled, default_voice, default_emotion, default_speed, service_url } = req.body;
  
  // 1. 参数验证
  if (!['a', 'b', 'c'].includes(default_voice)) {
    return res.status(400).json({ error: 'Invalid voice' });
  }
  if (!['neutral', 'happy', 'sad'].includes(default_emotion)) {
    return res.status(400).json({ error: 'Invalid emotion' });
  }
  
  let speed = parseFloat(default_speed) || 1.0;
  speed = Math.max(0.5, Math.min(2.0, speed));  // 约束到0.5-2.0范围
  
  // 2. 保存到数据库
  const settings = {
    enabled: enabled !== false,
    default_voice,
    default_emotion,
    default_speed: speed,
    speed_range: { min: 0.5, max: 2.0 },
    service_url: service_url || 'http://127.0.0.1:8010'
  };
  
  await sequelize.models.AppConfig.upsert({
    key: 'kokoro_tts_settings',
    value: JSON.stringify(settings)
  });
  
  // 3. 返回成功
  res.json({ success: true, settings });
}
```

### TTS合成时使用配置

**文件**: `backend/src/routes/kokoroTts.js`

```javascript
router.post('/kokoro-speak', async (req, res) => {
  const { text, voice, emotion, speed } = req.body;
  
  // 1. 获取管理员配置的默认参数
  let defaultVoice = 'a';
  let defaultEmotion = 'neutral';
  let defaultSpeed = 1.0;
  
  try {
    const kv = await sequelize.models.AppConfig.findOne({
      where: { key: 'kokoro_tts_settings' }
    });
    if (kv && kv.value) {
      const kokoroConfig = JSON.parse(kv.value);
      defaultVoice = kokoroConfig.default_voice || 'a';
      defaultEmotion = kokoroConfig.default_emotion || 'neutral';
      defaultSpeed = kokoroConfig.default_speed || 1.0;
    }
  } catch (_) {}
  
  // 2. 使用APP请求的参数，若未提供则使用默认值
  const resp = await axios.post(
    `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
    {
      text: text.trim(),
      voice: voice || defaultVoice,           // ← 使用默认人声
      emotion: emotion || defaultEmotion,     // ← 使用默认情感
      speed: Math.max(0.5, Math.min(2.0, parseFloat(speed) || defaultSpeed)), // ← 使用默认速度
    },
    { timeout: 30000 }
  );
  
  // 3. 返回响应
  res.json({
    audio_url: resp.data.audio_url,
    voice: resp.data.voice,
    emotion: resp.data.emotion,
  });
});
```

---

## 📱 APP侧对接

### 第3层Kokoro合成流程

APP在 `mobile/lib/utils/tts_helper.dart` 中集成了3层降级策略：

```dart
// 第1层：本地预录音频或远程URL
if (audioUrl != null && audioUrl.isNotEmpty) {
  await playLocalAudio(audioUrl);
  return;
}

// 第2层：设备系统TTS（安装了日语引擎时）
if (await ttsInst.speak(text)) {
  return;  // ← 若成功，不调用Kokoro
}

// 第3层：后端Kokoro合成
final resp = await Dio().post(
  'https://139.196.44.6:8002/api/v1/tts/kokoro-speak',
  data: {
    'text': '教えてください。',
    'voice': 'a',              // ← 可选，使用默认
    'emotion': 'neutral',      // ← 可选，使用默认
    'speed': 1.0               // ← 可选，使用默认
  }
);
```

### 配置如何影响APP

1. **管理员在后台设置**：通过菜单 🎤 Kokoro TTS 设置
2. **配置保存到数据库**：`AppConfig` 表中
3. **APP发送请求到后端**：可省略voice/emotion/speed参数
4. **后端使用默认值**：若APP未提供，则使用管理员配置的默认值
5. **Python Kokoro合成**：使用后端传来的参数
6. **返回音频给APP**：APP播放合成的语音

---

## ✅ 验证清单

部署完成后，请按以下步骤验证：

### 1️⃣ 后端验证

```bash
# SSH到服务器
ssh -p 22 root@139.196.44.6

# 查看PM2进程状态
pm2 status
# 确保 japanese-learn 和 kokoro-tts 都处于 online 状态

# 检查日志
pm2 logs japanese-learn --lines 20
```

### 2️⃣ 管理后台验证

1. 打开 `https://139.196.44.6:8002/admin`
2. 左侧菜单 → 系统 → 🎤 Kokoro TTS
3. 验证UI显示：
   - ✅ 启用开关
   - ✅ 三个人声单选按钮（a/b/c）
   - ✅ 三个情感单选按钮（neutral/happy/sad）
   - ✅ 语速滑块（0.5x-2.0x）
   - ✅ 服务URL输入框
   - ✅ 保存按钮

### 3️⃣ 参数修改验证

1. 在管理后台修改参数：
   ```
   人声: b (女清晰)
   情感: happy (高兴)
   语速: 1.3x
   ```

2. 点击"保存设置"

3. 查看数据库确认保存：
   ```bash
   mysql -u root -p japanese_learn -e \
     "SELECT key, value FROM app_configs WHERE key='kokoro_tts_settings';"
   ```

### 4️⃣ 功能测试

1. **编译并部署新APP**：
   ```bash
   cd mobile
   flutter clean
   flutter build apk --release
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

2. **打开APP测试**：
   - 进入 语法 → 选择任意课程
   - 点击例句播放按钮
   - 观察logcat日志验证完整流程：
     ```
     [TTS] 第3层：尝试Kokoro后端合成 - URL: https://139.196.44.6:8002/api/v1/tts/kokoro-speak
     [TTS] 请求数据: {"text":"...","voice":"b","emotion":"happy","speed":1.3}
     [TTS] 收到响应: 200
     [TTS] 返回的audio_url: /api/v1/tts/kokoro/audio/kokoro_abc123...wav
     [TTS] 最终播放URL (通过8002): https://139.196.44.6:8002/api/v1/tts/kokoro/audio/kokoro_abc123...wav
     ```

3. **验证音频质量**：
   - 播放音频，确认使用了配置的参数
   - 人声应为选定的b声（女清晰）
   - 情感应为高兴（语调稍高，语速稍快）
   - 语速应为1.3倍速（比标准速度快约30%）

---

## 📊 配置对比示例

### 示例1：初学者友好配置

```
启用：✅
人声：a (女优美) ← 清晰悦耳，易理解
情感：neutral (自然) ← 不分散注意力
语速：0.8x ← 较慢，便于跟读
```

**适用场景**：N5-N4初级学习者，需要慢速听力训练

### 示例2：标准教学配置

```
启用：✅
人声：b (女清晰) ← 清晰有力，适合课堂
情感：neutral (自然) ← 正式讲述
语速：1.0x ← 标准自然速度
```

**适用场景**：N4-N2常规课程，日常对话学习

### 示例3：快速听力训练配置

```
启用：✅
人声：c (男深沉) ← 差异化学习，避免单调
情感：happy (高兴) ← 增加趣味性
语速：1.5x ← 快速，适合进阶学习者
```

**适用场景**：N2-N1高级学习者，听力冲刺训练

---

## 🔍 常见问题

### Q: 配置修改后多久生效？

**A**: 立即生效。修改保存后，下次APP请求合成时就会使用新参数。

### Q: APP能否覆盖管理员配置？

**A**: 可以。APP请求中若指定了voice/emotion/speed，则使用APP指定的值；若未指定，则使用管理员配置的默认值。

### Q: 语速0.5x和2.0x有什么区别？

**A**: 语速为播放速度的倍数：
- 0.5x = 原速的50%（极慢，便于音标学习）
- 1.0x = 原速100%（标准，自然速度）
- 2.0x = 原速的200%（极快，难度较高）

### Q: 三种人声有什么区别？

**A**: 三种人声代表不同的声线特征：
- **a (女优美)**：音阶较高(220Hz)，柔和优美，容易吸引初学者
- **b (女清晰)**：中等音阶(180Hz)，清晰有力，适合听力训练
- **c (男深沉)**：音阶较低(100Hz)，稳重有力，增加多样性

可根据教学目标交替使用，避免学习疲劳。

### Q: 如何验证配置是否保存？

**A**: 
```bash
# 1. 查看数据库
mysql -u root -p japanese_learn -e \
  "SELECT value FROM app_configs WHERE key='kokoro_tts_settings';"

# 2. 检查后端日志
pm2 logs japanese-learn | grep "Kokoro"

# 3. 尝试合成，观察APP logcat
adb logcat | grep "\[TTS\]"
```

---

## 🚀 部署步骤总结

```bash
# 1. 拉取最新代码（如有更新）
cd /path/to/JapaneseLearn
git pull origin main

# 2. 后端无需重新编译，仅需重启Node.js进程
pm2 restart japanese-learn

# 3. 验证后端正常运行
pm2 logs japanese-learn --lines 5

# 4. 访问管理后台验证UI
# https://139.196.44.6:8002/admin → 左侧菜单 → 🎤 Kokoro TTS

# 5. 编译新APP（若有代码变更）
cd mobile
flutter build apk --release

# 6. 部署新APP到测试设备
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 7. 完成
```

---

## 📝 相关文件

- 📄 [backend/src/controllers/adminController.js](backend/src/controllers/adminController.js) - 配置API实现
- 📄 [backend/src/routes/kokoroTts.js](backend/src/routes/kokoroTts.js) - TTS代理路由
- 📄 [backend/public/admin/index.html](backend/public/admin/index.html) - 管理后台UI
- 📄 [mobile/lib/utils/tts_helper.dart](mobile/lib/utils/tts_helper.dart) - APP TTS合成逻辑
- 📄 [KOKORO_ARCHITECTURE_OPTIMIZED.md](KOKORO_ARCHITECTURE_OPTIMIZED.md) - 架构优化文档
- 📄 [KOKORO_TTS_URL_ACCESS_FLOW.md](KOKORO_TTS_URL_ACCESS_FLOW.md) - 请求流程详解
