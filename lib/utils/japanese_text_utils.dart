/// Strip raw formatting markers from vocabulary data.

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

/// Extract the best text for TTS from word/reading fields
String ttsText(String word, String reading) {
  final cr = cleanReading(reading);
  if (cr.isNotEmpty) return cr;
  final bracketMatch = RegExp(r'\[([^\]]*)\]').firstMatch(word);
  if (bracketMatch != null) return bracketMatch.group(1)!;
  final parenMatch = RegExp(r'[（(]([^)）]*)[)）]').firstMatch(word);
  if (parenMatch != null) return parenMatch.group(1)!;
  return cleanWord(word);
}
