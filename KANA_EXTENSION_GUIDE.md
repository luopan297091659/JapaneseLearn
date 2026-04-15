## 五十音拗音扩展部署指南（濁音、半濁音、拗音）

### 更新概述

系统现已支持完整的日本語字符集合，包括所有拗音（小書き仮名）：

| 分类 | 平假名数量 | 片假名数量 | 小计 | 示例 |
|------|----------|----------|------|------|
| 基础五十音（五十音） | 43 | 43 | 86 | あ、い、う、え、お... |
| 濁音（浊音） | 20 | 20 | 40 | が、ぎ、ぐ、ざ、じ... |
| 半濁音（半浊音） | 5 | 5 | 10 | ぱ、ぴ、ぷ、ぺ、ぽ |
| 拗音（小書き仮名） | 36 | 36 | 72 | きゃ、きゅ、きょ、しゃ、しゅ... |
| **总计** | **104** | **104** | **208** | - |

### 完整的拗音列表

#### 标准拗音（共36个平假名/36个片假名）

1. **K行拗音**: きゃ(kya), きゅ(kyu), きょ(kyo)
2. **G行拗音**: ぎゃ(gya), ぎゅ(gyu), ぎょ(gyo)
3. **S行拗音**: しゃ(sha), しゅ(shu), しょ(sho)
4. **J行拗音**: じゃ(ja), じゅ(ju), じょ(jo)
5. **Ch行拗音**: ちゃ(cha), ちゅ(chu), ちょ(cho)
6. **Dj行拗音**: ぢゃ(dja), ぢゅ(dju), ぢょ(djo)
7. **N行拗音**: にゃ(nya), にゅ(nyu), にょ(nyo)
8. **H行拗音**: ひゃ(hya), ひゅ(hyu), ひょ(hyo)
9. **B行拗音**: びゃ(bya), びゅ(byu), びょ(byo)
10. **P行拗音**: ぴゃ(pya), ぴゅ(pyu), ぴょ(pyo)
11. **M行拗音**: みゃ(mya), みゅ(myu), みょ(myo)
12. **R行拗音**: りゃ(rya), りゅ(ryu), りょ(ryo)

### 部署步骤

#### 1️⃣ 更新数据库表结构

```bash
# 备份现有数据（可选）
mysqldump -u [username] -p[password] [database] kana > kana_backup.sql

# 执行初始化脚本（会重建表）
mysql -u [username] -p[password] [database] < backend/database/init_kana_table.sql
```

**注意**: 脚本会新增 `category` 字段，用于分类五十音、濁音、半濁音、拗音。

#### 验证数据完整性

```sql
-- 检查总数是否为208
SELECT COUNT(*) as total FROM kana;

-- 按category统计
SELECT category, type, COUNT(*) as count 
FROM kana 
GROUP BY category, type 
ORDER BY type, 
  CASE category 
    WHEN '五十音' THEN 1
    WHEN '濁音' THEN 2
    WHEN '半濁音' THEN 3
    WHEN '拗音' THEN 4
  END;

-- 输出应为：
-- 五十音   hiragana  43
-- 五十音   katakana  43
-- 濁音     hiragana  20
-- 濁音     katakana  20
-- 半濁音   hiragana  5
-- 半濁音   katakana  5
-- 拗音     hiragana  36
-- 拗音     katakana  36
```

#### 2️⃣ 更新应用代码

| 文件 | 更改内容 |
|------|--------|
| `backend/src/models/index.js` | 添加 `category` 字段到 Kana 模型 |
| `backend/src/controllers/adminController.js` | 更新 `listKana()` 支持按category过滤 |
| `backend/database/init_kana_table.sql` | 新增208条完整数据记录 |

#### 3️⃣ 重启后端服务

```bash
# 方式1：使用PM2
pm2 restart japanese-learn

# 方式2：使用PowerShell脚本
.\deploy.ps1

# 方式3：手动重启
npm install  # 如果有新依赖
npm start
```

#### 4️⃣ 验证部署成功

```bash
# 查看日志
pm2 logs japanese-learn --lines 50

# 测试API
curl "http://127.0.0.1:8002/api/v1/admin/kana?type=hiragana" \
  -H "Authorization: Bearer [your-token]"

# 预期返回50条平假名（含拗音）
curl "http://127.0.0.1:8002/api/v1/admin/kana?type=hiragana&category=拗音" \
  -H "Authorization: Bearer [your-token]"

# 预期返回36条拗音平假名
```

### 使用示例

#### API查询参数

```bash
# 查询所有五十音
GET /api/v1/admin/kana

# 查询所有平假名
GET /api/v1/admin/kana?type=hiragana

# 查询所有片假名
GET /api/v1/admin/kana?type=katakana

# 查询拗音平假名
GET /api/v1/admin/kana?type=hiragana&category=拗音

# 查询濁音
GET /api/v1/admin/kana?category=濁音

# 生成选定的拗音音频
POST /api/v1/admin/kana/batch-audio
Content-Type: application/json
{
  "selectedIds": ["id1", "id2", "id3", ...]
}

# 生成所有未生成音频的五十音
POST /api/v1/admin/kana/batch-audio
Content-Type: application/json
{}
```

### 数据库字段说明

#### 新增 `category` 字段

| 值 | 说明 | 数量 |
|----|------|------|
| `五十音` | 基础50音 | 86 |
| `濁音` | 浊音（带濁点） | 40 |
| `半濁音` | 半浊音（带半濁点） | 10 |
| `拗音` | 小书き混合呼 | 72 |

#### 索引优化

旧索引：`UNIQUE(type, order_index)` → 新增`order_index`限制需移除  
新索引：`UNIQUE(type, character)` → 确保同类型字符唯一性

```sql
-- 新增索引便生
KEY `idx_kana_category` (`category`) COMMENT '按分类查询';
```

### 前端集成建议

#### Kana管理UI功能

1. **Tab页切换**
   - 五十音
   - 濁音
   - 半濁音
   - 拗音
   - 全部

2. **表格显示**
   ```
   | 字符 | 罗马音 | 分类 | 音频状态 | 操作 |
   |------|-------|------|--------|------|
   | あ  | a    | 五十音 | 已生成 | 播放 |
   | が  | ga   | 濁音   | 已生成 | 播放 |
   | きゃ | kya  | 拗音   | 未生成 | 生成 |
   ```

3. **批量操作**
   - 选中多个字符
   - "生成选中音频"
   - 进度条显示

### 故障排查

#### 问题1: 数据库初始化失败

```bash
# 检查MySQL连接
mysql -u root -p -h 127.0.0.1 database_name

# 查看表是否存在
SHOW TABLES LIKE 'kana';

# 查看当前表结构
DESCRIBE kana;
```

#### 问题2: 音频生成超时

- 拗音较多，总数为208条
- 建议增加超时时间：`Math.max(60000, textsToGenerate.length * 10000 + 30000)`
- 或分批生成：每次50条

#### 问题3: API返回错误

```json
{
  "error": "Unknown column 'category' in 'field list'"
}
```

**解决**: 确认数据库表已实际创建新字段，检查是否跳过了`init_kana_table.sql`执行

### 性能考虑

| 操作 | 预计时间 | 备注 |
|------|--------|------|
| 数据库初始化 | 5-10秒 | 208条INSERT |
| 生成全部音频 | 3-5分钟 | Kokoro TTS处理 |
| 查询按category过滤 | <100ms | 有索引优化 |
| 前端加载全部五十音 | <50ms | 浏览器渲染 |

### 回滚方案

如需回滚到原来的43+43版本（不含拗音）：

```bash
# 恢复之前的SQL备份
mysql -u [username] -p[password] [database] < kana_backup.sql

# 更新Kana模型，移除category字段
# 编辑 backend/src/models/index.js 注释掉category行

# 重启服务
pm2 restart japanese-learn
```

### 后续优化空间

1. **特殊拗音** - 后续可考虑添加：
   - `しゃ` / `しゅ` / `しょ` 的其他表示方法
   - 一些非标准但常见的组合

2. **音调变体** - 可按声调（せいちょう）分类：
   - 平声
   - 上声
   - 去声
   - 入声

3. **学习进度** - 绑定SRS系统：
   - 跟踪每个拗音的学习状态
   - 利用间隔重复算法

4. **发音视频** - 扩展音频为视频：
   - 嘴型演示
   - 笔画顺序

---

**版本**: v2.0 - 完整五十音扩展  
**更新日期**: 2024年4月  
**兼容性**: 数据库 ≥ MySQL 5.7，Node.js ≥ 14
