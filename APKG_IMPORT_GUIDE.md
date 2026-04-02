# Apkg 文法导入功能说明

## 功能概述

添加了管理员后端的 Apkg 文件导入功能，支持从 Anki 导出包（.apkg）中导入文法课程和例句，包括音频文件自动提取和保存。

## 后端 API

### 路由
```
POST /api/v1/admin/grammar/import-apkg
```

### 请求
- **方法**: POST (multipart/form-data)
- **权限**: 需要登录且具有 `grammar` 权限的管理员
- **参数**:
  - `file`: .apkg 文件 (二进制文件，最大 200MB)

### 响应

#### 成功 (200 OK)
```json
{
  "ok": true,
  "message": "导入成功：10 个课程，25 个例句，5 个音频文件",
  "stats": {
    "lessons": 10,
    "examples": 25,
    "audios": 5
  }
}
```

#### 错误
```json
{
  "error": "apkg 文件损坏：未找到 collection.anki2"
}
```

## 前端界面

### 访问地址
```
http://your-server:8002/admin/grammar-import.html
```

### 功能

#### 1. **导入标签页**
- 拖拽或点击上传 .apkg 文件
- 显示选中文件信息
- 导入进度条
- 导入结果统计（新增课程数、例句数、音频文件数）

#### 2. **课程列表标签页**
- 展示最近导入的课程
- 显示课程 JLPT 级别和例句数

## 技术实现细节

### 后端处理流程

1. **解析 Apkg**
   - 使用 `AdmZip` 解压 .apkg 文件（实际上是 zip 格式）
   - 提取 `collection.anki2` SQLite 数据库文件

2. **解析数据库**
   - 使用 `sql.js` 库在内存中解析 SQLite 数据库
   - 读取 `notes` 表,自动识别字段映射(pattern、explanation、examples 等)

3. **字段识别**
   - 自动检测各字段：
     - `pattern`: 文法说明
     - `explanation`: 英文解释
     - `explanation_zh`: 中文解释
     - `example`: 例句（可含 [sound:filename] 标签）

4. **音频提取**
   - 从例句中解析 `[sound:xxx]` 引用
   - 从 apkg 的文件列表中查找对应音频文件
   - 保存到 `/uploads/audio/grammar/` 目录
   - 返回音频 URL `/audio/grammar/filename.ext`

5. **数据保存**
   - 创建或获取 `grammar_lessons` 记录
   - 创建 `grammar_examples` 记录，关联音频 URL
   - 不覆盖已有数据（使用 `findOrCreate` 方式）
   - 递增 `grammar_version` 版本号，触发客户端同步

### 数据库表结构

#### grammar_lessons
```sql
CREATE TABLE grammar_lessons (
  id VARCHAR(36) PRIMARY KEY,
  title VARCHAR(255),
  title_zh VARCHAR(255),
  pattern TEXT,
  explanation TEXT,
  explanation_zh TEXT,
  jlpt_level ENUM('N5','N4','N3','N2','N1'),
  order_index INTEGER,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

#### grammar_examples
```sql
CREATE TABLE grammar_examples (
  id VARCHAR(36) PRIMARY KEY,
  grammar_lesson_id VARCHAR(36),
  sentence TEXT,
  reading TEXT,
  meaning_zh TEXT,
  audio_url VARCHAR(500),
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (grammar_lesson_id) REFERENCES grammar_lessons(id)
);
```

## Apkg 文件格式要求

### 推荐的字段结构

Anki 卡片应包含以下字段（自动识别）：

| 字段名 | 内容示例 | 说明 |
|--------|---------|------|
| Pattern | 〜ている | 文法说明 |
| Explanation | Progressive aspect | 英文解释 |
| ExplanationZh | 进行体 | 中文解释 |
| Example | 私は本を読ん...です。[sound:example.mp3] | 例句 + 音频 |

### 灵活的字段识别

系统自动识别以下字段名变体：

**Pattern**: pattern, 文型, grammar, 文法, structure, 構造
**Explanation**: explanation, explain, 説明, 解説, meaning, 意味
**ExplanationZh**: explanation_zh, 中文解释, chinese_exp, 翻訳, translation
**Example**: example, sentence, 例文, 例句, sample, usage, context

## 使用场景

### 场景 1: 导入新的文法库

```bash
# 用户在 Anki 中创建文法卡片集，导出为 apkg
# 在管理后台上传 apkg 文件
# 系统自动导入课程和例句
```

### 场景 2: 添加音频

```bash
# Apkg 文件中的例句包含 [sound:xxx.mp3] 标签
# 系统自动提取并保存音频文件到 /uploads/audio/grammar/
# 用户端使用 audio_url 播放音频
```

### 场景 3: 增量导入

```bash
# 多个 apkg 文件依次上传
# 重复的课程（同 pattern）自动去重，不覆盖
# 不存在的课程创建新记录
```

## 文件位置

### 后端
- **路由**: `backend/src/routes/admin.js` (L88: `/grammar/import-apkg`)
- **控制器**: `backend/src/controllers/adminController.js` (L495-617: `importGrammarApkg()`)
- **依赖**: 
  - `adm-zip`: 解压 apkg
  - `sql.js`: 解析 SQLite
  - `ankiService.js`: 字段识别和 HTML 清理

### 前端
- **页面**: `backend/public/admin/grammar-import.html`
- **访问**: `http://server:8002/admin/grammar-import.html`

### 音频存储
- **目录**: `/uploads/audio/grammar/`
- **自动创建**: 若目录不存在
- **URL**: `/audio/grammar/{filename}`

## 音频格式支持

系统支持的音频格式：
- `.mp3` (MPEG-1 Audio Layer 3)
- `.wav` (WAV/PCM)
- `.m4a` (MPEG-4 Audio)
- `.aac` (Advanced Audio Coding)
- `.flac` (Free Lossless Audio Codec)
- `.ogg` (Ogg Vorbis)
- `.webm` (WebM Audio)

## 错误处理

### 常见错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| apkg 文件损坏：未找到collection.anki2 | 上传的不是有效 apkg | 确保文件后缀为 .apkg，来自 Anki 导出 |
| apkg 文件中无有效 notes 数据 | apkg 中没有卡片 | 在 Anki 中创建卡片后再导出 |
| 网络错误 | 服务器连接失败 | 检查网络和服务器状态 |

### 日志

错误日志位于服务器：
```bash
# 查看导入日志
tail -f backend/logs/app.log
```

## 性能优化

### 允许的最大文件大小
- Apkg 文件: **200MB**
- 单个音频文件: **10MB**

### 处理流程优化
- 使用内存存储解析 apkg，不占用磁盘临时空间
- 流式复制音频文件，避免内存溢出
- 批量创建数据库记录

### 重复检查
- 使用课程 `pattern` 作为唯一标识
- 自动 `findOrCreate` 避免重复
- 同一例句多次出现自动去重

## 版本同步

导入完成后：
1. 更新 `content_version.grammar_version`++
2. 客户端检测到版本变化
3. 自动同步新的文法课程

## 相关配置

### 环境变量
```bash
# .env
UPLOAD_DIR=uploads  # 上传目录
MAX_FILE_SIZE=50mb  # 最大文件尺寸
```

### 数据库
```sql
-- 查看导入统计
SELECT COUNT(*) as total_lessons FROM grammar_lessons;
SELECT COUNT(*) as total_examples FROM grammar_examples;
SELECT COUNT(*) as total_with_audio FROM grammar_examples WHERE audio_url IS NOT NULL;
```

## 故障排查

### 🔍 检查清单

- [ ] 文件是否为有效 .apkg 格式
- [ ] 管理员账号是否具有 `grammar` 权限
- [ ] 服务器是否正常运行 (`pm2 logs`)
- [ ] 磁盘空间是否充足
- [ ] `/uploads/audio/grammar/` 目录是否可写

### 📋 测试步骤

```bash
# 1. 验证后端接口
curl -X POST http://localhost:8002/api/v1/admin/grammar/import-apkg \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@test.apkg"

# 2. 检查导入的课程
mysql -u root -p japanese_learn -e "SELECT COUNT(*) FROM grammar_lessons;"

# 3. 验证音频文件
ls -la /uploads/audio/grammar/
```

## 未来扩展

- [ ] 支持 CSV/TSV 直接导入
- [ ] 网页预览导入内容再确认
- [ ] 批量导入多个 apkg 文件
- [ ] 导入统计和日志导出
- [ ] 音频质量检测和转码
- [ ] 冲突解决方案（覆盖 vs 保留）

---

**版本**: 1.0  
**更新**: 2026-04-02  
**维护者**: AI Assistant
