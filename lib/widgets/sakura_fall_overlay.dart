import 'dart:math';
import 'package:flutter/material.dart';

import '../providers/app_appearance_provider.dart';

class SakuraFallController {
  SakuraFallController._();

  static final playId = ValueNotifier<int>(0);

  static void play() {
    playId.value++;
  }

  static void playIfEnabled(BuildContext context) {
    final visualTheme = Theme.of(context).extension<AppVisualTheme>();
    if (visualTheme?.sakuraBackground ?? false) {
      play();
    }
  }
}

class SakuraFallHost extends StatelessWidget {
  final Widget child;

  const SakuraFallHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: SakuraFallController.playId,
            builder: (context, playId, _) {
              return SakuraFallOverlay(playId: playId);
            },
          ),
        ),
      ],
    );
  }
}

class SakuraFallOverlay extends StatefulWidget {
  final int playId;
  final VoidCallback? onCompleted;

  const SakuraFallOverlay({
    super.key,
    required this.playId,
    this.onCompleted,
  });

  @override
  State<SakuraFallOverlay> createState() => _SakuraFallOverlayState();
}

class _SakuraFallOverlayState extends State<SakuraFallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _assetsPrecached = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsPrecached) return;
    _assetsPrecached = true;
    for (final asset in _SakuraFallSprite.assets) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  void didUpdateWidget(covariant SakuraFallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playId > 0 && widget.playId != oldWidget.playId) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.value == 0 || _controller.isDismissed) {
            return const SizedBox.shrink();
          }
          return Stack(
            children: [
              for (final sprite in _SakuraFallSprite.sprites)
                _FallingSakuraSprite(
                  sprite: sprite,
                  progress: _controller.value,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FallingSakuraSprite extends StatelessWidget {
  final _SakuraFallSprite sprite;
  final double progress;

  const _FallingSakuraSprite({
    required this.sprite,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    if (media.isEmpty) return const SizedBox.shrink();

    final local =
        ((progress - sprite.delay) / (1 - sprite.delay)).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();

    final fadeIn = (progress / 0.14).clamp(0.0, 1.0);
    final fadeOut = ((1 - progress) / 0.22).clamp(0.0, 1.0);
    final alpha = min(fadeIn, fadeOut) * sprite.opacity;
    final eased = Curves.easeInOutSine.transform(local);
    final drift = sin((eased * pi * sprite.wave) + sprite.phase) * sprite.sway;
    final x = media.width * sprite.x + drift;
    final y = -sprite.size * 1.5 +
        eased * (media.height + sprite.size * 4) * sprite.speed;
    final scalePulse = 1 + sin(eased * pi * 2 + sprite.phase) * 0.05;

    return Positioned(
      left: x - sprite.size / 2,
      top: y,
      width: sprite.size,
      height: sprite.size,
      child: Opacity(
        opacity: alpha,
        child: Transform.rotate(
          angle: sprite.startAngle + eased * pi * 2.2 * sprite.spin,
          child: Transform.scale(
            scale: scalePulse,
            child: Image.asset(
              sprite.asset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SakuraFallSprite {
  final String asset;
  final double x;
  final double delay;
  final double speed;
  final double size;
  final double sway;
  final double spin;
  final double startAngle;
  final double phase;
  final double wave;
  final double opacity;

  const _SakuraFallSprite({
    required this.asset,
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.sway,
    required this.spin,
    required this.startAngle,
    required this.phase,
    this.wave = 2.2,
    this.opacity = 0.78,
  });

  static const assets = [
    'assets/images/sakura/sakura_blossom.png',
    'assets/images/sakura/sakura_blossom_01.png',
    'assets/images/sakura/sakura_blossom_02.png',
    'assets/images/sakura/sakura_blossom_03.png',
    'assets/images/sakura/sakura_blossom_04.png',
    'assets/images/sakura/sakura_blossom_05.png',
    'assets/images/sakura/sakura_blossom_06.png',
    'assets/images/sakura/sakura_blossom_07.png',
    'assets/images/sakura/sakura_blossom_08.png',
    'assets/images/sakura/sakura_blossom_09.png',
  ];

  static final sprites = [
    _SakuraFallSprite(
      asset: assets[1],
      x: 0.08,
      delay: 0.00,
      speed: 0.88,
      size: 42,
      sway: 36,
      spin: 0.42,
      startAngle: -0.4,
      phase: 0.2,
    ),
    _SakuraFallSprite(
      asset: assets[2],
      x: 0.20,
      delay: 0.06,
      speed: 0.78,
      size: 34,
      sway: -28,
      spin: -0.36,
      startAngle: 0.7,
      phase: 1.1,
      opacity: 0.72,
    ),
    _SakuraFallSprite(
      asset: assets[3],
      x: 0.34,
      delay: 0.02,
      speed: 0.92,
      size: 46,
      sway: 30,
      spin: 0.48,
      startAngle: -0.9,
      phase: 2.4,
    ),
    _SakuraFallSprite(
      asset: assets[4],
      x: 0.50,
      delay: 0.13,
      speed: 0.74,
      size: 38,
      sway: -22,
      spin: -0.44,
      startAngle: 1.2,
      phase: 3.0,
      opacity: 0.70,
    ),
    _SakuraFallSprite(
      asset: assets[0],
      x: 0.63,
      delay: 0.05,
      speed: 0.84,
      size: 50,
      sway: 26,
      spin: 0.34,
      startAngle: -0.1,
      phase: 0.8,
      opacity: 0.62,
    ),
    _SakuraFallSprite(
      asset: assets[5],
      x: 0.76,
      delay: 0.11,
      speed: 0.88,
      size: 32,
      sway: -34,
      spin: -0.58,
      startAngle: 0.5,
      phase: 1.8,
    ),
    _SakuraFallSprite(
      asset: assets[6],
      x: 0.90,
      delay: 0.18,
      speed: 0.76,
      size: 28,
      sway: 24,
      spin: 0.68,
      startAngle: -1.1,
      phase: 2.8,
      opacity: 0.74,
    ),
    _SakuraFallSprite(
      asset: assets[7],
      x: 0.27,
      delay: 0.22,
      speed: 0.72,
      size: 30,
      sway: 24,
      spin: 0.52,
      startAngle: 0.2,
      phase: 2.1,
      wave: 2.8,
    ),
    _SakuraFallSprite(
      asset: assets[8],
      x: 0.57,
      delay: 0.26,
      speed: 0.70,
      size: 30,
      sway: -26,
      spin: -0.62,
      startAngle: -0.7,
      phase: 0.4,
      wave: 2.5,
    ),
    _SakuraFallSprite(
      asset: assets[9],
      x: 0.83,
      delay: 0.30,
      speed: 0.68,
      size: 28,
      sway: -20,
      spin: -0.50,
      startAngle: 0.9,
      phase: 1.6,
      opacity: 0.70,
    ),
  ];
}
