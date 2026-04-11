import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ReportDialog extends StatefulWidget {
  final String refType; // 'vocabulary' or 'grammar'
  final String refId;
  final String refTitle;

  const ReportDialog({
    super.key,
    required this.refType,
    required this.refId,
    required this.refTitle,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  static const _issueTypes = [
    '发音错误',
    '词义错误',
    '例句错误',
    '其他',
  ];

  String _selectedType = '发音错误';
  final _descController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写问题描述')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService().submitReport(
        refType: widget.refType,
        refId: widget.refId,
        refTitle: widget.refTitle,
        issueType: _selectedType,
        description: desc,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('反馈已提交，感谢您的报告！')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                Icon(Icons.bug_report_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Text('问题反馈', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.refTitle,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            const Text('问题类型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _issueTypes.map((t) => ChoiceChip(
                label: Text(t),
                selected: _selectedType == t,
                onSelected: (_) => setState(() => _selectedType = t),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text('问题描述', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: '请描述您发现的问题…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('提交'),
                ),
              ],
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
