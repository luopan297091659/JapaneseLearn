# 快速上手指南 - 批量生成优化 v1.1.0

## 🎯 新功能概览

### 1️⃣ 词汇/语法 - 支持勾选生成

#### 之前 ❌
- "一键生成"总是处理**所有**未生成音频的项目
- 用户无法选择只处理部分项目

#### 现在 ✅
- 勾选需要的词汇/语法 → 只为选中项生成
- 全部不勾选 → 处理全部（保持兼容）

#### 操作步骤
```
1. 打开"词汇管理" 或 "语法管理"
2. 在列表中勾选需要的项目 ☑️ ☑️ ☑️
3. 点击 "🎤 一键生成Kokoro音频" 按钮
4. 确认弹窗显示选中数量
5. 等待完成 ⏳
```

**提示内容示例**:
```
选中5项:  "确认为选中的5项词汇生成Kokoro音频？"
全选:     "确认为所有单词及例句生成Kokoro音频？"
```

---

### 2️⃣ 五十音 - 新增音频生成

#### 新增功能
- 日语平假名音频生成（あ～ん 共73个）
- 日语片假名音频生成（ア～ン 共73个）
- 支持单个或批量生成

#### API 端点

**查看五十音列表**:
```bash
curl -X GET "http://localhost:8002/api/v1/admin/kana" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"

# 返回示例:
{
  "data": [
    {
      "id": "uuid-1",
      "type": "hiragana",
      "character": "あ",
      "romanization": "a",
      "audio_url": null,
      "order_index": 0
    },
    ...
  ]
}
```

**批量生成五十音音频**:
```bash
# 方式1: 生成全部（未有音频）
curl -X POST "http://localhost:8002/api/v1/admin/kana/batch-audio" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'

# 方式2: 生成指定项目
curl -X POST "http://localhost:8002/api/v1/admin/kana/batch-audio" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": ["uuid-1", "uuid-2", "uuid-3"]}'

# 返回示例:
{
  "success": true,
  "message": "成功生成73/73个五十音音频",
  "generated": 73,
  "total": 73
}
```

---

## 🔧 部署检查清单

### 数据库初始化（第一次使用）

```bash
# 1. 连接MySQL
mysql -u root -p

# 2. 执行初始化脚本
source /path/to/backend/database/init_kana_table.sql;

# 3. 验证表创建
SELECT COUNT(*) as total FROM kana;
# 应显示: 146

# 4. 验证数据
SELECT type, COUNT(*) as count FROM kana GROUP BY type;
# 应显示:
# | type     | count |
# | hiragana | 73    |
# | katakana | 73    |
```

### 后端服务检查

```bash
# 1. 检查后端进程
pm2 list

# 2. 查看日志（如有错误）
pm2 logs japanese-learn --lines 50

# 3. 测试API响应
curl -X GET "http://localhost:8002/api/v1/admin/kana" \
  -H "Authorization: Bearer TEST_TOKEN"
```

### 前端验证

```bash
# 1. 打开管理后台浏览器
# 访问: http://localhost:8002/admin/

# 2. 进入"词汇管理"
# - 勾选几个词汇 ☑️
# - 点击"🎤 一键生成Kokoro音频"
# - 应显示：确认为选中的X项词汇生成Kokoro音频？

# 3. 进入"语法管理"
# - 勾选几个语法 ☑️
# - 点击"🎤 一键生成Kokoro音频"
# - 应显示：确认为选中的X项语法生成Kokoro音频？
```

---

## 📊 功能对比表

| 功能 | 之前 | 现在 | 改进 |
|------|------|------|------|
| 词汇批量生成 | 全部 | ✅ 全部/勾选 | 支持选择性处理 |
| 语法批量生成 | 全部 | ✅ 全部/勾选 | 支持选择性处理 |
| 已有音频跳过 | ✅ 有 | ✅ 有 | 已实现 |
| 五十音音频 | ❌ 无 | ✅ 有 | 新增功能 |
| 平假名数据 | ❌ 无 | ✅ 73个 | 完整五十音 |
| 片假名数据 | ❌ 无 | ✅ 73个 | 完整五十音 |

---

## ⚠️ 常见问题

### Q1: 点击"一键生成"后没反应
**A**: 
1. 检查前端浏览器开发者工具（F12 → Console）是否有错误
2. 检查网络请求是否发送成功（F12 → Network）
3. 确认 Token 有效
4. 检查后端日志: `pm2 logs japanese-learn`

### Q2: 勾选全不选时，是否还会生成全部？
**A**: 是的。这是向下兼容的设计：
- 勾选项目 → 只生成选中的
- 全不勾选 → 生成全部（原有行为）

### Q3: 生成五十音音频时超时
**A**:
1. 检查 Kokoro TTS 服务是否运行: `pm2 list`
2. 查看 Kokoro 日志: `pm2 logs kokoro-tts`
3. 网络连接: `curl http://127.0.0.1:8010/api/v1/health`
4. 尝试减少数量重新生成

### Q4: 如何重新生成已有音频的项目？
**A**: 当前版本会自动跳过已有音频的项目。若要强制重新生成，需要先清空音频URL：
```sql
UPDATE vocabulary SET audio_url = NULL WHERE id = 'uuid-xxx';
UPDATE kana SET audio_url = NULL WHERE id = 'uuid-xxx';
```
然后重新生成。

---

## 🚀 进阶用法

### 脚本批量更新（管理员）

#### 重置所有词汇音频（谨慎使用！）
```bash
# MySQL 脚本
UPDATE vocabulary SET audio_url = NULL;

# 然后在管理后台重新生成全部
```

#### 查看生成统计
```bash
# 已有音频的词汇数
SELECT COUNT(*) FROM vocabulary WHERE audio_url IS NOT NULL AND audio_url != '';

# 待生成的词汇数
SELECT COUNT(*) FROM vocabulary WHERE audio_url IS NULL OR audio_url = '';

# 五十音音频统计
SELECT type, 
       COUNT(*) as total,
       SUM(CASE WHEN audio_url IS NOT NULL AND audio_url != '' THEN 1 ELSE 0 END) as generated
FROM kana GROUP BY type;
```

---

## 📝 更新日志

### v1.1.0 (2026-04-04)
- ✨ 新增：词汇/语法批量生成支持勾选项
- ✨ 新增：五十音表和音频生成API
- 🐛 修复：生成函数参数支持
- 📊 改进：批量操作的用户提示
- 🚀 优化：数据库索引加速查询

---

## 📞 技术支持

**问题排查顺序**:
1. 检查浏览器控制台（F12）
2. 查看后端日志（`pm2 logs`）
3. 验证数据库连接
4. 检查网络（防火墙/代理）
5. 重启相关服务

**有效日志位置**:
- 后端: `/root/.pm2/logs/japanese-learn-error.log`
- Kokoro: `/root/.pm2/logs/kokoro-tts-error.log`
- 浏览器: DevTools Console

---

**祝使用愉快！** 🎉
