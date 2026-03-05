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
  static const _dbVersion = 1;

  static const tableVocab = 'local_vocabulary';

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
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 预留：未来版本迁移
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
          'part_of_speech':  c['part_of_speech'] ?? 'other',
          'jlpt_level':      c['jlpt_level'] ?? 'N3',
          'deck_name':       c['deck_name'],
          'synced':          0,
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

  /// 按牌组分页列出本地词汇
  Future<List<LocalVocabModel>> listByDeck({
    String? deckName,
    String? level,
    String? query,
    int page = 1,
    int limit = 30,
  }) async {
    final database = await db;
    final wheres = <String>[];
    final args   = <dynamic>[];

    if (deckName != null) { wheres.add('deck_name = ?'); args.add(deckName); }
    if (level    != null) { wheres.add('jlpt_level = ?'); args.add(level);   }
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

  /// 按牌组分页的总记录数
  Future<int> countByDeck({String? deckName, String? level, String? query}) async {
    final database = await db;
    final wheres = <String>[];
    final args   = <dynamic>[];
    if (deckName != null) { wheres.add('deck_name = ?'); args.add(deckName); }
    if (level    != null) { wheres.add('jlpt_level = ?'); args.add(level);   }
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

  /// 列出所有牌组名称及各自卡片数
  Future<List<({String deckName, int total, int pending})>> listDecks() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT deck_name,
             COUNT(*) AS total,
             SUM(CASE WHEN synced=0 THEN 1 ELSE 0 END) AS pending
      FROM $tableVocab
      GROUP BY deck_name
      ORDER BY MAX(created_at) DESC
    ''');
    return rows.map((r) => (
      deckName: (r['deck_name'] as String?) ?? 'Anki Import',
      total:    (r['total']    as int?) ?? 0,
      pending:  (r['pending']  as int?) ?? 0,
    )).toList();
  }

  /// 删除整个牌组
  Future<int> deleteDeck(String deckName) async {
    final database = await db;
    return database.delete(tableVocab, where: 'deck_name = ?', whereArgs: [deckName]);
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
    category:        deckName,
  );
}

// ─── 全局单例 ──────────────────────────────────────────────────────────────────
final localDb = LocalDb();
