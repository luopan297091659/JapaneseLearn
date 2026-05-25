import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../utils/japanese_text_utils.dart';
import 'api_service.dart';

class WordWidgetService {
  WordWidgetService._();

  static final WordWidgetService instance = WordWidgetService._();

  static const MethodChannel _channel = MethodChannel('kotabi/word_widget');
  static const String _cacheKey = 'word_widget_payload_v1';

  Future<void> sync({
    required VocabularyModel? word,
    required bool checkedInToday,
    required int streakDays,
    required String level,
  }) async {
    if (word == null) return;

    final token = await apiService.getAccessToken();
    final payload = <String, Object?>{
      'wordId': word.id,
      'word': word.word,
      'reading': cleanReading(word.reading),
      'meaningZh': word.meaningZh,
      'partOfSpeech': word.partOfSpeechRaw ?? word.partOfSpeech,
      'jlptLevel': word.jlptLevel,
      'exampleSentence': word.exampleSentence,
      'exampleReading': word.exampleReading,
      'exampleMeaningZh': word.exampleMeaningZh,
      'checkedInToday': checkedInToday,
      'streakDays': streakDays,
      'level': level,
      'baseUrl': AppConfig.baseUrl,
      'accessToken': token,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, payload.toString());

    try {
      await _channel.invokeMethod<void>('updateWordWidget', payload);
    } on MissingPluginException {
      // Desktop widgets are implemented by the host platforms. Android has a
      // receiver in this project; iOS needs the Widget Extension target to read
      // the same payload through the native side.
    } on PlatformException {
      // Widget updates should never block the home screen.
    }
  }

  Future<void> markCheckedIn({
    required int streakDays,
    required VocabularyModel? currentWord,
    required String level,
  }) {
    return sync(
      word: currentWord,
      checkedInToday: true,
      streakDays: streakDays,
      level: level,
    );
  }

  Future<String?> consumePendingDeepLink() async {
    try {
      return await _channel.invokeMethod<String>('consumePendingDeepLink');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  bool get supportsInWidgetCheckin => Platform.isAndroid;
}
