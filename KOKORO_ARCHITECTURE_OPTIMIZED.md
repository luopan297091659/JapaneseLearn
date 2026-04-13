# Kokoro TTS 架构优化方案 ✅

**日期**: 2026-04-03  
**目标**: 确保APP侧只通过8002访问Kokoro数据，8010只限制japanese-learn（Node.js）访问

---

## 优化前的问题 ❌

```
APP (HTTPS)
  ↓
  ├─→ 8002: POST /api/v1/tts/kokoro-speak
  │   ↓
  │   Node.js 后端
  │   ├─→ 8010: POST /api/v1/tts/kokoro
  │   │   ↓
  │   │   合成音频文件
  │   │
  │   └─→ 返回: http://139.196.44.6:8010/api/v1/tts/kokoro/audio/xxx.wav
  │
  └─→ 8010: GET /api/v1/tts/kokoro/audio/xxx.wav  ❌ 直接访问！

问题：APP绕过8002，直接访问8010，违反安全架构
后果：无法对8010端口进行访问控制，APP可绕过认证层
```

---

## 优化后的架构 ✅

```
APP (HTTPS)
  ↓
  ├─→ 8002: POST /api/v1/tts/kokoro-speak
  │   ↓
  │   Node.js 后端
  │   ├─→ 8010: POST /api/v1/tts/kokoro (内网，仅nodejs)
  │   │   ↓
  │   │   合成音频文件
  │   │
  │   └─→ 返回: /api/v1/tts/kokoro/audio/xxx.wav (相对路径)
  │
  └─→ 8002: GET /api/v1/tts/kokoro/audio/xxx.wav ✅（通过代理）
      ↓
      Node.js 代理：
        8010: GET /api/v1/tts/kokoro/audio/xxx.wav
      ↓
      返回给APP的音频数据

优势：
✅ APP永远通过8002访问（统一入口）
✅ 8010完全隐藏在内网，仅nodejs可访问
✅ 可在8002层实现认证、日志、限流等审计
✅ 符合安全架构要求
```

---

## 代码修改清单

### 1️⃣ 后端修改：返回相对路径 + 添加代理端点

**文件**: `backend/src/routes/kokoroTts.js`

**修改1：返回相对路径而非完整URL**

```javascript
// 改前：
const publicAudioUrl = `http://139.196.44.6:8010/api/v1/tts/kokoro/audio/${filename}`;
res.json({ audio_url: publicAudioUrl, ... });

// 改后：
res.json({
  audio_url: resp.data.audio_url,  // /api/v1/tts/kokoro/audio/{filename}
  voice: resp.data.voice,
  emotion: resp.data.emotion,
});
```

**修改2：添加新代理端点** 🆕

```javascript
router.get('/kokoro/audio/:filename', async (req, res) => {
  const { filename } = req.params;
  
  // 安全检查：防止路径遍历攻击
  if (!filename.match(/^kokoro_[a-f0-9]{32}\.wav$/)) {
    return res.status(400).json({ error: 'Invalid audio filename format' });
  }
  
  try {
    // 代理请求到本地8010
    const audioResponse = await axios.get(
      `http://127.0.0.1:8010/api/v1/tts/kokoro/audio/${filename}`,
      { responseType: 'arraybuffer', timeout: 5000 }
    );
    
    res.set('Content-Type', 'audio/wav');
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(audioResponse.data);
  } catch (error) {
    res.status(error.response?.status || 503).json({ error: 'Failed to retrieve audio' });
  }
});
```

**路由注册** (已在 `app.js` 中完成):
```javascript
app.use('/api/v1/tts', require('./routes/kokoroTts'));
```

### 2️⃣ APP侧修改：支持相对URL拼接

**文件**: `mobile/lib/utils/tts_helper.dart` (第3层降级)

```dart
final kokoroAudioUrl = resp.data['audio_url'] as String?;
if (kokoroAudioUrl != null && kokoroAudioUrl.isNotEmpty) {
  // 后端返回相对路径（/api/v1/tts/kokoro/audio/xxx.wav）
  // 拼接基地址后变为完整URL，永远通过8002访问
  String fullUrl = kokoroAudioUrl;
  if (!kokoroAudioUrl.startsWith('http')) {
    final baseUrl = AppConfig.kokoroTtsUrl.replaceAll(RegExp(r'/api/v1/tts/.*'), '');
    fullUrl = baseUrl + kokoroAudioUrl;  // https://139.196.44.6:8002 + /api/v1/tts/kokoro/audio/xxx.wav
  }
  debugPrint('[TTS] 最终播放URL (通过8002): $fullUrl');
  
  final player = AudioPlayer();
  await player.setUrl(fullUrl);
  await player.play();
}
```

---

## 完整请求流程 📋

### 步骤 1：APP发送合成请求

```
POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak
Content-Type: application/json

{
  "text": "教えてください。",
  "voice": "a",
  "emotion": "neutral",
  "speed": 1.0
}
```

### 步骤 2：Node.js后端代理到Python Kokoro

```
POST http://127.0.0.1:8010/api/v1/tts/kokoro
{...same data...}
```

Python Kokoro返回相对路径：
```json
{
  "audio_url": "/api/v1/tts/kokoro/audio/kokoro_abc123def456.wav",
  "voice": "a",
  "emotion": "neutral"
}
```

### 步骤 3：Node.js后端返回相对路径给APP

```
200 OK

{
  "audio_url": "/api/v1/tts/kokoro/audio/kokoro_abc123def456.wav",
  "voice": "a",
  "emotion": "neutral"
}
```

### 步骤 4：APP拼接URL并通过8002获取音频

```
GET https://139.196.44.6:8002/api/v1/tts/kokoro/audio/kokoro_abc123def456.wav
```

Node.js代理路由处理（新增）：
```javascript
router.get('/kokoro/audio/:filename', async (req, res) => {
  // 从本地8010获取音频
  const audioResponse = await axios.get(
    `http://127.0.0.1:8010/api/v1/tts/kokoro/audio/${kokoro_abc123def456.wav}`,
    { responseType: 'arraybuffer' }
  );
  res.send(audioResponse.data);
});
```

返回音频文件给APP。

### 步骤 5：AudioPlayer播放

```dart
await player.setUrl('https://139.196.44.6:8002/api/v1/tts/kokoro/audio/kokoro_abc123def456.wav');
await player.play();
```

---

## 安全性验证 🔒

### 防护 1：路径遍历攻击防护

```javascript
if (!filename.match(/^kokoro_[a-f0-9]{32}\.wav$/)) {
  return res.status(400).json({ error: 'Invalid audio filename format' });
}
```

✅ **只允许** `kokoro_` + 32位hex + `.wav` 的格式  
❌ **拒绝** `../../../etc/passwd`、`../../other_files/` 等

### 防护 2：8010隔离

**防火墙/网络配置**（部署环节）:
```bash
# 仅允许localhost (Node.js) 访问8010
iptables -A INPUT -p tcp --dport 8010 -s 127.0.0.1 -j ACCEPT
iptables -A INPUT -p tcp --dport 8010 -j DROP

# 或 UFW:
ufw allow from 127.0.0.1 to any port 8010
ufw deny 8010
```

### 防护 3：HTTPS证书处理

APP需要配置跳过证书验证（临时开发配置）：

```dart
// mobile/lib/utils/tts_helper.dart 中的Dio初始化
final dio = Dio();
dio.httpClientAdapter = DefaultHttpClientAdapter()
  ..onHttpClientCreate = (client) {
    client.badCertificateCallback = (_, __, ___) => true;
    return client;
  };
```

⚠️ **仅用于开发环节**，生产环境应使用合法SSL证书。

---

## 验证清单 ✅

| 项目 | 检查点 | 命令 | 预期结果 |
|------|--------|------|---------|
| **8002可达性** | APP可访问 | `curl -k https://139.196.44.6:8002/api/v1/tts/health` | 200 OK |
| **8010隔离** | 外部无法访问 | `curl http://139.196.44.6:8010/health` | 连接拒绝 ❌ |
| **8010内网访问** | Node.js可访问 | `docker exec japanese-learn curl http://127.0.0.1:8010/health` | 200 OK ✅ |
| **相对URL返回** | 后端响应格式 | `curl -X POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak -d {...}` | `"audio_url": "/api/v1/tts/..."` ✅ |
| **代理端点** | 音频下载 | `curl https://139.196.44.6:8002/api/v1/tts/kokoro/audio/kokoro_xxx.wav` | WAV文件 ✅ |
| **APP日志** | 完整流程 | `adb logcat \| grep "\[TTS\]"` | 显示8002的URL ✅ |

---

## 部署步骤

### 1. 更新后端代码

```bash
cd backend
git add -A
git commit -m "Optimize Kokoro architecture: return relative URLs + add audio proxy endpoint"
```

### 2. 重启Node.js服务

```bash
pm2 restart japanese-learn
pm2 logs japanese-learn  # 验证无错误
```

### 3. 重新编译APP（如尚未编译新版本）

```bash
cd mobile
flutter clean
flutter pub get
flutter build apk --release
```

### 4. 部署新APK并测试

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 5. 验证数据流

在APP中打开语法例句 → 点击播放按钮 → 检查logcat：

```
[TTS] 第3层：尝试Kokoro后端合成 - URL: https://139.196.44.6:8002/api/v1/tts/kokoro-speak
[TTS] 收到响应: 200
[TTS] 返回的audio_url: /api/v1/tts/kokoro/audio/kokoro_abc123...wav
[TTS] 最终播放URL (通过8002): https://139.196.44.6:8002/api/v1/tts/kokoro/audio/kokoro_abc123...wav
```

---

## 总结

| 方面 | 优化前 | 优化后 |
|------|-------|--------|
| **APP访问端口** | 8002 + 8010（直接） | 仅8002 ✅ |
| **8010访问限制** | 无限制 | 仅localhost ✅ |
| **安全入口** | 分散 | 统一8002 ✅ |
| **代码修改** | 多处 | 仅后端2处 ✅ |
| **性能影响** | 无 | 无（单跳代理） ✅ |
| **审计能力** | 困难 | 简单（8002集中） ✅ |

---

## 相关文件

- 📄 [backend/src/routes/kokoroTts.js](backend/src/routes/kokoroTts.js) - 后端路由（已更新）
- 📄 [mobile/lib/utils/tts_helper.dart](mobile/lib/utils/tts_helper.dart) - APP TTS逻辑（已更新注释）
- 📄 [backend/scripts/kokoro_tts_service.py](backend/scripts/kokoro_tts_service.py) - Python服务（无需变更）
- 📄 [KOKORO_TTS_URL_ACCESS_FLOW.md](KOKORO_TTS_URL_ACCESS_FLOW.md) - 详细流程文档（参考）
