## 📂 音频路径模块化分割方案
**时间**: 2026年4月5日  
**状态**: ✅ **已完成部署**

---

## 🎯 核心设计

所有Kokoro生成的音频现在按**功能模块**分离存储，便于管理、清理和统计：

```
uploads/
├── grammar/
│   └── audio/              ← 语法例句音频
│       ├── kokoro_abc123.wav
│       ├── kokoro_def456.wav
│       └── ...
├── audio/
│   ├── vocab/              ← 单词和例句音频
│   │   ├── kokoro_111222.wav
│   │   ├── kokoro_333444.wav
│   │   └── ...
│   └── kana/               ← 五十音音频
│       ├── kokoro_555666.wav
│       ├── kokoro_777888.wav
│       └── ...
```

---

## 📋 路径规范

| 功能模块 | 磁盘目录 | 数据库URL | 对应表 |
|---------|--------|---------|-------|
| **语法例句** | `/uploads/grammar/audio/` | `/uploads/grammar/audio/kokoro_xxx.wav` | grammar_examples |
| **单词和例句** | `/uploads/audio/vocab/` | `/uploads/audio/vocab/kokoro_xxx.wav` | vocabulary, vocabulary_examples |
| **五十音** | `/uploads/audio/kana/` | `/uploads/audio/kana/kokoro_xxx.wav` | kana_audio |

---

## 🔧 代码修改详情

### 1️⃣ audioLocalizationService.js
**核心改动**:
```javascript
// 路径配置（按功能模块）
const AUDIO_PATHS = {
  grammar: path.join(process.cwd(), 'uploads', 'grammar', 'audio'),
  vocabulary: path.join(process.cwd(), 'uploads', 'audio', 'vocab'),
  kana: path.join(process.cwd(), 'uploads', 'audio', 'kana')
};

// URL路径前缀
const AUDIO_URL_PREFIXES = {
  grammar: '/uploads/grammar/audio',
  vocabulary: '/uploads/audio/vocab',
  kana: '/uploads/audio/kana'
};

// 函数调用示例
await downloadAndLocalizeAudio(kokoroUrl, 'vocabulary');
await downloadAndLocalizeAudio(kokoroUrl, 'grammar');
await downloadAndLocalizeAudio(kokoroUrl, 'kana');
```

### 2️⃣ audioCleanupService.js
**核心改动**:
```javascript
// 按类型模式清理
const AUDIO_URL_PATTERNS = {
  grammar: '/uploads/grammar/audio/%',
  vocabulary: '/uploads/audio/vocab/%',
  kana: '/uploads/audio/kana/%'
};

// 查询示例
await Vocabulary.findAll({
  where: {
    audio_expires_at: { [Op.lt]: now },
    audio_url: { [Op.like]: AUDIO_URL_PATTERNS.vocabulary }
  }
});
```

### 3️⃣ kokoroAudioManagement.js
**核心改动**:
```javascript
// 管理路由支持多路径
router.post('/delete/:audioFilename', authenticate, requireRole('admin'), async (req, res) => {
  const audioType = req.body?.type || 'vocabulary'; // 从请求体指定类型
  const deleted = await audioLocalizationService.deleteLocalKokoroAudio(audioFilename, audioType);
  // ...
});
```

### 4️⃣ adminController.js
**词汇生成修改**:
```javascript
// 使用 'vocabulary' 类型
const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(
  successfulAudioUrls, 
  'vocabulary'  // ← 明确指定类型
);
```

**语法生成修改**:
```javascript
// 使用 'grammar' 类型
const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(
  successfulAudioUrls, 
  'grammar'  // ← 明确指定类型
);
```

### 5️⃣ kanaController.js
**五十音生成修改**:
```javascript
// 使用 'kana' 类型
const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(
  successfulAudioUrls, 
  'kana'  // ← 明确指定类型
);
```

---

## 📊 存储管理示例

### 查询每个模块的音频数量
```sql
-- 语法音频
SELECT COUNT(*) FROM grammar_examples 
WHERE audio_url LIKE '/uploads/grammar/audio/%';

-- 词汇音频
SELECT COUNT(*) FROM vocabulary 
WHERE audio_url LIKE '/uploads/audio/vocab/%';

-- 五十音音频
SELECT COUNT(*) FROM kana_audio 
WHERE audio_url LIKE '/uploads/audio/kana/%';
```

### 查询磁盘使用情况
```bash
# 每个模块的大小
du -sh uploads/grammar/audio/
du -sh uploads/audio/vocab/
du -sh uploads/audio/kana/

# 总大小
du -sh uploads/
```

### 清理特定模块的过期音频
```bash
# 使用管理API清理特定类型的音频
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/expired \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

---

## 🔄 清理流程优化

### 自动清理（每6小时一次）
```
[Cleanup] 开始清理任务 - 2026-04-05T08:00:00Z
  → 检查 /uploads/grammar/audio/ 过期音频
  → 检查 /uploads/audio/vocab/ 过期音频
  → 检查 /uploads/audio/kana/ 过期音频
[Cleanup] 已清理 grammar: 5, vocabulary: 12, kana: 3 个过期音频
[Cleanup] 清理完成 - 耗时: 1.2s
```

### 手动清理
```bash
# 清理所有过期音频
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/expired \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 清理孤立文件
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/orphaned \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 获取统计信息
curl http://localhost:8002/api/v1/kokoro-audio/stats \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

**统计响应示例**:
```json
{
  "success": true,
  "stats": {
    "diskUsage": {
      "bytes": 52428800,
      "gb": "50.00"
    },
    "audioCount": {
      "vocabulary": 520,
      "grammar": 340,
      "kana": 46,
      "total": 906
    },
    "expiredAudio": {
      "vocabulary": 12,
      "grammar": 5,
      "total": 17
    }
  }
}
```

---

## ✨ 优势分析

### 1. **清晰的模块隔离** ✅
- 不同功能的音频彻底分离
- 便于针对性管理和监控
- 减少误删风险

### 2. **高效的清理策略** ✅
- 可针对特定模块进行清理
- 支持独立的过期时间配置（未来扩展）
- 磁盘空间利用更合理

### 3. **灵活的统计分析** ✅
- 可单独查询每个模块的大小
- 支持模块级别的配额管理
- 便于用户行为分析

### 4. **向后兼容** ✅
- 单个例句生成仍使用 `/uploads/grammar/audio/`（原有路径）
- 系统自动适配新旧路径
- 平滑过渡，无需迁移

### 5. **扩展性强** ✅
- 易于添加新的音频类型
- 支持不同的清理策略
- 为未来的功能预留空间

---

## 📝 API调用示例

### 一键生成词汇音频
```bash
curl -X POST http://localhost:8002/api/v1/admin/generate-vocab-examples-kokoro \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": []}'

# 响应
{
  "success": true,
  "generated": 120,
  "total": 120,
  "audioUrls": [
    "/uploads/audio/vocab/kokoro_abc123.wav",
    "/uploads/audio/vocab/kokoro_def456.wav"
  ]
}
```

### 一键生成语法音频
```bash
curl -X POST http://localhost:8002/api/v1/admin/generate-grammar-examples-kokoro \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": []}'

# 响应
{
  "success": true,
  "generated": 85,
  "total": 85,
  "audioUrls": [
    "/uploads/grammar/audio/kokoro_xxx111.wav",
    "/uploads/grammar/audio/kokoro_xxx222.wav"
  ]
}
```

### 一键生成五十音音频
```bash
curl -X POST http://localhost:8002/api/v1/kana/admin/generate-audio \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 响应
{
  "success": true,
  "generated": 46,
  "total": 46,
  "message": "成功生成 46/46 个假名音频",
  "audioUrls": [
    "/uploads/audio/kana/kokoro_yyy111.wav",
    "/uploads/audio/kana/kokoro_yyy222.wav"
  ]
}
```

---

## ⚙️ 环境变量配置

在 `.env` 中配置：
```bash
# 音频清理配置
KOKORO_AUDIO_TTL_DAYS=30              # 音频存活时间（天）
MAX_AUDIO_STORAGE_GB=50               # 总磁盘上限（GB）
CLEANUP_CHECK_INTERVAL=21600000       # 清理检查间隔（毫秒，6小时）

# 模块级别的配额（可选扩展）
# VOCAB_AUDIO_MAX_GB=20
# GRAMMAR_AUDIO_MAX_GB=15
# KANA_AUDIO_MAX_GB=5
```

---

## 🚀 部署步骤

### 步骤1: 创建新目录
```bash
mkdir -p uploads/grammar/audio      # 已有，确保存在
mkdir -p uploads/audio/vocab        # 新建
mkdir -p uploads/audio/kana         # 新建

# 设置权限
chmod 755 uploads/grammar/audio
chmod 755 uploads/audio/vocab
chmod 755 uploads/audio/kana
```

### 步骤2: 重启后端服务
```bash
# 使用 PM2
pm2 restart japanese-learn

# 或直接重启进程
# Ctrl+C 然后运行启动命令
```

### 步骤3: 验证目录创建
```bash
# 检查日志
tail -f logs/app.log | grep "\[Audio\]"

# 验证目录
ls -la uploads/grammar/audio/
ls -la uploads/audio/vocab/
ls -la uploads/audio/kana/
```

### 步骤4: 测试新路径
```bash
# 生成测试词汇音频
curl -X POST http://localhost:8002/api/v1/admin/generate-vocab-examples-kokoro \
  -H "Authorization: Bearer TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": ["test-id"]}'

# 确认音频创建在正确路径
ls -la uploads/audio/vocab/
```

---

## 📈 监控和维护

### 定期检查磁盘使用
```bash
# 每日检查（可加入cron）
du -sh uploads/audio/*
du -sh uploads/grammar/audio/

# 详细统计
find uploads -name "kokoro_*.wav" -type f | wc -l
find uploads -name "kokoro_*.wav" -type f | xargs du -c | tail -1
```

### 日志监控
```bash
# 监听清理日志
grep "\[Cleanup\]" logs/app.log | tail -20

# 监听下载日志
grep "\[Audio\]" logs/app.log | tail -20
```

---

## 🎓 最佳实践

### DO ✅
- 定期检查各模块的磁盘使用情况
- 及时清理过期音频
- 为不同模块设置不同的保留期限（未来扩展）
- 监控磁盘使用趋势，提前规划扩容

### DON'T ❌
- 不要手动删除音频文件（会导致数据库不一致）
- 不要绕过API直接操作磁盘
- 不要关闭自动清理服务
- 不要混淆不同模块的路径

---

**总结**: ✅ 音频路径现已完全按功能模块分割，提供更清晰的纹理、更高效的管理和更好的可维护性。

