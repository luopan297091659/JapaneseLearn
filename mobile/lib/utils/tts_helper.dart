import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 全局 TTS 辅助工具，确保引擎正确初始化并提供诊断信息
class TtsHelper {
  TtsHelper._();
  static final TtsHelper instance = TtsHelper._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _engineAvailable = false;
  String? _diagInfo;
  List<String> _availableLanguages = [];
  bool _japaneseAvailable = false;

  /// 获取共享的 FlutterTts 实例（仅用于诊断，各屏幕仍使用自己的实例）
  FlutterTts get tts => _tts ??= FlutterTts();

  bool get engineAvailable => _engineAvailable;
  bool get japaneseAvailable => _japaneseAvailable;
  String get diagnosticInfo => _diagInfo ?? '未初始化';

  /// 初始化并检测 TTS 引擎状态（在 app 启动时调用一次）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final diag = StringBuffer();
    _tts = FlutterTts();

    try {
      // 1. 检查可用引擎
      try {
        final engines = await _tts!.getEngines;
        final engineList = engines is List ? engines.cast<String>() : <String>[];
        diag.writeln('TTS引擎: ${engineList.isEmpty ? "无" : engineList.join(", ")}');
        _engineAvailable = engineList.isNotEmpty;

        // 如果有 Google TTS，优先使用
        if (engineList.any((e) => e.contains('google'))) {
          final gEngine = engineList.firstWhere((e) => e.contains('google'));
          await _tts!.setEngine(gEngine);
          diag.writeln('使用引擎: $gEngine');
        }
      } catch (e) {
        diag.writeln('检测引擎失败: $e');
        _engineAvailable = true; // 假设可用，后续speak会验证
      }

      // 2. 检查可用语言
      try {
        final raw = await _tts!.getLanguages;
        final langs = raw is List ? raw : <dynamic>[];
        _availableLanguages = langs.map((l) => l.toString()).toList();
        _japaneseAvailable = _availableLanguages.any(
          (l) => l.toLowerCase().startsWith('ja'),
        );
        diag.writeln('可用语言数: ${_availableLanguages.length}');
        diag.writeln('日语支持: $_japaneseAvailable');
        if (_japaneseAvailable) {
          final jaLangs = _availableLanguages.where(
            (l) => l.toLowerCase().startsWith('ja'),
          );
          diag.writeln('日语变体: ${jaLangs.join(", ")}');
        }
      } catch (e) {
        diag.writeln('检测语言失败: $e');
      }

      // 3. 尝试设置日语
      try {
        final langResult = await _tts!.setLanguage('ja-JP');
        diag.writeln('setLanguage(ja-JP): $langResult');
      } catch (e) {
        diag.writeln('setLanguage失败: $e');
      }

      // 4. 尝试设置通用参数
      await _tts!.awaitSpeakCompletion(false);
      await _tts!.setSpeechRate(0.45);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);

    } catch (e) {
      diag.writeln('初始化异常: $e');
    }

    _diagInfo = diag.toString();
    debugPrint('【TTS诊断】\n$_diagInfo');
  }

  /// 配置一个 FlutterTts 实例用于日语播放
  /// 各屏幕仍使用自己的 FlutterTts 实例，用这个方法统一配置
  static Future<bool> configureForJapanese(FlutterTts tts) async {
    try {
      await tts.awaitSpeakCompletion(false);

      // 尝试设置 Google TTS 引擎
      try {
        final engines = await tts.getEngines;
        final engineList = engines is List ? engines.cast<String>() : <String>[];
        final google = engineList.where((e) => e.toString().contains('google'));
        if (google.isNotEmpty) {
          await tts.setEngine(google.first);
        }
      } catch (_) {}

      // 设置日语
      try {
        await tts.setLanguage('ja-JP');
      } catch (_) {
        // 即使设置失败也继续，speak 时会再试
      }

      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);

      return true;
    } catch (e) {
      debugPrint('TTS配置失败: $e');
      return false;
    }
  }

  /// 安全地朗读文本，返回是否成功
  static Future<bool> speakJapanese(FlutterTts tts, String text) async {
    try {
      // 每次 speak 前重新设置语言（Android TTS 有时会丢失设置）
      try { await tts.setLanguage('ja-JP'); } catch (_) {}
      await tts.setVolume(1.0);
      final result = await tts.speak(text);
      return result == 1;
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      return false;
    }
  }
}
