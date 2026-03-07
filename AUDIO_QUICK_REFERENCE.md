# 快速查询：单词语音功能文件清单与关键代码

## 🎯 快速导航

### 核心文件（必读）
```
前端音频播放组件:
  mobile/lib/widgets/audio_player_widget.dart (line 49-92)  ← 最重要
  
TTS 文本转语音:
  mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart (line 36-130)  ← 复杂实现
  
音频下载代理:
  mobile/lib/services/api_service.dart (line 164-172)  ← 证书绕过问题
  
后端 Anki 导入:
  backend/src/controllers/ankiController.js (line 47-350)  ← 核心逻辑
  backend/src/services/ankiService.js (line 1-100)  ← 工具函数
  
静态文件服务:
  backend/src/app.js (line 74)  ← 音频文件服务配置
```

---

## 📊 问题优先级排序

### 🔴 严重问题（立即处理）

1. **音频下载无重试机制** [HIGH]
   - 文件: `api_service.dart` L164-172
   - 风险: 任何网络抖动导致加载失败
   - 修复: 实现 3 次重试，指数退避

2. **SSL 证书完全信任** [HIGH]
   - 文件: `api_service.dart` L70-76
   - 风险: 易受中间人攻击
   - 修复: 实现证书固定 (Certificate Pinning)

3. **Anki 导入无上限检查** [HIGH]
   - 文件: `ankiController.js` L30-35, L240-350
   - 风险: 服务器存储爆满
   - 修复: 添加音频数量和总大小检查

### 🟡 中等问题（周内处理）

4. **TTS 引擎初始化不确定** [MEDIUM]
   - 文件: `vocabulary_detail_screen.dart` L60-90
   - 风险: `_ttsReady` 可能长期为 false
   - 修复: 添加 15 秒超时机制

5. **音频缓存机制薄弱** [MEDIUM]
   - 文件: `api_service.dart` L166
   - 风险: URL 变化导致重复下载，占用空间
   - 修复: 使用音频 ID 而非 URL hash

6. **错误提示不明确** [MEDIUM]
   - 文件: `audio_player_widget.dart` L86, HTML L2400
   - 风险: 用户无法排查问题
   - 修复: 区分网络/格式/设备错误

### 🟢 低优先级（可选）

7. **日语 TTS 引擎依赖** [LOW]
   - 文件: `vocabulary_detail_screen.dart` L60-90
   - 修复: 提供系统设置跳转链接

8. **预加载机制缺失** [LOW]
   - 修复: WiFi 环境下预加载常用音频

---

## 📁 完整文件结构

### 前端 Flutter

```
mobile/
├── lib/
│   ├── widgets/
│   │   └── audio_player_widget.dart ⭐⭐⭐
│   │       ├─ 行 49-92: _togglePlay() - URL 多源处理
│   │       ├─ 行 107-130: build() 界面渲染
│   │       └─ 关键: 自签名证书处理、本地文件支持
│   │
│   ├── services/
│   │   ├── api_service.dart ⭐⭐⭐
│   │   │   ├─ 行 70-76: Dio 证书信任配置 ⚠️ 安全问题
│   │   │   ├─ 行 164-172: downloadToTempFile() - 音频下载代理
│   │   │   └─ 行 300-340: getVocabularyById() 等数据接口
│   │   └── anki_parser.dart
│   │       └─ Anki 本地解析（客户端导入用）
│   │
│   ├── config/
│   │   └── app_config.dart ⭐⭐
│   │       ├─ baseUrl = 'https://139.196.44.6:8002/api/v1'
│   │       └─ serverRoot = 'https://139.196.44.6:8002'
│   │
│   ├── screens/
│   │   ├── vocabulary/
│   │   │   └── vocabulary_detail_screen.dart ⭐⭐⭐
│   │   │       ├─ 行 36-90: _initTts() - TTS 初始化 ⚠️ 超时风险
│   │   │       ├─ 行 94-130: _speak() - 播放逻辑
│   │   │       ├─ 行 382-390: build() 包含 AudioPlayerWidget
│   │   │       └─ 最复杂的 TTS 实现，需要重点关注
│   │   │
│   │   ├── listening/
│   │   │   └── listening_screen.dart ⭐
│   │   │       ├─ 行 114-150: _AudioPlayerSheet
│   │   │       └─ 听力材料列表与播放
│   │   │
│   │   ├── study/
│   │   │   ├── pronunciation_screen.dart ⭐⭐
│   │   │   │   ├─ 行 32-42: TTS + STT 初始化
│   │   │   │   ├─ 行 79-112: _toggleRecord() - 语音识别
│   │   │   │   ├─ 行 154-167: _calcScore() - 相似度计算
│   │   │   │   └─ 发音练习核心功能
│   │   │   │
│   │   │   ├── gojuon_screen.dart ⭐
│   │   │   │   └─ 五十音 TTS 学习
│   │   │   │
│   │   │   └── todofuken_quiz_screen.dart
│   │   │       └─ 都道府县测验 TTS
│   │   │
│   │   ├── grammar/
│   │   │   └── grammar_detail_screen.dart ⭐
│   │   │       ├─ 行 38-43: TTS 初始化
│   │   │       ├─ 行 182-200: AudioPlayerWidget for examples
│   │   │       └─ 语法示例音频播放
│   │   │
│   │   └── news/
│   │       └── nhk_detail_screen.dart
│   │           └─ 新闻文章 TTS 朗读
│   │
│   └── models/
│       └── models.dart
│           └─ VocabularyModel 包含 audioUrl 字段
│
└── android/
    └── app/src/main/AndroidManifest.xml
        └─ TTS 服务权限声明 (Android 11+)
```

### 后端 Node.js

```
backend/
├── src/
│   ├── services/
│   │   └── ankiService.js ⭐⭐⭐
│   │       ├─ 行 1-10: UPLOAD_AUDIO_DIR = './uploads/audio'
│   │       ├─ 行 14-23: getSqlJs() - sql.js 初始化
│   │       ├─ 行 25-40: stripHtml() - HTML 清理
│   │       ├─ 行 42-45: extractSoundRef() - [sound:xxx] 提取
│   │       ├─ 行 47-95: detectMapping() - 字段映射检测
│   │       └─ 核心工具库
│   │
│   ├── controllers/
│   │   └── ankiController.js ⭐⭐⭐
│   │       ├─ 行 29-44: Multer 配置（100MB 限制）
│   │       ├─ 行 47-120: serverParseApkg() ⚠️ 核心逻辑
│   │       │   ├─ 解压 .apkg
│   │       │   ├─ 提取 SQLite
│   │       │   ├─ 提取音频文件（line 67-79）
│   │       │   └─ 返回 {notes, audioUrlMap}
│   │       │
│   │       ├─ 行 164-236: previewImport() - 预览接口
│   │       │   └─ 返回字段映射和样本
│   │       │
│   │       └─ 行 240-350: serverImport() ⚠️ 主导入逻辑
│   │           ├─ 调用 serverParseApkg()
│   │           ├─ 字段映射与音频关联
│   │           ├─ 批量数据库导入（每 500 条）
│   │           ├─ 版本号更新（触发同步）
│   │           └─ ⚠️ 无音频数量/大小限制
│   │
│   ├── routes/
│   │   ├── admin.js ⭐⭐
│   │   │   ├─ 行 16-45: Multer 配置
│   │   │   ├─ 行 49+: /anki/server-import 路由
│   │   │   └─ 文件上传权限控制
│   │   │
│   │   ├── vocabulary.js ⭐
│   │   │   └─ GET /api/v1/vocabulary/{id} - 返回 audio_url
│   │   │
│   │   ├── grammar.js ⭐
│   │   │   └─ GET /api/v1/grammar/{id} - 返回音频
│   │   │
│   │   └── listening.js ⭐
│   │       └─ GET /api/v1/listening - 返回听力材料
│   │
│   ├── app.js ⭐⭐⭐
│   │   ├─ 行 74-76: 静态文件服务配置
│   │   │   app.use('/uploads', express.static(path.join(...)))
│   │   │   ⭐ 关键：音频文件由此路由服务
│   │   │
│   │   └─ 行 80+: 各功能路由挂载
│   │
│   └── models/
│       ├── Vocabulary.js - { ..., audio_url: STRING }
│       ├── GrammarExample.js - { ..., audio_url: STRING }
│       └── ListeningTrack.js - { ..., audio_url: STRING }
│
├── uploads/
│   └── audio/ ⭐⭐⭐
│       └─ 实际存储位置：{uuid}.{ext} (如 f47b8c92.mp3)
│           ⚠️ 目前为空（生产数据）
│
├── public/
│   ├── app/
│   │   └── index.html ⭐⭐
│   │       ├─ 行 2400: playAudio(url) - 原生音频播放
│   │       ├─ 行 1921: speakJa() - Web TTS
│   │       ├─ 行 1985-2030: 发音练习（JS实现）
│   │       └─ Web 前端完整实现
│   │
│   └── admin/
│       └── index.html ⭐⭐
│           ├─ 行 1390-1560: Anki 导入界面
│           ├─ 拖放上载区域
│           ├─ 预览与字段映射
│           └─ 管理后台界面

└── .env.example
    └─ PORT=8002, DB 配置等
```

---

## 🔍 关键代码行数速查

| 功能 | 文件 | 行数 | 说明 |
|-----|-----|------|------|
| TTS 初始化 | vocabulary_detail_screen.dart | 36-90 | 最完整实现，含超时风险 |
| TTS 播放 | vocabulary_detail_screen.dart | 94-130 | 乐观更新 + 错误处理 |
| 音频播放 | audio_player_widget.dart | 49-92 | 多源 URL 处理 |
| 下载代理 | api_service.dart | 164-172 | 缓存检查 + Dio 下载 |
| 证书信任 | api_service.dart | 70-76 | ⚠️ 安全漏洞 |
| Anki 解析 | ankiController.js | 47-120 | 音频提取核心 |
| 数据导入 | ankiController.js | 240-350 | ⚠️ 无限制风险 |
| 静态服务 | app.js | 74 | 音频文件提供 |
| 字段映射 | ankiService.js | 47-95 | 自动检测映射逻辑 |
| Web 播放 | index.html (app) | 2400 | 原生音频播放 |
| Web TTS | index.html (app) | 1921 | Web Speech API |
| Anki 导入 UI | index.html (admin) | 1390-1560 | 管理界面 |

---

## ⚠️ 问题修复代码片段

### 1️⃣ 音频下载重试（3 分钟实现）
```dart
// mobile/lib/services/api_service.dart
Future<String> downloadToTempFile(String url, {int maxRetries = 3}) async {
  // ... 现有缓存检查 ...
  
  int attempts = 0;
  while (attempts < maxRetries) {
    try {
      await _dio.download(url, file.path);
      return file.path;
    } catch (e) {
      attempts++;
      if (attempts >= maxRetries) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }
  }
}
```

### 2️⃣ Anki 导入限制（5 分钟实现）
```javascript
// backend/src/controllers/ankiController.js
async function serverImport(req, res) {
  // ... 现有代码 ...
  const audioCount = Object.keys(audioUrlMap).length;
  if (audioCount > 10000) {
    return res.status(400).json({ error: '音频过多' });
  }
}
```

### 3️⃣ TTS 超时处理（5 分钟实现）
```dart
// mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart
// 在 _initTts() 中添加
Future.delayed(const Duration(seconds: 15), () {
  if (mounted && !_ttsReady) {
    logger.warn('TTS 初始化超时');
    setState(() => _ttsReady = true);  // 降级处理
  }
});
```

---

## 📞 快速技术支持

### "音频无法播放" → 检查清单
1. ✅ 检查 `AppConfig.serverRoot` 是否正确
2. ✅ 验证音频文件是否存在: `curl https://server:8002/uploads/audio/{uuid}.mp3`
3. ✅ 检查网络连接（30 秒超时）
4. ✅ 查看日志 `_hasError` 状态

### "TTS 无声音" → 检查清单
1. ✅ Android: 系统设置 → 默认 TTS 引擎 → 选择日文引擎
2. ✅ iOS: 设置 → 辅助功能 → 旁白 → 安装日语
3. ✅ 检查 `_ttsReady` 标志是否为 true
4. ✅ 检查 `_ttsPlaying` 是否卡死

### "Anki 导入失败" → 检查清单
1. ✅ 文件格式: .apkg / .txt / .csv / .tsv
2. ✅ 文件大小: < 100MB
3. ✅ 字段映射是否正确
4. ✅ 网络连接（大文件可能超时）

---

## 📈 性能指标

| 指标 | 当前值 | 改进目标 | 优先级 |
|-----|--------|--------|--------|
| 下载超时 | 30s，无重试 | <10s，3 次重试 | HIGH |
| 缓存命中率 | URL hash（低） | 音频 ID（高） | MEDIUM |
| TTS 初始化 | 未知，无超时 | <15s 超时 | MEDIUM |
| 导入限制 | 无 | 10K 音频 / 5GB | HIGH |
| SSL 验证 | 无 | 证书固定 | HIGH |

