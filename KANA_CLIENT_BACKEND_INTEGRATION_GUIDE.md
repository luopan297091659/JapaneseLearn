# 🔗 五十音客户端-后端集成指南
**时间**: 2026年4月5日  
**目标**: 统一五十音数据源，从硬编码 → API 动态

---

## 📋 快速概览

| 阶段 | 任务 | 工作量 | 优先级 |
|------|------|--------|--------|
| **初始化** | 后端数据库初始化 | 10分钟 | 🔴 必须 |
| **生成音频** | 一键生成所有五十音音频 | 15分钟 | 🔴 必须 |
| **客户端集成** | 从API读取分类/字符数据 | 2小时 | 🟡 推荐 |
| **音频播放** | 从服务器获取音频，降级TTS | 1小时 | 🟡 推荐 |
| **进度同步** | 上报学习进度到后端 | 1小时 | 🟢 可选 |

---

## ✅ **阶段1：后端数据初始化（必须）**

### 步骤1.1: 执行数据库迁移脚本

前提：已执行 `07_create_kana_management_system.sql`

```bash
# SSH 连接到服务器或本地 MySQL
mysql -u root -p japanese_learn < backend/database/seeds/kana_seed.sql

# 或在 MySQL 客户端中执行
mysql> source backend/database/seeds/kana_seed.sql;
```

**验证结果**:
```sql
-- 应有 104 条记录
SELECT COUNT(*) AS total_kana FROM kana_characters;

-- 按分类统计
SELECT 
  c.name AS category,
  COUNT(k.id) AS count
FROM kana_categories c
LEFT JOIN kana_characters k ON c.id = k.category_id
GROUP BY c.id, c.name
ORDER BY c.order_index;
```

**预期结果**:
```
+--------+-------+
| name   | count |
+--------+-------+
| 平假名 |  46   |
| 片假名 |  46   | (与平假名共用一条记录)
| 浊音   |  20   |
| 半浊音 |   5   |
| 拗音   |  33   |
+--------+-------+
总计: 104 条
```

### 步骤1.2: 验证初始化

```bash
# 1. 查看分类
curl http://localhost:8002/api/v1/kana/categories \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 应返回：
# {
#   "success": true,
#   "categories": [
#     {"id": 1, "name": "平假名", "character_count": 46},
#     {"id": 2, "name": "片假名", "character_count": 46},
#     {"id": 3, "name": "浊音", "character_count": 20},
#     {"id": 4, "name": "半浊音", "character_count": 5},
#     {"id": 5, "name": "拗音", "character_count": 33}
#   ]
# }

# 2. 获取所有字符
curl "http://localhost:8002/api/v1/kana/characters?limit=10" \
  -H "Authorization: Bearer ADMIN_TOKEN"

# 应返回前10个字符及其详情
```

---

## 🔊 **阶段2：生成五十音音频（必须）**

### 步骤2.1: 一键生成

```bash
# 通过管理 API 生成所有五十音音频
curl -X POST http://localhost:8002/api/v1/kana/admin/generate-audio \
  -H "Authorization: Bearer ADMIN_TOKEN" \
  -H "Content-Type: application/json"

# 返回示例：
# {
#   "success": true,
#   "generated": 104,
#   "total": 104,
#   "audioUrl": "/uploads/audio/kana/",
#   "failedCharacters": [],
#   "message": "成功生成 104/104 个假名音频"
# }
```

### 步骤2.2: 验证生成

```bash
# 1. 检查磁盘文件
ls -la uploads/audio/kana/ | head -20
# 应显示 104 个 kokoro_*.wav 文件

# 2. 查询数据库
mysql> SELECT 
  k.hiragana, 
  k.katakana, 
  a.audio_url, 
  a.audio_type 
FROM kana_characters k
LEFT JOIN kana_audio a ON k.id = a.kana_character_id
LIMIT 10;

# 应显示音频 URL 如：
# あ ア /uploads/audio/kana/kokoro_abc123.wav standard
```

### 步骤2.3: 生成多种音频类型（可选）

```bash
# 后续可以生成其他类型（缓速、自然、音标等）
# 当前只生成了 'standard' 类型

# 如需扩展，修改 kanaController.js 的生成逻辑：
// audioTypes = ['standard', 'slow', 'natural']; // 改为多种类型
```

---

## 📱 **阶段3：客户端集成（推荐）**

### 步骤3.1: 创建客户端 API 服务

新建文件：`mobile/lib/services/kana_service.dart`

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class KanaService {
  final String baseUrl = 'http://localhost:8002/api/v1';

  /// 获取五十音分类列表
  Future<List<KanaCategory>> getKanaCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/kana/categories'),
        headers: {'Authorization': 'Bearer ${getToken()}'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<KanaCategory>.from(
          data['categories'].map((c) => KanaCategory.fromJson(c))
        );
      }
      throw Exception('Failed to load categories');
    } catch (e) {
      logger.error('获取分类失败: $e');
      // 返回默认分类（离线模式）
      return getDefaultCategories();
    }
  }

  /// 获取指定分类的所有字符
  Future<List<KanaCharacter>> getKanaCharacters({
    int? categoryId,
    String? platform, // 'hiragana' | 'katakana' | 'all'
  }) async {
    try {
      String url = '$baseUrl/kana/characters?limit=1000';
      if (categoryId != null) url += '&category_id=$categoryId';
      if (platform != null) url += '&platform=$platform';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${getToken()}'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<KanaCharacter>.from(
          data['characters'].map((c) => KanaCharacter.fromJson(c))
        );
      }
      throw Exception('Failed to load characters');
    } catch (e) {
      logger.error('获取字符失败: $e');
      return getDefaultCharacters(); // 离线模式
    }
  }

  /// 获取指定假名的音频 URL
  Future<String?> getKanaAudioUrl(
    String kanaCharacterId, {
    String audioType = 'standard',
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/kana/$kanaCharacterId/audio?type=$audioType'),
        headers: {'Authorization': 'Bearer ${getToken()}'},
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['audio_url']; // e.g., '/uploads/audio/kana/kokoro_xxx.wav'
      }
      return null;
    } catch (e) {
      logger.warning('获取音频失败: $e');
      return null; // 降级到 TTS
    }
  }

  /// 上报学习进度
  Future<void> reportKanaProgress({
    required String userId,
    required String kanaCharacterId,
    required bool isCorrect,
    DateTime? timestamp,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/kana/user/$userId/progress'),
        headers: {
          'Authorization': 'Bearer ${getToken()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'kana_character_id': kanaCharacterId,
          'correct': isCorrect,
          'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
        }),
      ).timeout(Duration(seconds: 10));
    } catch (e) {
      logger.error('上报进度失败: $e');
      // 离线时存储到本地，稍后同步
      saveProgressLocally(userId, kanaCharacterId, isCorrect);
    }
  }

  /// 离线模式：返回默认分类（客户端本地数据）
  List<KanaCategory> getDefaultCategories() {
    return [
      KanaCategory(id: 1, name: '平假名', characterCount: 46),
      KanaCategory(id: 2, name: '片假名', characterCount: 46),
      KanaCategory(id: 3, name: '浊音', characterCount: 20),
      KanaCategory(id: 4, name: '半浊音', characterCount: 5),
      KanaCategory(id: 5, name: '拗音', characterCount: 33),
    ];
  }

  /// 离线模式：返回默认字符（从 kana_data.dart 转换）
  List<KanaCharacter> getDefaultCharacters() {
    // 将现有的 gojuonData, dakuonData, youonData 转换为列表
    // ... 实现转换逻辑 ...
  }
}

// ============================================================================
// 数据模型
// ============================================================================

class KanaCategory {
  final int id;
  final String name;
  final String? nameEn;
  final int characterCount;

  KanaCategory({
    required this.id,
    required this.name,
    this.nameEn,
    required this.characterCount,
  });

  factory KanaCategory.fromJson(Map<String, dynamic> json) {
    return KanaCategory(
      id: json['id'],
      name: json['name'],
      nameEn: json['name_en'],
      characterCount: json['character_count'] ?? 0,
    );
  }
}

class KanaCharacter {
  final String id;
  final int categoryId;
  final String hiragana;
  final String? katakana;
  final String romaji;
  final int? strokeCount;
  final int orderIndex;

  KanaCharacter({
    required this.id,
    required this.categoryId,
    required this.hiragana,
    this.katakana,
    required this.romaji,
    this.strokeCount,
    required this.orderIndex,
  });

  factory KanaCharacter.fromJson(Map<String, dynamic> json) {
    return KanaCharacter(
      id: json['id'],
      categoryId: json['category_id'],
      hiragana: json['hiragana'],
      katakana: json['katakana'],
      romaji: json['romaji'],
      strokeCount: json['stroke_count'],
      orderIndex: json['order_index'],
    );
  }
}
```

### 步骤3.2: 更新五十音学习界面

修改：`mobile/lib/screens/study/gojuon_screen.dart`

```dart
// 原有的硬编码数据
// const gojuonData = [...];
// const dakuonData = [...];
// const youonData = [...];

// 替换为：
List<KanaCharacter> kanaCharacters = [];
bool isLoadingFromServer = false;

@override
void initState() {
  super.initState();
  loadKanaDataFromServer();
}

Future<void> loadKanaDataFromServer() async {
  setState(() => isLoadingFromServer = true);
  try {
    // 获取所有字符
    final kanaService = KanaService();
    kanaCharacters = await kanaService.getKanaCharacters();
    
    logger.info('已从服务器加载 ${kanaCharacters.length} 个假名字符');
  } catch (e) {
    logger.error('从服务器加载失败: $e');
    // 降级到本地数据
    kanaCharacters = getLocalKanaCharacters();
  } finally {
    setState(() => isLoadingFromServer = false);
  }
}

// 按分类重新组织数据
Map<int, List<KanaCharacter>> organizeByCategory(
  List<KanaCharacter> characters
) {
  final organized = <int, List<KanaCharacter>>{};
  for (final char in characters) {
    organized.putIfAbsent(char.categoryId, () => []).add(char);
  }
  return organized;
}

// UI 中使用：
@override
Widget build(BuildContext context) {
  if (isLoadingFromServer) {
    return Center(child: CircularProgressIndicator());
  }

  final byCategory = organizeByCategory(kanaCharacters);

  return TabBarView(
    children: [
      // 清音 Tab (category_id = 1)
      buildCategoryTab(byCategory[1] ?? [], '平假名'),
      // 浊音/半浊音 Tab (category_id = 3, 4)
      buildCategoryTab(
        [...?byCategory[3], ...?byCategory[4]], 
        '浊音/半浊音'
      ),
      // 拗音 Tab (category_id = 5)
      buildCategoryTab(byCategory[5] ?? [], '拗音'),
    ],
  );
}

Widget buildCategoryTab(List<KanaCharacter> characters, String title) {
  return GridView.builder(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 5,
      childAspectRatio: 1.0,
    ),
    itemCount: characters.length,
    itemBuilder: (context, index) {
      final char = characters[index];
      return GestureDetector(
        onTap: () => playAndShowKanaDetail(char),
        child: Card(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                char.hiragana,
                style: TextStyle(fontSize: 24),
              ),
              Text(
                char.katakana ?? '',
                style: TextStyle(fontSize: 18),
              ),
              Text(
                char.romaji,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    },
  );
}
```

### 步骤3.3: 更新音频播放逻辑

修改：`mobile/lib/widgets/kana_stroke_widget.dart`

```dart
Future<void> playKanaAudio(KanaCharacter character) async {
  final kanaService = KanaService();
  
  try {
    // 1. 尝试从服务器获取音频 URL
    final audioUrl = await kanaService.getKanaAudioUrl(
      character.id,
      audioType: 'standard', // 或 'slow', 'natural' 等
    );
    
    if (audioUrl != null) {
      // 2. 从服务器播放
      final serverUrl = 'http://localhost:8002'; // 从配置获取
      await playAudioFile('$serverUrl$audioUrl');
      logger.info('从服务器播放音频: $audioUrl');
      return;
    }
  } catch (e) {
    logger.warning('获取服务器音频失败: $e');
  }

  // 3. 降级：使用本地 TTS
  logger.info('降级到本地 TTS');
  await ttsEngine.speak(character.hiragana);
}

Future<void> playAudioFile(String url) async {
  // 使用 audio_players 或类似库播放
  await audioPlayer.play(UrlSource(url));
}
```

### 步骤3.4: 更新书写测试

修改：`mobile/lib/screens/quiz/kana_writing_test_screen.dart`

```dart
Future<void> initQuiz() async {
  final kanaService = KanaService();
  
  // 获取测试用的字符
  final allCharacters = await kanaService.getKanaCharacters();
  
  // 根据用户选择的范围筛选
  List<KanaCharacter> filteredCharacters = allCharacters;
  if (selectedFontType == 'hiragana') {
    filteredCharacters = allCharacters
      .where((c) => c.hiragana.isNotEmpty)
      .toList();
  } else if (selectedFontType == 'katakana') {
    filteredCharacters = allCharacters
      .where((c) => c.katakana?.isNotEmpty ?? false)
      .toList();
  }

  // 随机选择测试题
  quizItems = filteredCharacters
    ..shuffle()
    ..take(quizCount)
    .toList();
}

// 更新数据库学习进度
Future<void> submitAnswer(bool isCorrect) async {
  final kanaService = KanaService();
  final userId = getCurrentUserId();
  final currentItem = quizItems[currentIndex];
  
  await kanaService.reportKanaProgress(
    userId: userId,
    kanaCharacterId: currentItem.id,
    isCorrect: isCorrect,
  );
  
  // 更新本地进度（用于即时反馈）
  if (isCorrect) {
    localProgress[currentItem.romaji] = 
      (localProgress[currentItem.romaji] ?? 0) + 1;
  }
}
```

---

## 🎯 **阶段4：音频播放集成（推荐）**

此阶段在步骤3中已覆盖，但确保：

1. ✅ 配置正确的服务器地址（不要硬编码 localhost）
2. ✅ 设置合理的超时时间（10-30秒）
3. ✅ 实现完整的降级逻辑（网络错误 → TTS）
4. ✅ 缓存音频到本地（可选，提高性能）

### 音频缓存实现（可选）

```dart
// 在应用启动时，预下载所有五十音音频到本地存储
class AudioCacheManager {
  Future<void> cacheAllKanaAudio() async {
    final kanaService = KanaService();
    final characters = await kanaService.getKanaCharacters();
    
    for (final char in characters) {
      final audioUrl = await kanaService.getKanaAudioUrl(char.id);
      if (audioUrl != null) {
        // 下载并缓存
        final cachedPath = await downloadAndCache(audioUrl, char.id);
        logger.info('缓存音频: ${char.hiragana} -> $cachedPath');
      }
    }
  }

  Future<String> downloadAndCache(String url, String cacheKey) async {
    // 实现下载和本地缓存逻辑
    // ...
  }
}
```

---

## 📊 **阶段5：学习进度同步（可选）**

此阶段在步骤3.4 中已覆盖。

### 扩展功能

1. **离线同步**: 当网络不可用时，存储进度到本地，恢复网络后同步
2. **统计分析**: 定期同步后，获取用户的掌握率、学习趋势等
3. **跨设备同步**: 如果用户有多个设备，进度自动同步

```dart
// 离线进度存储
Future<void> saveProgressLocally(
  String userId,
  String kanaCharacterId,
  bool isCorrect,
) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'pending_progress_$userId';
  final pending = jsonDecode(prefs.getString(key) ?? '[]');
  
  pending.add({
    'kana_character_id': kanaCharacterId,
    'correct': isCorrect,
    'timestamp': DateTime.now().toIso8601String(),
  });
  
  await prefs.setString(key, jsonEncode(pending));
}

// 同步待处理的进度
Future<void> syncPendingProgress(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'pending_progress_$userId';
  final pending = jsonDecode(prefs.getString(key) ?? '[]');
  
  if (pending.isEmpty) return;
  
  final kanaService = KanaService();
  for (final item in pending) {
    try {
      await kanaService.reportKanaProgress(
        userId: userId,
        kanaCharacterId: item['kana_character_id'],
        isCorrect: item['correct'],
        timestamp: DateTime.parse(item['timestamp']),
      );
    } catch (e) {
      logger.error('同步失败: $e');
      break; // 某一条失败就停止，保留其他待同步
    }
  }
  
  // 清理已同步的记录
  await prefs.setString(key, '[]');
}
```

---

## ✅ **验证清单**

### 后端验证
- [ ] 数据库迁移执行成功（104条字符记录）
- [ ] API 能返回分类列表（5个分类）
- [ ] API 能返回字符数据（带 hiragana, katakana, romaji）
- [ ] 后端生成了音频文件到 `/uploads/audio/kana/`
- [ ] 管理API `/api/v1/kana/admin/generate-audio` 返回成功

### 客户端验证
- [ ] KanaService 类创建完成
- [ ] gojuon_screen.dart 能从 API 加载分类数据
- [ ] 音频播放可从服务器getConfig音频，降级到 TTS
- [ ] 书写测试能生成题目、评分音频
- [ ] 学习进度能上报到后端

---

## 🚀 **部署顺序**

```
1. 执行后端数据库初始化脚本 ✅
   ↓
2. 生成所有五十音音频 ✅
   ↓
3. 验证后端 API 可用 ✅
   ↓
4. 更新客户端（分步）
   - 创建 KanaService
   - 更新 gojuon_screen.dart
   - 更新音频播放逻辑
   - 更新书写测试
   - 添加进度同步
   ↓
5. 测试端到端流程
   ↓
6. 发布新版本客户端
```

---

## 📝 **注意事项**

### 数据一致性
- 客户端文件名规范：hiragana/katakana 应该对应 assets/svg/kana 中的文件
- 后端 romaji 应完全匹配客户端中的拼写（如 'chi' vs 'ti'）

### 网络兼容性
- 确保移动设备能访问后端服务器
- 配置通用的 API 地址（不能硬编码 localhost）
- 处理网络超时（推荐 30 秒以上超时）

### 性能优化
- 缓存分类和字符列表到本地（减少 API 调用）
- 批量下载音频而非逐个（使用并发下载）
- 离线模式下使用本地备份数据

---

**总结**: 五十音数据已经完全准备好从硬编码迁移到后端 API。后续需要逐步更新客户端代码，最终实现完整的客户端-后端集成。

