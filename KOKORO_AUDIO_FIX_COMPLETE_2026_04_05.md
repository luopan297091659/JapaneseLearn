# Kokoro音频路径统一修复 - 完整方案

**修复日期**: 2026年4月5日  
**问题根本**: 一键生成的音频文件路径混乱，导致不同来源的音频存储地址不一致

---

## 问题诊断

### 原来的路径不一致
```
一键生成音频:    /api/v1/tts/kokoro/audio/kokoro_294b9408de7c485aa1e61434b6a40d4f.wav
                 ↓ 存储位置：Kokoro Python 服务(8010)
                 ❌ 隔一段时间后不可用（服务重启、清理、磁盘满）

单个生成音频:    /uploads/grammar/audio/kokoro_016f548d81e3425892ce5bef5ffc312b.wav
                 ↓ 存储位置：Node.js 后端本地磁盘
                 ✓ 持久化存储
```

### 为什么一键生成的音频会失效
1. **存储位置不同**: 直接引用 Kokoro 服务(8010)的临时路径
2. **无本地备份**: 没有将音频下载到 Node 后端
3. **服务依赖**: 如果 8010 重启、清理策略触发、磁盘满，音频就会丢失
4. **没有链接策略**: 即使文件存在，代理访问也可能中断

---

## 修复方案

### 1. 统一音频存储路径

**修改后统一为本地路径**:
```
所有 Kokoro 生成的音频:  /audio/kokoro/kokoro_xxx.wav
                       ↓ 存储位置：Node.js 后端本地磁盘
                       ✓ 永久存储，持一致性
```

### 2. 实现的关键文件

#### 📄 [audioLocalizationService.js](backend/src/services/audioLocalizationService.js)
- **功能**: 从 Kokoro 服务下载音频并保存到本地
- **核心方法**:
  - `downloadAndLocalizeAudio(kokoroUrl)` - 单个下载
  - `batchDownloadAndLocalize(audioUrls)` - 批量下载
  - `ensureAudioDirectories()` - 初始化存储目录

**流程**:
```
Kokoro API 返回 /api/v1/tts/kokoro/audio/kokoro_xxx.wav
         ↓
audioLocalizationService 下载文件
         ↓
保存到本地 /uploads/audio/kokoro/kokoro_xxx.wav
         ↓
返回本地路径 /audio/kokoro/kokoro_xxx.wav
         ↓
存储到数据库
```

#### 📄 [audioCleanupService.js](backend/src/services/audioCleanupService.js)
- **功能**: 定时清理过期音频
- **特性**:
  - 计算音频过期时间（默认30天）
  - 定时清理策略
  - 防止磁盘爆满

#### ⚙️ [adminController.js](backend/src/controllers/adminController.js) 修改
**修改函数**:
1. `generateVocabExamplesKokoroAudio` - 词汇音频一键生成
2. `generateGrammarExamplesKokoroAudio` - 文法音频一键生成

**改进**:
```javascript
// 之前
const results = await axios.post(.../batch-generate...);
await Vocabulary.update({ audio_url: result.audio_url }); // ❌ 直接存储 Kokoro URL

// 之后
const results = await axios.post(.../batch-generate...);
const localPathsMap = await audioLocalizationService.batchDownloadAndLocalize(urls);
await Vocabulary.update({ 
  audio_url: localPathsMap.get(result.audio_url),  // ✓ 本地路径
  audio_url_type: 'kokoro',
  audio_generated_at: now,
  audio_expires_at: expiresAt
});
```

#### 📝 [app.js](backend/src/app.js) 初始化
在服务启动时添加：
```javascript
// 初始化音频存储服务
await audioLocalizationService.ensureAudioDirectories();

// 启动清理定时任务
audioCleanupService.startCleanupSchedule();
```

---

## 数据库架构更新

### 新增字段（迁移脚本: [06_add_audio_lifecycle_fields.sql](backend/database/migrations/06_add_audio_lifecycle_fields.sql)）

```sql
ALTER TABLE vocabulary ADD COLUMN:
  - audio_url_type (enum: none, upload, kokoro)
  - audio_generated_at (timestamp)
  - audio_expires_at (timestamp)

ALTER TABLE vocabulary_examples ADD SAME COLUMNS
ALTER TABLE grammar_examples ADD SAME COLUMNS
```

**作用**:
- `audio_url_type`: 区分音频来源（上传 vs Kokoro 生成）
- `audio_generated_at`: 记录生成时间（用于追踪）
- `audio_expires_at`: 记录过期时间（用于清理）

### 新建表

#### kokoro_audio_cleanup_logs
清理历史日志，记录：
- 清理时间 (cleanup_at)
- 文件名 (audio_filename)
- 原记录所在表 (table_name)
- 清理原因 (reason: expired/orphaned/manual)

#### kokoro_audio_stats
磁盘使用统计：
- 总文件数 (total_files)
- 总字节数 (total_bytes)
- 最后清理时间 (last_cleanup_at)

---

## 五十音管理系统实现

### 新增数据库表 ([07_create_kana_management_system.sql](backend/database/migrations/07_create_kana_management_system.sql))

#### kana_categories
五十音分类表：
```
1. 平假名 (hiragana)
2. 片假名 (katakana)
3. 浊音 (dakuten)
4. 半浊音 (handakuten)
5. 拗音 (yoon)
```

#### kana_characters
假名字符表：
- 平假名、片假名、罗马字、笔画数等

#### kana_audio
假名音频表：
- 支持多种语速/情感（standard, slow, natural, phonetic）
- 记录 Kokoro 生成时间和过期时间

#### user_kana_progress
用户学习进度表：
- 正确/错误次数统计
- 掌握状态标记
- 最后练习时间

### 后端实现

#### [kanaController.js](backend/src/controllers/kanaController.js)
- `generateKanaAudioBatch()` - 一键生成所有假名音频
- `getUserKanaProgress()`  - 查询学习进度

#### [kana.js 路由](backend/src/routes/kana.js)
```
GET  /api/v1/kana/categories                  - 获取分类
POST /api/v1/kana/admin/generate-audio        - 一键生成音频
GET  /api/v1/kana/user/:userId/progress       - 查询学习进度
```

---

## 客户端同步策略

### 手机端的音频处理逻辑

#### 语法模块
```javascript
// 获取语法例句的音频
const getGrammarAudio = (grammarExample) => {
  const audioUrl = grammarExample.audio_url;
  
  if (audioUrl && audioUrl.startsWith('/audio')) {
    // 本地持久化音频 - 直接使用
    return serverRoot + audioUrl;  // /audio/kokoro/xxx.wav
  } else if (audioUrl && audioUrl.startsWith('/api')) {
    // Kokoro 代理路径 - 通过代理访问
    return serverRoot + audioUrl;  // /api/v1/tts/kokoro/audio/xxx.wav
  } else {
    // 无音频 - 调用本地 TTS
    return null;  // 触发 FlutterTts 降级
  }
};
```

#### 五十音模块
```javascript
// 获取假名音频
const getKanaAudio = (kanaCharacter) => {
  const audioUrl = kanaCharacter.audio_url;
  
  if (audioUrl && audioUrl.startsWith('/audio')) {
    // 本地持久化音频
    return serverRoot + audioUrl;
  } else {
    // 无音频 - 调用本地 TTS
    return null;
  }
};
```

### 核心逻辑
1. **优先使用服务端音频** - 质量更好
2. **无音频或加载失败** - 自动降级到本地 TTS
3. **缓存策略** - 移动端自行缓存音频文件

---

## 部署检查清单

- [ ] 运行迁移脚本：`06_add_audio_lifecycle_fields.sql`
- [ ] 运行迁移脚本：`07_create_kana_management_system.sql`
- [ ] 确保 `/uploads/audio/kokoro/` 目录可写
- [ ] 重启 Node.js 后端服务
- [ ] 验证 `/health` 端点返回正常
- [ ] 管理后台测试一键生成音频功能
- [ ] 检查生成的音频路径是否为 `/audio/kokoro/` 格式
- [ ] 测试客户端音频播放（优先本地，次优代理）

---

## 预期结果

### ✅ 修复前后对比

| 方面 | 修复前 | 修复后 |
|-----|------|------|
| 音频存储位置 | Kokoro 服务(8010) | Node 后端本地 |
| 持久化 | ❌ 无保障 | ✓ 永久存储 |
| 过期管理 | ❌ 无 | ✓ 30天过期+定时清理 |
| 路径统一 | ❌ 混杂 | ✓ 统一为 `/audio/kokoro/` |
| 容错能力 | ❌ 弱 | ✓ 无依赖降级 |
| 磁盘管理 | ❌ 无 | ✓ 统计+清理 |

---

## 已实现的关键改进

### 🔄 管理系统完整性
```
adminController 改进 ✓
├─ generateVocabExamplesKokoroAudio() - 本地化
├─ generateGrammarExamplesKokoroAudio() - 本地化
└─ 支持断点恢复、部分成功处理

kanaController 新增 ✓
└─ generateKanaAudioBatch() - 一键生成五十音

音频管理后台 ✓
└─ kokoroAudioManagement.js - 统计、清理、日志
```

### 📊 数据库优化
```
表结构更新 ✓
├─ 音频生命周期字段
├─ 清理日志表
├─ 统计表
└─ 五十音完整系统

视图 ✓
└─ v_kana_with_audio - 快速查询假名+音频
```

### 🛡️ 可靠性提升
```
容错机制 ✓
├─ 自动重试（指数退避）
├─ 部分成功处理
├─ 本地缓存降级
└─ 定期清理维护
```

---

## 下一步优化方向

### 短期 (1-2周)
- [ ] 创建管理后台面板展示统计信息
- [ ] 实现手动触发清理功能
- [ ] 添加音频质量检查（文件完整性）

### 中期 (2-4周)
- [ ] 实现增量同步（只同步变更部分）
- [ ] 添加音频压缩选项（减少存储）
- [ ] CDN 集成（加速下载）

### 长期 (1个月+)
- [ ] 云存储备份方案
- [ ] 智能预加载策略
- [ ] 多语言 TTS 支持

---

## 常见问题

**Q: 为什么不继续使用 Kokoro 服务的路径?**
A: Kokoro 服务是临时生成，无法保证文件持久性。本地存储确保即使服务宕机，音频仍然可用。

**Q: 如何处理现有的旧音频?**
A: 旧音频路径为 `/api/v1/tts/kokoro/audio/...`，客户端会自动尝试下载。如果失败，降级到本地 TTS。

**Q: 磁盘容量不足怎么办?**
A: 音频清理服务会在过期时自动删除。可设置 `KOKORO_AUDIO_TTL_DAYS` 环境变量控制过期时间。

**Q: 可以手动删除某个音频吗?**
A: 可以，通过 API `/api/v1/kokoro-audio/delete/:audioFilename` (管理员权限)。
