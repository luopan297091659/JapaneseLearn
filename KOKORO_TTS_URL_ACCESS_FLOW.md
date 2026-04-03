# kokoroTtsUrl APP 侧访问流程详解

## 配置声明

**文件**: `mobile/lib/config/app_config.dart` (L4)

```dart
static const String kokoroTtsUrl = 'https://139.196.44.6:8002/api/v1/tts/kokoro-speak';
```

**重要特性**:
- ✅ 使用 HTTPS 协议（自签名证书）
- ✅ 指向后端代理而非 Python 服务（8002 不是 8010）
- ✅ 完整的 URL 路径

---

## 调用栈追踪

### 步骤 1️⃣：调用入口 
**文件**: `mobile/lib/screens/grammar/grammar_detail_screen.dart` (L84-100)

```dart
Future<void> _playExampleAudio(int idx, String text, String? audioUrl, {bool slow = false}) async {
  if (mounted) setState(() { _playingExampleIdx = idx; _exampleLoading = true; });
  try {
    await TtsHelper.playJapaneseSmart(
      audioUrl: audioUrl,                    // 例句是否有预录音频（通常为 null）
      text: text,                            // 例句文本，如 "教えてください。"
      tts: _tts,                             // FlutterTts 实例
      slow: slow,                            // 是否慢速 (false)
      onComplete: () {
        if (mounted) setState(() { 
          _playingExampleIdx = -1; 
          _exampleLoading = false; 
        });
      },
    );
  } catch (e) {
    debugPrint('Grammar audio error: $e');
    if (mounted) setState(() { _playingExampleIdx = -1; _exampleLoading = false; });
  }
}
```

---

### 步骤 2️⃣：进入 TTS Helper - 3层降级逻辑
**文件**: `mobile/lib/utils/tts_helper.dart` (L14-120)

```dart
static Future<void> playJapaneseSmart({
  String? audioUrl,
  required String text,
  FlutterTts? tts,
  bool slow = false,
  void Function()? onComplete,
}) async {
  debugPrint('[TTS] playJapaneseSmart called - audioUrl: $audioUrl, text: "$text", slow: $slow');
  
  // ─── 第1层：本地/服务器音频 ────────────────────────────────────
  if (audioUrl != null && audioUrl.isNotEmpty) {
    debugPrint('[TTS] 第1层：尝试播放本地/服务器音频 - URL: $audioUrl');
    try {
      // ... 尝试加载和播放本地文件或远程URL ...
      return;  // ✅ 成功则返回
    } catch (e) {
      debugPrint('[TTS] 第1层失败，尝试本地TTS: $e');
    }
  }
  
  // ─── 第2层：本地系统 TTS ────────────────────────────────────
  final ttsInst = tts ?? FlutterTts();
  try {
    debugPrint('[TTS] 第2层：尝试本地系统TTS');
    await configureForJapanese(ttsInst);
    await ttsInst.setVolume(1.0);
    await ttsInst.setSpeechRate(slow ? 0.25 : 0.5);
    ttsInst.setCompletionHandler(() {
      if (onComplete != null) onComplete();
    });
    final result = await ttsInst.speak(text);
    if (result == 1) {
      debugPrint('[TTS] 第2层成功，本地TTS播放');
      return;  // ✅ 本地TTS成功，直接返回，不调用Kokoro
    }
  } catch (e) {
    debugPrint('[TTS] 第2层失败，尝试Kokoro: $e');
  }
  
  // ─── 第3层：后端 Kokoro TTS ⭐️ ←─────────────────────────────
  try {
    debugPrint('[TTS] 第3层：尝试Kokoro后端合成 - URL: ${AppConfig.kokoroTtsUrl}');
    final dio = Dio();
    final requestData = {
      'text': text,
      'voice': 'a',
      'emotion': 'neutral',
      'speed': slow ? 0.7 : 1.0,
    };
    debugPrint('[TTS] 请求数据: ${jsonEncode(requestData)}');
    
    final resp = await dio.post(
      AppConfig.kokoroTtsUrl,  // ← 使用配置的URL
      data: jsonEncode(requestData),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    
    debugPrint('[TTS] 收到响应: ${resp.statusCode}');
    final kokoroAudioUrl = resp.data['audio_url'] as String?;
    debugPrint('[TTS] 返回的audio_url: $kokoroAudioUrl');
  } catch (e) {
    debugPrint('[TTS] Kokoro TTS后端失败: $e');
    if (onComplete != null) onComplete();
  }
}
```

---

## ⭐️ kokoroTtsUrl 的具体使用流程

### 请求阶段

```
1. APP 读取配置
   AppConfig.kokoroTtsUrl 
   = "https://139.196.44.6:8002/api/v1/tts/kokoro-speak"

2. 使用 Dio 发送 POST 请求
   dio.post(
     AppConfig.kokoroTtsUrl,
     data: {
       "text": "教えてください。",
       "voice": "a",
       "emotion": "neutral",
       "speed": 1.0
     }
   )

3. 网络层面的请求
   POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak HTTP/1.1
   Host: 139.196.44.6:8002
   Content-Type: application/json
   
   {
     "text": "教えてください。",
     "voice": "a",
     "emotion": "neutral",
     "speed": 1.0
   }
```

### 响应处理阶段

```
4. 后端返回响应
   200 OK
   Content-Type: application/json
   
   {
     "audio_url": "http://139.196.44.6:8010/api/v1/tts/kokoro/audio/kokoro_abc123.wav",
     "voice": "a",
     "emotion": "neutral"
   }

5. APP 解析响应
   final kokoroAudioUrl = resp.data['audio_url'] as String?;
   // kokoroAudioUrl = "http://139.196.44.6:8010/api/v1/tts/kokoro/audio/kokoro_abc123.wav"

6. 如果是相对URL，则拼接（这里是完整URL，直接使用）
   String fullUrl = kokoroAudioUrl;
   if (!kokoroAudioUrl.startsWith('http')) {
     // 如果是相对URL，从kokoroTtsUrl提取基地址
     final baseUrl = AppConfig.kokoroTtsUrl.replaceAll(RegExp(r'/api/v1/tts/.*'), '');
     fullUrl = baseUrl + kokoroAudioUrl;
   }
   // 这里: fullUrl = kokoroAudioUrl（因为已是完整URL）

7. AudioPlayer 播放音频
   final player = AudioPlayer();
   await player.setUrl(fullUrl);
   await player.play();
```

---

## 关键问题诊断

### ❌ 问题 1: URL 协议为 HTTPS 但 Dio 未信任自签名证书

**症状**:
```
[TTS] 收到响应之前就异常
[TTS] Kokoro TTS后端失败: HandshakeException: Unhandled Exception: 
  _CertificateException(certificate verify failed)
```

**原因**:
- 服务器使用自签名 SSL 证书
- Dio 默认会验证证书链
- 证书验证失败 → 请求被中止

**当前状态**:
- ❌ 需要在 Dio 中配置跳过证书验证

**修复方案**:
```dart
final dio = Dio();
dio.httpClientAdapter = DefaultHttpClientAdapter()
  ..onHttpClientCreate = (client) {
    client.badCertificateCallback = (_, __, ___) => true;
    return client;
  };

final resp = await dio.post(AppConfig.kokoroTtsUrl, ...);
```

---

### ❌ 问题 2: 后端路由不匹配

**症状**:
```
[TTS] 收到响应: 404
```

**检查路由注册**:
1. `backend/src/app.js` 是否有：
   ```javascript
   app.use('/api/v1/tts', require('./routes/kokoroTts'));
   ```

2. `backend/src/routes/kokoroTts.js` 是否有：
   ```javascript
   router.post('/kokoro-speak', async (req, res) => { ... });
   ```

当前状态：✅ 已确认注册正确

---

### ❌ 问题 3: 响应中 audio_url 为 null 或格式错误

**症状**:
```
[TTS] 返回的audio_url: null
[TTS] Kokoro TTS后端失败: ...
```

**可能原因**:
1. 后端 Kokoro Python 合成失败
2. 后端 Node.js 路由抛异常未捕获

**检查方法**:
```bash
# 远程测试后端
plink -pw "Xiaoyun@123" root@139.196.44.6

curl -X POST http://localhost:8002/api/v1/tts/kokoro-speak \
  -H "Content-Type: application/json" \
  -d '{"text":"こんにちは","voice":"a","emotion":"neutral","speed":1.0}'

# 查看返回值和日志
pm2 logs japanese-learn --lines 30
```

---

### ❌ 问题 4: 本地 TTS 在第2层成功，永不调用 Kokoro

**症状**:
```
[TTS] 第2层成功，本地TTS播放
[TTS] 第3层：... 这行永远不会出现
```

**原因**:
- 设备已安装日语 TTS 引擎
- `await ttsInst.speak(text)` 返回 `1`（成功）
- 函数直接返回，不执行第3层

**检查**:
```bash
adb logcat | grep "第2层成功" 
# 如果看到这行，说明是本地TTS成功了
```

**验证 TTS 引擎状态** (在APP中):
```dart
final engines = await tts.getEngines;
debugPrint('Available TTS engines: $engines');

final languages = await tts.getLanguages;
debugPrint('Available languages: $languages');
```

---

## 完整的网络请求流程图

```
┌─────────────────────────────────────────────────────────┐
│ 1. APP 读取配置                                          │
│    String url = AppConfig.kokoroTtsUrl                 │
│    url = "https://139.196.44.6:8002/api/v1/tts/kokoro-speak"
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Dio 构建 HTTPS 请求（需要处理自签名证书）           │
│    POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak
│    Content-Type: application/json                       │
│    {                                                     │
│      "text": "教えてください。",                         │
│      "voice": "a",                                      │
│      "emotion": "neutral",                              │
│      "speed": 1.0                                       │
│    }                                                     │
└──────────────────┬──────────────────────────────────────┘
                   │
        ❌ 自签名证书导致连接失败（可能位置）
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Node.js 后端接收请求（port 8002）                   │
│    Route: /api/v1/tts/kokoro-speak                     │
│    Handler: kokoroTtsRoutes.post('/kokoro-speak', ...)│
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Node.js 转发到 Python Kokoro（port 8010）            │
│    POST http://localhost:8010/api/v1/tts/kokoro       │
│    同样的 JSON 数据                                      │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Python Kokoro 合成音频                               │
│    - 使用 SimpleTTS 生成 WAV 文件头                    │
│    - 保存到 /tmp/kokoro_tts/kokoro_xxxxx.wav          │
│    - 返回相对路径：/api/v1/tts/kokoro/audio/...      │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 6. Node.js 转换 URL 为完整路径                          │
│    INPUT:  /api/v1/tts/kokoro/audio/kokoro_xxxxx.wav  │
│    OUTPUT: http://139.196.44.6:8010/api/v1/tts/...    │
│    返回 JSON：                                           │
│    {                                                     │
│      "audio_url": "http://139.196.44.6:8010/...",     │
│      "voice": "a",                                      │
│      "emotion": "neutral"                               │
│    }                                                     │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 7. APP 接收响应                                         │
│    final kokoroAudioUrl = resp.data['audio_url'];      │
│    kokoroAudioUrl = "http://139.196.44.6:8010/..."    │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 8. AudioPlayer 播放远程音频 URL                         │
│    final player = AudioPlayer();                        │
│    await player.setUrl(kokoroAudioUrl);                │
│    await player.play();                                 │
└────────────────────────────────────────────────────────┘
```

---

## 测试 kokoroTtsUrl 的快速方法

### 在 Windows 上测试（跳过 SSL 验证）

```powershell
# 测试后端是否可达
$Response = Invoke-WebRequest -Uri "https://139.196.44.6:8002/api/v1/tts/kokoro-speak" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"text":"こんにちは","voice":"a","emotion":"neutral","speed":1.0}' `
  -SkipCertificateCheck  # 跳过 SSL 验证

Write-Host $Response.Content | ConvertFrom-Json
```

### 在服务器上测试（localhost，无 SSL）

```bash
plink -pw "Xiaoyun@123" root@139.196.44.6 << 'EOF'
curl -X POST http://localhost:8002/api/v1/tts/kokoro-speak \
  -H "Content-Type: application/json" \
  -d '{"text":"こんにちは","voice":"a","emotion":"neutral","speed":1.0}' \
  | jq .
EOF
```

---

## 总结

| 阶段 | 操作 | 关键代码 | 可能失败点 |
|------|------|---------|----------|
| 配置 | 读取 URL | `AppConfig.kokoroTtsUrl` | ❌ 配置错误或空值 |
| 请求 | POST JSON | `dio.post(URL, data: ...)` | ❌ 自签名证书验证失败 |
| 网络 | 传输数据 | HTTP/HTTPS | ❌ 网络不可达、超时 |
| 后端路由 | 匹配端点 | `/api/v1/tts/kokoro-speak` | ❌ 路由未注册 |
| 代理转发 | 转发到 Python | `localhost:8010` | ❌ Python 服务未运行 |
| 音频合成 | 生成 WAV | SimpleTTS | ❌ 合成失败 |
| URL 转换 | localhost→IP | `replace('localhost', 'IP')` | ❌ URL 未正确转换 |
| 播放 | AudioPlayer | `setUrl().play()` | ❌ 音频 URL 无效 |

