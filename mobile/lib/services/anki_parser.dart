import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ─── 数据模型 ────────────────────────────────────────────────────────────────

class AnkiCard {
  final String word;
  final String reading;
  final String meaningZh;
  final String? meaningEn;
  final String? example;
  final String? audioUrl; // 本地音频文件路径（来自 .apkg 提取）

  const AnkiCard({
    required this.word,
    required this.reading,
    required this.meaningZh,
    this.meaningEn,
    this.example,
    this.audioUrl,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'reading': reading,
        'meaning_zh': meaningZh,
        if (meaningEn != null && meaningEn!.isNotEmpty) 'meaning_en': meaningEn,
        if (example != null && example!.isNotEmpty) 'example_sentence': example,
        if (audioUrl != null && audioUrl!.isNotEmpty) 'audio_url': audioUrl,
      };
}

class AnkiPreview {
  final List<String> fields;
  final List<Map<String, String>> samples;
  final int total;
  final String format;
  final Map<String, int?> autoMapping;

  const AnkiPreview({
    required this.fields,
    required this.samples,
    required this.total,
    required this.format,
    required this.autoMapping,
  });
}

// ─── 解析器 ──────────────────────────────────────────────────────────────────

class AnkiParser {
  // ── 工具 ──────────────────────────────────────────────────────────────────

  static String _stripHtml(String s) {
    return s
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\[sound:[^\]]*\]'), '') // 去掉 Anki 音频标签
        .trim();
  }

  /// 从字段原始内容中提取第一个 [sound:xxx] 文件名
  static String? _extractSoundRef(String raw) {
    final m = RegExp(r'\[sound:([^\]]+)\]').firstMatch(raw);
    return m?.group(1);
  }

  /// 读取 .apkg 中的 media JSON，将音频文件复制到永久目录
  /// 返回 { 原始文件名 → 本地绝对路径 }
  static Future<Map<String, String>> _buildAudioMap(
      Directory extractDir) async {
    final mediaFile = File('${extractDir.path}/media');
    if (!await mediaFile.exists()) return {};

    Map<String, dynamic> mediaJson;
    try {
      mediaJson = jsonDecode(await mediaFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docsDir.path}/anki_audio');
    await audioDir.create(recursive: true);

    final Map<String, String> result = {};
    for (final entry in mediaJson.entries) {
      final index = entry.key;          // '0', '1', ...
      final filename = entry.value.toString(); // 'audio.mp3'
      final src = File('${extractDir.path}/$index');
      if (!await src.exists()) continue;
      final dest = '${audioDir.path}/$filename';
      await src.copy(dest);
      result[filename] = dest;
    }
    return result;
  }

  static String _clamp(String s, int max) =>
      s.length > max ? s.substring(0, max) : s;

  /// 根据字段名 + 样本内容自动推断映射
  ///
  /// [rawSamples]: 前几行的原始字段值列表（可选），用于内容分析兜底
  static Map<String, int?> detectMapping(List<String> fields,
      [List<List<String>>? rawSamples]) {
    int? word, reading, meaningZh, meaningEn, example, posField;

    // ── Step 1: 字段名匹配 ───────────────────────────────────────────────────
    for (int i = 0; i < fields.length; i++) {
      final name = fields[i].toLowerCase();

      // 品词字段优先识别，排除在外
      if (RegExp(r'(品詞|品词|pos|part.of.speech|词性|词类|partsofspeech|type)',
              caseSensitive: false)
          .hasMatch(name)) {
        posField ??= i;
        continue;
      }

      if (word == null &&
          RegExp(r'(expression|front|word|kanji|vocab|japanese|jp|単語|日本語|词|表达式|日语|表現)',
                  caseSensitive: false)
              .hasMatch(name)) {
        word = i;
      } else if (reading == null &&
          RegExp(r'(reading|kana|hiragana|furigana|読み|よみ|かな|ひらがな|pronunciation)',
                  caseSensitive: false)
              .hasMatch(name)) {
        reading = i;
      }

      if (meaningZh == null &&
          RegExp(r'(meaning|意味|中文|chinese|翻訳|back|中国語|释义|定义|translation|意思)',
                  caseSensitive: false)
              .hasMatch(name)) {
        meaningZh = i;
      }
      if (meaningEn == null &&
          RegExp(r'(english|^en$|meaning_en|definition|gloss)', caseSensitive: false)
              .hasMatch(name)) {
        meaningEn = i;
      }
      if (example == null &&
          RegExp(r'(example|sentence|例文|例句|sample|context|usage)', caseSensitive: false)
              .hasMatch(name)) {
        example = i;
      }
    }

    // ── Step 2: 内容分析兜底 ──────────────────────────────────────────────────
    // 当字段名无法确定时，分析每列的实际内容特征
    if (rawSamples != null && rawSamples.isNotEmpty) {
      // 统计每列特征
      final colCount = rawSamples.fold(0, (m, r) => r.length > m ? r.length : m);

      // ── 2a: 优先识别振假名格式 (漢字[よみ]) ─────────────────────────────
      // 含有「漢字[ひらがな]」括号格式的字段，100% 是 Anki 振假名日语单词列
      final furiganaRe = RegExp(
          r'[\u4e00-\u9fff\uff10-\uff19\u3041-\u30ff]+\[[^\]]*[\u3040-\u30ff][^\]]*\]');
      for (int i = 0; i < colCount && word == null; i++) {
        if (i == posField) continue;
        final vals = rawSamples
            .map((r) => i < r.length ? r[i].trim() : '')
            .where((v) => v.isNotEmpty)
            .toList();
        if (vals.any((v) => furiganaRe.hasMatch(v))) {
          word = i;
        }
      }

      for (int i = 0; i < colCount; i++) {
        final vals = rawSamples
            .map((r) => i < r.length ? r[i].trim() : '')
            .where((v) => v.isNotEmpty)
            .toList();
        if (vals.isEmpty) continue;

        final avgLen = vals.fold(0.0, (s, v) => s + v.length) / vals.length;

        // 检测品词列：值非常短 & 全是品词缩写
        final looksLikePos = avgLen <= 3.0 &&
            vals.every((v) =>
                v.length <= 4 &&
                RegExp(r'^(名|動|形|副|助|感|接頭|接尾|代|連|他|自|一|二|三|格|終|並)$')
                    .hasMatch(v));
        if (looksLikePos) {
          posField ??= i;
          continue;
        }

        final hasJapanese =
            vals.any((v) => RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(v));
        final hasHiraganaOrKana =
            vals.any((v) => RegExp(r'[\u3040-\u30ff]').hasMatch(v));
        final hasChinese =
            vals.any((v) => RegExp(r'[\u4e00-\u9fff]').hasMatch(v));
        // 纯中文字段：有汉字但完全没有假名 → 必定是释义，不能作为日语单词
        final isChineseOnly = hasChinese &&
            !vals.any((v) => RegExp(r'[\u3040-\u30ff]').hasMatch(v));
        final hasOnlyKanaOrKanji = vals.every((v) =>
            RegExp(r'^[\u3040-\u30ff\u4e00-\u9fff\u3000-\u303f\uff00-\uffef～〜ー・\s]+$')
                .hasMatch(v));
        // 中文释义特征：含汉字 & 含标点/多个词 & 不全是日文
        final looksLikeMeaning = hasChinese &&
            vals.any((v) => v.contains(RegExp(r'[、，。：；！？,.]')) || v.length > 6);

        if (i == posField) continue;

        // 跳过已被振假名识别为 word 的列
        if (i == word) continue;

        if (word == null && !isChineseOnly && hasJapanese && avgLen <= 20 && hasOnlyKanaOrKanji) {
          word = i;
        } else if (reading == null &&
            hasHiraganaOrKana &&
            avgLen <= 30 &&
            i != word) {
          reading = i;
        } else if (meaningZh == null && looksLikeMeaning && i != word && i != reading) {
          meaningZh = i;
        } else if (meaningZh == null && hasChinese && i != word && i != reading) {
          meaningZh = i;
        }
      }
    }

    // ── Step 3: 终极兜底 — 跳过品词列 ──────────────────────────────────────
    if (word == null) {
      for (int i = 0; i < fields.length; i++) {
        if (i != posField) {
          word = i;
          break;
        }
      }
      word ??= 0;
    }
    if (meaningZh == null && meaningEn == null) {
      for (int i = 0; i < fields.length; i++) {
        if (i != word && i != reading && i != posField) {
          meaningZh = i;
          break;
        }
      }
      // 实在找不到就用 word+1
      if (meaningZh == null && fields.length >= 2) {
        meaningZh = word == 0 ? 1 : 0;
      }
    }

    // ── Step 4: 互换校验 ────────────────────────────────────────────────────
    // 若 word 列完全没有假名 (纯汉字/中文)，而 reading 列含振假名格式，说明两者颠倒
    if (word != null && rawSamples != null && rawSamples.isNotEmpty) {
      final furiganaRe = RegExp(
          r'[\u4e00-\u9fff\uff10-\uff19\u3041-\u30ff]+\[[^\]]*[\u3040-\u30ff][^\]]*\]');
      final wordVals = rawSamples
          .map((r) => word! < r.length ? r[word!].trim() : '')
          .where((v) => v.isNotEmpty)
          .toList();
      final wordHasKana =
          wordVals.any((v) => RegExp(r'[\u3040-\u30ff]').hasMatch(v));
      final wordHasFurigana = wordVals.any((v) => furiganaRe.hasMatch(v));

      if (!wordHasKana && !wordHasFurigana && reading != null) {
        final readingVals = rawSamples
            .map((r) => reading! < r.length ? r[reading!].trim() : '')
            .where((v) => v.isNotEmpty)
            .toList();
        final readingHasFurigana =
            readingVals.any((v) => furiganaRe.hasMatch(v));
        if (readingHasFurigana) {
          // reading 列才是真正的日语单词，与 word 互换
          final tmp = word;
          word = reading;
          reading = tmp;
        }
      }
    }

    return {
      'word': word,
      'reading': reading,
      'meaning_zh': meaningZh,
      'meaning_en': meaningEn,
      'example': example,
    };
  }

  // ── 公开 API ───────────────────────────────────────────────────────────────

  /// 预览：解析文件，返回字段列表、自动映射、前5条样本，不做任何网络请求
  static Future<AnkiPreview> preview(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.apkg') return _previewApkg(filePath);
    return _previewTxt(filePath, ext);
  }

  /// 按映射解析全部卡片
  static Future<List<AnkiCard>> parse(
      String filePath, Map<String, int?> mapping) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.apkg') return _parseApkg(filePath, mapping);
    return _parseTxt(filePath, ext, mapping);
  }

  // ── .apkg ────────────────────────────────────────────────────────────────

  /// 解压 .apkg → 临时目录，返回目录路径（调用方负责清理）
  static Future<Directory> _extractApkg(String filePath) async {
    final tmpDir = await getTemporaryDirectory();
    final extractDir = Directory(
        '${tmpDir.path}/anki_${DateTime.now().millisecondsSinceEpoch}');
    await extractDir.create(recursive: true);

    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (file.isFile) {
        final outFile = File('${extractDir.path}/${file.name}');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }
    return extractDir;
  }

  /// 打开解压后的 SQLite，读取 notes + 字段名映射
  /// 自动尝试 anki21b → anki21 → anki2，任一格式可打开即停止
  static Future<
      ({
        List<Map<String, Object?>> notes,
        Map<dynamic, List<String>> fieldMap
      })> _readAnkiDb(String extractDirPath) async {
    final candidates = [
      'collection.anki21b', // 新版（zstd 压缩 SQLite，sqflite 不支持需跳过）
      'collection.anki21',
      'collection.anki2',
    ];

    Database? db;
    String? openedPath;

    for (final c in candidates) {
      final f = File('$extractDirPath/$c');
      if (!await f.exists()) continue;
      Database? tryDb;
      try {
        // singleInstance:false 确保每次都是全新连接，避免复用损坏的缓存连接
        tryDb = await openDatabase(
          f.path,
          readOnly: true,
          singleInstance: false,
        );
        // 做一次查询验证文件是否真的是有效 SQLite（anki21b 是 zstd，会在此处抛异常）
        await tryDb.rawQuery('SELECT COUNT(*) FROM notes');
        db = tryDb;
        openedPath = f.path;
        break;
      } catch (e) {
        // anki21b 等压缩格式会在 open 或 query 阶段抛异常，尝试下一个
        try { await tryDb?.close(); } catch (_) {}
        tryDb = null;
      }
    }

    if (db == null) {
      // 列出实际解压出的文件，帮助诊断
      final found = candidates
          .where((c) => File('$extractDirPath/$c').existsSync())
          .toList();
      final allFiles = Directory(extractDirPath)
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList();
      if (found.contains('collection.anki21b')) {
        throw Exception(
            '该 .apkg 使用 Anki 新版格式（collection.anki21b，zstd 压缩），'
            '当前版本暂不支持。\n\n'
            '解决方法：在 Anki 桌面端重新导出，'
            '勾选 "Legacy (.apkg)" 或取消"支持 Anki 2.1.28 及更高版本"');
      }
      throw Exception(
          '无法打开 Anki 数据库。\n'
          '压缩包内文件：${allFiles.isEmpty ? "（无）" : allFiles.join(", ")}\n'
          '支持的格式：collection.anki21 / collection.anki2');
    }

    final Map<dynamic, List<String>> fieldMap = {};

    // 新格式：notetypes + fields 两张表
    bool newFormatOk = false;
    try {
      final notetypes = await db.rawQuery('SELECT id FROM notetypes');
      if (notetypes.isNotEmpty) {
        for (final nt in notetypes) {
          final mid = nt['id'];
          final flds = await db.rawQuery(
              'SELECT name FROM fields WHERE ntid = ? ORDER BY ord', [mid]);
          fieldMap[mid] = flds.map((f) => f['name']!.toString()).toList();
        }
        newFormatOk = fieldMap.isNotEmpty;
      }
    } catch (_) {}

    // 旧格式：models JSON 存放在 col 表
    if (!newFormatOk) {
      try {
        final colRows = await db.rawQuery('SELECT models FROM col LIMIT 1');
        if (colRows.isNotEmpty && colRows.first['models'] != null) {
          final modelsJson =
              jsonDecode(colRows.first['models']!.toString()) as Map<String, dynamic>;
          for (final entry in modelsJson.entries) {
            final model = entry.value as Map<String, dynamic>;
            final flds = (model['flds'] as List?)
                    ?.map((f) => (f as Map<String, dynamic>)['name']?.toString() ?? '')
                    .toList() ??
                [];
            if (flds.isNotEmpty) fieldMap[int.tryParse(entry.key) ?? entry.key] = flds;
          }
        }
      } catch (_) {}
    }

    final notes = await db.rawQuery('SELECT id, mid, tags, flds FROM notes');
    await db.close();
    return (notes: notes, fieldMap: fieldMap);
  }

  static Future<AnkiPreview> _previewApkg(String filePath) async {
    final extractDir = await _extractApkg(filePath);
    try {
      final data = await _readAnkiDb(extractDir.path);
      final notes = data.notes;
      final fieldMap = data.fieldMap;

      if (notes.isEmpty) {
        return const AnkiPreview(
            fields: [], samples: [], total: 0, format: 'apkg', autoMapping: {});
      }

      final firstMid = notes.first['mid'];
      // key 可能是 int 或 String，做双重查找
      final fields = fieldMap[firstMid] ??
          fieldMap[firstMid?.toString()] ??
          (fieldMap.isNotEmpty ? fieldMap.values.first : <String>[]);

      // 先提取原始样本（用于内容分析的字段自动识别）
      final rawSamples = notes.take(10).map((note) {
        return note['flds']!.toString().split('\x1f')
            .map((f) => _stripHtml(f))
            .toList();
      }).toList();

      final mapping = detectMapping(fields, rawSamples);

      final samples = notes.take(5).map((note) {
        final flds = note['flds']!.toString().split('\x1f');
        return Map.fromEntries(fields.asMap().entries.map(
            (e) => MapEntry(e.value, _stripHtml(
                e.key < flds.length ? flds[e.key] : ''))));
      }).toList();

      return AnkiPreview(
        fields: fields,
        samples: samples,
        total: notes.length,
        format: 'apkg',
        autoMapping: mapping,
      );
    } finally {
      await extractDir.delete(recursive: true).catchError((_) => extractDir);
    }
  }

  static Future<List<AnkiCard>> _parseApkg(
      String filePath, Map<String, int?> mapping) async {
    final extractDir = await _extractApkg(filePath);
    try {
      // 提取音频文件到永久目录，建立 filename → localPath 映射
      final audioMap = await _buildAudioMap(extractDir);

      final data = await _readAnkiDb(extractDir.path);
      return data.notes
          .map((n) {
            final rawFlds = n['flds']!.toString().split('\x1f');
            // 从任意字段中找第一个 [sound:xxx] 引用
            String? audioUrl;
            for (final raw in rawFlds) {
              final ref = _extractSoundRef(raw);
              if (ref != null) {
                audioUrl = audioMap[ref];
                break;
              }
            }
            return _buildCard(rawFlds, mapping, audioUrl: audioUrl);
          })
          .whereType<AnkiCard>()
          .toList();
    } finally {
      await extractDir.delete(recursive: true).catchError((_) => extractDir);
    }
  }

  // ── .txt / .csv / .tsv ────────────────────────────────────────────────────

  static Future<(List<String> fields, List<List<String>> rows)> _readTxtFile(
      String filePath, String ext) async {
    final text = await File(filePath).readAsString();
    final sep = ext == '.csv' ? ',' : '\t';
    final allLines = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();

    if (allLines.isEmpty) return (<String>[], <List<String>>[]);

    final firstCells = allLines[0]
        .split(sep)
        .map((c) => c.trim().replaceAll(RegExp(r'^"|"$'), ''))
        .toList();

    final looksLikeHeader = firstCells.every((c) =>
        RegExp(r'^[a-zA-Z\u4e00-\u9fff_\- ]+$').hasMatch(c) &&
        !RegExp(r'[\u3040-\u30ff]').hasMatch(c));

    List<String> fields;
    List<String> dataLines;
    if (looksLikeHeader && allLines.length > 1) {
      fields = firstCells;
      dataLines = allLines.sublist(1);
    } else {
      fields = List.generate(firstCells.length, (i) => '字段${i + 1}');
      dataLines = allLines;
    }

    final rows = dataLines
        .map((line) => line
            .split(sep)
            .map((c) => c.trim().replaceAll(RegExp(r'^"|"$'), ''))
            .toList())
        .toList();

    return (fields, rows);
  }

  static Future<AnkiPreview> _previewTxt(String filePath, String ext) async {
    final (fields, rows) = await _readTxtFile(filePath, ext);
    final rawSamples = rows.take(10).toList();
    final mapping = detectMapping(fields, rawSamples);
    final samples = rows.take(5).map((flds) => Map.fromEntries(
        fields.asMap().entries.map(
            (e) => MapEntry(e.value, e.key < flds.length ? flds[e.key] : '')))).toList();

    return AnkiPreview(
      fields: fields,
      samples: samples,
      total: rows.length,
      format: ext.replaceFirst('.', ''),
      autoMapping: mapping,
    );
  }

  static Future<List<AnkiCard>> _parseTxt(
      String filePath, String ext, Map<String, int?> mapping) async {
    final (_, rows) = await _readTxtFile(filePath, ext);
    return rows.map((r) => _buildCard(r, mapping)).whereType<AnkiCard>().toList();
  }

  // ── 构建单张卡片 ────────────────────────────────────────────────────────────

  static AnkiCard? _buildCard(List<String> flds, Map<String, int?> mapping,
      {String? audioUrl}) {
    final wi = mapping['word'];
    if (wi == null || wi >= flds.length) return null;

    final word = _clamp(_stripHtml(flds[wi]), 100);
    if (word.isEmpty) return null;

    final ri = mapping['reading'];
    String reading =
        (ri != null && ri < flds.length) ? _stripHtml(flds[ri]) : '';
    if (reading.isEmpty) reading = word;
    reading = _clamp(reading, 200);

    final zhi = mapping['meaning_zh'];
    final eni = mapping['meaning_en'];
    String meaningZh = '';
    if (zhi != null && zhi < flds.length) meaningZh = _stripHtml(flds[zhi]);
    if (meaningZh.isEmpty && eni != null && eni < flds.length) {
      meaningZh = _stripHtml(flds[eni]);
    }
    if (meaningZh.isEmpty) meaningZh = '-';
    meaningZh = _clamp(meaningZh, 1000);

    final exi = mapping['example'];
    final example = (exi != null && exi < flds.length)
        ? _clamp(_stripHtml(flds[exi]), 2000)
        : null;

    final meaningEn = (eni != null && eni < flds.length)
        ? _clamp(_stripHtml(flds[eni]), 1000)
        : null;

    return AnkiCard(
      word: word,
      reading: reading,
      meaningZh: meaningZh,
      meaningEn: meaningEn,
      example: example,
      audioUrl: audioUrl,
    );
  }
}
