import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'package:path_drawing/path_drawing.dart';

/// 外部控制器，用于触发动画/评分
class KanaStrokeController {
  VoidCallback? _playCallback;
  VoidCallback? _clearCallback;
  VoidCallback? _undoCallback;
  int Function()? _scoreCallback;
  bool Function()? _hasStrokesCallback;

  void play() => _playCallback?.call();
  void clear() => _clearCallback?.call();
  void undo() => _undoCallback?.call();
  int calculateScore() => _scoreCallback?.call() ?? 0;
  bool get hasStrokes => _hasStrokesCallback?.call() ?? false;

  void _attach({
    required VoidCallback play,
    required VoidCallback clear,
    required VoidCallback undo,
    required int Function() score,
    required bool Function() hasStrokes,
  }) {
    _playCallback = play;
    _clearCallback = clear;
    _undoCallback = undo;
    _scoreCallback = score;
    _hasStrokesCallback = hasStrokes;
  }

  void _detach() {
    _playCallback = null;
    _clearCallback = null;
    _undoCallback = null;
    _scoreCallback = null;
    _hasStrokesCallback = null;
  }
}

/// 假名笔画动画 + 书写练习组件
class KanaStrokeWidget extends StatefulWidget {
  final String kana;
  final bool isKatakana;
  final Color backgroundColor;

  /// 纯动画模式：隐藏工具栏，禁用绘制
  final bool animationOnly;

  /// 测试模式：隐藏工具栏和参考，启用绘制
  final bool testMode;

  /// 是否自动播放动画（默认 true）
  final bool autoPlay;

  /// 动画完成回调
  final VoidCallback? onAnimationComplete;

  /// 外部控制器
  final KanaStrokeController? controller;

  const KanaStrokeWidget({
    super.key,
    required this.kana,
    this.isKatakana = false,
    this.backgroundColor = Colors.white,
    this.animationOnly = false,
    this.testMode = false,
    this.autoPlay = true,
    this.onAnimationComplete,
    this.controller,
  });

  @override
  State<KanaStrokeWidget> createState() => _KanaStrokeWidgetState();
}

class _KanaStrokeWidgetState extends State<KanaStrokeWidget>
    with SingleTickerProviderStateMixin {
  // SVG data
  List<Path> _shadowPaths = [];
  List<_StrokeInfo> _strokes = [];
  bool _loaded = false;
  bool _svgError = false;

  // Animation
  AnimationController? _animCtrl;

  // User drawing
  final List<_DrawStroke> _userStrokes = [];
  _DrawStroke? _currentDraw;
  bool _showRef = true;

  // Canvas size for scoring
  Size? _lastCanvasSize;

  String get _svgAsset {
    final dir = widget.isKatakana ? 'katakana' : 'hiragana';
    return 'assets/svg/kana/$dir/${widget.kana}.svg';
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(
      play: _playAnim,
      clear: _clear,
      undo: _undo,
      score: _calculateScore,
      hasStrokes: () => _userStrokes.isNotEmpty,
    );
    _loadSvg();
  }

  @override
  void didUpdateWidget(KanaStrokeWidget old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._detach();
      widget.controller?._attach(
        play: _playAnim,
        clear: _clear,
        undo: _undo,
        score: _calculateScore,
        hasStrokes: () => _userStrokes.isNotEmpty,
      );
    }
    if (old.kana != widget.kana || old.isKatakana != widget.isKatakana) {
      _animCtrl?.dispose();
      _animCtrl = null;
      _userStrokes.clear();
      _currentDraw = null;
      _loadSvg();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _animCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadSvg() async {
    setState(() {
      _loaded = false;
      _svgError = false;
      _shadowPaths = [];
      _strokes = [];
    });
    try {
      final text = await rootBundle.loadString(_svgAsset);
      _parseSvg(text);
      setState(() => _loaded = true);
      if (widget.autoPlay && !widget.testMode) {
        _playAnim();
      }
    } catch (e) {
      debugPrint('SVG load error: $e');
      setState(() { _loaded = true; _svgError = true; });
    }
  }

  // ── SVG parsing ──

  void _parseSvg(String svgText) {
    final doc = XmlDocument.parse(svgText);
    final root = doc.rootElement;

    // 1. Shadow paths (filled shapes) with IDs
    final idToPath = <String, Path>{};
    for (final g in root.descendants.whereType<XmlElement>()) {
      if (g.getAttribute('data-strokesvg') != 'shadows') continue;
      for (final p in g.descendants.whereType<XmlElement>()) {
        if (p.name.local != 'path') continue;
        final id = p.getAttribute('id');
        final d = p.getAttribute('d');
        if (id != null && d != null) {
          final path = parseSvgPathData(d);
          idToPath[id] = path;
          _shadowPaths.add(path);
        }
      }
    }

    // 2. ClipPaths → shadow path mapping
    final clipToPath = <String, Path>{};
    for (final cp in root.descendants.whereType<XmlElement>()) {
      if (cp.name.local != 'clipPath') continue;
      final cpId = cp.getAttribute('id');
      final use = cp.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'use').firstOrNull;
      if (cpId == null || use == null) continue;
      final href = use.getAttribute('href') ??
          use.getAttribute('xlink:href') ?? '';
      if (href.startsWith('#')) {
        final ref = idToPath[href.substring(1)];
        if (ref != null) clipToPath[cpId] = ref;
      }
    }

    // 3. Stroke paths
    final strokeMap = <int, _StrokeInfo>{};

    void addStrokePath(XmlElement el, int idx) {
      if (el.name.local != 'path') return;
      final d = el.getAttribute('d');
      if (d == null) return;
      final path = parseSvgPathData(d);
      Path? clip;
      final cpRef = el.getAttribute('clip-path');
      if (cpRef != null) {
        final m = RegExp(r'url\(#([^)]+)\)').firstMatch(cpRef);
        if (m != null) clip = clipToPath[m.group(1)];
      }
      strokeMap.putIfAbsent(idx, () => _StrokeInfo(idx));
      strokeMap[idx]!.segments.add(_StrokeSeg(path, clip));
    }

    for (final g in root.descendants.whereType<XmlElement>()) {
      if (g.getAttribute('data-strokesvg') != 'strokes') continue;
      for (final child in g.children.whereType<XmlElement>()) {
        final style = child.getAttribute('style') ?? '';
        final im = RegExp(r'--i\s*:\s*(\d+)').firstMatch(style);
        final idx = im != null ? int.parse(im.group(1)!) : strokeMap.length;

        if (child.name.local == 'path') {
          addStrokePath(child, idx);
        } else if (child.name.local == 'g') {
          for (final p in child.children.whereType<XmlElement>()) {
            addStrokePath(p, idx);
          }
        }
      }
    }

    _strokes = strokeMap.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    // Compute path metrics
    for (final s in _strokes) {
      for (final seg in s.segments) {
        seg.metrics = seg.path.computeMetrics().toList();
        seg.totalLen = seg.metrics.fold(0.0, (sum, m) => sum + m.length);
      }
      s.totalLen = s.segments.fold(0.0, (sum, seg) => sum + seg.totalLen);
    }
  }

  // ── Animation ──

  void _playAnim() {
    _animCtrl?.dispose();
    if (_strokes.isEmpty) return;
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 550 * _strokes.length + 300),
    )..addListener(() => setState(() {}));
    _animCtrl!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
    _animCtrl!.forward();
  }

  void _replayAnim() {
    _userStrokes.clear();
    _currentDraw = null;
    _playAnim();
  }

  // ── User drawing ──

  void _startDraw(Offset p) {
    _currentDraw = _DrawStroke()..points.add(p);
    _userStrokes.add(_currentDraw!);
    setState(() {});
  }

  void _addPoint(Offset p) {
    _currentDraw?.points.add(p);
    setState(() {});
  }

  void _endDraw() => _currentDraw = null;

  void _undo() {
    if (_userStrokes.isNotEmpty) {
      _userStrokes.removeLast();
      _currentDraw = null;
      setState(() {});
    }
  }

  void _clear() {
    _userStrokes.clear();
    _currentDraw = null;
    setState(() {});
  }

  // ── Scoring ──

  int _calculateScore() {
    if (_strokes.isEmpty || _userStrokes.isEmpty) return 0;
    final canvasSize = _lastCanvasSize;
    if (canvasSize == null) return 0;

    final scale = canvasSize.shortestSide / 1024;
    final ox = (canvasSize.width - 1024 * scale) / 2;
    final oy = (canvasSize.height - 1024 * scale) / 2;

    // 1. Stroke count score (max 25)
    final expectedCount = _strokes.length;
    final actualCount = _userStrokes.length;
    final countDiff = (actualCount - expectedCount).abs();
    final countScore = countDiff == 0 ? 25 : countDiff == 1 ? 18 : countDiff == 2 ? 10 : 0;

    // 2. Sample reference strokes
    final refSampled = <List<Offset>>[];
    for (final stroke in _strokes) {
      refSampled.add(_sampleStrokePath(stroke));
    }

    // 3. Normalize user strokes
    final userNorm = <List<Offset>>[];
    for (final stroke in _userStrokes) {
      final points = stroke.points.map((p) {
        final svgX = ((p.dx - ox) / scale / 1024).clamp(0.0, 1.0);
        final svgY = ((p.dy - oy) / scale / 1024).clamp(0.0, 1.0);
        return Offset(svgX, svgY);
      }).toList();
      userNorm.add(points);
    }

    // 4. Match strokes and compute similarity (max 75)
    double totalSimilarity = 0;
    int matched = 0;
    final usedRef = <int>{};
    final matchCount = min(userNorm.length, refSampled.length);

    for (int i = 0; i < matchCount; i++) {
      double bestSim = 0;
      int bestJ = -1;
      for (int j = 0; j < refSampled.length; j++) {
        if (usedRef.contains(j)) continue;
        final sim = _strokeSimilarity(refSampled[j], userNorm[i]);
        if (sim > bestSim) {
          bestSim = sim;
          bestJ = j;
        }
      }
      if (bestJ >= 0) {
        usedRef.add(bestJ);
        totalSimilarity += bestSim;
        matched++;
      }
    }

    final avgSim = matched > 0 ? totalSimilarity / max(matched, _strokes.length) : 0.0;
    final matchScore = (75 * avgSim).round();

    return (countScore + matchScore).clamp(0, 100);
  }

  List<Offset> _sampleStrokePath(_StrokeInfo stroke, {int numSamples = 20}) {
    if (stroke.totalLen <= 0) return [];
    final points = <Offset>[];
    for (int i = 0; i <= numSamples; i++) {
      final t = i / numSamples;
      final targetLen = t * stroke.totalLen;
      var remaining = targetLen;
      bool found = false;
      for (final seg in stroke.segments) {
        for (final metric in seg.metrics) {
          if (remaining <= metric.length) {
            final tangent = metric.getTangentForOffset(remaining);
            if (tangent != null) {
              points.add(Offset(
                tangent.position.dx / 1024,
                tangent.position.dy / 1024,
              ));
            }
            found = true;
            break;
          }
          remaining -= metric.length;
        }
        if (found) break;
      }
    }
    return points;
  }

  double _strokeSimilarity(List<Offset> ref, List<Offset> user) {
    if (ref.isEmpty || user.isEmpty) return 0;
    final userResampled = _resamplePoints(user, ref.length);
    double totalDist = 0;
    for (int i = 0; i < ref.length; i++) {
      totalDist += (ref[i] - userResampled[i]).distance;
    }
    final avgDist = totalDist / ref.length;
    return (1 - (avgDist / 0.3)).clamp(0.0, 1.0);
  }

  List<Offset> _resamplePoints(List<Offset> points, int count) {
    if (points.isEmpty) return List.filled(count, Offset.zero);
    if (points.length == 1) return List.filled(count, points.first);
    if (count <= 1) return [points.first];

    double totalLen = 0;
    for (int i = 1; i < points.length; i++) {
      totalLen += (points[i] - points[i - 1]).distance;
    }
    if (totalLen == 0) return List.filled(count, points.first);

    final result = <Offset>[points.first];
    final segLen = totalLen / (count - 1);
    double accumulated = 0;
    int srcIdx = 1;

    for (int i = 1; i < count - 1; i++) {
      final target = segLen * i;
      while (srcIdx < points.length &&
          accumulated + (points[srcIdx] - points[srcIdx - 1]).distance < target) {
        accumulated += (points[srcIdx] - points[srcIdx - 1]).distance;
        srcIdx++;
      }
      if (srcIdx >= points.length) {
        result.add(points.last);
        continue;
      }
      final segDist = (points[srcIdx] - points[srcIdx - 1]).distance;
      if (segDist == 0) {
        result.add(points[srcIdx]);
      } else {
        final t = (target - accumulated) / segDist;
        result.add(Offset.lerp(points[srcIdx - 1], points[srcIdx], t)!);
      }
    }
    result.add(points.last);
    return result;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.animationOnly || widget.testMode) {
      return _buildCanvas(cs, enableDrawing: widget.testMode);
    }
    return Column(
      children: [
        _buildToolbar(cs),
        const SizedBox(height: 8),
        Expanded(child: _buildCanvas(cs)),
      ],
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            _showRef ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 20,
          ),
          tooltip: _showRef ? '隐藏参考' : '显示参考',
          onPressed: () => setState(() => _showRef = !_showRef),
        ),
        if (_strokes.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            tooltip: '播放笔顺动画',
            onPressed: _replayAnim,
          ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.undo_rounded, size: 20),
          tooltip: '撤销',
          onPressed: _userStrokes.isEmpty ? null : _undo,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_rounded, size: 20),
          tooltip: '清除',
          onPressed: _userStrokes.isEmpty ? null : _clear,
        ),
      ],
    );
  }

  Widget _buildCanvas(ColorScheme cs, {bool enableDrawing = true}) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastCanvasSize = constraints.biggest;
          final painter = CustomPaint(
            painter: _KanaCanvasPainter(
              shadowPaths: _shadowPaths,
              strokes: _strokes,
              animValue: _animCtrl?.value ?? (widget.testMode ? 0.0 : 1.0),
              userStrokes: _userStrokes,
              showRef: widget.testMode ? false : _showRef,
              svgError: _svgError,
              kana: widget.kana,
            ),
            child: const SizedBox.expand(),
          );
          if (!enableDrawing) return painter;
          return Listener(
            onPointerDown: (e) => _startDraw(e.localPosition),
            onPointerMove: (e) => _addPoint(e.localPosition),
            onPointerUp: (_) => _endDraw(),
            onPointerCancel: (_) => _endDraw(),
            child: painter,
          );
        },
      ),
    );
  }
}

// ── Data classes ──

class _StrokeSeg {
  final Path path;
  final Path? clip;
  List<ui.PathMetric> metrics = [];
  double totalLen = 0;
  _StrokeSeg(this.path, this.clip);
}

class _StrokeInfo {
  final int index;
  final List<_StrokeSeg> segments = [];
  double totalLen = 0;
  _StrokeInfo(this.index);
}

class _DrawStroke {
  final List<Offset> points = [];
}

// ── Canvas painter ──

class _KanaCanvasPainter extends CustomPainter {
  final List<Path> shadowPaths;
  final List<_StrokeInfo> strokes;
  final double animValue;
  final List<_DrawStroke> userStrokes;
  final bool showRef;
  final bool svgError;
  final String kana;

  _KanaCanvasPainter({
    required this.shadowPaths,
    required this.strokes,
    required this.animValue,
    required this.userStrokes,
    required this.showRef,
    required this.svgError,
    required this.kana,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (svgError || strokes.isEmpty) {
      // Fallback: show character as text reference
      if (showRef) {
        final tp = TextPainter(
          text: TextSpan(
            text: kana,
            style: TextStyle(
              fontSize: size.width * 0.6,
              color: Colors.grey.withValues(alpha: 0.12),
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(
          (size.width - tp.width) / 2,
          (size.height - tp.height) / 2,
        ));
      }
    } else {
      // SVG-based rendering
      final scale = size.shortestSide / 1024;
      final ox = (size.width - 1024 * scale) / 2;
      final oy = (size.height - 1024 * scale) / 2;

      canvas.save();
      canvas.translate(ox, oy);
      canvas.scale(scale);

      // Shadow reference (grey fill)
      if (showRef) {
        final shadowPaint = Paint()
          ..color = Colors.grey.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill;
        for (final sp in shadowPaths) {
          canvas.drawPath(sp, shadowPaint);
        }
      }

      // Animated strokes
      _drawAnimatedStrokes(canvas);

      canvas.restore();
    }

    // User drawing strokes (in screen coordinates)
    _drawUserStrokes(canvas, size);
  }

  void _drawAnimatedStrokes(Canvas canvas) {
    if (strokes.isEmpty) return;

    final strokePaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 80
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final n = strokes.length;
    final perStroke = 1.0 / n;

    for (int i = 0; i < n; i++) {
      final stroke = strokes[i];
      final start = i * perStroke;
      final end = (i + 1) * perStroke;

      double fraction;
      if (animValue >= end) {
        fraction = 1.0;
      } else if (animValue <= start) {
        break; // no more strokes to draw
      } else {
        fraction = (animValue - start) / (end - start);
      }

      for (final seg in stroke.segments) {
        canvas.save();
        if (seg.clip != null) {
          canvas.clipPath(seg.clip!);
        }

        if (fraction >= 1.0) {
          canvas.drawPath(seg.path, strokePaint);
        } else {
          final drawLen = seg.totalLen * fraction;
          final partial = _extractPartial(seg.metrics, drawLen);
          canvas.drawPath(partial, strokePaint);
        }
        canvas.restore();
      }
    }
  }

  Path _extractPartial(List<ui.PathMetric> metrics, double length) {
    final result = Path();
    var remaining = length;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final drawLen = remaining.clamp(0, m.length).toDouble();
      result.addPath(m.extractPath(0, drawLen), Offset.zero);
      remaining -= drawLen;
    }
    return result;
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    final cx = size.width / 2;
    final cy = size.height / 2;
    _dashedLine(canvas, Offset(0, cy), Offset(size.width, cy), paint);
    _dashedLine(canvas, Offset(cx, 0), Offset(cx, size.height), paint);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    final d = b - a;
    final dist = d.distance;
    if (dist == 0) return;
    final dx = d.dx / dist, dy = d.dy / dist;
    double drawn = 0;
    while (drawn < dist) {
      final s = Offset(a.dx + dx * drawn, a.dy + dy * drawn);
      drawn += 6;
      if (drawn > dist) drawn = dist;
      final e = Offset(a.dx + dx * drawn, a.dy + dy * drawn);
      c.drawLine(s, e, p);
      drawn += 4;
    }
  }

  void _drawUserStrokes(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in userStrokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, 3, paint);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length - 1; i++) {
        final mid = Offset(
          (stroke.points[i].dx + stroke.points[i + 1].dx) / 2,
          (stroke.points[i].dy + stroke.points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(
          stroke.points[i].dx, stroke.points[i].dy, mid.dx, mid.dy,
        );
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_KanaCanvasPainter old) => true;
}
