import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getNotifications(limit: 50);
      final data = (res['data'] as List?) ?? [];
      _list = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      _list = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['is_read'] == true || n['is_read'] == 1) return;
    try {
      await _api.markNotificationRead(n['id'] as int);
      setState(() => n['is_read'] = true);
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await _api.markAllNotificationsRead();
      setState(() {
        for (final n in _list) {
          n['is_read'] = true;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已全部标为已读'), duration: Duration(seconds: 1)),
        );
      }
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    try {
      await _api.deleteNotification(n['id'] as int);
      setState(() => _list.removeWhere((x) => x['id'] == n['id']));
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'order_approved':
        return Icons.check_circle_rounded;
      case 'order_rejected':
        return Icons.cancel_rounded;
      case 'report_resolved':
        return Icons.verified_rounded;
      case 'report_rejected':
        return Icons.info_outline_rounded;
      case 'report_replied':
        return Icons.chat_bubble_outline_rounded;
      case 'xp_award':
        return Icons.emoji_events_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type, ColorScheme cs) {
    switch (type) {
      case 'order_approved':
      case 'report_resolved':
        return Colors.green;
      case 'order_rejected':
      case 'report_rejected':
        return Colors.redAccent;
      case 'report_replied':
        return cs.primary;
      case 'xp_award':
        return Colors.amber.shade700;
      default:
        return cs.primary;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
      if (diff.inHours < 24) return '${diff.inHours} 小时前';
      if (diff.inDays < 7) return '${diff.inDays} 天前';
      return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('消息通知'),
        actions: [
          if (_list.any((n) => !(n['is_read'] == true || n['is_read'] == 1)))
            TextButton(
              onPressed: _markAllRead,
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 60, color: cs.outline),
                      const SizedBox(height: 12),
                      Text('暂无通知', style: TextStyle(color: cs.outline)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                    itemBuilder: (ctx, i) {
                      final n = _list[i];
                      final type = (n['type'] as String?) ?? 'system';
                      final isRead = n['is_read'] == true;
                      final color = _colorForType(type, cs);
                      return Dismissible(
                        key: ValueKey(n['id']),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete(n),
                        child: ListTile(
                          onTap: () {
                            _markRead(n);
                            _showDetail(n);
                          },
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                backgroundColor: color.withOpacity(0.12),
                                child: Icon(_iconForType(type), color: color),
                              ),
                              if (!isRead)
                                Positioned(
                                  right: -2, top: -2,
                                  child: Container(
                                    width: 10, height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            (n['title'] as String?) ?? '',
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((n['content'] as String?)?.isNotEmpty ?? false)
                                Text(
                                  n['content'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                                ),
                              const SizedBox(height: 2),
                              Text(_formatTime((n['created_at'] ?? n['createdAt']) as String?),
                                  style: TextStyle(fontSize: 11, color: cs.outline)),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showDetail(Map<String, dynamic> n) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconForType((n['type'] as String?) ?? 'system'),
                      color: _colorForType((n['type'] as String?) ?? 'system', cs)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text((n['title'] as String?) ?? '',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_formatTime((n['created_at'] ?? n['createdAt']) as String?),
                  style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 16),
              if ((n['content'] as String?)?.isNotEmpty ?? false)
                Text(n['content'] as String,
                    style: const TextStyle(fontSize: 14, height: 1.6)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
