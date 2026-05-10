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
  List<_SakuraFallSprite> _sprites = const [];
  bool _assetsPrecached = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      });
    _sprites = _SakuraFallSprite.randomBatch();
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
      _sprites = _SakuraFallSprite.randomBatch();
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
              for (final sprite in _sprites)
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
    final drift = sin((eased * pi * sprite.wave) + sprite.phase) * sprite.sway +
        sin((eased * pi * 5.2) + sprite.phase * 0.7) * sprite.sway * 0.24;
    final x = media.width * sprite.x + drift;
    final y = -sprite.size * 1.5 +
        eased * (media.height + sprite.size * 4) * sprite.speed;
    final scalePulse = 1 + sin(eased * pi * 2 + sprite.phase) * 0.07;

    return Positioned(
      left: x - sprite.size / 2,
      top: y,
      width: sprite.size,
      height: sprite.size,
      child: Opacity(
        opacity: alpha,
        child: Transform.rotate(
          angle: sprite.startAngle +
              eased * pi * 2.2 * sprite.spin +
              sin(eased * pi * 3.4 + sprite.phase) * 0.18,
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

  static List<_SakuraFallSprite> randomBatch() {
    final seed = DateTime.now().microsecondsSinceEpoch ^
        SakuraFallController.playId.value * 1000003;
    final random = Random(seed);
    final fullFlowerAssets = [
      assets[0],
      assets[1],
      assets[2],
      assets[3],
      assets[4]
    ];
    final petalAssets = [assets[5], assets[6], assets[7], assets[8], assets[9]];

    final sprites = <_SakuraFallSprite>[];
    for (var i = 0; i < 26; i++) {
      final isFullFlower = i < 11 || random.nextDouble() < 0.38;
      final assetPool = isFullFlower ? fullFlowerAssets : petalAssets;
      final asset = assetPool[random.nextInt(assetPool.length)];
      final size = isFullFlower
          ? 28 + random.nextDouble() * 34
          : 16 + random.nextDouble() * 22;
      final fromLeft = random.nextBool() ? -0.08 : 0.08;
      final fromRight = random.nextBool() ? 1.08 : 0.92;

      sprites.add(
        _SakuraFallSprite(
          asset: asset,
          x: i.isEven
              ? fromLeft + random.nextDouble() * 1.08
              : fromRight - random.nextDouble() * 1.08,
          delay: random.nextDouble() * 0.46,
          speed: 0.66 + random.nextDouble() * 0.34,
          size: size,
          sway: (random.nextBool() ? 1 : -1) * (18 + random.nextDouble() * 48),
          spin: (random.nextBool() ? 1 : -1) *
              (0.20 + random.nextDouble() * 0.70),
          startAngle: -pi + random.nextDouble() * pi * 2,
          phase: random.nextDouble() * pi * 2,
          wave: 1.6 + random.nextDouble() * 2.2,
          opacity: isFullFlower
              ? 0.50 + random.nextDouble() * 0.28
              : 0.45 + random.nextDouble() * 0.30,
        ),
      );
    }
    return sprites;
  }
}
