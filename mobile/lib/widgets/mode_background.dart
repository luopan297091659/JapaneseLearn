import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/app_appearance_provider.dart';

// ─── Anime full-screen background ──────────────────────────────────────────
class AnimeModeBackground extends StatelessWidget {
  final Widget child;
  const AnimeModeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF7FBFF),
            const Color(0xFFFDF8FF),
            const Color(0xFFF9FFFC),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _AnimePatternPainter extends CustomPainter {
  final List<Color> colors;
  _AnimePatternPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);

    final bubble = Paint()..style = PaintingStyle.fill;
    final sparkle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final dots = <Offset>[
      Offset(size.width * 0.12, size.height * 0.14),
      Offset(size.width * 0.82, size.height * 0.18),
      Offset(size.width * 0.64, size.height * 0.62),
      Offset(size.width * 0.18, size.height * 0.74),
      Offset(size.width * 0.9, size.height * 0.84),
    ];

    for (int i = 0; i < dots.length; i++) {
      bubble.color = Colors.white.withValues(alpha: i.isEven ? 0.34 : 0.20);
      canvas.drawCircle(dots[i], 36 + (i * 6), bubble);
    }

    final stars = <Offset>[
      Offset(size.width * 0.28, size.height * 0.22),
      Offset(size.width * 0.74, size.height * 0.36),
      Offset(size.width * 0.42, size.height * 0.78),
      Offset(size.width * 0.08, size.height * 0.52),
    ];

    for (final center in stars) {
      sparkle.color = Colors.white.withValues(alpha: 0.8);
      _drawSparkle(canvas, center, 10, sparkle);
    }

    final stripe = Paint()
      ..color = const Color(0xFFAEDCFF).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width * 0.9, size.height * 0.0), radius: size.width * 0.7),
      pi * 0.46,
      pi * 0.48,
      false,
      stripe,
    );
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Paint p) {
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawLine(Offset(c.dx - r * 0.7, c.dy - r * 0.7), Offset(c.dx + r * 0.7, c.dy + r * 0.7), p);
    canvas.drawLine(Offset(c.dx + r * 0.7, c.dy - r * 0.7), Offset(c.dx - r * 0.7, c.dy + r * 0.7), p);
  }

  @override
  bool shouldRepaint(covariant _AnimePatternPainter oldDelegate) => false;
}

// ─── Anime card decoration overlay ─────────────────────────────────────────
/// 当处于酷炫模式时，在卡片上叠加星光/闪耀装饰图案。
/// 可直接包裹任意 Widget（通常为 Container 卡片），无需手动传 animeMode 参数。
class AnimeCardDecoration extends StatelessWidget {
  final Widget child;
  final Color color;
  final double borderRadius;

  const AnimeCardDecoration({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _AnimeCardPainter extends CustomPainter {
  final Color color;
  const _AnimeCardPainter({required this.color});

  /// 绘制 8 角星（4 尖）
  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = Path();
    final inner = r * 0.42;
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4 - pi / 2;
      final radius = i.isEven ? r : inner;
      final x = cx + radius * cos(angle);
      final y = cy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// 绘制 ✦ 闪耀线条
  void _drawSparkle(Canvas canvas, double cx, double cy, double r, Paint paint) {
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), paint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), paint);
    final d = r * 0.55;
    canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), paint);
    canvas.drawLine(Offset(cx + d, cy - d), Offset(cx - d, cy + d), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.32)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 星形
    _drawStar(canvas, w * 0.90, h * 0.18, 6.0, fillPaint);
    _drawStar(canvas, w * 0.09, h * 0.82, 4.5, fillPaint);
    _drawStar(canvas, w * 0.94, h * 0.74, 3.5, fillPaint);

    // 闪耀
    _drawSparkle(canvas, w * 0.06, h * 0.22, 5.0, strokePaint);
    _drawSparkle(canvas, w * 0.79, h * 0.88, 4.5, strokePaint);

    // 小圆点
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.74, h * 0.10), 3.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.17, h * 0.55), 2.5, dotPaint);
    canvas.drawCircle(Offset(w * 0.04, h * 0.96), 5.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _AnimeCardPainter old) => old.color != color;
}
