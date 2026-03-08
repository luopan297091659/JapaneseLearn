import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../utils/tts_helper.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserModel? _user;
  ProgressSummaryModel? _progress;
  bool _loading = true;
  bool? _notifOverride; // 乐观更新开关状态
  Map<String, bool> _permissions = {};

  @override
  void initState() { super.initState(); _load(); _checkPermissions(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        apiService.getMe(),
        apiService.getProgressSummary(),
      ]);
      setState(() {
        _user = results[0] as UserModel;
        _progress = results[1] as ProgressSummaryModel;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    final mic = await Permission.microphone.status;
    final camera = await Permission.camera.status;
    final notification = await Permission.notification.status;
    final storage = await Permission.storage.status;
    if (mounted) {
      setState(() {
        _permissions = {
          'microphone': mic.isGranted,
          'camera': camera.isGranted,
          'notification': notification.isGranted,
          'storage': storage.isGranted,
        };
      });
    }
  }

  Future<void> _logout() async {
    await apiService.logout();
    if (mounted) context.go('/login');
  }

  // ── 学习目标 ───────────────────────────────────────────────────
  Future<void> _editGoal() async {
    final current = _user?.dailyGoalMinutes ?? 15;
    int selected = current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('学习目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('每日学习目标：$selected 分钟',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Slider(
                value: selected.toDouble(),
                min: 5, max: 120, divisions: 23,
                label: '$selected 分钟',
                onChanged: (v) => setSt(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [5, 15, 30, 60, 90, 120].map((m) => GestureDetector(
                  onTap: () => setSt(() => selected = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected == m
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$m分',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected == m ? Colors.white : null,
                        )),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('保存')),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != current) {
      try {
        await apiService.updateProfile(dailyGoalMinutes: selected);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ── 学习提醒开关 ───────────────────────────────────────────────
  Future<void> _toggleNotification(bool value) async {
    setState(() => _notifOverride = value); // 乐观更新
    try {
      await apiService.updateProfile(notificationEnabled: value);
    } catch (e) {
      setState(() => _notifOverride = !value); // 回滚
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败：$e'), behavior: SnackBarBehavior.floating));
    }
  }

  // ── 编辑个人信息（用户名）──────────────────────────────────────
  Future<void> _editPersonalInfo() async {
    final ctrl = TextEditingController(text: _user?.username ?? '');
    String? errorMsg;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('个人信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMsg != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              TextField(
                controller: ctrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setSt(() => errorMsg = '用户名不能为空');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && ctrl.text.trim() != _user?.username) {
      try {
        await apiService.updateProfile(username: ctrl.text.trim());
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
    ctrl.dispose();
  }

  // ── JLPT 等级设置 ─────────────────────────────────────────────
  Future<void> _editJlptLevel() async {
    const levels = ['N5', 'N4', 'N3', 'N2', 'N1'];
    String selected = _user?.level ?? 'N3';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('JLPT 等级'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择您当前的日语水平：',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: levels.map((lvl) {
                  final isSelected = selected == lvl;
                  return GestureDetector(
                    onTap: () => setSt(() => selected = lvl),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(color: Theme.of(ctx).colorScheme.primary, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(lvl,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : null,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != _user?.level) {
      try {
        await apiService.updateProfile(level: selected);
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  // ── 修改密码 ───────────────────────────────────────────────────
  Future<void> _testTts() async {
    final tts = FlutterTts();
    final diag = StringBuffer();
    bool speakSuccess = false;

    try {
      // 1. 检测引擎
      try {
        final engines = await tts.getEngines;
        final list = engines is List ? engines : [];
        diag.writeln('可用引擎: ${list.isEmpty ? "无" : list.join(", ")}');
        if (list.any((e) => e.toString().contains('google'))) {
          await tts.setEngine(list.firstWhere((e) => e.toString().contains('google')).toString());
          diag.writeln('已选引擎: Google TTS');
        }
      } catch (e) {
        diag.writeln('引擎检测失败: $e');
      }

      // 2. 检测语言
      try {
        final raw = await tts.getLanguages;
        final langs = raw is List ? raw.map((l) => l.toString()).toList() : <String>[];
        final jaLangs = langs.where((l) => l.toLowerCase().startsWith('ja')).toList();
        diag.writeln('可用语言总数: ${langs.length}');
        diag.writeln('日语支持: ${jaLangs.isEmpty ? "❌ 无" : "✅ ${jaLangs.join(", ")}"}');

        // 也检测中文
        final zhLangs = langs.where((l) => l.toLowerCase().startsWith('zh') || l.toLowerCase().contains('chinese')).toList();
        diag.writeln('中文变体: ${zhLangs.isEmpty ? "无" : zhLangs.join(", ")}');
      } catch (e) {
        diag.writeln('语言检测失败: $e');
      }

      // 3. 配置并测试
      await tts.awaitSpeakCompletion(false);
      try { await tts.setLanguage('ja-JP'); } catch (_) {}
      await tts.setVolume(1.0);
      await tts.setSpeechRate(0.45);
      await tts.setPitch(1.0);

      final result = await tts.speak('こんにちは');
      diag.writeln('speak() 结果: $result (1=成功, 0=失败)');
      speakSuccess = result == 1;
    } catch (e) {
      diag.writeln('测试异常: $e');
    }

    // 加上全局诊断
    diag.writeln('\n--- 全局诊断 ---');
    diag.writeln(TtsHelper.instance.diagnosticInfo);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(speakSuccess ? Icons.check_circle : Icons.error,
                color: speakSuccess ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(speakSuccess ? 'TTS 正常' : 'TTS 异常'),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(diag.toString(), style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                if (!speakSuccess) ...[
                  const Divider(height: 24),
                  const Text('修复步骤：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text('1. 安装「Google 文字转语音」引擎', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('2. 在 Google TTS 中下载日语语音包', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('3. 将默认 TTS 引擎切换为 Google', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      icon: const Icon(Icons.shop, size: 16),
                      label: const Text('安装Google TTS', style: TextStyle(fontSize: 12)),
                      onPressed: () => launchUrl(
                        Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.tts'),
                        mode: LaunchMode.externalApplication,
                      ),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('TTS设置', style: TextStyle(fontSize: 12)),
                      onPressed: () async {
                        try {
                          if (Platform.isAndroid) {
                            const intent = AndroidIntent(
                              action: 'com.android.settings.TTS_SETTINGS',
                            );
                            await intent.launch();
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('请手动打开：设置 → 系统 → 语言 → 文字转语音'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    )),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
    }

    tts.stop();
  }

  Future<void> _changePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCurrent = true, obscureNew = true, obscureConfirm = true;
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('修改密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMsg != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              TextField(
                controller: currentCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: '当前密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setSt(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: '新密码（至8位）',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setSt(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setSt(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                setSt(() => errorMsg = null);
                if (newCtrl.text != confirmCtrl.text) {
                  setSt(() => errorMsg = '两次输入的新密码不一致');
                  return;
                }
                if (newCtrl.text.length < 8) {
                  setSt(() => errorMsg = '新密码至少8个字符');
                  return;
                }
                if (currentCtrl.text.isEmpty) {
                  setSt(() => errorMsg = '请输入当前密码');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await apiService.changePassword(currentCtrl.text, newCtrl.text);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('密码已更新！请重新登录'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  await apiService.logout();
                  if (mounted) context.go('/login');
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('修改失败：当前密码不正确或网络错误'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('确认修改'),
            ),
          ],
        ),
      ),
    );
    currentCtrl.dispose(); newCtrl.dispose(); confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    final locale = ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(s.profile),
        actions: [
          TextButton(onPressed: _logout, child: Text(s.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile header
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: cs.primaryContainer,
                                child: Text(
                                  _user?.username.substring(0, 1).toUpperCase() ?? 'U',
                                  style: TextStyle(fontSize: 28, color: cs.primary, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Positioned(
                                bottom: 0, right: 0,
                                child: GestureDetector(
                                  onTap: _editPersonalInfo,
                                  child: Container(
                                    width: 22, height: 22,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.surface, width: 2),
                                    ),
                                    child: const Icon(Icons.edit, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(_user?.username ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                                ]),
                                Text(_user?.email ?? '', style: TextStyle(color: cs.outline)),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _editJlptLevel,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primary, borderRadius: BorderRadius.circular(4)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('JLPT ${_user?.level ?? 'N5'}',
                                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit, size: 10, color: Colors.white),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(children: [
                    _StatCard(icon: Icons.local_fire_department, color: Colors.orange,
                        label: s.streakDays, value: '${_progress?.streakDays ?? 0}${s.day}'),
                    const SizedBox(width: 8),
                    _StatCard(icon: Icons.timer, color: Colors.blue,
                        label: s.totalMinutes, value: '${_progress?.totalStudyMinutes ?? 0}${s.minute}'),
                    const SizedBox(width: 8),
                    _StatCard(icon: Icons.quiz, color: Colors.purple,
                        label: s.avgScore, value: '${(_progress?.quizStats?.avgScore ?? 0).toStringAsFixed(0)}%'),
                  ]),
                  const SizedBox(height: 16),
                  // SRS stats
                  if (_progress?.srsStats != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.srsCards, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _SrsStatItem(label: s.total, value: '${_progress!.srsStats!.total}'),
                                _SrsStatItem(label: s.graduated, value: '${_progress!.srsStats!.graduated}', color: Colors.green),
                                _SrsStatItem(label: s.inProgress, value: '${_progress!.srsStats!.total - _progress!.srsStats!.graduated}', color: Colors.blue),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_progress!.srsStats!.total > 0)
                              LinearProgressIndicator(
                                value: _progress!.srsStats!.graduated / _progress!.srsStats!.total,
                                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation(Colors.green),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Settings section
                  Text(s.settings, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  // ── 权限状态栏 ──
                  if (Platform.isAndroid && _permissions.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.security_rounded, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('权限管理', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                TextButton.icon(
                                  onPressed: () async {
                                    await openAppSettings();
                                    // 返回后刷新权限状态
                                    Future.delayed(const Duration(milliseconds: 500), _checkPermissions);
                                  },
                                  icon: const Icon(Icons.settings, size: 16),
                                  label: const Text('设置', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _PermChip(icon: Icons.mic, label: '麦克风', granted: _permissions['microphone'] ?? false),
                                _PermChip(icon: Icons.volume_up, label: '扬声器', granted: true),
                                _PermChip(icon: Icons.camera_alt, label: '相机', granted: _permissions['camera'] ?? false),
                                _PermChip(icon: Icons.photo_library, label: '存储/相册', granted: _permissions['storage'] ?? false),
                                _PermChip(icon: Icons.notifications, label: '通知', granted: _permissions['notification'] ?? false),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    child: Column(
                      children: [
                        // TTS 语音测试（放在最前面方便找到）
                        ListTile(
                          leading: const Icon(Icons.record_voice_over_rounded),
                          title: const Text('TTS 语音测试'),
                          subtitle: const Text('检测语音引擎是否可用'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _testTts,
                        ),
                        const Divider(height: 1, indent: 56),
                        // Language switcher
                        ListTile(
                          leading: const Icon(Icons.language_rounded),
                          title: Text(s.language),
                          subtitle: Text(locale.languageCode == 'zh' ? s.langZh : s.langEn),
                          trailing: ToggleButtons(
                            isSelected: [
                              locale.languageCode == 'zh',
                              locale.languageCode == 'en',
                            ],
                            onPressed: (i) {
                              ref.read(localeProvider.notifier).setLocale(
                                i == 0 ? const Locale('zh') : const Locale('en'),
                              );
                            },
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
                            borderRadius: BorderRadius.circular(8),
                            children: const [
                              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('中', style: TextStyle(fontWeight: FontWeight.bold))),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('EN', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.person_outline_rounded),
                          title: const Text('个人信息'),
                          subtitle: Text(_user?.username ?? ''),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _editPersonalInfo,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.school_rounded),
                          title: const Text('JLPT 等级'),
                          subtitle: Text('当前级别：${_user?.level ?? 'N3'}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary, borderRadius: BorderRadius.circular(4)),
                              child: Text(_user?.level ?? 'N3',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ]),
                          onTap: _editJlptLevel,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.bar_chart_rounded),
                          title: Text(s.studyGoal),
                          subtitle: Text(s.dailyGoalFmt.replaceAll('%d', '${_user?.dailyGoalMinutes ?? 15}')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _editGoal,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.notifications_outlined),
                          title: Text(s.notifications),
                          trailing: Switch(
                            value: _notifOverride ?? (_user?.notificationEnabled ?? true),
                            onChanged: _toggleNotification,
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.upload_file_rounded),
                          title: Text(s.ankiImport),
                          subtitle: Text(s.ankiImportSubtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/anki-import'),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(s.changePassword),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _changePassword,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    ),
  );
}

class _SrsStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SrsStatItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ]);
}

class _PermChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool granted;
  const _PermChip({required this.icon, required this.label, required this.granted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: granted ? Colors.green.withValues(alpha: 0.1) : cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted ? Colors.green.withValues(alpha: 0.4) : cs.error.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: granted ? Colors.green : cs.error),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: granted ? Colors.green.shade700 : cs.error)),
          const SizedBox(width: 4),
          Icon(granted ? Icons.check_circle : Icons.cancel, size: 14, color: granted ? Colors.green : cs.error),
        ],
      ),
    );
  }
}
