import 'package:flutter_test/flutter_test.dart';
import 'package:Kotabi/utils/japanese_text_utils.dart';

void main() {
  group('normalizeJapaneseTtsText', () {
    test('converts bracket furigana to kana reading', () {
      expect(normalizeJapaneseTtsText('鉛[えん] 筆[ぴつ]'), 'えんぴつ');
    });

    test('keeps okurigana around furigana readings', () {
      expect(normalizeJapaneseTtsText('助[たす]け 合[あ]います'), 'たすけあいます');
    });
  });

  group('ttsText', () {
    test('uses furigana reading when reading field contains bracket markup',
        () {
      expect(ttsText('铅笔', '鉛[えん] 筆[ぴつ]'), 'えんぴつ');
    });

    test('uses furigana reading when word field contains bracket markup', () {
      expect(ttsText('鉛[えん] 筆[ぴつ]', ''), 'えんぴつ');
    });
  });
}
