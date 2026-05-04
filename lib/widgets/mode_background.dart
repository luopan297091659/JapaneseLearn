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

class SakuraModeBackground extends StatelessWidget {
  final Widget child;
  const SakuraModeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? const [Color(0xFF1F171B), Color(0xFF281D22), Color(0xFF302329)]
        : const [Color(0xFFFFF8F5), Color(0xFFFFF1F5), Color(0xFFFFFAF0)];

    return CustomPaint(
      painter: _SakuraBackgroundPainter(colors: colors, isDark: isDark),
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
      Rect.fromCircle(
          center: Offset(size.width * 0.9, size.height * 0.0),
          radius: size.width * 0.7),
      pi * 0.46,
      pi * 0.48,
      false,
      stripe,
    );
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Paint p) {
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawLine(Offset(c.dx - r * 0.7, c.dy - r * 0.7),
        Offset(c.dx + r * 0.7, c.dy + r * 0.7), p);
    canvas.drawLine(Offset(c.dx + r * 0.7, c.dy - r * 0.7),
        Offset(c.dx - r * 0.7, c.dy + r * 0.7), p);
  }

  @override
  bool shouldRepaint(covariant _AnimePatternPainter oldDelegate) => false;
}

// ─── Anime card decoration overlay ─────────────────────────────────────────
/// 当处于蓝调模式时，在卡片上叠加星光/闪耀装饰图案。
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
    final visual = Theme.of(context).extension<AppVisualTheme>();
    if (visual?.sakuraBackground == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CustomPaint(
          foregroundPainter: _SakuraCardPainter(color: color),
          child: child,
        ),
      );
    }
    return child;
  }
}

class _SakuraBackgroundPainter extends CustomPainter {
  final List<Color> colors;
  final bool isDark;

  const _SakuraBackgroundPainter({
    required this.colors,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);

    _drawPaperTexture(canvas, size);
    _drawSakuraBranch(canvas, size);
    _drawFallingPetals(canvas, size);
  }

  void _drawPaperTexture(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFFD96C8C))
          .withValues(alpha: isDark ? 0.018 : 0.035)
      ..style = PaintingStyle.fill;

    const points = <Offset>[
      Offset(0.08, 0.10),
      Offset(0.24, 0.18),
      Offset(0.43, 0.09),
      Offset(0.67, 0.15),
      Offset(0.90, 0.11),
      Offset(0.13, 0.35),
      Offset(0.36, 0.30),
      Offset(0.58, 0.37),
      Offset(0.82, 0.31),
      Offset(0.20, 0.56),
      Offset(0.48, 0.52),
      Offset(0.73, 0.58),
      Offset(0.94, 0.50),
      Offset(0.09, 0.78),
      Offset(0.31, 0.72),
      Offset(0.54, 0.83),
      Offset(0.79, 0.76),
      Offset(0.93, 0.90),
    ];
    for (int i = 0; i < points.length; i++) {
      final dot = points[i];
      canvas.drawCircle(
        Offset(size.width * dot.dx, size.height * dot.dy),
        1.2 + (i % 3) * 0.45,
        paint,
      );
    }
  }

  void _drawSakuraBranch(Canvas canvas, Size size) {
    final branchPaint = Paint()
      ..color = (isDark ? const Color(0xFFC99BA7) : const Color(0xFF8F5F69))
          .withValues(alpha: isDark ? 0.20 : 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final mainBranch = Path()
      ..moveTo(size.width * 1.03, size.height * 0.03)
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.03,
        size.width * 0.77,
        size.height * 0.12,
        size.width * 0.63,
        size.height * 0.10,
      )
      ..cubicTo(
        size.width * 0.51,
        size.height * 0.08,
        size.width * 0.43,
        size.height * 0.16,
        size.width * 0.33,
        size.height * 0.14,
      );
    canvas.drawPath(mainBranch, branchPaint);

    _drawTwig(canvas, size, const Offset(0.76, 0.095), const Offset(0.72, 0.04),
        branchPaint);
    _drawTwig(canvas, size, const Offset(0.67, 0.105), const Offset(0.61, 0.18),
        branchPaint);
    _drawTwig(canvas, size, const Offset(0.52, 0.125), const Offset(0.47, 0.06),
        branchPaint);

    final blossomPaint = Paint()
      ..color = (isDark ? const Color(0xFFF4C8D2) : const Color(0xFFEFA7B8))
          .withValues(alpha: isDark ? 0.36 : 0.46)
      ..style = PaintingStyle.fill;
    final blushPaint = Paint()
      ..color = (isDark ? const Color(0xFFFFE3E8) : const Color(0xFFFFF7FA))
          .withValues(alpha: isDark ? 0.25 : 0.44)
      ..style = PaintingStyle.fill;

    _drawBlossom(canvas, Offset(size.width * 0.72, size.height * 0.052), 9.0,
        -0.15, blossomPaint, blushPaint);
    _drawBlossom(canvas, Offset(size.width * 0.62, size.height * 0.172), 8.2,
        0.28, blossomPaint, blushPaint);
    _drawBlossom(canvas, Offset(size.width * 0.49, size.height * 0.071), 7.4,
        -0.40, blossomPaint, blushPaint);
    _drawBlossom(canvas, Offset(size.width * 0.84, size.height * 0.045), 6.8,
        0.46, blossomPaint, blushPaint);
    _drawBud(canvas, Offset(size.width * 0.36, size.height * 0.145), 4.8,
        blossomPaint);
    _drawBud(canvas, Offset(size.width * 0.58, size.height * 0.112), 3.8,
        blossomPaint);
  }

  void _drawTwig(
      Canvas canvas, Size size, Offset start, Offset end, Paint branchPaint) {
    final path = Path()
      ..moveTo(size.width * start.dx, size.height * start.dy)
      ..quadraticBezierTo(
        size.width * ((start.dx + end.dx) / 2 + 0.015),
        size.height * ((start.dy + end.dy) / 2),
        size.width * end.dx,
        size.height * end.dy,
      );
    canvas.drawPath(path, branchPaint);
  }

  void _drawFallingPetals(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? const Color(0xFFF4C8D2) : const Color(0xFFEFA7B8))
          .withValues(alpha: isDark ? 0.18 : 0.26)
      ..style = PaintingStyle.fill;
    const petals = <({Offset position, double size, double rotation})>[
      (position: Offset(0.16, 0.16), size: 9.0, rotation: -0.70),
      (position: Offset(0.88, 0.22), size: 7.2, rotation: 0.65),
      (position: Offset(0.70, 0.38), size: 8.4, rotation: 1.10),
      (position: Offset(0.26, 0.43), size: 6.8, rotation: -1.20),
      (position: Offset(0.54, 0.57), size: 7.5, rotation: 0.20),
      (position: Offset(0.12, 0.69), size: 8.0, rotation: 1.35),
      (position: Offset(0.83, 0.75), size: 6.4, rotation: -0.45),
      (position: Offset(0.39, 0.86), size: 7.0, rotation: 0.95),
    ];

    for (final petal in petals) {
      _drawSinglePetal(
        canvas,
        Offset(size.width * petal.position.dx, size.height * petal.position.dy),
        petal.size,
        petal.rotation,
        paint,
      );
    }
  }

  void _drawSinglePetal(
      Canvas canvas, Offset c, double r, double rotation, Paint p) {
    final tip = Offset(c.dx + cos(rotation) * r, c.dy + sin(rotation) * r);
    final base = Offset(
        c.dx - cos(rotation) * r * 0.55, c.dy - sin(rotation) * r * 0.55);
    final left = Offset(
      c.dx + cos(rotation - pi / 2) * r * 0.36,
      c.dy + sin(rotation - pi / 2) * r * 0.36,
    );
    final right = Offset(
      c.dx + cos(rotation + pi / 2) * r * 0.36,
      c.dy + sin(rotation + pi / 2) * r * 0.36,
    );
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(left.dx, left.dy, left.dx, left.dy, tip.dx, tip.dy)
      ..cubicTo(right.dx, right.dy, right.dx, right.dy, base.dx, base.dy);
    canvas.drawPath(path, p);
  }

  void _drawPetal(Canvas canvas, Offset c, double r, double rotation, Paint p) {
    final path = Path();
    final tip = Offset(c.dx + cos(rotation) * r, c.dy + sin(rotation) * r);
    final notch = Offset(
        c.dx + cos(rotation) * r * 0.72, c.dy + sin(rotation) * r * 0.72);
    final left = Offset(c.dx + cos(rotation - 0.55) * r * 0.56,
        c.dy + sin(rotation - 0.55) * r * 0.56);
    final right = Offset(c.dx + cos(rotation + 0.55) * r * 0.56,
        c.dy + sin(rotation + 0.55) * r * 0.56);
    path
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(left.dx, left.dy, notch.dx, notch.dy)
      ..quadraticBezierTo(tip.dx, tip.dy, notch.dx, notch.dy)
      ..quadraticBezierTo(right.dx, right.dy, c.dx, c.dy);
    canvas.drawPath(path, p);
  }

  void _drawBlossom(Canvas canvas, Offset c, double r, double rotation, Paint p,
      Paint highlight) {
    for (int i = 0; i < 5; i++) {
      final angle = rotation - pi / 2 + i * 2 * pi / 5;
      _drawPetal(
        canvas,
        Offset(c.dx + cos(angle) * r * 0.22, c.dy + sin(angle) * r * 0.22),
        r,
        angle,
        p,
      );
    }
    canvas.drawCircle(c, r * 0.26, highlight);
    final center = Paint()
      ..color = const Color(0xFFD96C8C).withValues(alpha: isDark ? 0.24 : 0.36)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r * 0.12, center);
  }

  void _drawBud(Canvas canvas, Offset c, double r, Paint p) {
    _drawSinglePetal(canvas, c, r, -0.85, p);
    _drawSinglePetal(
        canvas, Offset(c.dx + r * 0.38, c.dy + r * 0.18), r * 0.78, -0.35, p);
  }

  @override
  bool shouldRepaint(covariant _SakuraBackgroundPainter oldDelegate) => false;
}

class _SakuraCardPainter extends CustomPainter {
  final Color color;
  const _SakuraCardPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final petalPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    _drawBlossom(
        canvas, Offset(size.width * 0.90, size.height * 0.18), 4.8, petalPaint);
    _drawSinglePetal(canvas, Offset(size.width * 0.12, size.height * 0.82), 6.0,
        -0.55, petalPaint);
    _drawSinglePetal(canvas, Offset(size.width * 0.82, size.height * 0.80), 4.8,
        0.70, petalPaint);

    final dot = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.70, size.height * 0.12), 2.5, dot);
    canvas.drawCircle(Offset(size.width * 0.20, size.height * 0.18), 2.0, dot);
    canvas.drawCircle(Offset(size.width * 0.94, size.height * 0.62), 3.0, dot);

    final seal = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 24, size.height - 22, 14, 14),
      const Radius.circular(3),
    );
    canvas.drawRRect(seal, accentPaint);
  }

  void _drawSinglePetal(
      Canvas canvas, Offset c, double r, double rotation, Paint p) {
    final tip = Offset(c.dx + cos(rotation) * r, c.dy + sin(rotation) * r);
    final base = Offset(
        c.dx - cos(rotation) * r * 0.55, c.dy - sin(rotation) * r * 0.55);
    final left = Offset(c.dx + cos(rotation - pi / 2) * r * 0.34,
        c.dy + sin(rotation - pi / 2) * r * 0.34);
    final right = Offset(c.dx + cos(rotation + pi / 2) * r * 0.34,
        c.dy + sin(rotation + pi / 2) * r * 0.34);
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(left.dx, left.dy, left.dx, left.dy, tip.dx, tip.dy)
      ..cubicTo(right.dx, right.dy, right.dx, right.dy, base.dx, base.dy);
    canvas.drawPath(path, p);
  }

  void _drawPetal(Canvas canvas, Offset c, double r, double rotation, Paint p) {
    final path = Path();
    final tip = Offset(c.dx + cos(rotation) * r, c.dy + sin(rotation) * r);
    final notch = Offset(
        c.dx + cos(rotation) * r * 0.72, c.dy + sin(rotation) * r * 0.72);
    final left = Offset(c.dx + cos(rotation - 0.55) * r * 0.56,
        c.dy + sin(rotation - 0.55) * r * 0.56);
    final right = Offset(c.dx + cos(rotation + 0.55) * r * 0.56,
        c.dy + sin(rotation + 0.55) * r * 0.56);
    path
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(left.dx, left.dy, notch.dx, notch.dy)
      ..quadraticBezierTo(tip.dx, tip.dy, notch.dx, notch.dy)
      ..quadraticBezierTo(right.dx, right.dy, c.dx, c.dy);
    canvas.drawPath(path, p);
  }

  void _drawBlossom(Canvas canvas, Offset c, double r, Paint p) {
    for (int i = 0; i < 5; i++) {
      final angle = -pi / 2 + i * 2 * pi / 5;
      _drawPetal(
        canvas,
        Offset(c.dx + cos(angle) * r * 0.18, c.dy + sin(angle) * r * 0.18),
        r,
        angle,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SakuraCardPainter old) => old.color != color;
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
  void _drawSparkle(
      Canvas canvas, double cx, double cy, double r, Paint paint) {
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
