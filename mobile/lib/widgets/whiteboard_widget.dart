import 'package:flutter/material.dart';

// ─── Data ────────────────────────────────────────────────────────────────────

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _Stroke({required this.color, required this.width}) : points = [];

  void addPoint(Offset p) => points.add(p);
}

// ─── Notifier (持有所有笔迹数据，变化时只触发 CustomPainter 重绘) ────────────────

class _StrokeNotifier extends ChangeNotifier {
  final List<_Stroke> strokes = [];
  _Stroke? current;

  void startStroke(Color color, double width, Offset point) {
    current = _Stroke(color: color, width: width)..addPoint(point);
    strokes.add(current!);
    notifyListeners();
  }

  void addPoint(Offset point) {
    current?.addPoint(point);
    notifyListeners();
  }

  void endStroke() {
    current = null;
    notifyListeners();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      strokes.removeLast();
      current = null;
      notifyListeners();
    }
  }

  void clear() {
    strokes.clear();
    current = null;
    notifyListeners();
  }

  bool get isEmpty => strokes.isEmpty;
}

// ─── Background Painter (参考字 + 网格，单独隔离避免每帧重绘) ─────────────────────

class _BackgroundPainter extends CustomPainter {
  final String? refChar;

  _BackgroundPainter({this.refChar});

  @override
  void paint(Canvas canvas, Size size) {
    // 纯白画布，不绘制参考文字和格线
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.refChar != refChar;
}

// ─── Stroke Painter (笔迹，由 Notifier 驱动，不触发 Widget 重建) ──────────────────

class _StrokePainter extends CustomPainter {
  final _StrokeNotifier notifier;

  _StrokePainter(this.notifier) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in notifier.strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
        continue;
      }

      // 贝塞尔平滑曲线，比逐点直线更流畅
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length - 1; i++) {
        final mid = Offset(
          (stroke.points[i].dx + stroke.points[i + 1].dx) / 2,
          (stroke.points[i].dy + stroke.points[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(
          stroke.points[i].dx, stroke.points[i].dy,
          mid.dx, mid.dy,
        );
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => false; // 由 repaint: notifier 驱动
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class WhiteboardWidget extends StatefulWidget {
  final String? referenceChar;
  final Color backgroundColor;

  const WhiteboardWidget({
    super.key,
    this.referenceChar,
    this.backgroundColor = Colors.white,
  });

  @override
  State<WhiteboardWidget> createState() => _WhiteboardWidgetState();
}

class _WhiteboardWidgetState extends State<WhiteboardWidget> {
  final _notifier = _StrokeNotifier();

  Color _penColor = Colors.black;
  double _penWidth = 6.0;
  bool _isEraser = false;

  static const _colors = [
    Colors.black,
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
  ];

  static const _widths = [3.0, 6.0, 10.0, 16.0];

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  // ── actions ─────────────────────────────────────────────────────────────
  void _undo() {
    _notifier.undo();
    setState(() {}); // 只刷新工具栏按钮禁用状态
  }

  void _clear() {
    _notifier.clear();
    setState(() {});
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildToolbar(cs),
        const SizedBox(height: 8),
        Expanded(child: _buildCanvas()),
      ],
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 颜色 + 笔宽 + 橡皮擦（可滚动）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._colors.map((c) => _ColorDot(
                        color: c,
                        selected: !_isEraser && _penColor == c,
                        onTap: () => setState(() { _penColor = c; _isEraser = false; }),
                      )),
                  const SizedBox(width: 4),
                  Container(width: 1, height: 22, color: cs.outline.withValues(alpha: 0.3)),
                  const SizedBox(width: 4),
                  ..._widths.map((w) => _WidthDot(
                        width: w,
                        color: _isEraser ? Colors.grey : _penColor,
                        selected: !_isEraser && _penWidth == w,
                        onTap: () => setState(() { _penWidth = w; _isEraser = false; }),
                      )),
                  const SizedBox(width: 4),
                  Container(width: 1, height: 22, color: cs.outline.withValues(alpha: 0.3)),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 36, height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '橡皮擦',
                      icon: Icon(Icons.auto_fix_high_rounded, size: 20,
                          color: _isEraser ? cs.primary : cs.onSurface),
                      onPressed: () => setState(() => _isEraser = !_isEraser),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 撤销 + 清除（始终可见）
          Container(width: 1, height: 22, color: cs.outline.withValues(alpha: 0.3)),
          ListenableBuilder(
            listenable: _notifier,
            builder: (_, __) => SizedBox(
              width: 36, height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '撤销',
                icon: Icon(Icons.undo_rounded, size: 20),
                onPressed: _notifier.isEmpty ? null : _undo,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _notifier,
            builder: (_, __) => SizedBox(
              width: 36, height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '清除',
                icon: Icon(Icons.delete_sweep_rounded, size: 20),
                onPressed: _notifier.isEmpty ? null : _clear,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
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
      // Listener 比 GestureDetector 少一层手势竞技，响应更即时
      child: Listener(
        onPointerDown: (e) {
          _notifier.startStroke(
            _isEraser ? widget.backgroundColor : _penColor,
            _isEraser ? _penWidth * 3.5 : _penWidth,
            e.localPosition,
          );
        },
        onPointerMove: (e) => _notifier.addPoint(e.localPosition),
        onPointerUp: (_) => _notifier.endStroke(),
        onPointerCancel: (_) => _notifier.endStroke(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景层：参考字 + 网格，单独 RepaintBoundary 隔离
            RepaintBoundary(
              child: CustomPaint(
                painter: _BackgroundPainter(refChar: widget.referenceChar),
                child: const SizedBox.expand(),
              ),
            ),
            // 笔迹层：由 _StrokeNotifier 驱动，仅此层重绘
            RepaintBoundary(
              child: CustomPaint(
                painter: _StrokePainter(_notifier),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  final double width;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _WidthDot(
      {required this.width, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = (width * 1.4).clamp(6.0, 22.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Colors.white, width: 1.5)
              : null,
        ),
      ),
    );
  }
}
