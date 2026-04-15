## 🚀 五十音拗音扩展 - 快速部署指南

**当前版本**: 2.0 - 完整拗音支持  
**部署时间**: 约 5-10 分钟  
**难度级别**: ⭐⭐ 中等（需要数据库访问权限）

---

## ✅ 已完成的更新

### 📁 文件清单

| 文件 | 变更类型 | 影响范围 | 状态 |
|------|---------|--------|------|
| `backend/database/init_kana_table.sql` | 新增 | 数据库 | ✅ 完成 |
| `backend/src/models/index.js` | 修改 | ORM模型 | ✅ 完成 |
| `backend/src/controllers/adminController.js` | 修改 | API函数 | ✅ 完成 |
| `KANA_EXTENSION_GUIDE.md` | 新增 | 文档 | ✅ 完成 |
| `KANA_EXTENSION_CHANGELOG.md` | 新增 | 文档 | ✅ 完成 |
| `KANA_YOUON_REFERENCE.md` | 新增 | 参考资料 | ✅ 完成 |

### 📊 数据规模

```
旧版本: 146条记录 (73平假名 + 73片假名)
新版本: 208条记录 (104平假名 + 104片假名)
增加量: +62条 (+43%)
```

### 新增拗音内容

```
基础拗音: 36个 (11组 × 3音)
包括: きゃ、しゃ、ちゃ、にゃ、ひゃ、みゃ、りゃ 等
支持: 平假名 + 片假名 双份录入
```

---

## ⚡ 3分钟快速部署

### 步骤 1️⃣: 备份现有数据（可选但推荐）

```powershell
# Windows PowerShell
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
mysqldump -u root -p[password] [database] kana > "kana_backup_$timestamp.sql"

# Linux/Mac
mysqldump -u root -p [database] kana > kana_backup_$(date +%s).sql
```

### 步骤 2️⃣: 执行数据库初始化脚本

```powershell
# Windows PowerShell
mysql -u root -p[password] [database] < backend\database\init_kana_table.sql

# Linux/Mac
mysql -u root -p [database] < backend/database/init_kana_table.sql
```

**期望输出**: 无错误，约 2-3 秒执行完成

### 步骤 3️⃣: 验证数据导入

```sql
-- 从数据库CLI执行以下查询

-- 查询 1: 检查总记录数
SELECT COUNT(*) as total_records FROM kana;
-- 预期: 208

-- 查询 2: 验证分类分布
SELECT category, COUNT(*) as count FROM kana GROUP BY category;
-- 预期输出:
-- 五十音   | 86
-- 濁音     | 40
-- 半濁音   | 10
-- 拗音     | 72

-- 查询 3: 按类型验证
SELECT type, COUNT(*) as count FROM kana GROUP BY type;
-- 预期输出:
-- hiragana | 104
-- katakana | 104

-- 查询 4: 检查拗音是否正确导入
SELECT COUNT(*) FROM kana WHERE category = '拗音';
-- 预期: 72

-- 查询 5: 验证特定拗音
SELECT character, romanization, type FROM kana 
WHERE category = '拗音' AND character IN ('きゃ', 'キャ', 'しゃ', 'シャ');
-- 预期: 4条记录
```

### 步骤 4️⃣: 重启后端服务

```bash
# 方式A: 使用PM2
pm2 restart japanese-learn

# 方式B: 使用PowerShell脚本
.\deploy.ps1

# 方式C: 手动重启
npm install
npm start
```

### 步骤 5️⃣: 测试API端点

```bash
# 获取所有拗音（分类查询）
curl "http://127.0.0.1:8002/api/v1/admin/kana?category=拗音" \
  -H "Authorization: Bearer YOUR_TOKEN"

# 预期: 返回72条拗音记录

# 获取拗音平假名（组合查询）
curl "http://127.0.0.1:8002/api/v1/admin/kana?type=hiragana&category=拗音" \
  -H "Authorization: Bearer YOUR_TOKEN"

# 预期: 返回36条拗音平假名
```

---

## 📋 完整部署清单

- [ ] 备份数据库
  ```bash
  mysqldump -u user -ppassword database kana > backup.sql
  ```

- [ ] 验证备份成功
  ```bash
  ls -lh backup.sql  # 文件大小应 > 5KB
  ```

- [ ] 执行初始化脚本
  ```bash
  mysql -u user -ppassword database < backend/database/init_kana_table.sql
  ```

- [ ] 验证数据（运行查询1-5）
  ```sql
  SELECT COUNT(*) FROM kana;
  ```

- [ ] 检查ORM模型
  ```bash
  node -c "const m = require('./backend/src/models'); console.log('✓ Model OK')" 2>&1
  ```

- [ ] 重启后端
  ```bash
  pm2 restart japanese-learn
  ```

- [ ] 检查日志
  ```bash
  pm2 logs japanese-learn --lines 30
  ```

- [ ] 测试API
  ```bash
  curl "http://127.0.0.1:8002/api/v1/admin/kana?category=拗音" \
    -H "Authorization: Bearer $TOKEN"
  ```

- [ ] 生成全部音频（可选）
  ```bash
  curl -X POST "http://127.0.0.1:8002/api/v1/admin/kana/batch-audio" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}'
  ```

- [ ] ✅ 部署完成！

---

## 🔍 部署常见问题

### ❓ Q: 执行SQL脚本时出错 "Unknown column"

**原因**: 表结构未正确更新  
**解决**:
```sql
-- 检查category字段是否存在
SHOW COLUMNS FROM kana;

-- 如果缺少，手动添加
ALTER TABLE kana ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT '五十音';

-- 重新执行初始化脚本
source backend/database/init_kana_table.sql;
```

### ❓ Q: 数据导入后拗音为空

**原因**: SQL脚本可能未正确执行INSERT语句  
**解决**:
```sql
-- 检查INSERT结果
SELECT COUNT(*) FROM kana WHERE category = '拗音';

-- 如果为0，手动检查是否有错误
-- 重新执行脚本或逐行执行INSERT
```

### ❓ Q: API返回 404

**原因**: 后端服务未重启或代码未更新  
**解决**:
```bash
# 确保代码已更新
git status
git diff backend/src/controllers/adminController.js

# 清空缓存重启
pm2 kill
npm install
npm start
```

### ❓ Q: 生成音频超时

**原因**: 208个字符一次性生成太多  
**解决**:
```bash
# 分批生成（每批50个）
# 或增加超时时间在代码中

# 临时方案：生成部分
curl -X POST "http://127.0.0.1:8002/api/v1/admin/kana/batch-audio" \
  -H "Content-Type: application/json" \
  -d '{"selectedIds": ["id1", "id2", ..., "id50"]}'
```

### ❓ Q: 如何回滚到旧版本

**步骤**:
```bash
# 恢复备份
mysql -u user -ppassword database < kana_backup.sql

# 还原代码
git revert HEAD

# 重启服务
pm2 restart japanese-learn
```

---

## 🎯 部署后验证

### 功能清单

- [ ] ✅ 数据库包含208条记录
- [ ] ✅ API可按категория查询
- [ ] ✅ 拗音平假名能正常获取 (36条)
- [ ] ✅ 拗音片假名能正常获取 (36条)
- [ ] ✅ 濁音能正常获取 (40条)
- [ ] ✅ 半濁音能正常获取 (10条)
- [ ] ✅ 音频生成功能正常
- [ ] ✅ 日志无错误

### 性能指标

| 操作 | 预期时间 | 实际时间 |
|------|---------|---------|
| 数据库初始化 | 5-10s | ___ |
| API查询 (全部) | <100ms | ___ |
| API查询 (按分类) | <50ms | ___ |
| 生成音频 (全部208) | 3-5分钟 | ___ |

---

## 📚 文档导航

新增的3份详细文档：

1. **[KANA_EXTENSION_GUIDE.md](KANA_EXTENSION_GUIDE.md)** - 完整部署指南
   - 详细的设置步骤
   - SQL验证查询
   - API使用示例
   
2. **[KANA_EXTENSION_CHANGELOG.md](KANA_EXTENSION_CHANGELOG.md)** - 变更日志
   - 代码修改对比
   - 数据库结构变更
   - 兼容性说明

3. **[KANA_YOUON_REFERENCE.md](KANA_YOUON_REFERENCE.md)** - 拗音参考表
   - 全部36个拗音的汉字表
   - 发音、罗马音、常用词汇
   - 学习建议

---

## 🚀 下一步

### 可选增强功能

- [ ] 前端五十音管理UI
  - 按category分tab显示
  - 支持音频播放
  - 音频生成进度条

- [ ] 拗音学习模块
  - 拗音专项练习
  - 发音纠正
  - 拗音与标准音的对比

- [ ] 数据统计
  - 各category的音频生成率
  - 学习进度追踪
  - 常用词库统计

### 官方资源推荐

- 📖 **教科书**: NHK World Easy Japanese
- 🎤 **发音教学**: Forvo.com 日本語板块
- 📱 **App**: Google Translate, Microsoft Translator (含拗音)

---

## 💬 支持与反馈

**问题反馈**:
- 检查日志: `pm2 logs japanese-learn`
- 数据库诊断: 运行验证查询1-5
- 提供错误堆栈跟踪

**联系方式**:
- 提交Issue到项目仓库
- 邮箱: [support email]
- Discord: [server link]

---

**🎉 祝部署成功！**

当部署完成后，您的系统将支持：
- ✅ 基础五十音 (86)
- ✅ 濁音 (40)
- ✅ 半濁音 (10)
- ✅ 拗音 (72)
- ✅ 完整208规模音频库

---

**文件版本**: 2.0  
**最后更新**: 2024-04-04  
**创建者**: AI Assistant  
**预计部署时间**: 5-10 分钟 ⏱️
