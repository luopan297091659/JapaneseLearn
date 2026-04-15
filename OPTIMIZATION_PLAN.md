# 批量生成和五十音优化方案

日期: 2026-04-04

## 问题分析

### 问题1：批量生成不支持"已勾选项"
**现状**:
- 前端有词汇/文法列表，每行都有checkbox用于选择
- "一键生成Kokoro音频"按钮直接调用后端接口，不传递勾选项
- 后端`generateVocabExamplesKokoroAudio()`和`generateGrammarExamplesKokoroAudio()`总是处理**所有**未生成音频的项目

**需求**:
- 一键生成应该只处理**当前界面已勾选的项目**
- 未勾选=全选全部（向下兼容）

**影响范围**:
- 前端: `/admin/index.html` - `renderVocab()`, `generateVocabKokoroAudio()` 
- 前端: `/admin/index.html` - `renderGrammar()`, `generateGrammarKokoroAudio()`
- 后端: `adminController.js` - `generateVocabExamplesKokoroAudio()`
- 后端: `adminController.js` - `generateGrammarExamplesKokoroAudio()`

---

### 问题2：五十音无建表与生成能力
**现状**:
- 系统中无`gojuon`表
- 管理员界面无五十音管理功能
- 五十音音频依赖本地PPS（字母发音系统）

**需求**:
- 创建`Kana`表: 记录平假名/片假名及音频
- 创建管理接口: CRUD + 批量生成
- 创建前端界面: 五十音列表 + 批量生成按钮

**数据结构**:
```
Kana {
  id: UUID,
  type: ENUM('hiragana', 'katakana'),
  character: VARCHAR(10),           // 「あ」、「ア」
  romanization: VARCHAR(20),        // 「a」
  audio_url: VARCHAR(500),          // 音频URL或null
  order_index: INT,                 // 50音顺序(0-45)
  created_at/updated_at: DATETIME
}
```

**索引**:
- unique(type, order_index)
- (type)

---

### 问题3：已有音频不需要重新生成
**现状**: ✅ 代码中已有WHERE过滤逻辑  
**需求**: 前端应显示"跳过X项已有音频"的提示

---

## 实施计划

### Phase 1: 优化词汇和文法批量生成（支持勾选）
**时间**: 30分钟

#### Step 1.1: 后端接口改造
文件: `adminController.js`

**函数**: `generateVocabExamplesKokoroAudio()`
- 添加请求参数: `selectedIds` (UUID数组，optional)
- 如果提供: 只处理这些ID的词汇
- 如果未提供: 处理所有无音频的词汇（向下兼容）

```javascript
async function generateVocabExamplesKokoroAudio(req, res) {
  const selectedIds = req.body.selectedIds || null;  // NEW
  
  let where = { audio_url: { [Op.or]: [null, ''] } };
  if (selectedIds && selectedIds.length > 0) {
    where.id = { [Op.in]: selectedIds };           // NEW
  }
  
  const vocabs = await Vocabulary.findAll({ where, ... });
  // ...rest unchanged
}
```

**同时改造**: `generateGrammarExamplesKokoroAudio()`

#### Step 1.2: 前端界面改造
文件: `backend/public/admin/index.html`

**函数**: `generateVocabKokoroAudio()` → 增强为 `generateVocabKokoroAudio()`
```javascript
async function generateVocabKokoroAudio(){
  // 收集勾选的ID
  const selected = Array.from(document.querySelectorAll('.v-cb:checked'))
    .map(cb => cb.value);
  
  const msg = selected.length > 0 
    ? `确认为选中的${selected.length}项生成Kokoro音频？`
    : '确认为所有单词及例句生成Kokoro音频？';
  
  if(!confirm(msg)) return;
  
  const progressDiv = ... // UI反馈
  
  try {
    const resp = await api('POST', '/admin/vocabulary/generate-kokoro-audio', {
      selectedIds: selected.length > 0 ? selected : null  // NEW
    });
    toast(`✓ 成功生成${resp.generated}/${resp.total}个音频`);
    loadVocab();
  } finally {
    progressDiv.remove();
  }
}
```

**同时改造**: `generateGrammarKokoroAudio()`

---

### Phase 2: 创建五十音表和管理接口
**时间**: 60分钟

#### Step 2.1: 数据库建表
执行SQL:
```sql
CREATE TABLE `kana` (
  `id` CHAR(36) PRIMARY KEY,
  `type` ENUM('hiragana','katakana') NOT NULL,
  `character` VARCHAR(10) NOT NULL,
  `romanization` VARCHAR(20) NOT NULL,
  `audio_url` VARCHAR(500) NULL,
  `order_index` INT NOT NULL,
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_kana_type_order` (`type`, `order_index`),
  KEY `idx_kana_type` (`type`)
);

-- 插入平假名数据（50个）
-- INSERT INTO kana (id, type, character, romanization, order_index) VALUES ...

-- 插入片假名数据（50个）  
-- INSERT INTO kana (id, type, character, romanization, order_index) VALUES ...
```

#### Step 2.2: Sequelize Model定义
文件: `models/index.js`

```javascript
const Kana = sequelize.define('Kana', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  type: { type: DataTypes.ENUM('hiragana', 'katakana'), allowNull: false },
  character: { type: DataTypes.STRING(10), allowNull: false },
  romanization: { type: DataTypes.STRING(20), allowNull: false },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  order_index: { type: DataTypes.INTEGER, allowNull: false },
}, {
  tableName: 'kana',
  indexes: [
    { unique: true, fields: ['type', 'order_index'] },
    { fields: ['type'] },
  ],
});

module.exports = { ..., Kana };
```

#### Step 2.3: 后端接口
文件: `adminController.js`

**新增接口**:
1. `GET /admin/kana` - 列出所有五十音
2. `POST /admin/kana/:id` - 更新单个五十音 
3. `POST /admin/kana/batch-audio` - 批量生成音频（关键）
4. `DELETE /admin/kana/:id` - 删除（可选）

```javascript
// 列出五十音
async function listKana(req, res) {
  try {
    const kanas = await Kana.findAll({
      attributes: ['id', 'type', 'character', 'romanization', 'audio_url', 'order_index'],
      order: [['order_index', 'ASC']],
    });
    res.json({ data: kanas });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// 批量生成五十音音频
async function batchGenerateKanaAudio(req, res) {
  const { selectedIds } = req.body;  // optional
  
  try {
    let where = {};
    if (selectedIds && selectedIds.length > 0) {
      where.id = { [Op.in]: selectedIds };
    }
    
    const kanas = await Kana.findAll({
      where: { ...where, audio_url: { [Op.or]: [null, ''] } },
      attributes: ['id', 'character', 'romanization'],
      order: [['order_index', 'ASC']],
      raw: false,
    });
    
    if (kanas.length === 0) {
      return res.json({ success: true, message: '所有五十音都已有音频', generated: 0, total: 0 });
    }
    
    const textsToGenerate = kanas.map(k => k.character);
    const timeoutMs = Math.max(30000, textsToGenerate.length * 5000 + 20000);
    
    const resp = await axios.post(
      'http://127.0.0.1:8010/api/v1/tts/batch-generate',
      { texts: textsToGenerate, voice: 'a', emotion: 'neutral', speed: 1.0 },
      { timeout: timeoutMs }
    );
    
    const results = resp.data.results || [];
    const updatePromises = [];
    
    for (let i = 0; i < results.length; i++) {
      if (results[i]?.success && results[i]?.audio_url) {
        updatePromises.push(
          Kana.update(
            { audio_url: results[i].audio_url },
            { where: { id: kanas[i].id } }
          )
        );
      }
    }
    
    await Promise.all(updatePromises);
    res.json({
      success: true,
      generated: updatePromises.length,
      total: textsToGenerate.length,
      message: `成功生成${updatePromises.length}/${textsToGenerate.length}个五十音音频`,
    });
  } catch (apiErr) {
    res.status(504).json({ error: '音频生成超时或失败: ' + apiErr.message });
  }
}
```

#### Step 2.4: 前端管理界面
文件: `backend/public/admin/index.html`

**新增导航菜单**:
```html
<div class="nav-item" onclick="nav('kana')" id="nav-kana">
  <span class="icon">🔤</span>五十音配置
</div>
```

**新增内容区**:
```javascript
// PAGE_TITLES 等常量中添加
kana: '五十音管理'
PAGE_DESCS.kana = '管理平假名/片假名音频'
PAGE_ICONS.kana = '🔤'
PAGE_FNS.kana = renderKana

async function renderKana() {
  document.getElementById('content').innerHTML = `
    <div class="toolbar">
      <button class="btn btn-primary" onclick="generateKanaAudio()" 
        style="background:#8b5cf6;color:#fff">🎤 生成所有五十音音频</button>
    </div>
    
    <div class="panel">
      <div class="panel-header"><h3>平假名（ひらがな）</h3></div>
      <table>
        <thead><tr><th>字符</th><th>罗马音</th><th>音频</th><th>操作</th></tr></thead>
        <tbody id="hiragana-body"></tbody>
      </table>
    </div>
    
    <div class="panel">
      <div class="panel-header"><h3>片假名（カタカナ）</h3></div>
      <table>
        <thead><tr><th>字符</th><th>罗马音</th><th>音频</th><th>操作</th></tr></thead>
        <tbody id="katakana-body"></tbody>
      </table>
    </div>
  `;
  
  await loadKana();
}

async function loadKana() {
  try {
    const d = await api('GET', '/admin/kana');
    const hiragana = (d.data || []).filter(k => k.type === 'hiragana');
    const katakana = (d.data || []).filter(k => k.type === 'katakana');
    
    document.getElementById('hiragana-body').innerHTML = hiragana.map(k => `
      <tr>
        <td style="font-size:24px;text-align:center">${esc(k.character)}</td>
        <td>${esc(k.romanization)}</td>
        <td>${k.audio_url ? '✅' : '❌'}</td>
        <td>
          ${k.audio_url ? `<audio controls style="width:120px"><source src="${k.audio_url}"></audio>` : '无'}
        </td>
      </tr>
    `).join('');
    
    // 同理处理 katakana-body
  } catch (e) {
    toast('加载五十音失败: ' + e.message, true);
  }
}

async function generateKanaAudio() {
  if (!confirm('确认为所有五十音生成Kokoro音频？')) return;
  
  try {
    const resp = await api('POST', '/admin/kana/batch-audio', {});
    toast(`✓ 成功生成${resp.generated}/${resp.total}个五十音音频`);
    loadKana();
  } catch (e) {
    toast('生成失败: ' + e.message, true);
  }
}
```

---

## 实施步骤（优先级）

### Phase 1: 优化勾选逻辑 (HIGH) - 30分钟
1. ✅ 修改后端: 添加`selectedIds`参数支持
2. ✅ 修改前端: 收集并传递勾选ID

### Phase 2: 五十音功能 (MEDIUM) - 90分钟  
1. ✅ 创建`kana`表并初始化数据
2. ✅ Sequelize Model定义
3. ✅ 后端接口实现
4. ✅ 前端管理界面
5. ✅ 导航菜单集成

---

## 测试场景

### 测试1: 词汇勾选生成
- [ ] 在词汇管理页面勾选3个词汇
- [ ] 点击"一键生成Kokoro音频"
- [ ] 验证: 只有勾选的3个词汇生成音频
- [ ] 验证: 已有音频的词汇被跳过，提示消息正确

### 测试2: 五十音生成
- [ ] 进入"五十音配置"页面
- [ ] 点击"生成所有五十音音频"
- [ ] 验证: 所有50个平假名+50个片假名都生成音频
- [ ] 验证: 超时处理正确

### 测试3: 向下兼容
- [ ] 不勾选任何词汇，直接点击"一键生成"
- [ ] 验证: 处理所有无音频的词汇（原有行为）

---

## 技术债清单

- [ ] 五十音初始数据需通过脚本插入（prep_kana_data.sql）
- [ ] Kokoro TTS 是否支持日语字符？如不支持，需转罗马音处理
- [ ] 音频存储路径管理（S3/本地）
- [ ] 音频生成进度反馈UI优化
