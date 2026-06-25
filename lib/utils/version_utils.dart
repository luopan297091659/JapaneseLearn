int compareVersions(String? current, String? latest) {
  if (current == null || current.trim().isEmpty) {
    return latest == null || latest.trim().isEmpty ? 0 : -1;
  }
  if (latest == null || latest.trim().isEmpty) {
    return 1;
  }

  final left = _extractNumericParts(current);
  final right = _extractNumericParts(latest);
  final maxLen = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < maxLen; i++) {
    final a = i < left.length ? left[i] : 0;
    final b = i < right.length ? right[i] : 0;
    if (a != b) return a.compareTo(b);
  }

  return 0;
}

List<int> _extractNumericParts(String input) {
  final normalized = input.split('+').first.trim();
  final matches = RegExp(r'\d+').allMatches(normalized);
  if (matches.isEmpty) return const [0];
  return matches.map((match) => int.parse(match.group(0)!)).toList();
}
