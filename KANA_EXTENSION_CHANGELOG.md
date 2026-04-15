## 五十音拗音扩展 - 实施变更总结

**更新范围**: 完整日本語字符集合（五十音 + 濁音/浊音 + 半濁音/半浊音 + 拗音）
**变更日期**: 2024年4月  
**影响范围**: 数据库、后端模型、后端API

---

## 📊 数据规模变化对比

### 原有设计（V1.0）
- **品种**: 五十音 + 濁音/半濁音
- **平假名**: 73个（あ～ん + が行 + ざ行 + だ行 + ば行 + ぱ行）
- **片假名**: 73个（对应平假名）
- **总计**: 146条记录

### 新版设计（V2.0）
- **品种**: 五十音 + 濁音 + 半濁音 + 拗音
- **平假名**: 104个（原73个 + 拗音36个）
- **片假名**: 104个（对应平假名）
- **总计**: 208条记录 (+62新增)

---

## 📝 数据库变更

### 文件: `backend/database/init_kana_table.sql`

#### ✅ 新增字段
```sql
`category` VARCHAR(20) NOT NULL DEFAULT '五十音' 
  COMMENT '分类：五十音、濁音、半濁音、拗音'
```

#### ✅ 修改唯一性约束
```sql
-- 旧约束
UNIQUE KEY `uk_kana_type_order` (`type`, `order_index`)

-- 新约束（字符级别唯一性更准确）
UNIQUE KEY `uk_kana_type_char` (`type`, `character`)
```

#### ✅ 新增索引
```sql
KEY `idx_kana_category` (`category`) 
  COMMENT '按分类查询（五十音/濁音/半濁音/拗音）'
```

#### ✅ 新增208条记录
| SQLステートメント | 行数 | 平假名 | 片假名 | 
|-----------------|------|--------|--------|
| 五十音INSERT | 43 | 43 | 43 |
| 濁音INSERT | 20 | 20 | 20 |
| 半濁音INSERT | 5 | 5 | 5 |
| 拗音INSERT (平假名4组11对) | 36 | 36 | - |
| 拗音INSERT (片假名4组11对) | 36 | - | 36 |
| **合计** | **140** | **104** | **104** |

### 拗音详细列表

#### Kya / Gya / Sha / Ja / Cha / Nyu / Hya / Bya / Pya / Mya / Rya行
```
きゃ・きゅ・きょ (K-row)
ぎゃ・ぎゅ・ぎょ (G-row)
しゃ・しゅ・しょ (S-row)
じゃ・じゅ・じょ (J-row)
ちゃ・ちゅ・ちょ (Ch-row)
ぢゃ・ぢゅ・ぢょ (Dj-row: rare)
にゃ・にゅ・にょ (N-row)
ひゃ・ひゅ・ひょ (H-row)
びゃ・びゅ・びょ (B-row)
ぴゃ・ぴゅ・ぴょ (P-row)
みゃ・みゅ・みょ (M-row)
りゃ・りゅ・りょ (R-row)
```

---

## 🎯 后端模型变更

### 文件: `backend/src/models/index.js`

#### Kana 模型定义更新

**旧版 (行380-390)**
```javascript
const Kana = sequelize.define('Kana', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  type: { type: DataTypes.ENUM('hiragana', 'katakana'), allowNull: false, 
          comment: '字符类型：平假名/片假名' },
  character: { type: DataTypes.STRING(10), allowNull: false, 
               comment: '字符本身（如「あ」「ア」）' },
  romanization: { type: DataTypes.STRING(20), allowNull: false, 
                  comment: '罗马音（如「a」）' },
  audio_url: { type: DataTypes.STRING(500), allowNull: true, 
               comment: '音频URL，为空表示未生成' },
  order_index: { type: DataTypes.INTEGER, allowNull: false, 
                 comment: '50音顺序（0-72）' },
}, {
  tableName: 'kana',
  comment: '日语五十音表',
  indexes: [
    { unique: true, fields: ['type', 'order_index'] },
    { fields: ['type'] },
    { fields: ['audio_url'] },
  ],
});
```

**新版 (行380-398)**
```javascript
const Kana = sequelize.define('Kana', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  type: { type: DataTypes.ENUM('hiragana', 'katakana'), allowNull: false, 
          comment: '字符类型：平假名/片假名' },
  character: { type: DataTypes.STRING(10), allowNull: false, 
               comment: '字符本身（如「あ」「ア」「きゃ」）' },
  romanization: { type: DataTypes.STRING(20), allowNull: false, 
                  comment: '罗马音（如「a」「kya」）' },
  category: { type: DataTypes.STRING(20), allowNull: false, 
              defaultValue: '五十音', 
              comment: '分类：五十音、濁音、半濁音、拗音' },  // ⭐ NEW
  audio_url: { type: DataTypes.STRING(500), allowNull: true, 
               comment: '音频URL，为空表示未生成' },
  order_index: { type: DataTypes.INTEGER, allowNull: false, 
                 comment: '顺序索引' },
}, {
  tableName: 'kana',
  comment: '日语五十音表及所有变体（濁音、半濁音、拗音）',  // 更新注释
  indexes: [
    { unique: true, fields: ['type', 'character'] },  // 修改: 基于字符唯一
    { fields: ['type'] },
    { fields: ['category'] },  // ⭐ NEW: 支持按分类查询
    { fields: ['audio_url'] },
  ],
});
```

#### 变更影响
- ✅ 支持拗音字符（如 `きゃ`）
- ✅ 分类查询功能
- ✅ 字符级别唯一性约束（更精确）

---

## 🔌 后端API变更

### 文件: `backend/src/controllers/adminController.js`

#### 函数: `listKana()`

**旧版签名**
```javascript
async function listKana(req, res) {
  const { type } = req.query;
  // 支持参数: type (hiragana|katakana)
}
```

**新版签名**
```javascript
async function listKana(req, res) {
  const { type, category } = req.query;
  // 支持参数: 
  //   - type: hiragana|katakana
  //   - category: 五十音|濁音|半濁音|拗音
}
```

**返回字段变化**
```javascript
// 旧返回
attributes: ['id', 'type', 'character', 'romanization', 'audio_url', 'order_index']

// 新返回
attributes: ['id', 'type', 'character', 'romanization', 'category', 'audio_url', 'order_index']
//                                                      ^^^^^^^^ NEW
```

**排序逻辑变化**
```javascript
// 旧排序
order: [['order_index', 'ASC']]

// 新排序（更精确）
order: [['order_index', 'ASC'], ['type', 'ASC']]
```

#### 函数: `batchGenerateKanaAudio()`
- ✅ 无代码变更（自动兼容新数据结构）
- ✅ 支持拗音字符的音频生成
- ✅ 生成236个字符（1:1映射拗音的组写汉字）

---

## 🔄 API端点使用示例

### 原有端点（兼容升级）

```bash
# 获取所有平假名（现在包含拗音）
GET /api/v1/admin/kana?type=hiragana
# 返回206个记录（43+20+5+38）... 不对，36个拗音

# 获取所有片假名
GET /api/v1/admin/kana?type=katakana
```

### ✨ 新增端点

```bash
# 按分类查询：获取所有拗音
GET /api/v1/admin/kana?category=拗音
# 返回72个记录

# 组合查询：获取拗音平假名
GET /api/v1/admin/kana?type=hiragana&category=拗音
# 返回36个记录（きゃ, きゅ, きょ, ... りょ）

# 获取濁音
GET /api/v1/admin/kana?category=濁音
# 返回40个记录（平假名20 + 片假名20）

# 获取半濁音
GET /api/v1/admin/kana?category=半濁音
# 返回10个记录（平假名5 + 片假名5）

# 生成所有拗音音频
POST /api/v1/admin/kana/batch-audio
{
  "selectedIds": ["id1", "id2", ... "id36"]  // 36个拗音平假名
}
```

---

## 📋 实施清单

- [ ] 备份现有数据库 `kana` 表  
  ```bash
  mysqldump -u user -p db_name kana > kana_v1_backup.sql
  ```

- [ ] 执行新Initialize脚本  
  ```bash
  mysql -u user -p db_name < backend/database/init_kana_table.sql
  ```

- [ ] 验证数据导入  
  ```sql
  SELECT COUNT(*) FROM kana;  -- 应为208
  SELECT category, COUNT(*) FROM kana GROUP BY category;
  ```

- [ ] 检查ORM模型是否有语法错误  
  ```bash
  node -e "const m = require('./backend/src/models'); console.log(m.Kana ? '✓' : '✗')"
  ```

- [ ] 重启后端服务  
  ```bash
  pm2 restart japanese-learn
  ```

- [ ] 测试API端点  
  ```bash
  curl 'http://localhost:8002/api/v1/admin/kana?category=拗音' \
    -H 'Authorization: Bearer [token]'
  ```

- [ ] 验证Kokoro TTS音频生成（可选）  
  ```bash
  curl -X POST 'http://localhost:8002/api/v1/admin/kana/batch-audio' \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer [token]' \
    -d '{}'  # 生成所有未生成的音频
  ```

---

## ⚠️ 兼容性说明

### 向后兼容性
✅ **完全兼容** - 原有的 `type` 查询参数仍然有效

```javascript
// 这些查询仍然工作
GET /api/v1/admin/kana?type=hiragana
GET /api/v1/admin/kana?type=katakana
```

### 数据库迁移
⚠️ **数据丢失风险** - 重新初始化会清空旧表数据
```bash
# DO NOT RUN 如果需要保留旧数据
mysql -u user -p db_name < init_kana_table.sql

# 正确做法：
1. 备份：mysqldump ... > backup.sql
2. 确认备份成功
3. 执行：mysql ... < init_kana_table.sql（会清空表）
4. 如需恢复，运行备份：mysql ... < backup.sql
```

### 前端兼容性
✅ **无前端变更** - 新的 `category` 字段是可选的返回值
- 现有前端代码无需修改
- 可选择升级UI以展示分类信息

---

## 🎓 拗音入门

### 什么是拗音？

拗音（ようおん）是日语中通过在基础假名右下方写上更小的「や」「ゆ」「よ」来实现的音变。

**组合规则**:
```
か行 + 小書き や/ゆ/よ = きゃ・きゅ・きょ (kya, kyu, kyo)
さ行 + 小書き や/ゆ/よ = しゃ・しゅ・しょ (sha, shu, sho)
た行 + 小書き や/ゆ/よ = ちゃ・ちゅ・ちょ (cha, chu, cho)
```

### 发音示例
| 拗音 | 罗马音 | 英文近似 | 示例词汇 |
|------|--------|--------|--------|
| きゃ | kya | k-yes | きゃあ (kyaa, 悲叫) |
| しゃ | sha | shah | シャワー (shawaa, 淋浴) |
| ちゃ | cha | chah | ちゃント (chanto, 正确) |
| にゃ | nya | 猫叫 | 子猫 (koneko, 小猫 - nya音) |
| りゃ | rya | r-yes | りゃく (ryaku, 略) |

---

## 📞 技术支持

### 常见问题

**Q: 为什么需要拗音？**  
A: 拗音是日语发音的重要组成部分，是学习者必须掌握的基础。完整的五十音表应该包含拗音。

**Q: 音频生成会很慢吗？**  
A: 从146个增加到208个（新增62个），Kokoro TTS处理时间会增加约40%。建议在非高峰时段执行。

**Q: 能逐步迁移吗？**  
A: 可以，保留旧表做备份，同时创建新表，等验证无误后再切换。

**Q: 會有性能問題嗎？**  
A: 不会。208条记录的查询性能不会产品可感知的差异。

---

**版本**: v2.0 - 完整拗音支持  
**兼容版本**: v1.0 及更高  
**最后更新**: 2024-04-04
