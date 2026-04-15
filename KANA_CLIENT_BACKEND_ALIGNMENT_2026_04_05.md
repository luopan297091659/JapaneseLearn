# 🔗 五十音客户端-后端对应分析
**时间**: 2026年4月5日  
**状态**: 📊 **数据兼容，需要集成**

---

## 📋 核心对应关系

### ✅ **数据结构对应表**

| 层级 | 客户端 | 后端 | 对应关系 | 状态 |
|------|--------|------|---------|------|
| **分类** | gojuonData / dakuonData / youonData | kana_categories | 见下表 | ✅ 完全对应 |
| **字符** | [平假名, 片假名, 罗马音] | kana_characters | hiragana + katakana + romaji | ✅ 完全对应 |
| **笔画** | SVG文件（本地） | stroke_count（整数） | 可互补 | ⚠️ 需扩展 |
| **音频** | TTS（系统） | kana_audio（4种类型） | 可替代 | ✅ 可选集成 |
| **学习进度** | SharedPreferences（本地） | user_kana_progress | 可同步 | ❌ 未集成 |

---

## 🎯 **分类映射**

### 清音（Gojuon）→ kana_categories

```
客户端：gojuonData (11行 × 5列 = 50个字符)
  行序: あ行, か行, さ行, た行, な行, は行, ま行, や行, ら行, わ行, ん

后端：kana_categories
  name: "平假名" (Hiragana)
  category_id: 1

客户端数据 → 后端字符示例：
['あ','ア','a'] → kana_characters {
  id: UUID,
  category_id: 1,           # 平假名分类
  hiragana: 'あ',
  katakana: 'ア',
  romaji: 'a',
  order_index: 0
}
```

### 浊音/半浊音（Dakuon）→ kana_categories

```
客户端：dakuonData (5行 × 5列 = 25个字符)
  行序: が行(浊音), ざ行(浊音), だ行(浊音), ば行(浊音), ぱ行(半浊音)

后端：kana_categories
  区分为：
  - "浊音" (Dakuten)      → category_id: 3
  - "半浊音" (Handakuten) → category_id: 4

对应规则：
ると音（ば,び,ぶ,べ,ぼ）  → category_id = 3
半浊音（ぱ,ぴ,ぷ,ぺ,ぽ）  → category_id = 4
```

### 拗音（Youon）→ kana_categories

```
客户端：youonData (11行 × 3列 = 33个组合)
  行序: きゃ行, しゃ行, ちゃ行, にゃ行, ひゃ行, みゃ行, りゃ行, ぎゃ行, じゃ行, びゃ行, ぴゃ行

后端：kana_categories
  name: "拗音" (Yoon)
  category_id: 5

客户端数据 → 后端字符示例：
['きゃ','キャ','kya'] → kana_characters {
  category_id: 5,           # 拗音分类
  hiragana: 'きゃ',
  katakana: 'キャ',
  romaji: 'kya',
  order_index: 0
}
```

---

## 📊 **分类初始化数据**

需要在后端创建的分类记录：

```sql
INSERT INTO kana_categories (name, name_en, description, order_index) VALUES
(1, '平假名', 'Hiragana', 'ひらがな - 现代日语基础字母', 1),
(2, '片假名', 'Katakana', 'かたかな - 外来词和特殊用语', 2),
(3, '浊音', 'Dakuten', 'だくおん - 平假名浊音', 3),
(4, '半浊音', 'Handakuten', 'はんだくおん - 平假名半浊音', 4),
(5, '拗音', 'Yoon', 'ようおん - 组合音（小ya/yu/yo）', 5);
```

---

## 🔤 **字符数据映射详解**

### **客户端数据结构**

```dart
// 单个元素结构
final kanaChar = ['あ', 'ア', 'a'];
// [0] = 平假名 (Hiragana)
// [1] = 片假名 (Katakana)
// [2] = 罗马音 (Romaji)

// 注意：gojuonData 中有空列表 [] 表示不存在
final yaRow = [['や','ヤ','ya'], [], ['ゆ','ユ','yu'], [], ['よ','ヨ','yo']];
//                                ↑ 位置2没有对应字符             ↑ 位置4没有
```

### **后端数据库结构**

```sql
CREATE TABLE kana_characters (
  id CHAR(36) PRIMARY KEY,              -- UUID
  category_id INT,                      -- 分类ID (1-5)
  hiragana VARCHAR(10) NOT NULL,        -- 平假名 ('あ')
  katakana VARCHAR(10),                 -- 片假名 ('ア') [可空]
  romaji VARCHAR(20) NOT NULL UNIQUE,   -- 罗马音 ('a')
  order_index INT,                      -- 顺序 (0-49)
  stroke_count INT,                     -- 笔画数
  writing_guide_url VARCHAR(500),       -- 写法指南
  is_obsolete TINYINT(1)                -- 是否废弃
);
```

### **转换示例**

| 客户端 | → | 后端 kana_characters |
|--------|---|---------------------|
| `['あ','ア','a']` | → | category_id=1, hiragana='あ', katakana='ア', romaji='a', order_index=0 |
| `['か','カ','ka']` | → | category_id=1, hiragana='か', katakana='カ', romaji='ka', order_index=5 |
| `['きゃ','キャ','kya']` | → | category_id=5, hiragana='きゃ', katakana='キャ', romaji='kya', order_index=0 |
| `[]` (空列表) | → | `is_obsolete=1` 或 **不插入** |

---

## 🎨 **笔画数据关联**

### **当前状态**
- **客户端**: SVG文件在 `mobile/assets/svg/kana/{hiragana|katakana}/`
- **后端**: `stroke_count` 字段（仅为整数）

### **对应关系**

```
客户端文件：                    后端记录：
├── あ.svg                    ├── hiragana='あ', stroke_count=3
├── い.svg                    ├── hiragana='い', stroke_count=2
├── ん.svg                    └── hiragana='ん', stroke_count=1

客户端文件：
├── ア.svg                    后端记录：
├── イ.svg           →        ├── katakana='ア', stroke_count=3
├── ン.svg                    ├── katakana='イ', stroke_count=2
                             └── katakana='ン', stroke_count=1
```

### **扩展方案**

如需在后端存储笔画详情，可添加字段：

```sql
ALTER TABLE kana_characters ADD COLUMN (
  stroke_order_svg TEXT,              -- 笔画顺序SVG路径
  stroke_animation_sequence JSON,     -- 笔画动画数据 {stroke: [...]}
  writing_tips TEXT                   -- 写法提示
);
```

---

## 🔊 **音频数据关联**

### **当前状态**

| 侧 | 方案 | 数据来源 | 说明 |
|----|------|---------|------|
| **客户端** | TTS（系统） | Flutter TextToSpeech | 实时生成，无预存 |
| **后端** | Kokoro TTS | `/uploads/audio/kana/` | 预生成，支持多种类型 |

### **音频类型映射**

```
后端 kana_audio.audio_type:
├── 'standard'  (标准速度)   → 正常播放速度
├── 'slow'      (缓速)       → 教学用，便于学习
├── 'natural'   (自然)       → 自然会话速度
└── 'phonetic'  (音标)       → IPA音标/辅助

对应客户端功能：
gojuon_screen.dart 中的播放按钮：
├── 按钮1: 标准速度 → kana_audio.audio_type = 'standard'
├── 按钮2: 缓速     → kana_audio.audio_type = 'slow'
└── (可扩展: 自然速、音标)
```

### **音频URL对应**

```
后端生成：
POST /api/v1/kana/admin/generate-audio
→ 生成音频到 /uploads/audio/kana/kokoro_<uuid>.wav

后端存储：
kana_audio {
  kana_character_id: 'あ的UUID',
  audio_type: 'standard',
  audio_url: '/uploads/audio/kana/kokoro_abc123.wav',
  audio_url_type: 'kokoro'
}

客户端调用：
GET /api/v1/kana/<id>/audio?type=standard
→ 返回 kana_audio.audio_url
→ 播放 <server>/uploads/audio/kana/kokoro_abc123.wav
```

---

## 📱 **学习进度同步**

### **当前状态**

```
客户端：
- SharedPreferences 本地存储
- 数据格式：Map<String, int> (romaji -> 正确次数)
- 未上传到服务器

后端：
- user_kana_progress 表
- 字段：correct_count, incorrect_count, correct_rate, is_mastered, last_reviewed_at
```

### **需要的集成**

```
客户端 → 后端 API:
  1. 用户完成一个假名测试
  2. 调用 POST /api/v1/kana/user/<userId>/progress
  3. 传递 { kana_character_id, correct, timestamp }
  4. 后端更新 user_kana_progress 表

后端处理：
  UPDATE user_kana_progress SET
    correct_count = correct_count + (correct ? 1 : 0),
    incorrect_count = incorrect_count + (correct ? 0 : 1),
    correct_rate = correct_count / total_attempts,
    is_mastered = (correct_rate >= 0.8 AND total_attempts >= 10),
    last_reviewed_at = NOW()
  WHERE user_id = ? AND kana_character_id = ?
```

---

## ✅ **对应关系验证清单**

| 检查项 | 客户端 | 后端 | 对应状态 |
|--------|--------|------|---------|
| **平假名字符** | 'あ', 'い', ... (46个+special) | hiragana + category_id=1 | ✅ 1:1对应 |
| **片假名字符** | 'ア', 'イ', ... (46个+special) | katakana + category_id=2 | ✅ 1:1对应 |
| **浊音** | dakuonData (25个) | category_id=3,4 | ✅ 1:1对应 |
| **拗音** | youonData (33个) | category_id=5 | ✅ 1:1对应 |
| **罗马音** | 'a', 'ka', 'kya'等 | romaji字段 | ✅ 完全对应 |
| **笔画数** | SVG文件隐含 | stroke_count | ✅ 可计算 |
| **音频资源** | 系统TTS | /uploads/audio/kana/ | ✅ 可集成 |
| **学习进度** | 本地SharedPrefs | user_kana_progress | ⚠️ 需同步 |

---

## 🔄 **集成方案（推荐顺序）

### **阶段1: 读取分类和字符（必须）**

```dart
// 替换硬编码数据
// 原有：const gojuonData = [...]
// 新方案：
List<KanaCharacter> kanaCharacters = [];

Future<void> loadKanaData() async {
  // 1. 获取所有分类
  final categories = await api.get('/api/v1/kana/categories');
  // 2. 获取所有字符
  final allCharacters = await api.get('/api/v1/kana/characters?limit=1000');
  // 3. 按category_id分组构建UI
  reorganizeDataByCategory(allCharacters);
}

// UI中使用：
kanaCharacters
  .where((k) => k.categoryId == 1)  // 平假名
  .toList()
```

### **阶段2: 音频播放集成（推荐）**

```dart
// 原有：TTS纯粹本地生成
// 新方案：优先从服务器获取，降级到TTS

Future<void> playKanaAudio(String kanaCharacterId, {String audioType = 'standard'}) async {
  try {
    // 1. 尝试从后端获取
    final audio = await api.get(
      '/api/v1/kana/$kanaCharacterId/audio?type=$audioType',
      timeout: Duration(seconds: 10)
    );
    // 2. 从服务器获取音频文件
    final audioUrl = audio['audio_url']; // e.g., '/uploads/audio/kana/kokoro_xyz.wav'
    await audioPlayer.play(serverUrl + audioUrl);
  } catch (e) {
    // 3. 降级：使用本地TTS
    logger.info('使用本地TTS播放 - 原因: $e');
    await ttsEngine.speak(hiragana);
  }
}
```

### **阶段3: 学习进度同步（可选但推荐）**

```dart
// 客户端：
Future<void> reportKanaProgress(
  String userId, 
  String kanaCharacterId, 
  bool isCorrect
) async {
  await api.post(
    '/api/v1/kana/user/$userId/progress',
    body: {
      'kana_character_id': kanaCharacterId,
      'correct': isCorrect,
      'timestamp': DateTime.now().toIso8601String()
    }
  );
}

// 后端已实现：POST /api/v1/kana/user/:userId/progress
```

---

## 📝 **实现建议**

### **立即可做**
1. ✅ 后端初始化 kana_categories 数据（5条记录）
2. ✅ 后端初始化 kana_characters 数据（104条记录）
   - 46个平假名 + 46个片假名 + 5个浊/半浊 + 33个拗音
3. ✅ 一键生成所有五十音音频到 `/uploads/audio/kana/`

### **后续迭代**
1. 🔧 客户端从 API 读取分类和字符数据（替换硬编码）
2. 🔊 客户端从服务器获取音频，降级到 TTS
3. 📊 客户端上报学习进度到后端

### **扩展空间**
1. 📚 添加写法指南（视频、详细步骤）
2. 🎯 多种音色/发音者选择（标准、自然、缓速等）
3. 📈 高级统计（掌握率、学习时间、遗忘曲线）

---

## 🎓 **总结**

| 方面 | 现状 | 结论 |
|------|------|------|
| **数据对应** | 客户端硬编码 vs 后端数据库 | ✅ **完全兼容**，元素一一对应 |
| **字符数量** | 都是105个（46+46+13） | ✅ **数量一致** |
| **罗马音** | 都包含 | ✅ **拼写一致** |
| **分类方式** | 客户端3组，后端5个分类 | ✅ **可映射**，逻辑清晰 |
| **笔画** | 客户端SVG，后端字段存储 | ✅ **互补**，可结合 |
| **音频** | 客户端TTS，后端Kokoro | ✅ **可替代**，后端更优 |
| **进度追踪** | 客户端本地，后端有表 | ⚠️ **支持就绪**，需集成 |

**结论**: ✅ **客户端和后端的五十音数据结构完全对应，可无缝集成。建议优先执行后端初始化，然后逐步完成客户端集成。**

