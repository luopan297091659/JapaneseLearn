import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';
import 'api_service.dart';

/// 本地 → 服务端同步服务
///
/// 策略：先写本地，联网时批量上传待同步记录并标记为已同步。
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  bool _syncing = false;

  /// 将本地待同步词汇上传到服务器
  ///
  /// 返回 [SyncResult]，包含成功数、失败数、错误信息。
  /// 已在同步时直接返回 null，避免重复触发。
  Future<SyncResult?> syncVocabulary({
    String jlptLevel     = 'N3',
    String partOfSpeech  = 'other',
  }) async {
    if (_syncing) return null;
    _syncing = true;
    try {
      final pending = await localDb.pendingCards(limit: 1000);
      if (pending.isEmpty) {
        return SyncResult(uploaded: 0, failed: 0, skipped: 0);
      }

      // 按牌组分组分批上传（每组最多 500 条）
      final byDeck = <String, List<Map<String, dynamic>>>{};
      for (final c in pending) {
        final deck = (c['deck_name'] as String?) ?? 'Anki Import';
        byDeck.putIfAbsent(deck, () => []).add(c);
      }

      int uploaded = 0, failed = 0, skipped = 0;

      for (final entry in byDeck.entries) {
        final deckName = entry.key;
        final cards    = entry.value;

        // 取第一张卡的元数据当代表值（同一牌组相同）
        final level = cards.first['jlpt_level'] as String? ?? jlptLevel;
        final pos   = cards.first['part_of_speech'] as String? ?? partOfSpeech;

        const chunkSize = 500;
        for (int i = 0; i < cards.length; i += chunkSize) {
          final chunk = cards.sublist(i, (i + chunkSize).clamp(0, cards.length));
          try {
            final result = await apiService.bulkImportVocabulary(
              cards:        chunk,
              deckName:     deckName,
              jlptLevel:    level,
              partOfSpeech: pos,
            );
            final syncedIds = chunk.map((c) => c['id'] as String).toList();
            await localDb.markSynced(syncedIds);
            uploaded += (result['imported'] as int?)  ?? chunk.length;
            skipped  += (result['failed']   as int?)  ?? 0;
          } catch (_) {
            failed += chunk.length;
          }
        }
      }

      return SyncResult(uploaded: uploaded, failed: failed, skipped: skipped);
    } finally {
      _syncing = false;
    }
  }

  // ── 快捷：仅查询待同步数量（不上传）
  Future<int> pendingCount() => localDb.pendingCount();

  // ── 检测服务端内容版本，若有更新则清除客户端缓存，触发下次访问时重新拉取 ──────
  ///
  /// 返回 true 表示检测到版本更新（缓存已清除）。
  Future<bool> checkContentVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localVer = prefs.getInt('content_version') ?? 0;

      final resp = await apiService.get('/sync/version');
      final serverVer = (resp['version'] as num?)?.toInt() ?? 0;

      if (serverVer > localVer) {
        // 清除 API 内存缓存，下次页面访问时拉取最新数据
        apiService.invalidateCache();
        await prefs.setInt('content_version', serverVer);
        await prefs.setInt('vocab_version', (resp['vocab_version'] as num?)?.toInt() ?? 0);
        await prefs.setInt('grammar_version', (resp['grammar_version'] as num?)?.toInt() ?? 0);
        return true;
      }
      return false;
    } catch (_) {
      return false; // 离线或错误时静默失败
    }
  }
}

class SyncResult {
  final int uploaded;
  final int failed;
  final int skipped;

  const SyncResult({
    required this.uploaded,
    required this.failed,
    required this.skipped,
  });

  bool get hasError => failed > 0;
  bool get allDone  => failed == 0;
}

// ─── 全局单例 ──────────────────────────────────────────────────────────────────
final syncService = SyncService();
