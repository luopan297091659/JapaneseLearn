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

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SakuraBackgroundPainter(colors: colors, isDark: isDark),
          ),
        ),
        child,
      ],
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
  final bool enableSakuraDecoration;

  const AnimeCardDecoration({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = 16,
    this.enableSakuraDecoration = true,
  });

  @override
  Widget build(BuildContext context) {
    final visual = Theme.of(context).extension<AppVisualTheme>();
    if (enableSakuraDecoration && visual?.sakuraBackground == true) {
      final variant = ((color.r * 255).round() +
                  (color.g * 255).round() * 3 +
                  (color.b * 255).round() * 7)
              .abs() %
          9;
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            Positioned(
              top: -8,
              right: -18,
              bottom: -8,
              width: 230,
              child: _SakuraCardBranchImage(variant: variant),
            ),
            child,
          ],
        ),
      );
    }
    return child;
  }
}

class _SakuraCardBranchImage extends StatelessWidget {
  final int variant;

  const _SakuraCardBranchImage({required this.variant});

  static const _asset = 'assets/images/sakura/sakura_branch.png';

  @override
  Widget build(BuildContext context) {
    final scale = switch (variant) {
      0 => 0.88,
      1 => 0.82,
      2 => 0.92,
      3 => 0.86,
      4 => 0.94,
      5 => 0.84,
      6 => 0.90,
      7 => 0.82,
      _ => 0.90,
    };
    final turns = switch (variant) {
      0 => -0.006,
      1 => 0.010,
      2 => -0.012,
      3 => 0.014,
      4 => -0.010,
      5 => 0.008,
      6 => -0.014,
      7 => 0.010,
      _ => -0.008,
    };
    final alignment = switch (variant) {
      0 => Alignment.centerRight,
      1 => Alignment.topRight,
      2 => Alignment.bottomRight,
      3 => Alignment.centerRight,
      4 => Alignment.topRight,
      5 => Alignment.bottomRight,
      6 => Alignment.centerRight,
      7 => Alignment.topRight,
      _ => Alignment.bottomRight,
    };

    return IgnorePointer(
      child: Opacity(
        opacity: 0.60,
        child: Transform.rotate(
          angle: turns * pi * 2,
          alignment: alignment,
          child: Transform.scale(
            scale: scale,
            alignment: alignment,
            child: Image.asset(
              _asset,
              alignment: alignment,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
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
  final int variant;

  const _SakuraCardPainter({
    required this.color,
    required this.variant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final branchPaint = Paint()
      ..color = const Color(0xFF6E1C24).withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final twigPaint = Paint()
      ..color = const Color(0xFF7D2630).withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final petalPaint = Paint()
      ..color = const Color(0xFFEFA7B8).withValues(alpha: 0.38)
      ..style = PaintingStyle.fill;
    final petalDeepPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..style = PaintingStyle.fill;
    final centerPaint = Paint()
      ..color = const Color(0xFFC84665).withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    _drawCardBranch(
      canvas,
      size,
      variant,
      branchPaint,
      twigPaint,
      petalPaint,
      petalDeepPaint,
      highlightPaint,
      centerPaint,
    );

    final seal = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 24, size.height - 22, 14, 14),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      seal,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCardBranch(
    Canvas canvas,
    Size size,
    int variant,
    Paint branchPaint,
    Paint twigPaint,
    Paint petalPaint,
    Paint petalDeepPaint,
    Paint highlightPaint,
    Paint centerPaint,
  ) {
    final branch = switch (variant) {
      0 => _BranchSpec(stroke: 4.0, path: const [
          Offset(1.08, 0.14),
          Offset(0.80, 0.18),
          Offset(0.60, 0.42),
          Offset(0.36, 0.50)
        ], twigs: const [
          (Offset(0.78, 0.20), Offset(0.72, 0.04)),
          (Offset(0.64, 0.35), Offset(0.72, 0.56)),
          (Offset(0.50, 0.47), Offset(0.42, 0.28)),
        ], blossoms: const [
          (Offset(0.76, 0.10), 7.0, -0.2),
          (Offset(0.66, 0.31), 8.0, 0.4),
          (Offset(0.47, 0.42), 7.0, -0.6),
        ], buds: const [
          Offset(0.71, 0.04),
          Offset(0.40, 0.29)
        ], petals: const [
          Offset(0.86, 0.72),
          Offset(0.53, 0.76)
        ]),
      1 => _BranchSpec(stroke: 3.2, path: const [
          Offset(0.40, 0.08),
          Offset(0.58, 0.25),
          Offset(0.82, 0.22),
          Offset(1.05, 0.36)
        ], twigs: const [
          (Offset(0.56, 0.23), Offset(0.50, 0.44)),
          (Offset(0.76, 0.23), Offset(0.83, 0.06)),
          (Offset(0.88, 0.27), Offset(0.92, 0.52)),
        ], blossoms: const [
          (Offset(0.53, 0.40), 7.0, 0.2),
          (Offset(0.72, 0.20), 6.5, -0.5),
          (Offset(0.91, 0.43), 8.0, 0.7),
        ], buds: const [
          Offset(0.83, 0.07),
          Offset(0.96, 0.51)
        ], petals: const [
          Offset(0.62, 0.70),
          Offset(0.88, 0.76)
        ]),
      2 => _BranchSpec(stroke: 4.8, path: const [
          Offset(1.10, 0.78),
          Offset(0.86, 0.60),
          Offset(0.70, 0.40),
          Offset(0.50, 0.20)
        ], twigs: const [
          (Offset(0.83, 0.58), Offset(0.98, 0.44)),
          (Offset(0.71, 0.42), Offset(0.61, 0.62)),
          (Offset(0.58, 0.28), Offset(0.69, 0.12)),
        ], blossoms: const [
          (Offset(0.94, 0.45), 7.2, -0.1),
          (Offset(0.64, 0.58), 7.8, 0.5),
          (Offset(0.66, 0.14), 6.8, -0.8),
        ], buds: const [
          Offset(0.98, 0.44),
          Offset(0.58, 0.61)
        ], petals: const [
          Offset(0.79, 0.18),
          Offset(0.46, 0.62)
        ]),
      3 => _BranchSpec(stroke: 3.4, path: const [
          Offset(0.98, 0.05),
          Offset(0.78, 0.22),
          Offset(0.66, 0.50),
          Offset(0.52, 0.86)
        ], twigs: const [
          (Offset(0.78, 0.22), Offset(0.91, 0.30)),
          (Offset(0.67, 0.48), Offset(0.53, 0.38)),
          (Offset(0.58, 0.70), Offset(0.72, 0.82)),
        ], blossoms: const [
          (Offset(0.88, 0.28), 7.0, 0.1),
          (Offset(0.55, 0.40), 7.5, -0.4),
          (Offset(0.72, 0.79), 6.8, 0.6),
        ], buds: const [
          Offset(0.91, 0.30),
          Offset(0.52, 0.86)
        ], petals: const [
          Offset(0.41, 0.28),
          Offset(0.86, 0.72)
        ]),
      4 => _BranchSpec(stroke: 5.2, path: const [
          Offset(0.36, 0.78),
          Offset(0.56, 0.56),
          Offset(0.76, 0.38),
          Offset(1.10, 0.22)
        ], twigs: const [
          (Offset(0.55, 0.57), Offset(0.49, 0.30)),
          (Offset(0.75, 0.39), Offset(0.68, 0.68)),
          (Offset(0.90, 0.30), Offset(0.95, 0.08)),
        ], blossoms: const [
          (Offset(0.50, 0.33), 8.0, -0.2),
          (Offset(0.70, 0.64), 7.0, 0.6),
          (Offset(0.94, 0.10), 7.2, -0.5),
        ], buds: const [
          Offset(0.36, 0.78),
          Offset(0.66, 0.68)
        ], petals: const [
          Offset(0.86, 0.62),
          Offset(0.56, 0.16)
        ]),
      5 => _BranchSpec(stroke: 3.8, path: const [
          Offset(1.06, 0.50),
          Offset(0.78, 0.50),
          Offset(0.62, 0.32),
          Offset(0.42, 0.16)
        ], twigs: const [
          (Offset(0.78, 0.50), Offset(0.82, 0.74)),
          (Offset(0.65, 0.35), Offset(0.56, 0.54)),
          (Offset(0.50, 0.22), Offset(0.60, 0.08)),
        ], blossoms: const [
          (Offset(0.82, 0.70), 7.8, 0.3),
          (Offset(0.56, 0.50), 6.8, -0.6),
          (Offset(0.59, 0.10), 7.4, 0.7),
        ], buds: const [
          Offset(0.41, 0.16),
          Offset(0.92, 0.49)
        ], petals: const [
          Offset(0.73, 0.18),
          Offset(0.88, 0.82)
        ]),
      6 => _BranchSpec(stroke: 4.4, path: const [
          Offset(0.44, 0.92),
          Offset(0.56, 0.66),
          Offset(0.76, 0.54),
          Offset(1.06, 0.56)
        ], twigs: const [
          (Offset(0.56, 0.66), Offset(0.44, 0.52)),
          (Offset(0.73, 0.55), Offset(0.76, 0.31)),
          (Offset(0.89, 0.55), Offset(0.98, 0.72)),
        ], blossoms: const [
          (Offset(0.47, 0.52), 7.0, -0.2),
          (Offset(0.76, 0.34), 8.0, 0.4),
          (Offset(0.98, 0.70), 6.8, -0.7),
        ], buds: const [
          Offset(0.42, 0.91),
          Offset(0.88, 0.55)
        ], petals: const [
          Offset(0.64, 0.20),
          Offset(0.70, 0.82)
        ]),
      7 => _BranchSpec(stroke: 3.6, path: const [
          Offset(1.08, 0.92),
          Offset(0.86, 0.76),
          Offset(0.74, 0.52),
          Offset(0.58, 0.28)
        ], twigs: const [
          (Offset(0.85, 0.75), Offset(0.92, 0.50)),
          (Offset(0.73, 0.52), Offset(0.58, 0.58)),
          (Offset(0.64, 0.38), Offset(0.75, 0.22)),
        ], blossoms: const [
          (Offset(0.91, 0.52), 7.5, 0.1),
          (Offset(0.59, 0.56), 7.0, -0.3),
          (Offset(0.75, 0.24), 6.8, 0.7),
        ], buds: const [
          Offset(1.02, 0.88),
          Offset(0.56, 0.29)
        ], petals: const [
          Offset(0.42, 0.70),
          Offset(0.86, 0.20)
        ]),
      _ => _BranchSpec(stroke: 4.6, path: const [
          Offset(0.38, 0.28),
          Offset(0.62, 0.30),
          Offset(0.80, 0.18),
          Offset(1.06, 0.12)
        ], twigs: const [
          (Offset(0.62, 0.30), Offset(0.58, 0.58)),
          (Offset(0.78, 0.20), Offset(0.86, 0.42)),
          (Offset(0.90, 0.16), Offset(0.96, 0.04)),
        ], blossoms: const [
          (Offset(0.58, 0.54), 7.6, 0.3),
          (Offset(0.86, 0.40), 7.0, -0.4),
          (Offset(0.96, 0.06), 6.8, 0.6),
        ], buds: const [
          Offset(0.39, 0.29),
          Offset(1.03, 0.12)
        ], petals: const [
          Offset(0.72, 0.70),
          Offset(0.48, 0.14)
        ]),
    };

    _drawCurvedBranch(canvas, size, branch.path, branch.stroke, branchPaint);
    for (final twig in branch.twigs) {
      _drawTwig(canvas, size, twig.$1, twig.$2, twigPaint);
    }
    for (final blossom in branch.blossoms) {
      _drawDetailedBlossom(
        canvas,
        _p(size, blossom.$1),
        blossom.$2,
        blossom.$3,
        petalPaint,
        petalDeepPaint,
        highlightPaint,
        centerPaint,
      );
    }
    for (final bud in branch.buds) {
      _drawBud(canvas, _p(size, bud), 4.2, petalDeepPaint);
    }
    for (final petal in branch.petals) {
      _drawSinglePetal(canvas, _p(size, petal), 5.4, -0.7, petalPaint);
    }
  }

  Offset _p(Size size, Offset unit) {
    return Offset(size.width * unit.dx, size.height * unit.dy);
  }

  void _drawCurvedBranch(Canvas canvas, Size size, List<Offset> points,
      double stroke, Paint paint) {
    final path = Path()
      ..moveTo(size.width * points.first.dx, size.height * points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final control = Offset(
        size.width * ((previous.dx + current.dx) / 2),
        size.height * ((previous.dy + current.dy) / 2 - 0.04),
      );
      path.quadraticBezierTo(
        control.dx,
        control.dy,
        size.width * current.dx,
        size.height * current.dy,
      );
    }
    canvas.drawPath(path, paint..strokeWidth = stroke);
  }

  void _drawTwig(
      Canvas canvas, Size size, Offset start, Offset end, Paint paint) {
    final path = Path()
      ..moveTo(size.width * start.dx, size.height * start.dy)
      ..quadraticBezierTo(
        size.width * ((start.dx + end.dx) / 2),
        size.height * ((start.dy + end.dy) / 2 - 0.03),
        size.width * end.dx,
        size.height * end.dy,
      );
    canvas.drawPath(path, paint..strokeWidth = 1.9);
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

  void _drawDetailedBlossom(
    Canvas canvas,
    Offset c,
    double r,
    double rotation,
    Paint petalPaint,
    Paint deepPaint,
    Paint highlightPaint,
    Paint centerPaint,
  ) {
    for (int i = 0; i < 5; i++) {
      final angle = rotation - pi / 2 + i * 2 * pi / 5;
      _drawPetal(
        canvas,
        Offset(c.dx + cos(angle) * r * 0.17, c.dy + sin(angle) * r * 0.17),
        r,
        angle,
        i.isEven ? petalPaint : deepPaint,
      );
    }
    canvas.drawCircle(c, r * 0.28, highlightPaint);
    canvas.drawCircle(c, r * 0.11, centerPaint);

    final stamen = Paint()
      ..color = centerPaint.color.withValues(alpha: 0.52)
      ..strokeWidth = 0.55
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 6; i++) {
      final angle = rotation + i * pi / 3;
      canvas.drawLine(
        c,
        Offset(c.dx + cos(angle) * r * 0.48, c.dy + sin(angle) * r * 0.48),
        stamen,
      );
    }
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

  void _drawBud(Canvas canvas, Offset c, double r, Paint p) {
    _drawSinglePetal(canvas, c, r, -0.65, p);
    _drawSinglePetal(
        canvas, Offset(c.dx + r * 0.32, c.dy + r * 0.14), r * 0.72, -0.22, p);
  }

  @override
  bool shouldRepaint(covariant _SakuraCardPainter old) =>
      old.color != color || old.variant != variant;
}

class _BranchSpec {
  final double stroke;
  final List<Offset> path;
  final List<(Offset, Offset)> twigs;
  final List<(Offset, double, double)> blossoms;
  final List<Offset> buds;
  final List<Offset> petals;

  const _BranchSpec({
    required this.stroke,
    required this.path,
    required this.twigs,
    required this.blossoms,
    required this.buds,
    required this.petals,
  });
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
