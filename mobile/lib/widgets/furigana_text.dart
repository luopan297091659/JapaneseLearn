import 'package:flutter/material.dart';

/// 振假名段落：汉字 + 上方注音，或纯文本
class _FuriganaPart {
  final String base;      // 底部文字（汉字或纯假名/符号）
  final String? reading;  // 上方注音（仅汉字段有值）
  const _FuriganaPart(this.base, [this.reading]);
}

/// 解析 bracket 标注格式：「助[たす]け 合[あ]います」
/// → [_FuriganaPart("助","たす"), _FuriganaPart("け "), _FuriganaPart("合","あ"), _FuriganaPart("います")]
List<_FuriganaPart> _parseFurigana(String raw) {
  // 去除 ! 标记
  raw = raw.replaceAll('!', '');
  final parts = <_FuriganaPart>[];
  final re = RegExp(r'([^\[\]]+)\[([^\]]+)\]');
  // 匹配末尾连续汉字（CJK Unified Ideographs）
  final kanjiTailRe = RegExp(r'([\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]+)$');
  int pos = 0;
  for (final m in re.allMatches(raw)) {
    // m.start 之前的纯文字
    if (m.start > pos) {
      final plain = raw.substring(pos, m.start);
      if (plain.isNotEmpty) parts.add(_FuriganaPart(plain));
    }
    final fullBase = m.group(1)!;
    final reading = m.group(2)!;
    // 将 base 拆分：末尾汉字 + 前面纯文本
    final kanjiMatch = kanjiTailRe.firstMatch(fullBase);
    if (kanjiMatch != null && kanjiMatch.start > 0) {
      parts.add(_FuriganaPart(fullBase.substring(0, kanjiMatch.start)));
      parts.add(_FuriganaPart(kanjiMatch.group(0)!, reading));
    } else {
      parts.add(_FuriganaPart(fullBase, reading));
    }
    pos = m.end;
  }
  // 尾部剩余文字
  if (pos < raw.length) {
    final tail = raw.substring(pos);
    if (tail.isNotEmpty) parts.add(_FuriganaPart(tail));
  }
  return parts;
}

/// 检测文本是否包含 bracket 振假名标注
bool hasFurigana(String text) => text.contains(RegExp(r'[^\[\]]+\[[^\]]+\]'));

/// 振假名显示组件 — 将 reading 标注在 kanji 上方
class FuriganaText extends StatelessWidget {
  final String text;            // 原始 bracket 标注文本
  final double fontSize;        // 主文字大小
  final Color? color;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  const FuriganaText({
    super.key,
    required this.text,
    this.fontSize = 24,
    this.color,
    this.fontWeight = FontWeight.bold,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _parseFurigana(text);
    final cs = Theme.of(context).colorScheme;
    final baseColor = color ?? cs.primary;
    final readingSize = (fontSize * 0.55).clamp(10.0, 20.0);

    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: baseColor,
      height: 1.15,
    );

    final readingStyle = TextStyle(
      fontSize: readingSize,
      fontWeight: FontWeight.w600,
      color: baseColor.withValues(alpha: 0.85),
      height: 1.1,
    );

    return Wrap(
      alignment: textAlign == TextAlign.center
          ? WrapAlignment.center
          : textAlign == TextAlign.end
              ? WrapAlignment.end
              : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: 4,
      children: parts.map((p) {
        if (p.reading != null) {
          // Stack: base determines width, reading centered above via FittedBox
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(top: readingSize + 2),
                child: Text(p.base, style: baseStyle),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(p.reading!, style: readingStyle, textAlign: TextAlign.center),
                ),
              ),
            ],
          );
        } else {
          return Padding(
            padding: EdgeInsets.only(top: readingSize + 2),
            child: Text(p.base, style: baseStyle),
          );
        }
      }).toList(),
    );
  }
}
