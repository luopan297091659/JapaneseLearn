# 批量生成和五十音优化 - 完成报告

**完成日期**: 2026年4月4日  
**优化版本**: v1.1.0  
**涉及模块**: 词汇管理、文法管理、五十音管理

---

## 1. 优化概览

本次优化主要解决两个问题：

### ✅ 问题1：批量生成支持"已勾选项"（已完成）
**改进**:
- 前端词汇/文法列表中的"一键生成Kokoro音频"现在支持勾选指定项目
- 用户可选择只为勾选的项目生成音频
- 未勾选时保持原有行为（生成全部）

**修改范围**:
- `backend/public/admin/index.html`: `generateVocabKokoroAudio()` 和 `generateGrammarKokoroAudio()`
- `backend/src/controllers/adminController.js`: `generateVocabExamplesKokoroAudio()` 添加 `selectedIds` 参数

### ✅ 问题2：五十音表建立和音频生成（已完成基础实现）
**新增功能**:
- 创建 `kana` 数据库表，存储平假名和片假名
- 后端接口支持列出五十音和批量生成音频
- 前端管理界面可访问（待UI完善）

**新增文件**:
- `backend/database/init_kana_table.sql`: 数据库初始化脚本
- 五十音管理后端接口: `/api/v1/admin/kana` 和 `/api/v1/admin/kana/batch-audio`

### ✅ 问题3：已有音频不需要重新生成（已实现）
- 代码中已有 WHERE 过滤逻辑
- 在响应消息中显示"已跳过X项已有音频"

---

## 2. 代码修改详情

### A. 前端修改 (HTML/JavaScript)

**文件**: `backend/public/admin/index.html`

#### 修改1: 词汇生成函数
```javascript
async function generateVocabKokoroAudio(){
  // ✅ 收集勾选的词汇ID
  const selectedIds = Array.from(document.querySelectorAll('.v-cb:checked'))
    .map(cb => cb.value);
  const isSelective = selectedIds.length > 0;
  
  // 根据是否勾选显示不同提示
  const confirmMsg = isSelective 
    ? `确认为选中的${selectedIds.length}项词汇生成Kokoro音频？`
    : '确认为所有单词及例句生成Kokoro音频？';
  
  if(!confirm(confirmMsg)) return;
  
  // ... 进度条UI ...
  
  try {
    // ✅ 传递选中项ID列表
    const body = selectedIds.length > 0 ? { selectedIds } : {};
    const resp = await api('POST', '/admin/vocabulary/generate-kokoro-audio', body);
    toast(`✓ 成功生成${resp.generated}/${resp.total}个音频`);
    loadVocab();
  } catch(e) {
    toast('生成失败: ' + e.message, true);
  }
}
```

#### 修改2: 文法生成函数
```javascript
async function generateGrammarKokoroAudio(){
  const selectedIds = Array.from(document.querySelectorAll('.gr-cb:checked'))
    .map(cb => cb.value);
  // ...
  const body = selectedIds.length > 0 ? { grammar_ids: selectedIds } : {};
  const resp = await api('POST', '/admin/grammar/generate-kokoro-audio', body);
  // ...
}
```

### B. 后端修改 (Node.js/JavaScript)

**文件1**: `backend/src/controllers/adminController.js`

#### 修改1: 词汇生成函数参数支持
```javascript
async function generateVocabExamplesKokoroAudio(req, res) {
  try {
    // ✅ 支持指定词汇ID列表
    const { selectedIds } = req.body || {};
    
    let vocabWhere = { audio_url: { [Op.or]: [null, ''] } };
    if (selectedIds && Array.isArray(selectedIds) && selectedIds.length > 0) {
      vocabWhere.id = { [Op.in]: selectedIds };  // 只处理选中的ID
    }
    
    const vocabs = await Vocabulary.findAll({
      where: vocabWhere,
      attributes: ['id', 'word', 'reading'],
      raw: false,
    });
    // ... rest of function
  }
}
```

#### 修改2: 新增五十音管理函数
```javascript
// 列出所有五十音
async function listKana(req, res) {
  const { type } = req.query;  // 可选: hiragana或katakana
  let where = {};
  if (type) where.type = type;
  
  const kanas = await sequelize.models.Kana.findAll({
    where,
    attributes: ['id', 'type', 'character', 'romanization', 'audio_url', 'order_index'],
    order: [['order_index', 'ASC']],
    raw: true,
  });
  
  res.json({ data: kanas });
}

// 批量生成五十音音频
async function batchGenerateKanaAudio(req, res) {
  const { selectedIds } = req.body || {};
  
  let where = { audio_url: { [Op.or]: [null, ''] } };
  if (selectedIds && Array.isArray(selectedIds) && selectedIds.length > 0) {
    where.id = { [Op.in]: selectedIds };
  }
  
  const Kana = sequelize.models.Kana;
  const kanas = await Kana.findAll({
    where,
    attributes: ['id', 'character', 'romanization'],
    order: [['order_index', 'ASC']],
  });
  
  // 调用Kokoro API生成音频...
}
```

**文件2**: `backend/src/models/index.js`

#### 新增: Kana 数据模型
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

**文件3**: `backend/src/routes/admin.js`

#### 新增: 五十音路由
```javascript
// 导入新函数
const { ..., listKana, batchGenerateKanaAudio } = require('../controllers/adminController');

// 注册路由
router.get('/kana', permissionCheck('vocabulary'), asyncHandler(listKana));
router.post('/kana/batch-audio', permissionCheck('vocabulary'), asyncHandler(batchGenerateKanaAudio));
```

### C. 数据库修改 (SQL)

**文件**: `backend/database/init_kana_table.sql`

创建五十音表并初始化平假名(73个)和片假名(73个)数据：
```sql
CREATE TABLE kana (
  id CHAR(36) PRIMARY KEY,
  type ENUM('hiragana','katakana') NOT NULL,
  character VARCHAR(10) NOT NULL,
  romanization VARCHAR(20) NOT NULL,
  audio_url VARCHAR(500) NULL,
  order_index INT NOT NULL,
  ...
);

INSERT INTO kana VALUES (UUID(), 'hiragana', 'あ', 'a', NULL, 0), ...
```

---

## 3. 功能使用指南

### 词汇批量生成（改进）

**操作流程**:
1. 进入"词汇管理"页面
2. 在词汇列表中勾选需要生成音频的词汇（或全不勾选为全选）
3. 点击"🎤 一键生成Kokoro音频"按钮
4. 确认弹窗显示目标数量
5. 等待生成完成

**提示信息示例**:
- 已勾选: "💬 确认为选中的5项词汇生成Kokoro音频？"
- 未勾选: "💬 确认为所有单词及例句生成Kokoro音频？"

### 五十音音频生成

**当前状态**: 后端接口已完成，前端UI待完善

**API接口**:
```bash
# 列出所有五十音
GET /api/v1/admin/kana
GET /api/v1/admin/kana?type=hiragana  # 只显示平假名

# 批量生成五十音音频
POST /api/v1/admin/kana/batch-audio
Body: { selectedIds: ["uuid1", "uuid2"] }  # 可选，不提供则全选
```

**手动测试**:
```bash
curl -X GET http://localhost:8002/api/v1/admin/kana \
  -H "Authorization: Bearer YOUR_TOKEN"

curl -X POST http://localhost:8002/api/v1/admin/kana/batch-audio \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

## 4. 部署步骤

### 步骤1: 初始化数据库（一次性，如未执行）
```bash
cd backend/database
mysql -u root -p < init_kana_table.sql
```

### 步骤2: 代码部署
```bash
cd backend
git add -A
git commit -m "Feature: Add selective batch audio generation and Kana management"
npm test  # 可选：运行测试
```

### 步骤3: 启动后端服务
```bash
npm start
# 或通过 deploy.ps1
.\deploy.ps1
```

### 步骤4: 验证（可选）
```bash
# 检查五十音表是否存在
mysql -u root -p -e "SELECT COUNT(*) FROM kana;"

# 验证API响应
curl -X GET http://localhost:8002/api/v1/admin/kana \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq '.data | length'
# 应返回: 146（73个平假名+73个片假名）
```

---

## 5. 技术细节

### 数据库设计
```
表: kana
- 总行数: 146 (73 平假名 + 73 片假名)
- 主键: id (UUID)
- 唯一约束: (type, order_index)
- 索引: type, audio_url (加速查询未生成的)
```

### 性能优化
- 批量生成时使用 `Promise.all()` 并发更新（避免顺序更新）
- Kokoro 超时计算: `max(30s, text_count * 5s + 20s buffer)`
- 前端缓存清理: 生成完成后自动清除 `_vocabCache` 和 `_grammarCache`

### 错误处理
- **ECONNABORTED**: 超时错误 → 返回 504 Gateway Timeout
- **ECONNREFUSED**: Kokoro服务无法连接 → 返回 503 Service Unavailable
- **其他错误**: 返回 500 及详细信息

---

## 6. 已知限制与改进方向

### 当前限制
1. ⚠️ 五十音前端UI未完善（仅有后端接口）
2. ⚠️ Kokoro TTS 对日语字符的处理需验证
3. ⚠️ 音频存储路径依赖环境配置

### 改进方向（未来版本）
- [ ] 五十音前端管理界面（列表、实时播放、进度反馈）
- [ ] 音频质量校验（检测生成的音频是否有效）
- [ ] 库存导出（导出五十音音频为 zip/apkg）
- [ ] 性能监控（记录生成耗时、success rate等）
- [ ] 多语言支持（片假名、小假名、促音等变化形式）

---

## 7. 测试清单

### 单元测试
- [ ] 词汇勾选ID收集正确
- [ ] 文法勾选ID收集正确
- [ ] 后端参数验证（selectedIds 类型检查）
- [ ] WHERE 过滤逻辑（已有音频正确排除）

### 集成测试
- [ ] 词汇：勾选3个 → 生成3个（+例句）
- [ ] 词汇：全不勾选 → 生成全部
- [ ] 文法：勾选2个 → 生成2个的例句
- [ ] 五十音：生成73个平假名
- [ ] 五十音：生成73个片假名

### 用户验收测试
- [ ] UI 提示信息清晰（显示目标数量）
- [ ] 进度条反馈（生成过程中显示百分比）
- [ ] 重复生成：已有音频自动跳过
- [ ] 错误处理：Kokoro 超时正确提示

---

## 8. 版本控制

**Git Commit**:
```
commit: Fix: Filter out vocabs/grammars with existing audio URLs + Add Kana management

- Optimize batch audio generation to support selected items (vocabulary & grammar)
- Add Kana table and backend API for Japanese Hiragana/Katakana audio generation
- Support both selective and full batch processing
- Improve error handling and timeout management
```

**文件变更统计**:
- `backend/public/admin/index.html`: +40 lines (勾选收集逻辑)
- `backend/src/controllers/adminController.js`: +130 lines (Kana API)
- `backend/src/models/index.js`: +25 lines (Kana model)
- `backend/src/routes/admin.js`: +5 lines (Kana routes)
- `backend/database/init_kana_table.sql`: 新建 (150 lines)

**总计**: 约 350 行新增/修改代码

---

## 9. 反馈和支持

**遇到问题**:
1. 检查 Kokoro TTS 服务是否运行 (`pm2 list`)
2. 验证数据库表已创建 (`SELECT * FROM kana LIMIT 1;`)
3. 查看后端日志: `/root/.pm2/logs/japanese-learn-*`
4. 检查前端浏览器控制台错误

**联系相关负责人**:
- 后端: 检查 adminController.js 函数实现
- 数据库: 确认 kana 表初始化脚本执行
- 前端: 查看网络请求和响应数据

---

**报告完成日期**: 2026-04-04  
**优化状态**: ✅ Phase 1-2 完成, Phase 3 (前端UI) 待完善
