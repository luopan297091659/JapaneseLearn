import 'dart:convert';
import 'package:dio/dio.dart';
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

  static const _slowSpeedKey = 'slow_speed';
  static const _languageKey = 'app_language';
  static const _appearanceModeKey = 'app_appearance_mode';
  static const _pendingAppearanceModeSyncKey =
      'pending_app_appearance_mode_sync';
  static const _validAppearanceModes = {'classic', 'anime', 'sakura'};

  bool _syncing = false;

  // ── 功能开关缓存 ──
  Map<String, bool>? _featureToggles;

  // ── 功能分级缓存 ──
  List<Map<String, dynamic>>? _featureTiers;

  /// 从服务端拉取移动端功能开关，缓存到 SharedPreferences。
  /// 返回 {featureId: enabled}，离线时使用上次缓存结果。
  Future<Map<String, bool>> fetchFeatureToggles({bool force = false}) async {
    if (_featureToggles != null && !force) return _featureToggles!;
    final prefs = await SharedPreferences.getInstance();
    try {
      final resp = await apiService.get('/sync/features?platform=mobile');
      final features = resp['features'] as Map<String, dynamic>? ?? {};
      final map = features.map((k, v) => MapEntry(k, v == true));
      _featureToggles = map;
      await prefs.setString('feature_toggles', jsonEncode(map));
      return map;
    } catch (_) {
      // 离线则读本地缓存
      final cached = prefs.getString('feature_toggles');
      if (cached != null) {
        final map = (jsonDecode(cached) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v == true));
        _featureToggles = map;
        return map;
      }
      return _featureToggles = {};
    }
  }

  /// 判断某功能是否启用，未配置的默认启用
  bool isFeatureEnabled(String featureId) {
    if (_featureToggles == null || !_featureToggles!.containsKey(featureId)) {
      return true; // 未拉取或未配置的功能默认开启
    }
    return _featureToggles![featureId]!;
  }

  /// 从服务端拉取功能分级配置（会员/免费差异）
  Future<List<Map<String, dynamic>>> fetchFeatureTiers(
      {bool force = false}) async {
    if (_featureTiers != null && !force) return _featureTiers!;
    final prefs = await SharedPreferences.getInstance();
    try {
      final resp = await apiService.get('/sync/tiers');
      final tiers = (resp['tiers'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      _featureTiers = tiers;
      await prefs.setString('feature_tiers', jsonEncode(tiers));
      return tiers;
    } catch (_) {
      final cached = prefs.getString('feature_tiers');
      if (cached != null) {
        final tiers = (jsonDecode(cached) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _featureTiers = tiers;
        return tiers;
      }
      return _featureTiers = [];
    }
  }

  /// 获取某功能的分级配置，null 表示未配置（不受会员限制）
  Map<String, dynamic>? getFeatureTier(String featureId) {
    if (_featureTiers == null) return null;
    try {
      return _featureTiers!.firstWhere((t) => t['id'] == featureId);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> collectLocalUserPreferences({
    int? dailyGoalMinutes,
    bool? notificationEnabled,
    double? slowSpeed,
    String? locale,
    String? appearanceMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'daily_goal_minutes':
          dailyGoalMinutes ?? (prefs.getInt('daily_goal_minutes') ?? 15),
      'notification_enabled': notificationEnabled ??
          (prefs.getBool('notification_enabled') ?? true),
      'slow_speed': slowSpeed ?? (prefs.getDouble(_slowSpeedKey) ?? 0.5),
      'locale': locale ?? (prefs.getString(_languageKey) ?? 'zh'),
      'appearance_mode':
          appearanceMode ?? (prefs.getString(_appearanceModeKey) ?? 'classic'),
    };
  }

  Future<Map<String, dynamic>> syncUserPreferences({
    int? dailyGoalMinutes,
    bool? notificationEnabled,
    double? slowSpeed,
    String? locale,
    String? appearanceMode,
  }) async {
    final payload = await collectLocalUserPreferences(
      dailyGoalMinutes: dailyGoalMinutes,
      notificationEnabled: notificationEnabled,
      slowSpeed: slowSpeed,
      locale: locale,
      appearanceMode: appearanceMode,
    );
    return apiService.updateUserPreferences(payload);
  }

  Future<Map<String, dynamic>> fetchUserPreferences(
      {bool persistLocal = true}) async {
    final remote = await apiService.getUserPreferences();
    if (persistLocal) {
      final prefs = await SharedPreferences.getInstance();
      if (remote['daily_goal_minutes'] is num) {
        await prefs.setInt('daily_goal_minutes',
            (remote['daily_goal_minutes'] as num).round());
      }
      if (remote['notification_enabled'] is bool) {
        await prefs.setBool(
            'notification_enabled', remote['notification_enabled'] == true);
      }
      if (remote['slow_speed'] is num) {
        await prefs.setDouble(
            _slowSpeedKey, (remote['slow_speed'] as num).toDouble());
      }
      if (remote['locale'] is String) {
        await prefs.setString(_languageKey, remote['locale'] as String);
      }
      if (remote['appearance_mode'] is String) {
        final remoteAppearance = remote['appearance_mode'] as String;
        final localAppearance = prefs.getString(_appearanceModeKey);
        final pendingAppearance =
            prefs.getString(_pendingAppearanceModeSyncKey);
        final canApplyRemoteAppearance =
            _validAppearanceModes.contains(remoteAppearance) &&
                (pendingAppearance == null || pendingAppearance.isEmpty) &&
                (localAppearance == null ||
                    localAppearance.isEmpty ||
                    localAppearance == remoteAppearance);
        if (canApplyRemoteAppearance) {
          await prefs.setString(_appearanceModeKey, remoteAppearance);
        }
      }
    }
    return remote;
  }

  /// 将本地待同步词汇上传到服务器
  ///
  /// 返回 [SyncResult]，包含成功数、失败数、错误信息。
  /// 已在同步时直接返回 null，避免重复触发。
  Future<SyncResult?> syncVocabulary({
    String? jlptLevel,
    String partOfSpeech = 'other',
    String? deckName,
  }) async {
    if (_syncing) return null;
    _syncing = true;
    try {
      final pending =
          await localDb.pendingCards(limit: 20000, deckName: deckName);
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

      bool throttled = false;

      for (final entry in byDeck.entries) {
        final deckName = entry.key;
        final cards = entry.value;

        // 取第一张卡的元数据当代表值（同一牌组相同）
        final level = cards.first['jlpt_level'] as String? ?? jlptLevel;
        final pos = cards.first['part_of_speech'] as String? ?? partOfSpeech;

        const chunkSize = 800;
        for (int i = 0; i < cards.length; i += chunkSize) {
          final chunk =
              cards.sublist(i, (i + chunkSize).clamp(0, cards.length));
          try {
            final result = await _bulkImportVocabularyWithRetry(
              cards: chunk,
              deckName: deckName,
              jlptLevel: level,
              partOfSpeech: pos,
            );
            final syncedIds = chunk.map((c) => c['id'] as String).toList();
            await localDb.markSynced(syncedIds);
            uploaded += (result['imported'] as int?) ?? chunk.length;
            skipped += (result['failed'] as int?) ?? 0;
            if (i + chunkSize < cards.length) {
              await Future.delayed(const Duration(milliseconds: 350));
            }
          } on _SyncThrottleException {
            failed += chunk.length;
            throttled = true;
            break;
          } catch (_) {
            failed += chunk.length;
          }
        }
        if (throttled) break;
      }

      return SyncResult(uploaded: uploaded, failed: failed, skipped: skipped);
    } finally {
      _syncing = false;
    }
  }

  // ── 快捷：仅查询待同步数量（不上传）
  Future<int> pendingCount() => localDb.pendingCount();

  Future<Map<String, dynamic>> _bulkImportVocabularyWithRetry({
    required List<Map<String, dynamic>> cards,
    required String deckName,
    required String? jlptLevel,
    required String partOfSpeech,
  }) async {
    const maxRetries = 4;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await apiService.bulkImportVocabulary(
          cards: cards,
          deckName: deckName,
          jlptLevel: jlptLevel,
          partOfSpeech: partOfSpeech,
        );
      } catch (e) {
        final isTooManyRequests =
            e is DioException && e.response?.statusCode == 429;
        if (!isTooManyRequests) rethrow;
        if (attempt >= maxRetries) {
          throw _SyncThrottleException();
        }
        final delaySeconds = 1 << (attempt + 1);
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
    throw _SyncThrottleException();
  }

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

        // 检查子版本号，按需清除离线缓存
        final localVocabVer = prefs.getInt('vocab_version') ?? 0;
        final localGrammarVer = prefs.getInt('grammar_version') ?? 0;
        final serverVocabVer = (resp['vocab_version'] as num?)?.toInt() ?? 0;
        final serverGrammarVer =
            (resp['grammar_version'] as num?)?.toInt() ?? 0;

        if (serverVocabVer > localVocabVer) {
          await localDb.clearCachedVocabulary();
        }
        if (serverGrammarVer > localGrammarVer) {
          await localDb.clearCachedGrammar();
        }

        await prefs.setInt('content_version', serverVer);
        await prefs.setInt('vocab_version', serverVocabVer);
        await prefs.setInt('grammar_version', serverGrammarVer);
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
  bool get allDone => failed == 0;
}

// ─── 全局单例 ──────────────────────────────────────────────────────────────────
final syncService = SyncService();

class _SyncThrottleException implements Exception {}
