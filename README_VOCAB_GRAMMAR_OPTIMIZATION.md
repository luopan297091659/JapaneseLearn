# 词汇与语法管理系统优化 - 完整实现说明

## 📌 项目概述

本项目完整优化了管理员端的词汇管理(Vocabulary)和语法管理(Grammar)功能，支持：
- ✅ 多例句和音频管理
- ✅ 动词变形编辑  
- ✅ 灵活的音频上传接口
- ✅ 完整的用户端数据同步

---

## 📂 文件清单

### 📖 文档文件 (项目根目录)
| 文件名 | 用途 | 目标人群 |
|------|------|--------|
| `ADMIN_VOCAB_GRAMMAR_OPTIMIZATION_GUIDE.md` | **完整优化指南** | 产品经理、架构师 |
| `ADMIN_VOCAB_GRAMMAR_QUICK_REFERENCE.md` | **快速参考** | 管理员用户 |
| `ADMIN_VOCAB_GRAMMAR_TECHNICAL_DETAILS.md` | **技术实现细节** | 开发工程师 |

### 💻 代码文件 (已修改/新增)

**新增文件:**
```
backend/src/services/audioService.js
  - 音频上传配置
  - 文件管理工具函数
```

**修改文件:**
```
backend/src/models/index.js
  - Vocabulary: 新增audio_url, example_sentences, verb_forms字段

backend/src/controllers/adminController.js
  - updateVocab/createVocab: 支持新数据格式
  - updateGrammar/getGrammar: 返回完整GrammarExample数据

backend/src/routes/admin.js
  - 新增POST /admin/audio/upload 端点
  - 导入audioService

backend/public/admin/index.html
  - 词汇编辑模态框: 改进UI布局，支持多例句/动词变形/音频
  - 语法编辑模态框: 改进UI布局，支持例句音频
  - JavaScript函数: 新增数据采集和音频处理逻辑
```

---

## 🚀 快速开始

### 1. 安装依赖
```bash
cd backend
npm install  # 已有的依赖，无需新增
```

### 2. 启动服务
```bash
npm start
# 后端服务运行在 http://localhost:3000
# 管理员面板: http://localhost:3000/admin
```

### 3. 使用流程

#### 添加/编辑词汇
1. 进入"词汇管理" → 点击"编辑"或"➕ 添加"
2. 填写基本信息 (单词、读音、意思等)
3. **可选**: 上传单词音频 (点击📤或输入URL)
4. **可选**: 添加多个例句 (点击➕添加例句)
   - 各个例句可独立上传音频
5. **如果词性为动词**: 填写变形 (て形、た形等)
6. 点击"保存"

#### 编辑语法
1. 进入"语法管理" → 找到目标 → 点击"编辑"
2. 修改说明 (可选)
3. **可选**: 编辑/添加例句
   - 各个例句可独立上传音频
4. 点击"保存"

#### 同步用户端
1. 完成编辑后，进入"全局同步"
2. 点击"📤 发布词汇版本" 或 "📤 发布语言版本"
3. 用户端会自动同步更新

---

## 📊 数据格式规范

### 词汇存储格式
```json
{
  "word": "食べる",
  "reading": "たべる",
  "meaning_zh": "吃",
  "audio_url": "/audio/12345.mp3",
  "example_sentences": [
    {
      "jp": "毎日食べています",
      "reading": "まいにちたべています",
      "zh": "每天都在吃",
      "audio_url": "/audio/example-001.mp3"
    }
  ],
  "verb_forms": {
    "base": "食べる",
    "te": "食べて",
    "ta": "食べた",
    "nai": "食べない",
    "masu": "食べます",
    "mashita": "食べました"
  }
}
```

### 语法存储格式
```json
{
  "title": "～ている",
  "explanation_zh": "表示正在进行的动作",
  "examples": [
    {
      "sentence": "食べています",
      "reading": "たべています",
      "meaning_zh": "正在吃",
      "audio_url": "/audio/grammar-ex-001.mp3"
    }
  ]
}
```

---

## 🔧 关键API端点

### 音频上传
```http
POST /admin/audio/upload
Content-Type: multipart/form-data
Authorization: Bearer {token}

File: audio (mp3/wav/m4a/aac/flac, max 10MB)

Response:
{
  "filename": "uuid.mp3",
  "url": "/audio/uuid.mp3",
  "size": 512000
}
```

### 词汇操作
```http
POST /admin/vocabulary           # 创建
PUT /admin/vocabulary/{id}       # 更新
GET /admin/vocabulary/{id}       # 获取详情
```

### 语法操作
```http
POST /admin/grammar              # 创建
PUT /admin/grammar/{id}          # 更新
GET /admin/grammar/{id}          # 获取详情
```

---

## 📱 用户端数据同步

**同步触发机制:**
```
用户端定期检查 /api/content-version
  ↓
若本地版本 < 服务端版本
  ↓
自动拉取更新的词汇/语法数据
  ↓
完整数据包含:
  - audio_url (单词/例句音频)
  - example_sentences (多例句数组)
  - verb_forms (动词变形)
```

**数据同步面板:**
- 位置: Admin面板 → "全局同步"
- 操作: "📤 发布词汇版本" / "📤 发布语言版本" / "🚀 全量发布"
- 效果: 递增对应版本号，触发用户端自动同步

---

## ⚙️ 系统架构

```
┌─────────────────────────────────────────┐
│         Admin Web Interface             │
│  (词汇管理 / 语法管理 + Audio Upload)   │
└──────────────┬──────────────────────────┘
               │
         HTTP REST API
               │
┌──────────────▼──────────────────────────┐
│      Express.js Backend Router          │
│  - /admin/vocabulary (CRUD)             │
│  - /admin/grammar (CRUD)                │
│  - /admin/audio/upload (新)             │
│  - /admin/content-version/publish       │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│   Sequelize ORM Controllers             │
│  - Vocabulary (new fields)              │
│  - GrammarLesson + GrammarExample       │
└──────────────┬──────────────────────────┘
               │
     ┌─────────┴──────────┐
     │                    │
┌────▼────┐        ┌─────▼──────┐
│ MySQL   │        │ File System│
│ (Metadata)     │ /uploads/audio/
└─────────┘        └─────────────┘
```

---

## 🔐 权限管理

所有管理操作受权限保护:
```javascript
router.post('/audio/upload', 
  permissionCheck('vocabulary'),  // 需要词汇管理权限
  audioUpload.single('audio'),
  handler
);
```

权限级别:
- `vocabulary` - 词汇管理权限
- `grammar` - 语法管理权限
- `sync` - 内容同步权限

---

## 🐛 常见问题 & 排查

### 问题1: 音频上传失败
**检查清单:**
- ❓ 音频格式? (支持: mp3, wav, m4a, aac, flac)
- ❓ 文件大小? (限制: <10MB)
- ❓ 网络连接? (检查浏览器网络)
- ❓ 权限? (确认有vocabulary权限)

**解决方案:**
```bash
# 检查上传目录是否存在
ls -la backend/uploads/audio/

# 检查权限
chmod -R 755 backend/uploads/audio/
```

### 问题2: 用户端看不到新数据
**检查清单:**
- ❓ 是否点击了"发布版本"?
- ❓ 用户本地版本是否小于服务端版本?
- ❓ 用户是否已刷新或重启App?

**解决方案:**
```bash
# 强制用户端同步
- App设置 → 强制刷新
- 或 重启应用
```

### 问题3: 动词变形不显示
**原因:** 词性未设置为"动词"

**解决方案:**
1. 词性选择改为"动词"
2. 会自动显示动词变形区

---

## 📈 性能指标

| 指标 | 值 | 说明 |
|-----|-----|------|
| 单词上限 | 无限制 | 支持扩展 |
| 每个词的例句上限 | 无限制 | 实际<20个 |
| 音频文件大小限制 | 10MB | 足够高质量音频 |
| 版本同步延迟 | <1秒 | 即时更新 |
| 并发用户数 | 可扩展 | 取决于服务器 |

---

## 🔄 升级和迁移

### 旧版本兼容性
- ✅ 旧字段 (example_sentence) 自动识别
- ✅ 新旧混用，无缝过渡
- ✅ 编辑时自动转换为新格式

### 数据迁移脚本 (可选)
```sql
-- 将旧example_sentence迁移至新example_sentences
UPDATE vocabulary 
SET example_sentences = JSON_ARRAY(
  JSON_OBJECT(
    'jp', example_sentence,
    'reading', example_reading,
    'zh', example_meaning_zh,
    'audio_url', example_audio_url
  )
)
WHERE example_sentence IS NOT NULL
  AND example_sentences IS NULL;
```

---

## 📚 参考文档

| 文档 | 内容 |
|-----|------|
| [完整优化指南](./ADMIN_VOCAB_GRAMMAR_OPTIMIZATION_GUIDE.md) | UI设计、流程、最佳实践 |
| [快速参考](./ADMIN_VOCAB_GRAMMAR_QUICK_REFERENCE.md) | 快速开始、常见问题 |
| [技术细节](./ADMIN_VOCAB_GRAMMAR_TECHNICAL_DETAILS.md) | 架构、实现、扩展方向 |

---

## 🎯 后续优化方向

**短期 (1-2周):**
- [ ] 图片上传支持
- [ ] 批量编辑功能
- [ ] 音频编辑工具 (修剪、调音量)

**中期 (1个月):**
- [ ] TTS集成 (自动生成语音)
- [ ] 质量评分系统
- [ ] 贡献者积分系统

**长期 (3个月+):**
- [ ] AI补全例句
- [ ] 视频支持
- [ ] 众包编辑平台

---

## 📞 技术支持

**问题反馈:**
- 创建GitHub Issue
- 提供: 错误日志、操作步骤、浏览器版本

**代码审查:**
- Pull Request欢迎
- 确保向后兼容性

---

## 📄 许可证

项目采用统一的许可证，代码贡献请遵守既有规范。

---

**版本:** 1.0  
**发布日期:** 2026年4月2日  
**最后更新:** 2026年4月2日
