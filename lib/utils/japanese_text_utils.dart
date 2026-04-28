/// Strip raw formatting markers from vocabulary data.
library;

/// Clean word field: remove !, [...], (...) markers
String cleanWord(String raw) {
  var s = raw.replaceAll('!', '');
  s = s.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  s = s.replaceAll(RegExp(r'[（(][^)）]*[)）]'), '');
  return s.trim();
}

/// Clean reading field: remove !, @digit, [...], (...) markers
String cleanReading(String raw) {
  var s = raw.replaceAll('!', '');
  s = s.replaceAll(RegExp(r'@\d+'), '');
  s = s.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  s = s.replaceAll(RegExp(r'[（(][^)）]*[)）]'), '');
  return s.trim();
}

/// Convert bracket furigana text to a TTS-friendly reading.
/// Example: 鉛[えん] 筆[ぴつ] -> えんぴつ
String normalizeJapaneseTtsText(String raw) {
  var s = raw.replaceAll('!', '');
  s = s.replaceAll(RegExp(r'@\d+'), '');
  s = s.replaceAllMapped(
    RegExp(r'([^\[\]]+)\[([^\]]+)\]'),
    (m) {
      final base = m.group(1)!;
      final reading = m.group(2)!.trim();
      final kanjiTail = RegExp(
        r'([\u3400-\u9fff\uf900-\ufaff]+)$',
      ).firstMatch(base);
      if (kanjiTail == null) return reading;
      return '${base.substring(0, kanjiTail.start)}$reading';
    },
  );

  final japaneseAroundSpace = RegExp(
    r'([\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff])\s+([\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff])',
  );
  String previous;
  do {
    previous = s;
    s = s.replaceAllMapped(
        japaneseAroundSpace, (m) => '${m.group(1)}${m.group(2)}');
  } while (s != previous);

  return s.trim();
}

/// Extract the best text for TTS from word/reading fields
String ttsText(String word, String reading) {
  if (reading.contains(RegExp(r'[^\[\]]+\[[^\]]+\]'))) {
    return normalizeJapaneseTtsText(reading);
  }
  final cr = cleanReading(reading);
  if (cr.isNotEmpty) return cr;
  if (word.contains(RegExp(r'[^\[\]]+\[[^\]]+\]'))) {
    return normalizeJapaneseTtsText(word);
  }
  final parenMatch = RegExp(r'[（(]([^)）]*)[)）]').firstMatch(word);
  if (parenMatch != null) return parenMatch.group(1)!;
  return cleanWord(word);
}
