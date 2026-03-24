import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// 本地 SQLite 数据库服务
///
/// 存储 Anki 导入的词汇卡片，支持离线使用 + 联网同步。
/// 同步状态字段 [synced]: 0 = 待同步, 1 = 已同步到服务器
class LocalDb {
  static final LocalDb _instance = LocalDb._internal();
  factory LocalDb() => _instance;
  LocalDb._internal();

  Database? _db;

  static const _dbName    = 'japanese_learn_local.db';
  static const _dbVersion = 5;

  static const tableVocab = 'local_vocabulary';
  static const tableCachedVocab = 'cached_vocabulary';
  static const tableCachedGrammar = 'cached_grammar';

  // ─── 初始化 ─────────────────────────────────────────────────────────────
  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir  = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableVocab (
        id               TEXT    PRIMARY KEY,
        word             TEXT    NOT NULL,
        reading          TEXT    NOT NULL,
        meaning_zh       TEXT    NOT NULL,
        meaning_en       TEXT,
        example_sentence TEXT,
        example_reading  TEXT,
        example_meaning_zh TEXT,
        example_audio_url TEXT,
        audio_url        TEXT,
        is_learned       INTEGER NOT NULL DEFAULT 0,
        learning_stage   INTEGER NOT NULL DEFAULT 0,
        part_of_speech   TEXT    NOT NULL DEFAULT 'other',
        jlpt_level       TEXT    NOT NULL DEFAULT 'N3',
        deck_name        TEXT,
        synced           INTEGER NOT NULL DEFAULT 0,
        created_at       INTEGER NOT NULL
      )
    ''');
    // 加速按牌组/等级筛选
    await db.execute('CREATE INDEX idx_deck ON $tableVocab (deck_name)');
    await db.execute('CREATE INDEX idx_level ON $tableVocab (jlpt_level)');
    await db.execute('CREATE INDEX idx_synced ON $tableVocab (synced)');

    // ─── 离线缓存表 ─────────────────────────────────────────────────────
    await _createCacheTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN example_reading TEXT');
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN example_meaning_zh TEXT');
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN example_audio_url TEXT');
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN audio_url TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN is_learned INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE $tableVocab ADD COLUMN learning_stage INTEGER NOT NULL DEFAULT 0');
      await db.execute('UPDATE $tableVocab SET learning_stage = CASE WHEN is_learned = 1 THEN 1 ELSE 0 END');
    }
    if (oldVersion < 5) {
      await _createCacheTables(db);
    }
  }

  Future<void> _createCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCachedVocab (
        id                TEXT    PRIMARY KEY,
        word              TEXT    NOT NULL,
        reading           TEXT    NOT NULL,
        meaning_zh        TEXT    NOT NULL,
        meaning_en        TEXT,
        part_of_speech    TEXT    NOT NULL DEFAULT 'noun',
        part_of_speech_raw TEXT,
        jlpt_level        TEXT    NOT NULL,
        example_sentence  TEXT,
        example_reading   TEXT,
        example_meaning_zh TEXT,
        example_audio_url TEXT,
        audio_url         TEXT,
        image_url         TEXT,
        category          TEXT,
        sort_order        INTEGER NOT NULL DEFAULT 0,
        cached_at         INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cv_level ON $tableCachedVocab (jlpt_level)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cv_word ON $tableCachedVocab (word)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCachedGrammar (
        id              TEXT    PRIMARY KEY,
        title           TEXT    NOT NULL,
        title_zh        TEXT,
        jlpt_level      TEXT    NOT NULL,
        pattern         TEXT    NOT NULL,
        explanation     TEXT,
        explanation_zh  TEXT,
        usage_notes     TEXT,
        examples_json   TEXT,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        cached_at       INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cg_level ON $tableCachedGrammar (jlpt_level)');
  }

  // ─── 写入 ────────────────────────────────────────────────────────────────

  /// 批量插入卡片（已存在的 id 跳过，不覆盖）
  Future<int> insertCards(List<Map<String, dynamic>> cards) async {
    final database = await db;
    int inserted = 0;
    final batch = database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in cards) {
      batch.insert(
        tableVocab,
        {
          'id':              c['id'] as String,
          'word':            c['word'] as String,
          'reading':         c['reading'] as String,
          'meaning_zh':      c['meaning_zh'] as String,
          'meaning_en':      c['meaning_en'],
          'example_sentence': c['example_sentence'],
          'example_reading': c['example_reading'],
          'example_meaning_zh': c['example_meaning_zh'],
          'example_audio_url': c['example_audio_url'],
          'audio_url': c['audio_url'],
          'is_learned': c['is_learned'] ?? 0,
          'learning_stage': c['learning_stage'] ?? ((c['is_learned'] ?? 0) == 1 ? 1 : 0),
          'part_of_speech':  c['part_of_speech'] ?? 'other',
          'jlpt_level':      c['jlpt_level'] ?? 'N3',
          'deck_name':       c['deck_name'],
          'synced':          1,
          'created_at':      now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      inserted++;
    }
    await batch.commit(noResult: true);
    return inserted;
  }

  /// 将一批卡片 id 标记为已同步
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    // SQLite 每次 IN 参数上限约 999，分批处理
    const chunkSize = 500;
    for (int i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, (i + chunkSize).clamp(0, ids.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      await database.rawUpdate(
        'UPDATE $tableVocab SET synced = 1 WHERE id IN ($placeholders)',
        chunk,
      );
    }
  }

  // ─── 查询 ────────────────────────────────────────────────────────────────

  /// 查询待同步的卡片（synced=0），最多返回 [limit] 条
  Future<List<Map<String, dynamic>>> pendingCards({int limit = 1000}) async {
    final database = await db;
    return database.query(
      tableVocab,
      where: 'synced = 0',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  /// 待同步数量
  Future<int> pendingCount() async {
    final database = await db;
    final res = await database.rawQuery(
        'SELECT COUNT(*) AS cnt FROM $tableVocab WHERE synced = 0');
    return (res.first['cnt'] as int?) ?? 0;
  }

  /// 按牌组分页列出本地词汇（支持 prefix 模式匹配子牌组）
  Future<List<LocalVocabModel>> listByDeck({
    String? deckName,
    bool prefixMatch = false,
    String? level,
    String? query,
    int? learningStage,
    int page = 1,
    int limit = 30,
  }) async {
    final database = await db;
    final wheres = <String>[];
    final args   = <dynamic>[];

    if (deckName != null) {
      if (prefixMatch) {
        wheres.add('(deck_name = ? OR deck_name LIKE ?)');
        args.addAll([deckName, '$deckName::%']);
      } else {
        wheres.add('deck_name = ?');
        args.add(deckName);
      }
    }
    if (level    != null) { wheres.add('jlpt_level = ?'); args.add(level);   }
    if (learningStage != null) {
      wheres.add('learning_stage = ?');
      args.add(learningStage);
    }
    if (query    != null && query.isNotEmpty) {
      wheres.add('(word LIKE ? OR reading LIKE ? OR meaning_zh LIKE ?)');
      args.addAll(['%$query%', '%$query%', '%$query%']);
    }

    final where  = wheres.isEmpty ? null : wheres.join(' AND ');
    final offset = (page - 1) * limit;
    final rows = await database.query(
      tableVocab,
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LocalVocabModel.fromMap).toList();
  }

  /// 按牌组分页的总记录数（支持 prefix 模式匹配子牌组）
  Future<int> countByDeck({
    String? deckName,
    bool prefixMatch = false,
    String? level,
    String? query,
    int? learningStage,
  }) async {
    final database = await db;
    final wheres = <String>[];
    final args   = <dynamic>[];
    if (deckName != null) {
      if (prefixMatch) {
        wheres.add('(deck_name = ? OR deck_name LIKE ?)');
        args.addAll([deckName, '$deckName::%']);
      } else {
        wheres.add('deck_name = ?');
        args.add(deckName);
      }
    }
    if (level    != null) { wheres.add('jlpt_level = ?'); args.add(level);   }
    if (learningStage != null) {
      wheres.add('learning_stage = ?');
      args.add(learningStage);
    }
    if (query    != null && query.isNotEmpty) {
      wheres.add('(word LIKE ? OR reading LIKE ? OR meaning_zh LIKE ?)');
      args.addAll(['%$query%', '%$query%', '%$query%']);
    }
    final where = wheres.isEmpty ? null : wheres.join(' AND ');
    final res = await database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableVocab ${where != null ? "WHERE $where" : ""}',
      args.isEmpty ? null : args,
    );
    return (res.first['cnt'] as int?) ?? 0;
  }

  Future<Map<int, int>> countByLearningStage({
    String? deckName,
    bool prefixMatch = false,
    String? level,
    String? query,
  }) async {
    final database = await db;
    final wheres = <String>[];
    final args = <dynamic>[];

    if (deckName != null) {
      if (prefixMatch) {
        wheres.add('(deck_name = ? OR deck_name LIKE ?)');
        args.addAll([deckName, '$deckName::%']);
      } else {
        wheres.add('deck_name = ?');
        args.add(deckName);
      }
    }
    if (level != null) {
      wheres.add('jlpt_level = ?');
      args.add(level);
    }
    if (query != null && query.isNotEmpty) {
      wheres.add('(word LIKE ? OR reading LIKE ? OR meaning_zh LIKE ?)');
      args.addAll(['%$query%', '%$query%', '%$query%']);
    }

    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await database.rawQuery(
      'SELECT learning_stage, COUNT(*) AS cnt FROM $tableVocab $where GROUP BY learning_stage',
      args.isEmpty ? null : args,
    );

    final counts = <int, int>{0: 0, 1: 0, 2: 0};
    for (final row in rows) {
      final stage = row['learning_stage'] as int?;
      final count = row['cnt'] as int? ?? 0;
      if (stage != null && counts.containsKey(stage)) {
        counts[stage] = count;
      }
    }
    return counts;
  }

  Future<LocalVocabModel?> getCardById(String id) async {
    final database = await db;
    final rows = await database.query(
      tableVocab,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalVocabModel.fromMap(rows.first);
  }

  Future<void> setLearned(String id, {required bool isLearned}) async {
    final database = await db;
    await database.update(
      tableVocab,
      {
        'is_learned': isLearned ? 1 : 0,
        'learning_stage': isLearned ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setLearningStage(String id, {required int stage}) async {
    final database = await db;
    final safeStage = stage < 0 ? 0 : (stage > 2 ? 2 : stage);
    await database.update(
      tableVocab,
      {
        'learning_stage': safeStage,
        'is_learned': safeStage > 0 ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 列出所有牌组名称及各自卡片数
  Future<List<({String deckName, int total, int pending})>> listDecks() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT deck_name,
             COUNT(*) AS total,
             SUM(CASE WHEN synced=0 THEN 1 ELSE 0 END) AS pending
      FROM $tableVocab
      GROUP BY deck_name
      ORDER BY deck_name ASC
    ''');
    return rows.map((r) => (
      deckName: (r['deck_name'] as String?) ?? 'Anki Import',
      total:    (r['total']    as int?) ?? 0,
      pending:  (r['pending']  as int?) ?? 0,
    )).toList();
  }

  /// 删除整个牌组（支持按前缀删除子牌组）
  Future<int> deleteDeck(String deckName) async {
    final database = await db;
    // 删除精确匹配 + 所有子牌组（deck_name LIKE 'deckName::%'）
    return database.delete(
      tableVocab,
      where: 'deck_name = ? OR deck_name LIKE ?',
      whereArgs: [deckName, '$deckName::%'],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── 离线缓存：系统单词 ─────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  /// 批量缓存系统单词（upsert），附带排序序号
  Future<void> cacheVocabulary(List<VocabularyModel> items, {int sortOffset = 0}) async {
    if (items.isEmpty) return;
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();
    for (int i = 0; i < items.length; i++) {
      final v = items[i];
      batch.insert(tableCachedVocab, {
        'id':               v.id,
        'word':             v.word,
        'reading':          v.reading,
        'meaning_zh':       v.meaningZh,
        'meaning_en':       v.meaningEn,
        'part_of_speech':   v.partOfSpeech,
        'part_of_speech_raw': v.partOfSpeechRaw,
        'jlpt_level':       v.jlptLevel,
        'example_sentence': v.exampleSentence,
        'example_reading':  v.exampleReading,
        'example_meaning_zh': v.exampleMeaningZh,
        'example_audio_url': v.exampleAudioUrl,
        'audio_url':        v.audioUrl,
        'image_url':        v.imageUrl,
        'category':         v.category,
        'sort_order':       sortOffset + i,
        'cached_at':        now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 从本地缓存查询系统单词（分页），支持搜索
  Future<Map<String, dynamic>> getCachedVocabulary({
    required String level,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    final database = await db;
    final wheres = <String>['jlpt_level = ?'];
    final args = <dynamic>[level];
    if (query != null && query.isNotEmpty) {
      wheres.add('(word LIKE ? OR reading LIKE ? OR meaning_zh LIKE ?)');
      args.addAll(['%$query%', '%$query%', '%$query%']);
    }
    final where = wheres.join(' AND ');
    final countRes = await database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCachedVocab WHERE $where', args,
    );
    final total = (countRes.first['cnt'] as int?) ?? 0;

    final offset = (page - 1) * limit;
    final rows = await database.query(
      tableCachedVocab,
      where: where,
      whereArgs: args,
      orderBy: 'sort_order ASC',
      limit: limit,
      offset: offset,
    );
    final data = rows.map(_vocabFromRow).toList();
    return {'total': total, 'data': data};
  }

  /// 从缓存获取某级别全部单词 ID（保持排序）
  Future<List<String>> getCachedVocabularyIds(String level) async {
    final database = await db;
    final rows = await database.query(
      tableCachedVocab,
      columns: ['id'],
      where: 'jlpt_level = ?',
      whereArgs: [level],
      orderBy: 'sort_order ASC',
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  /// 查询某级别缓存数量
  Future<int> cachedVocabCount(String level) async {
    final database = await db;
    final res = await database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCachedVocab WHERE jlpt_level = ?', [level],
    );
    return (res.first['cnt'] as int?) ?? 0;
  }

  /// 清除某级别的缓存单词，不传 level 则清除全部
  Future<void> clearCachedVocabulary({String? level}) async {
    final database = await db;
    if (level != null) {
      await database.delete(tableCachedVocab, where: 'jlpt_level = ?', whereArgs: [level]);
    } else {
      await database.delete(tableCachedVocab);
    }
  }

  VocabularyModel _vocabFromRow(Map<String, dynamic> r) => VocabularyModel(
    id:              r['id'] as String,
    word:            r['word'] as String,
    reading:         r['reading'] as String,
    meaningZh:       r['meaning_zh'] as String,
    meaningEn:       r['meaning_en'] as String?,
    partOfSpeech:    r['part_of_speech'] as String? ?? 'noun',
    partOfSpeechRaw: r['part_of_speech_raw'] as String?,
    jlptLevel:       r['jlpt_level'] as String,
    exampleSentence: r['example_sentence'] as String?,
    exampleReading:  r['example_reading'] as String?,
    exampleMeaningZh: r['example_meaning_zh'] as String?,
    exampleAudioUrl: r['example_audio_url'] as String?,
    audioUrl:        r['audio_url'] as String?,
    imageUrl:        r['image_url'] as String?,
    category:        r['category'] as String?,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── 离线缓存：系统文法 ─────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  /// 批量缓存文法条目（upsert），examples 序列化为 JSON
  Future<void> cacheGrammar(List<GrammarLessonModel> items, {int sortOffset = 0}) async {
    if (items.isEmpty) return;
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();
    for (int i = 0; i < items.length; i++) {
      final g = items[i];
      final exJson = jsonEncode(g.examples.map((e) => {
        'id': e.id, 'sentence': e.sentence,
        'reading': e.reading, 'meaning_zh': e.meaningZh,
        'audio_url': e.audioUrl,
      }).toList());
      batch.insert(tableCachedGrammar, {
        'id':             g.id,
        'title':          g.title,
        'title_zh':       g.titleZh,
        'jlpt_level':     g.jlptLevel,
        'pattern':        g.pattern,
        'explanation':    g.explanation,
        'explanation_zh': g.explanationZh,
        'usage_notes':    g.usageNotes,
        'examples_json':  exJson,
        'sort_order':     sortOffset + i,
        'cached_at':      now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 从本地缓存查询文法（分页）
  Future<Map<String, dynamic>> getCachedGrammar({
    required String level,
    int page = 1,
    int limit = 20,
  }) async {
    final database = await db;
    final countRes = await database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCachedGrammar WHERE jlpt_level = ?', [level],
    );
    final total = (countRes.first['cnt'] as int?) ?? 0;

    final offset = (page - 1) * limit;
    final rows = await database.query(
      tableCachedGrammar,
      where: 'jlpt_level = ?',
      whereArgs: [level],
      orderBy: 'sort_order ASC',
      limit: limit,
      offset: offset,
    );
    final data = rows.map(_grammarFromRow).toList();
    return {'total': total, 'data': data};
  }

  /// 查询某级别缓存文法数量
  Future<int> cachedGrammarCount(String level) async {
    final database = await db;
    final res = await database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableCachedGrammar WHERE jlpt_level = ?', [level],
    );
    return (res.first['cnt'] as int?) ?? 0;
  }

  /// 清除某级别的缓存文法，不传 level 则清除全部
  Future<void> clearCachedGrammar({String? level}) async {
    final database = await db;
    if (level != null) {
      await database.delete(tableCachedGrammar, where: 'jlpt_level = ?', whereArgs: [level]);
    } else {
      await database.delete(tableCachedGrammar);
    }
  }

  GrammarLessonModel _grammarFromRow(Map<String, dynamic> r) {
    List<GrammarExampleModel> examples = [];
    final exStr = r['examples_json'] as String?;
    if (exStr != null && exStr.isNotEmpty) {
      final list = jsonDecode(exStr) as List<dynamic>;
      examples = list.map((e) => GrammarExampleModel.fromJson(
        Map<String, dynamic>.from(e as Map),
      )).toList();
    }
    return GrammarLessonModel(
      id:            r['id'] as String,
      title:         r['title'] as String,
      titleZh:       r['title_zh'] as String?,
      jlptLevel:     r['jlpt_level'] as String,
      pattern:       r['pattern'] as String,
      explanation:   r['explanation'] as String?,
      explanationZh: r['explanation_zh'] as String?,
      usageNotes:    r['usage_notes'] as String?,
      examples:      examples,
    );
  }

  // ─── 关闭 ────────────────────────────────────────────────────────────────
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

// ─── 本地词汇模型 ─────────────────────────────────────────────────────────────

class LocalVocabModel {
  final String  id;
  final String  word;
  final String  reading;
  final String  meaningZh;
  final String? meaningEn;
  final String? exampleSentence;
  final String? exampleReading;
  final String? exampleMeaningZh;
  final String? exampleAudioUrl;
  final String? audioUrl;
  final bool isLearned;
  final int learningStage;
  final String  partOfSpeech;
  final String  jlptLevel;
  final String? deckName;
  final bool    synced;
  final DateTime createdAt;

  const LocalVocabModel({
    required this.id,
    required this.word,
    required this.reading,
    required this.meaningZh,
    this.meaningEn,
    this.exampleSentence,
    this.exampleReading,
    this.exampleMeaningZh,
    this.exampleAudioUrl,
    this.audioUrl,
    this.isLearned = false,
    this.learningStage = 0,
    required this.partOfSpeech,
    required this.jlptLevel,
    this.deckName,
    required this.synced,
    required this.createdAt,
  });

  factory LocalVocabModel.fromMap(Map<String, dynamic> m) => LocalVocabModel(
    id:              m['id'] as String,
    word:            m['word'] as String,
    reading:         m['reading'] as String,
    meaningZh:       m['meaning_zh'] as String,
    meaningEn:       m['meaning_en'] as String?,
    exampleSentence: m['example_sentence'] as String?,
    exampleReading:  m['example_reading'] as String?,
    exampleMeaningZh: m['example_meaning_zh'] as String?,
    exampleAudioUrl: m['example_audio_url'] as String?,
    audioUrl:        m['audio_url'] as String?,
    isLearned:       (m['is_learned'] as int? ?? 0) == 1,
    learningStage:   (() {
      final stage = m['learning_stage'] as int?;
      if (stage != null) return stage;
      return (m['is_learned'] as int? ?? 0) == 1 ? 1 : 0;
    })(),
    partOfSpeech:    m['part_of_speech'] as String? ?? 'other',
    jlptLevel:       m['jlpt_level'] as String? ?? 'N3',
    deckName:        m['deck_name'] as String?,
    synced:          (m['synced'] as int? ?? 0) == 1,
    createdAt:       DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  /// 转为 VocabularyModel（用于复用现有 UI 组件）
  VocabularyModel toVocabularyModel() => VocabularyModel(
    id:              id,
    word:            word,
    reading:         reading,
    meaningZh:       meaningZh,
    meaningEn:       meaningEn,
    partOfSpeech:    partOfSpeech,
    jlptLevel:       jlptLevel,
    exampleSentence: exampleSentence,
    exampleReading:  exampleReading,
    exampleMeaningZh: exampleMeaningZh,
    exampleAudioUrl: exampleAudioUrl,
    audioUrl:        audioUrl,
    category:        deckName,
  );

  LocalVocabModel copyWith({
    bool? isLearned,
  }) {
    return LocalVocabModel(
      id: id,
      word: word,
      reading: reading,
      meaningZh: meaningZh,
      meaningEn: meaningEn,
      exampleSentence: exampleSentence,
      exampleReading: exampleReading,
      exampleMeaningZh: exampleMeaningZh,
      exampleAudioUrl: exampleAudioUrl,
      audioUrl: audioUrl,
      isLearned: isLearned ?? this.isLearned,
        learningStage: learningStage,
      partOfSpeech: partOfSpeech,
      jlptLevel: jlptLevel,
      deckName: deckName,
      synced: synced,
      createdAt: createdAt,
    );
  }

    LocalVocabModel copyWithStage(int stage) {
      final safeStage = stage < 0 ? 0 : (stage > 2 ? 2 : stage);
      return LocalVocabModel(
        id: id,
        word: word,
        reading: reading,
        meaningZh: meaningZh,
        meaningEn: meaningEn,
        exampleSentence: exampleSentence,
        exampleReading: exampleReading,
        exampleMeaningZh: exampleMeaningZh,
        exampleAudioUrl: exampleAudioUrl,
        audioUrl: audioUrl,
        isLearned: safeStage > 0,
        learningStage: safeStage,
        partOfSpeech: partOfSpeech,
        jlptLevel: jlptLevel,
        deckName: deckName,
        synced: synced,
        createdAt: createdAt,
      );
    }
}

// ─── 全局单例 ──────────────────────────────────────────────────────────────────
final localDb = LocalDb();
