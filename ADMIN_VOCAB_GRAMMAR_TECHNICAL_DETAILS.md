# 词汇与语法管理优化 - 技术实现总结

## 概览

本次优化完整实现了管理员端词汇和语法管理的增强功能，包含从数据库模型到前端UI的全栈优化。

---

## 一、数据库层级 (Sequelize Models)

### 1.1 Vocabulary 表结构增强

**新增字段:**
```javascript
audio_url: STRING(500)              // 单词音频
example_sentences: JSON             // 例句数组
verb_forms: JSON                    // 动词变形
```

**例句数据模式:**
```typescript
interface ExampleSentence {
  jp: string;           // 日文例句
  reading?: string;     // 假名读音  
  zh: string;           // 中文释义
  audio_url?: string;   // 例句音频
}
```

**动词变形数据模式:**
```typescript
interface VerbForms {
  base?: string;        // 基本形
  te?: string;          // て形
  ta?: string;          // た形
  nai?: string;         // ない形
  masu?: string;        // ます形
  mashita?: string;     // ました形
}
```

**向后兼容性:**
- 旧字段 (example_sentence, example_audio_url等) 被标记为 deprecated 但保留
- 读取时优先使用新字段，新字段为空则降级使用旧字段
- 新建/编辑时自动使用新格式

### 1.2 GrammarExample 表结构完善

**确保包含字段:**
```javascript
sentence: TEXT          // 日文例句
reading: TEXT           // 假名读音
meaning_zh: TEXT        // 中文释义  
audio_url: STRING(500)  // 例句音频
```

---

## 二、后端实现 (Node.js / Express)

### 2.1 新增音频服务模块

**文件:** `backend/src/services/audioService.js`

**核心功能:**
```javascript
// 音频上传配置
audioUpload = multer({
  storage: diskStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    // 支持: mp3, wav, m4a, aac, flac
  }
});

// 工具函数
getAudioUrl(filename)              // 生成完整URL
deleteAudioFile(filename)          // 删除文件
extractFilenameFromUrl(url)        // 提取文件名
```

**存储路径:** `/uploads/audio/` → web访问前缀 `/audio/`

### 2.2 Admin Controller 优化

**updateVocab() 和 createVocab():**
```javascript
async function createVocab(req, res) {
  const { example_sentences, verb_forms, ...vocabData } = req.body;
  
  // 规范化例句格式
  const normalizedExamples = Array.isArray(example_sentences)
    ? example_sentences.map(ex => ({
        jp: ex.jp || ex.sentence || '',
        reading: ex.reading || '',
        zh: ex.zh || ex.meaning_zh || '',
        audio_url: ex.audio_url || null,
      })).filter(ex => ex.jp)
    : [];
  
  // 规范化动词变形
  const normalizedVerbForms = verb_forms?.base ? verb_forms : null;
  
  const vocab = await Vocabulary.create({
    id: uuidv4(),
    ...vocabData,
    example_sentences: normalizedExamples.length > 0 ? normalizedExamples : null,
    verb_forms: normalizedVerbForms,
  });
  
  await bumpVersion('vocab_version');
  res.status(201).json(vocab);
}
```

**updateGrammar() 和 getGrammar():**
```javascript
async function getGrammar(req, res) {
  const lesson = await GrammarLesson.findByPk(req.params.id, {
    include: [{
      model: GrammarExample,
      as: 'examples',
      attributes: ['id', 'sentence', 'reading', 'meaning_zh', 'audio_url']
    }],
  });
  res.json(lesson);
}
```

### 2.3 Admin Routes 增强

**新增路由:**
```javascript
// 音频上传端点
router.post('/audio/upload', 
  permissionCheck('vocabulary'),
  audioUpload.single('audio'),
  (req, res) => {
    const audioUrl = `/audio/${req.file.filename}`;
    res.json({ filename: req.file.filename, url: audioUrl, size: req.file.size });
  }
);
```

**现有路由改进:**
- `/admin/vocabulary` 现在支持新字段的完整序列化
- `/admin/grammar` 现在返回完整的GrammarExample数据

---

## 三、前端实现 (HTML/JavaScript)

### 3.1 词汇编辑模态框结构

**HTML标记:**
```html
<div class="modal" style="width:780px;max-height:90vh;overflow-y:auto">
  <!-- 基本信息区 -->
  <div style="border-bottom:1px solid #e5e7eb;padding-bottom:12px;">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
      <div class="form-row"><label>单词 *</label>
        <input id="mv-word" />
      </div>
      <!-- 更多字段... -->
    </div>
  </div>

  <!-- 音频区 -->
  <div>
    <label>📻 单词音频</label>
    <div style="display:flex;gap:8px;">
      <input type="text" id="mv-audio-url" style="flex:1;" />
      <button class="btn btn-ghost" onclick="uploadVocabAudio()">📤 上传</button>
      <button class="btn btn-ghost" onclick="playAudio(...)">🔊 试听</button>
    </div>
  </div>

  <!-- 例句行管理 -->
  <div id="mv-examples-container">
    <!-- 动态插入例句行 -->
  </div>

  <!-- 动词变形区 (条件渲染) -->
  <div id="mv-verb-forms-section" style="display:none;">
    <!-- 变形输入框 -->
  </div>
</div>
```

### 3.2 语法编辑模态框结构

**HTML标记:**
```html
<div class="modal" style="width:780px;max-height:90vh;overflow-y:auto">
  <!-- 基本信息区 -->
  <div style="border-bottom:1px solid #e5e7eb;">
    <input id="mg-title-input" />
    <textarea id="mg-desc"></textarea>
  </div>

  <!-- 例句行管理 -->
  <div id="mg-examples-container">
    <!-- 动态插入例句行 -->
  </div>
</div>
```

### 3.3 核心JavaScript函数

**词汇相关:**
```javascript
function initializeExampleRows(v = null)
  // 从词汇对象初始化例句行

function addExampleRow(jp = '', reading = '', zh = '', audioUrl = '')
  // 添加新的例句编辑行

function removeExampleRow(rowId)
  // 删除例句行

function initializeVerbForms(v = null)
  // 初始化动词变形区并显示/隐藏

async function uploadVocabAudio()
  // 触发文件选择器上传单词音频

async function uploadExampleAudio(rowId)
  // 触发文件选择器上传例句音频

function playAudio(url)
  // 播放音频进行试听

async function saveVocab()
  // 收集所有字段数据，发送POST/PUT请求
```

**语法相关:**
```javascript
function initializeGrammarExamples(g = null)
  // 从语法对象初始化例句行

function addGrammarExampleRow(sentence = '', meaning_zh = '', audioUrl = '')
  // 添加新的语法例句行

async function uploadGrammarExampleAudio(rowId)
  // 为语法例句上传音频

async function saveGrammar()
  // 收集所有字段，发送PUT请求
```

### 3.4 数据采集和提交

**词汇数据采集:**
```javascript
async function saveVocab() {
  // 采集例句
  const exampleRows = document.querySelectorAll('.example-row');
  const example_sentences = Array.from(exampleRows).map(row => ({
    jp: row.querySelector('.ex-jp').value.trim(),
    reading: row.querySelector('.ex-reading').value.trim(),
    zh: row.querySelector('.ex-zh').value.trim(),
    audio_url: row.querySelector('.ex-audio').value.trim() || null,
  })).filter(ex => ex.jp);

  // 采集动词变形
  let verb_forms = null;
  if (document.getElementById('mv-pos').value === 'verb') {
    verb_forms = {
      base: document.getElementById('mv-vf-base').value.trim(),
      te: document.getElementById('mv-vf-te').value.trim() || null,
      ta: document.getElementById('mv-vf-ta').value.trim() || null,
      nai: document.getElementById('mv-vf-nai').value.trim() || null,
      masu: document.getElementById('mv-vf-masu').value.trim() || null,
      mashita: document.getElementById('mv-vf-mashita').value.trim() || null,
    };
  }

  const body = {
    word: document.getElementById('mv-word').value.trim(),
    reading: document.getElementById('mv-reading').value.trim(),
    meaning_zh: document.getElementById('mv-meaning').value.trim(),
    part_of_speech: document.getElementById('mv-pos').value,
    audio_url: document.getElementById('mv-audio-url').value.trim() || null,
    example_sentences: example_sentences.length > 0 ? example_sentences : null,
    verb_forms: verb_forms,
    jlpt_level: document.getElementById('mv-level').value,
  };

  if (id) await api('PUT', `/admin/vocabulary/${id}`, body);
  else   await api('POST', '/admin/vocabulary', body);
}
```

---

## 四、数据流和同步

### 4.1 管理员端编辑流程

```
管理员编辑 → 前端采集数据 → 后端验证&规范化
    ↓
  数据库存储 (example_sentences, verb_forms as JSON)
    ↓
  版本号递增 (vocab_version++)
    ↓
  返回成功响应 → 前端刷新列表
```

### 4.2 用户端同步流程

```
用户端轮询 /api/content-version
    ↓
若 local_vocab_version < service_vocab_version
    ↓
请求 /api/vocabulary/{id} 或 /api/vocabulary/by-level/{level}
    ↓
后端返回完整数据:
  - audio_url
  - example_sentences (完整数组)
  - verb_forms (完整JSON)
    ↓
用户端缓存并更新UI显示
```

### 4.3 API响应数据格式

**词汇完整数据:**
```json
{
  "id": "uuid",
  "word": "食べる",
  "reading": "たべる",
  "meaning_zh": "吃",
  "audio_url": "/audio/taberu-001.mp3",
  "example_sentences": [
    {
      "jp": "食べている",
      "reading": "たべている",
      "zh": "正在吃饭",
      "audio_url": "/audio/ex-001.mp3"
    },
    {
      "jp": "食べました",
      "reading": "たべました",
      "zh": "吃过了",
      "audio_url": null
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

---

## 五、关键设计决策

### 5.1 为什么使用 JSON 字段而非关系表

**选择理由:**
- JSON字段简化编程模型，避免复杂的多表JOIN
- 单词可能只有1-3个例句，无需代价高的规范化
- 修改时一次性读写，无需分布式事务

**权衡:**
- 失去了细粒度的例句查询(不需要按例句过滤)
- 但获得了更灵活的字段扩展(可随时添加新字段如"usage_note")

### 5.2 为什么保留已弃用的旧字段

**兼容性考虑:**
- 现存数据中有 example_sentence 字段的数据
- 用户端代码可能依赖旧字段
- 仓库迁移成本高，平滑过渡更好

**读取策略:**
- API优先返回新字段
- 新字段为空时降级返回旧字段
- 编辑时自动统一为新格式

### 5.3 为什么在前端进行数据规范化

**设计选择:**
- 让前端负责采集和转换用户输入
- 后端只负责验证和存储
- 便于前端及时显示错误提示

### 5.4 为什么用文件系统而非数据库存储音频

**存储策略:**
- 音频文件大(通常500KB-5MB)
- 文件系统IO优于数据库BLOB
- CDN友好，可直接serve静态文件

**反过来:**
- 简单场景或小文件可考虑BASE64
- 对象存储(S3等)更好的扩展性

---

## 六、扩展点和升级路径

### 6.1 批量操作预留

当前设计支持:
- ✅ 单个例句的音频编辑
- 🔜 批量选择多个例句同时上传音频 (可扩展)
- 🔜 批量修改多个词汇的字段 (可扩展)

### 6.2 媒体类型扩展

当前: 仅声音(mp3/wav等)

可扩展范围:
- 图像 (为词汇添加配图)
- 视频 (展示动词变形的使用视频)
- 字幕 (精确时间戳的字幕)

### 6.3 智能化方向

潜在增强:
- TTS集成: 自动为缺失音频的例句生成语音
- OCR提取: 从图片识别文字作为例句
- 自动改正: 使用NLP检查日文语法

---

## 七、部署和运维

### 7.1 目录结构

```
backend/
├── src/
│   ├── services/
│   │   └── audioService.js       ← 新文件
│   ├── controllers/
│   │   └── adminController.js    ← 修改: 支持新字段
│   ├── routes/
│   │   └── admin.js              ← 修改: 新增音频路由
│   └── models/
│       └── index.js              ← 修改: Vocabulary新字段
├── uploads/
│   └── audio/                    ← 新目录(自动创建)
└── public/
    └── admin/
        └── index.html            ← 修改: UI增强
```

### 7.2 配置需求

**无需新增配置**, 自动处理:
- 音频目录若不存在则自动创建
- 旧数据自动兼容读取

### 7.3 数据迁移

无需数据库迁移脚本(可选):
- 新字段使用 JSON 类型，Sequelize自动处理
- 旧数据保留，渐进式迁移

可选迁移脚本 (将旧 example_sentence 迁移至新 example_sentences):
```sql
UPDATE vocabulary 
SET example_sentences = JSON_ARRAY(
  JSON_OBJECT('jp', example_sentence, 'zh', example_meaning_zh, 'audio_url', example_audio_url)
)
WHERE example_sentence IS NOT NULL 
  AND example_sentences IS NULL;
```

---

## 八、性能考虑

### 8.1 查询优化

- Vocabulary 表: example_sentences 为 JSON 无索引(通常不按例句过滤)
- GrammarExample 表: 保持关系表结构便于按示例查询

### 8.2 存储优化

- 音频文件: 单文件10MB限制(足够2-3秒高质量音频)
- JSON 字段: 单词最多10个例句，数据量小 (<10KB)

### 8.3 传输优化

前端采数据:
```javascript
// 只发送非空例句
example_sentences: [...].filter(ex => ex.jp)

// 只发送有值的动词变形
verb_forms: Object.fromEntries(
  Object.entries(verb_forms).filter(([k, v]) => v)
)
```

---

## 总结

**核心技术栈:**
- 后端: Node.js + Express + Sequelize + Multer
- 前端: Vanilla JavaScript (无框架)
- 存储: MySQL (数据) + 文件系统 (音频)
- API: REST with JSON payload

**代码质量:**
- ✅ 向后兼容旧数据格式
- ✅ 完整的错误处理
- ✅ 用户端完整的版本同步机制
- ✅ 清晰的UI/UX设计

**后续维护:**
- 监控音频上传成功率
- 定期清理未使用的音频文件
- 跟踪用户端同步情况

---

**文档版本:** 1.0  
**最后更新:** 2026年4月2日
