import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/whiteboard_widget.dart';

/// 词汇白板练习页 —— 全单词一张画布，背景显示完整单词/读音作为参考
enum _RefMode { word, reading, none }

class VocabWhiteboardScreen extends StatefulWidget {
  final String word;
  final String reading;
  final String meaningZh;

  const VocabWhiteboardScreen({
    super.key,
    required this.word,
    required this.reading,
    required this.meaningZh,
  });

  @override
  State<VocabWhiteboardScreen> createState() => _VocabWhiteboardScreenState();
}

class _VocabWhiteboardScreenState extends State<VocabWhiteboardScreen> {
  _RefMode _refMode = _RefMode.reading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final refText = _refMode == _RefMode.word
        ? widget.word
        : _refMode == _RefMode.reading
            ? widget.reading
            : null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/vocabulary'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.word,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.reading,
                style: TextStyle(
                    fontSize: 12, color: cs.primary, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          _RefModeButton(current: _refMode, onChanged: (m) => setState(() => _refMode = m)),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.go('/home'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            // —— 释义提示 ——————————————————————————————————————————————————
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.meaningZh,
                style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer),
                textAlign: TextAlign.center,
              ),
            ),

            // —— 白板画布 ————————————————————————————————————————————————
            Expanded(
              child: WhiteboardWidget(
                key: ValueKey(refText ?? '__none__'),
                referenceChar: refText,
              ),
            ),

            const SizedBox(height: 10),

            // —— 提示文字 ————————————————————————————————————————————————
            Text(
              '在上方画布中练习书写  •  右上角可切换参考显示模式',
              style: TextStyle(fontSize: 11, color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ——— 参考模式切换按钮 —————————————————————————————————————————————————————————

class _RefModeButton extends StatelessWidget {
  final _RefMode current;
  final ValueChanged<_RefMode> onChanged;
  const _RefModeButton({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<_RefMode>(
      initialValue: current,
      onSelected: onChanged,
      tooltip: '参考显示',
      icon: Icon(
        current == _RefMode.none
            ? Icons.visibility_off_rounded
            : Icons.visibility_rounded,
        color: current == _RefMode.none ? cs.outline : cs.primary,
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _RefMode.reading,
          child: _ModeItem(
            icon: Icons.text_fields_rounded,
            label: '参考假名读音',
            active: current == _RefMode.reading,
          ),
        ),
        PopupMenuItem(
          value: _RefMode.word,
          child: _ModeItem(
            icon: Icons.translate_rounded,
            label: '参考单词写法',
            active: current == _RefMode.word,
          ),
        ),
        PopupMenuItem(
          value: _RefMode.none,
          child: _ModeItem(
            icon: Icons.visibility_off_rounded,
            label: '隐藏参考',
            active: current == _RefMode.none,
          ),
        ),
      ],
    );
  }
}

class _ModeItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _ModeItem({required this.icon, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: active ? cs.primary : cs.onSurface),
      const SizedBox(width: 10),
      Text(label,
          style: TextStyle(
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? cs.primary : cs.onSurface)),
      if (active) ...[
        const Spacer(),
        Icon(Icons.check_rounded, size: 16, color: cs.primary),
      ],
    ]);
  }
}
