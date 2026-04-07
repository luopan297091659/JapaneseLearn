# 🚀 音频模块化路径 - 部署检查清单

**文档**: 2026年4月5日  
**后端状态**: ✅ 代码完成  
**部署状态**: ⏳ 等待执行

---

## 📋 立即执行清单

### ✅ 步骤1: 创建新目录结构 (2分钟)

```bash
# Windows PowerShell
mkdir -Force uploads/audio/vocab
mkdir -Force uploads/audio/kana

# Linux/Mac
mkdir -p uploads/audio/vocab
mkdir -p uploads/audio/kana
chmod 755 uploads/audio/vocab uploads/audio/kana
```

**验证**:
```bash
# 检查目录是否创建成功
ls -la uploads/grammar/audio/      # 应该已存在
ls -la uploads/audio/vocab/        # 新建
ls -la uploads/audio/kana/         # 新建
```

---

### ✅ 步骤2: 执行数据库迁移 (5分钟)

前提: MySQL服务已启动，japanese_learn数据库存在

```bash
# Windows PowerShell
mysql -u root -p japanese_learn < .\backend\database\migrations\06_add_audio_lifecycle_fields.sql
mysql -u root -p japanese_learn < .\backend\database\migrations\07_create_kana_management_system.sql

# Linux/Mac
mysql -u root -p japanese_learn < backend/database/migrations/06_add_audio_lifecycle_fields.sql
mysql -u root -p japanese_learn < backend/database/migrations/07_create_kana_management_system.sql
```

**验证**:
```sql
-- 连接到数据库后执行
SHOW COLUMNS FROM grammar_examples LIKE 'audio_%';
SHOW COLUMNS FROM vocabulary LIKE 'audio_%';
SHOW COLUMNS FROM vocabulary_examples LIKE 'audio_%';
SHOW TABLES LIKE 'kana_%';
```

应该看到:
- `grammar_examples`: audio_url_type, audio_generated_at, audio_expires_at
- `vocabulary`: audio_url_type, audio_generated_at, audio_expires_at
- `vocabulary_examples`: audio_url_type, audio_generated_at, audio_expires_at
- `kana_categories` 表存在
- `kana_characters` 表存在
- `kana_audio` 表存在
- `user_kana_progress` 表存在

---

### ✅ 步骤3: 重启后端服务 (3分钟)

```bash
# 使用 PM2
pm2 stop japanese-learn
pm2 start japanese-learn

# 或查看 PM2 状态
pm2 status

# 查看启动日志
pm2 logs japanese-learn | head -50
```

**验证日志应包含**:
```
[日期 时间] [info] Audio storage directories initialized.
[日期 时间] [info] Kokoro audio cleanup scheduler started.
```

---

### ✅ 步骤4: 验证服务健康 (2分钟)

```bash
# 检查健康状态
curl http://localhost:8002/health

# 应该返回
# {"status":"ok",...}
```

---

## 🧪 功能测试 (15分钟)

### 测试1: 词汇音频生成路径

```bash
# 生成单个词汇例句音频（使用现有功能）
# 管理员后台 → 词汇管理 → 选择词条 → 右侧音频按钮

# 验证: 文件应该在这里
ls -la uploads/audio/vocab/
# 应该看到 kokoro_*.wav 文件
```

**数据库验证**:
```sql
SELECT word_id, audio_url, audio_url_type, audio_expires_at 
FROM vocabulary 
WHERE audio_url IS NOT NULL 
LIMIT 5;

-- 应该看到:
-- audio_url: /uploads/audio/vocab/kokoro_*.wav
-- audio_url_type: kokoro
-- audio_expires_at: 2026-05-05... (30天后)
```

---

### 测试2: 文法音频生成路径

```bash
# 一键生成所有文法例句音频
# 管理员后台 → 文法管理 → "一键生成Kokoro音频"

# 验证: 文件应该在这里
ls -la uploads/grammar/audio/
# 应该看到 kokoro_*.wav 文件

# 数据库验证
SELECT example_id, audio_url, audio_url_type 
FROM grammar_examples 
WHERE audio_url IS NOT NULL 
LIMIT 5;

-- 应该看到:
-- audio_url: /uploads/grammar/audio/kokoro_*.wav
-- audio_url_type: kokoro
```

---

### 测试3: 五十音音频生成路径

```bash
# 一键生成所有五十音音频
# 管理员后台 → 五十音管理 → "一键生成Kokoro音频"

# 验证: 文件应该在这里
ls -la uploads/audio/kana/
# 应该看到 kokoro_*.wav 文件 (46个假名)

# 数据库验证
SELECT character_id, japanese, audio_url, audio_url_type 
FROM kana_audio 
WHERE audio_url IS NOT NULL 
LIMIT 10;

-- 应该看到:
-- audio_url: /uploads/audio/kana/kokoro_*.wav
-- audio_url_type: kokoro
```

---

### 测试4: 自动清理服务

等待6小时让清理服务自动运行，或手动触发:

```bash
# 检查已过期的音频
# 等待足够长的时间，或修改代码中的TTL为短期测试

# 手动清理 (需要管理员token)
curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/expired \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json"

# 应该看到已清理的计数
```

---

### 测试5: 管理API统计

```bash
# 获取音频统计信息
curl http://localhost:8002/api/v1/kokoro-audio/stats \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# 应该返回类似:
# {
#   "success": true,
#   "stats": {
#     "diskUsage": {
#       "bytes": 52428800,
#       "gb": "50.00"
#     },
#     "audioCount": {
#       "vocabulary": 520,
#       "grammar": 340,
#       "kana": 46,
#       "total": 906
#     }
#   }
# }
```

---

## 📱 客户端同步实现 (后续)

### 策略
1. 客户端尝试从服务器获取音频文件，超时30秒
2. 获取成功: 使用服务器音频
3. 获取失败: 降级到本地TTS生成

### 实现位置
- [ ] `lib/screens/grammar_detail_screen.dart` - 文法例句音频加载
- [ ] `lib/screens/gojuon_screen.dart` - 五十音音频加载
- [ ] `lib/widgets/audio_player_widget.dart` - 通用音频播放器

### 代码示例
```dart
// 文法例句音频加载
Future<void> loadGrammarAudio(String exampleId) async {
  try {
    // 尝试从服务器获取
    final response = await http.get(
      Uri.parse('http://server:8002/uploads/grammar/audio/kokoro_$exampleId.wav'),
      timeout: Duration(seconds: 30),
    );
    if (response.statusCode == 200) {
      // 使用服务器音频
      playAudioFromBytes(response.bodyBytes);
      return;
    }
  } catch (e) {
    // 获取失败
  }
  
  // 降级到TTS
  await generateAudioWithTTS(grammarText);
}
```

---

## 📊 监控建议

### 日常检查脚本
```bash
# daily_audio_check.sh
#!/bin/bash

echo "=== 音频目录大小 ==="
du -sh uploads/audio/vocab/
du -sh uploads/audio/kana/
du -sh uploads/grammar/audio/

echo "=== 音频文件计数 ==="
echo "词汇音频: $(find uploads/audio/vocab/ -name 'kokoro_*.wav' | wc -l)"
echo "文法音频: $(find uploads/grammar/audio/ -name 'kokoro_*.wav' | wc -l)"
echo "五十音音频: $(find uploads/audio/kana/ -name 'kokoro_*.wav' | wc -l)"

echo "=== 最近生成的音频 ==="
find uploads/ -name 'kokoro_*.wav' -type f -mtime -1 | wc -l
```

### 定期任务 (crontab)
```bash
# 每天早上6点检查磁盘使用
0 6 * * * /path/to/daily_audio_check.sh >> /var/log/audio_check.log 2>&1

# 每天晚上10点清理过期音频
0 22 * * * curl -X POST http://localhost:8002/api/v1/kokoro-audio/cleanup/expired
```

---

## 🆘 故障排查

### 问题1: 新目录创建失败

```bash
# 检查权限
ls -la uploads/
# 应该看到 rwxr-xr-x

# 修复权限
chmod 755 uploads/
chmod 755 uploads/audio/
chmod 755 uploads/audio/vocab/
chmod 755 uploads/audio/kana/
```

### 问题2: 生成的音频路径错误

```bash
# 检查正在使用的代码版本
grep -r "batchDownloadAndLocalize" backend/controllers/

# 应该看到所有调用都指定了type参数:
# 'vocabulary', 'grammar', 或 'kana'
```

### 问题3: 数据库表不存在

```bash
# 检查迁移脚本是否执行
mysql -u root -p japanese_learn -e "SHOW TABLES LIKE 'kana%';"

# 如果为空，手动执行迁移
mysql -u root -p japanese_learn < backend/database/migrations/07_create_kana_management_system.sql
```

### 问题4: 清理服务未启动

```bash
# 检查日志
grep "\[Cleanup\]" logs/app.log

# 确保在app.js中启动了清理服务
grep "startCleanupSchedule" backend/app.js
```

---

## ✨ 成功标志

- ✅ 3个目录都已创建
- ✅ 数据库迁移执行成功
- ✅ 后端服务正常启动
- ✅ 词汇音频生成到 `/uploads/audio/vocab/`
- ✅ 文法音频生成到 `/uploads/grammar/audio/`
- ✅ 五十音音频生成到 `/uploads/audio/kana/`
- ✅ 管理API能返回正确的统计数据
- ✅ 清理服务定期运行

---

## 📞 支持

**相关文档**:
- [AUDIO_MODULAR_PATH_STRUCTURE_2026_04_05.md](AUDIO_MODULAR_PATH_STRUCTURE_2026_04_05.md) - 完整设计文档
- [audio_modular_path_design_2026_04_05.md](/memories/repo/audio_modular_path_design_2026_04_05.md) - 设计决策记录

**代码变更**:
- audioLocalizationService.js - 路径配置的来源
- audioCleanupService.js - 清理逻辑
- kokoroAudioManagement.js - 管理API

---

**预计部署时间**: ~30分钟  
**建议部署时段**: 非业务高峰期

