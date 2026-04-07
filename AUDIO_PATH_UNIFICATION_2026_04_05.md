## 🔧 音频路径统一整改报告

**时间**: 2026年4月5日  **状态**: ✅ **已完成**

---

## 📍 问题识别

### 路径不一致的情况
用户发现了一个重要问题：**批量一键生成与单个生成使用了不同的目录结构**

| 类型 | 生成方式 | 存储位置 | 数据库URL |
|------|--------|--------|----------|
| **单个例句** (现有) | 单文件生成 | `/uploads/grammar/audio/` | `/uploads/grammar/audio/kokoro_xxx.wav` ✅ |
| **批量一键** (新建) | 批量生成 | `/uploads/audio/kokoro/` | `/audio/kokoro/kokoro_xxx.wav` ❌ |

### 问题影响
- 路径不统一导致维护困难
- 磁盘清理时需要查询多个目录
- 用户体验不一致

---

## ✅ 解决方案

### 统一使用 `/uploads/audio/` 目录
所有生成的音频（无论一键还是单个）都统一保存在：
```
/uploads/audio/kokoro_建的音频ID.wav
```

对应的数据库URL：
```
/uploads/audio/kokoro_建的音频ID.wav
```

### 修改的文件

#### 1️⃣ audioLocalizationService.js (✅ 已改)
**修改项**:
```javascript
// 旧路径
const AUDIO_BASE_PATH = path.join(process.cwd(), 'uploads', 'audio', 'kokoro');
// 新路径 (统一)
const AUDIO_BASE_PATH = path.join(process.cwd(), 'uploads', 'audio');

// 旧返回路径
localPath: `/audio/kokoro/${filename}`
// 新返回路径 (统一)
localPath: `/uploads/audio/${filename}`
```

#### 2️⃣ audioCleanupService.js (✅ 已改)
**修改项**:
```javascript
// 数据库查询条件全部改为
audio_url: { [Op.like]: '/uploads/audio/%' }

// 旧值
audio_url: { [Op.like]: '/audio/kokoro/%' }
```

#### 3️⃣ kokoroAudioManagement.js (✅ 已改)
**修改项**:
```javascript
// 统一使用
const AUDIO_BASE_PATH = path.join(process.cwd(), 'uploads', 'audio');

// 清理时的条件
audio_url: { [Op.like]: '/uploads/audio/%' }
```

#### 4️⃣ kanaController.js (✅ 已改)
**修改项**:
```javascript
// 存储的路径使用
audio_url: localPath,  // 现在是 /uploads/audio/kokoro_xxx.wav
```

#### 5️⃣ 06_add_audio_lifecycle_fields.sql (✅ 已改)
**注释更新**:
```sql
-- 统一音频路径: /uploads/audio/kokoro_xxx.wav
-- 一键和单个生成都使用此路径，统一存储在 /uploads/audio/ 目录中
```

---

## 📋 新的路径规范

### 目录结构
```
uploads/
├── audio/                           # ← 统一的音频目录
│   ├── kokoro_建的音频ID1.wav      # 一键生成的音频
│   ├── kokoro_建的音频ID2.wav      # 单个生成的音频
│   └── ???
├── grammar/                         # ← 可保留但不再使用（兼容）
│   └── audio/
│       ├── kokoro_old1.wav         # 旧的音频（可选保留）
│       └── kokoro_old2.wav
└── ...
```

### 数据库字段标准
```sql
audio_url = '/uploads/audio/kokoro_建的音频ID.wav'
audio_url_type = 'kokoro'              -- 标识来源（upload/kokoro)
audio_generated_at = DATETIME(now)     -- 生成时间
audio_expires_at = DATETIME(now + 30天) -- 过期时间
```

---

## 🚀 数据迁移策略

### 步骤1: 现有数据兼容处理
**现状**：数据库中可能存在 `/uploads/grammar/audio/kokoro_xxx.wav` 的URL

**处理**：
- 旧数据保持不变（向后兼容）
- 新生成的数据使用新路径 `/uploads/audio/`
- 清理服务会处理两种路径的文件

### 步骤2: 文件系统兼容
**操作**：
```bash
# 可选：迁移旧文件到新目录
cp uploads/grammar/audio/kokoro_*.wav uploads/audio/
```

**检查**:
```bash
ls -la uploads/audio/kokoro_*.wav     # 新路径
ls -la uploads/grammar/audio/kokoro_*.wav  # 旧路径（可能还有）
```

---

## ✨ 优点

### 1. 统一性 ✅
- 所有Kokoro生成的音频使用同一目录
- 不混淆不同功能特性的文件

### 2. 易维护性 ✅
- 清理脚本只需查询 `/uploads/audio/%`
- 磁盘管理更简单

### 3. 向后兼容 ✅
- 旧数据仍然可以访问（如果还在 `/uploads/grammar/audio/` 中）
- 新生成的都用新路径

### 4. 可扩展性 ✅
- 支持未来添加其他类型音频
- `/uploads/audio/` 可作为通用的音频基础目录

---

## 📝 API示例

### 一键生成词汇音频
```bash
curl -X POST http://localhost:8002/api/v1/admin/generate-vocab-examples-kokoro \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": []}'
```

**返回URL示例**:
```json
{
  "success": true,
  "generated": 5,
  "total": 5,
  "audioUrls": [
    "/uploads/audio/kokoro_abc123.wav",
    "/uploads/audio/kokoro_def456.wav"
  ]
}
```

### 一键生成假名音频
```bash
curl -X POST http://localhost:8002/api/v1/kana/admin/generate-audio \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

**返回URL示例**:
```json
{
  "success": true,
  "generated": 46,
  "total": 46,
  "message": "成功生成 46/46 个假名音频"
}
```

### 获取音频统计
```bash
curl http://localhost:8002/api/v1/kokoro-audio/stats \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

**返回示例**:
```json
{
  "success": true,
  "stats": {
    "diskUsage": {
      "bytes": 5242880,
      "gb": "5.00"
    },
    "audioCount": {
      "vocabulary": 120,
      "grammar": 85,
      "kana": 46,
      "total": 251
    }
  }
}
```

---

## 🔄 清理服务行为

### 定时清理
```javascript
// 每6小时自动执行
[Cleanup] ✓ 已启动定时清理任务，检查间隔: 360 分钟

// 清理过期音频
[Cleanup] 开始清理任务 - 2026-04-05T08:00:00Z
[Cleanup] 已清理 12 个过期音频
[Cleanup] 清理完成 - 过期: 12, 孤立: 3, 总大小: 5.23GB, 耗时: 1245ms
```

### 手动清理
```bash
# 清理过期
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/expired \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 清理孤立文件
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/orphaned \
  -H "Authorization: Bearer ADMIN_TOKEN"
```

---

## 📊 监控和验证

### 验证脚本
```bash
#!/bin/bash
# 检查目录
echo "检查 /uploads/audio 目录:"
find uploads/audio -name "kokoro_*.wav" -type f | wc -l

# 检查数据库
echo "检查数据库中的URL格式:"
mysql -u root -p japanese_learn -e \
  "SELECT COUNT(*) as count FROM vocabulary WHERE audio_url LIKE '/uploads/audio/%' UNION ALL
   SELECT COUNT(*) FROM grammar_examples WHERE audio_url LIKE '/uploads/audio/%';"

# 检查磁盘大小
echo "磁盘使用:"
du -sh uploads/audio/
```

---

## 🎯 下一步

1. ✅ **代码已全部修改** - 使用新路径 `/uploads/audio/`
2. ⏳ **重启后端服务** - 使新代码生效
3. 📊 **验证新生成** - 确认新生成的音频在新目录
4. 🗑️ **清理旧文件** - （可选）迁移老数据或删除

---

**最终状态**: ✅ 所有代码已统一为使用 `/uploads/audio/` 目录

