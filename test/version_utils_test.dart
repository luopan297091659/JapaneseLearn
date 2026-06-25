import 'package:flutter_test/flutter_test.dart';
import 'package:Kotabi/utils/version_utils.dart';

void main() {
  group('compareVersions', () {
    test('treats build metadata as equal for version comparison', () {
      expect(compareVersions('1.2.3+100', '1.2.3'), 0);
      expect(compareVersions('1.2.3', '1.2.3+100'), 0);
    });

    test('compares numeric segments correctly', () {
      expect(compareVersions('1.2.10', '1.2.9'), 1);
      expect(compareVersions('1.2.9', '1.2.10'), -1);
    });

    test('handles prefixed versions from App Store style values', () {
      expect(compareVersions('v1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.2.3', 'v1.2.3'), 0);
    });

    test('treats missing segments as zero for comparison', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.3'), -1);
    });
  });
}
