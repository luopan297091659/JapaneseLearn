import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../../config/app_config.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../providers/app_appearance_provider.dart';
import '../../utils/tts_helper.dart';
import '../../services/plan_reminder_service.dart';
import '../common/legal_webview_page.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with WidgetsBindingObserver {
  UserModel? _user;
  bool _loading = true;
  bool? _notifOverride; // 乐观更新开关状态
  Map<String, bool> _permissions = {};
  double _slowSpeed = 0.5;
  String _appVersion = '';
  bool _checkingUpdate = false;
  Uint8List? _avatarBytes;
  int _reminderHour = 20;
  int _reminderMinute = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(); _checkPermissions(); _loadSlowSpeed(); _loadAppVersion(); _loadReminderTime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  Future<void> _loadSlowSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _slowSpeed = prefs.getDouble('slow_speed') ?? 0.5);
  }

  Future<void> _setSlowSpeed(double v) async {
    final speed = (v * 100).round() / 100.0;
    setState(() => _slowSpeed = speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('slow_speed', speed);
    try {
      await syncService.syncUserPreferences(slowSpeed: speed);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        apiService.getMe(),
        apiService.getProgressSummary(),
      ]);
      final user = results[0] as UserModel;
      final avatarBytes = await _downloadAvatarBytes(user.avatarUrl);
      final prefs = await SharedPreferences.getInstance();
      final remotePreferences = user.preferences;
      if (remotePreferences['slow_speed'] is num) {
        await prefs.setDouble('slow_speed', (remotePreferences['slow_speed'] as num).toDouble());
      }
      if (remotePreferences['locale'] is String) {
        await prefs.setString('app_language', remotePreferences['locale'] as String);
      }
      if (remotePreferences['appearance_mode'] is String) {
        await prefs.setString('app_appearance_mode', remotePreferences['appearance_mode'] as String);
      }
      await prefs.setInt('daily_goal_minutes', user.dailyGoalMinutes);
      await prefs.setBool('notification_enabled', user.notificationEnabled);
      setState(() {
        _user = user;
        _avatarBytes = avatarBytes;
        _slowSpeed = (remotePreferences['slow_speed'] as num?)?.toDouble() ?? _slowSpeed;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<Uint8List?> _downloadAvatarBytes(String? rawUrl) async {
    final url = _avatarAbsoluteUrl(rawUrl);
    if (url == null) return null;
    try {
      final res = await apiService.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkPermissions() async {
    final mic = await Permission.microphone.status;
    final camera = await Permission.camera.status;
    final notification = await Permission.notification.status;
    final media = Platform.isIOS
        ? await Permission.photos.status
        : await Permission.storage.status;
    if (mounted) {
      setState(() {
        _permissions = {
          'microphone': mic.isGranted,
          'camera': camera.isGranted,
          'notification': notification.isGranted,
          'media': media.isGranted,
        };
      });
    }
  }

  Future<void> _logout() async {
    await apiService.logout();
    if (mounted) context.go('/login');
  }

  Future<void> _confirmDeleteAccount() async {
    final passwordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('账户删除'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作将永久删除您的账户及所有数据，包括学习进度、SRS卡片、测验记录等，且不可恢复。'),
            const SizedBox(height: 16),
            const Text('请输入密码确认：'),
            const SizedBox(height: 8),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '输入密码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final password = passwordCtrl.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入密码'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    try {
      await apiService.deleteAccount(password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('账户已删除')),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('401') ? '密码不正确' : '删除失败，请重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  String? _avatarAbsoluteUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${AppConfig.serverRoot}$raw';
  }

  Future<void> _editAvatar() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null || path.isEmpty) return;

      final editedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _AvatarEditorDialog(file: File(path)),
      );
      if (editedBytes == null) return;

      final user = await apiService.uploadAvatarBytes(
        editedBytes,
        fileName: 'avatar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (!mounted) return;
      setState(() {
        _user = user;
        _avatarBytes = editedBytes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像上传失败：$e')),
      );
    }
  }

  String _memberPlanLabel(String? plan) {
    const labels = {
      'monthly': '月度会员',
      'yearly': '年度会员',
      'lifetime': '终身会员',
    };
    return labels[plan] ?? plan ?? '标准会员';
  }

  // ── 学习目标 ───────────────────────────────────────────────────
  Future<void> _editGoal() async {
    final current = _user?.dailyGoalMinutes ?? 15;
    int selected = current;
    const presets = [5, 15, 30, 60, 90, 120];
    // 确保 selected 是合法值
    if (!presets.contains(selected)) {
      selected = presets.reduce((a, b) => (a - selected).abs() < (b - selected).abs() ? a : b);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final idx = presets.indexOf(selected);
          return AlertDialog(
            title: const Text('学习目标'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('每日学习目标：$selected 分钟',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Slider(
                  value: idx.toDouble(),
                  min: 0, max: (presets.length - 1).toDouble(),
                  divisions: presets.length - 1,
                  label: '$selected 分钟',
                  onChanged: (v) => setSt(() => selected = presets[v.round()]),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: presets.map((m) => GestureDetector(
                    onTap: () => setSt(() => selected = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          );
        },
      ),
    );
    if (confirmed == true && selected != current) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('daily_goal_minutes', selected);
        await apiService.updateProfile(dailyGoalMinutes: selected);
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  // ── 学习提醒 ─────────────────────────────────────────────────
  Future<void> _loadReminderTime() async {
    final t = await PlanReminderService.instance.getReminderTime();
    if (mounted) setState(() { _reminderHour = t.hour; _reminderMinute = t.minute; });
  }

  Future<void> _toggleNotification(bool value) async {
    setState(() => _notifOverride = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_enabled', value);
      await apiService.updateProfile(notificationEnabled: value);
      if (value) {
        await PlanReminderService.instance.scheduleDailyReminder(
          planName: '学习计划',
          hour: _reminderHour,
          minute: _reminderMinute,
        );
      } else {
        await PlanReminderService.instance.cancelDailyReminder();
      }
    } catch (e) {
      setState(() => _notifOverride = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
      helpText: '选择每日提醒时间',
    );
    if (picked == null || !mounted) return;
    setState(() { _reminderHour = picked.hour; _reminderMinute = picked.minute; });
    await PlanReminderService.instance.saveReminderTime(hour: picked.hour, minute: picked.minute);
    final enabled = _notifOverride ?? (_user?.notificationEnabled ?? true);
    if (enabled) {
      await PlanReminderService.instance.scheduleDailyReminder(
        planName: '学习计划',
        hour: picked.hour,
        minute: picked.minute,
      );
    }
  }

  int _compareVersions(String current, String latest) {
    List<int> parse(String input) {
      final normalized = input.split('+').first.trim();
      return normalized.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }

    final left = parse(current);
    final right = parse(latest);
    final maxLen = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLen; i++) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  Future<void> _checkAppUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final latest = await apiService.getLatestPublishedAppRelease(
        platform: Platform.isAndroid ? 'android' : 'ios',
      );
      final latestVersion = latest['version'] as String? ?? '';
      final changelog = latest['changelog'] as String? ?? '';
      final rawDownloadUrl = latest['download_url'] as String? ?? '';
      final downloadUrl = rawDownloadUrl.startsWith('http')
          ? rawDownloadUrl
          : '${AppConfig.serverRoot}$rawDownloadUrl';
      final currentVersion = _appVersion.split('+').first;
      final needUpdate = latestVersion.isNotEmpty && _compareVersions(currentVersion, latestVersion) < 0;

      if (!mounted) return;

      if (!needUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_appVersion.isEmpty ? '当前已是最新版本' : '当前已是最新版本（$_appVersion）')),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本：${_appVersion.isEmpty ? currentVersion : _appVersion}'),
              const SizedBox(height: 6),
              Text('最新版本：$latestVersion'),
              if (changelog.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('更新内容', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(changelog, style: const TextStyle(fontSize: 13, height: 1.5)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后再说')),
            FilledButton(
              onPressed: () async {
                Uri? uri;
                if (Platform.isIOS) {
                  // 优先使用服务端返回的下载地址（App Store链接）
                  if (downloadUrl.contains('apps.apple.com') || downloadUrl.contains('itunes.apple.com')) {
                    uri = Uri.parse(downloadUrl);
                  }
                } else {
                  uri = Uri.parse(downloadUrl);
                }
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('请在 App Store 中搜索「言旅」进行更新')),
                    );
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('立即升级'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查更新失败，请检查网络后重试'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
        }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败：$e'), behavior: SnackBarBehavior.floating));
        }
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
      try { await TtsHelper.setJapaneseVoice(tts); } catch (_) {}
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
                if (!speakSuccess && Platform.isAndroid) ...[
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
                if (!speakSuccess && Platform.isIOS) ...[
                  const Divider(height: 24),
                  const Text('提示：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text('请前往 设置 → 辅助功能 → 朗读内容 → 声音，下载日语语音包。', style: TextStyle(fontSize: 13)),
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('密码已更新！请重新登录'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  }
                  await apiService.logout();
                  if (mounted) context.go('/login');
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('修改失败：当前密码不正确或网络错误'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  }
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
    final appearance = ref.watch(appAppearanceProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(s.profile),
        actions: [
          FutureBuilder<int>(
            future: apiService.getNotificationUnreadCount(),
            builder: (ctx, snap) {
              final unread = snap.data ?? 0;
              return IconButton(
                tooltip: '消息通知',
                onPressed: () async {
                  await context.push('/notifications');
                  if (mounted) setState(() {});
                },
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (unread > 0)
                      Positioned(
                        right: -4, top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
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
                  // ── 个人信息卡片 ──
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        children: [
                          // 头像 + 用户名 + 邮箱
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: _editAvatar,
                                child: CircleAvatar(
                                  radius: 38,
                                  backgroundColor: cs.primaryContainer,
                                  backgroundImage: (_avatarBytes != null)
                                    ? MemoryImage(_avatarBytes!)
                                      : null,
                                  child: (_avatarBytes == null)
                                      ? Text(
                                          _user?.username.substring(0, 1).toUpperCase() ?? 'U',
                                          style: TextStyle(fontSize: 30, color: cs.primary, fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                              ),
                              Positioned(
                                bottom: 0, right: 0,
                                child: GestureDetector(
                                  onTap: _editAvatar,
                                  child: Container(
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.surface, width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _user?.username ?? '',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _user?.email ?? '',
                            style: TextStyle(fontSize: 13, color: cs.outline),
                          ),
                          const SizedBox(height: 12),
                          // 标签行：JLPT + 会员
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _editJlptLevel,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text('JLPT ${_user?.level ?? 'N5'}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.edit, size: 10, color: Colors.white),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => context.push('/membership', extra: _user?.isMember ?? false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _user?.isMember == true
                                        ? const Color(0xFFF59E0B)
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(
                                      _user?.isMember == true ? '👑 会员' : '免费用户',
                                      style: TextStyle(
                                        color: _user?.isMember == true ? Colors.white : cs.outline,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(Icons.chevron_right, size: 14,
                                      color: _user?.isMember == true ? Colors.white : cs.outline),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // ── 会员入口横幅（嵌入卡片底部）──
                          GestureDetector(
                            onTap: () => context.push('/membership', extra: _user?.isMember ?? false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _user?.isMember == true
                                      ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                                      : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.workspace_premium, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _user?.isMember == true
                                          ? '${_memberPlanLabel(_user?.membershipPlan)} · 查看权益'
                                          : '升级会员，解锁全部功能 →',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios_rounded,
                                      color: Colors.white.withValues(alpha: 0.7), size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Settings section
                  Text(s.settings, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  // ── 权限状态栏 ──
                  if (_permissions.isNotEmpty) ...[
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
                                _PermChip(
                                  icon: Icons.photo_library,
                                  label: Platform.isIOS ? '相册' : '存储/相册',
                                  granted: _permissions['media'] ?? false,
                                ),
                                _PermChip(icon: Icons.notifications, label: '通知', granted: _permissions['notification'] ?? false),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ── 邀请码卡片 ──
                  if (_user?.inviteCode != null) ...[
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.card_giftcard_rounded, size: 20, color: cs.primary),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('我的邀请码', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              Text('已邀请 ${_user!.inviteCount} 人', style: TextStyle(fontSize: 13, color: cs.outline)),
                            ]),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                final code = _user!.inviteCode!;
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('邀请码 $code 已复制'), behavior: SnackBarBehavior.floating),
                                );
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(
                                      _user!.inviteCode!,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 4,
                                        color: cs.primary,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.copy_rounded, size: 20, color: cs.primary),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('分享邀请码给好友，注册时填写即可', style: TextStyle(fontSize: 12, color: cs.outline)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
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
                          leading: const Icon(Icons.palette_rounded),
                          title: const Text('界面模式'),
                          subtitle: Text(
                            appearance == AppAppearanceMode.anime ? '蓝调模式' : '经典模式',
                          ),
                          trailing: ToggleButtons(
                            isSelected: [
                              appearance == AppAppearanceMode.classic,
                              appearance == AppAppearanceMode.anime,
                            ],
                            onPressed: (i) {
                              ref.read(appAppearanceProvider.notifier).setMode(
                                i == 0 ? AppAppearanceMode.classic : AppAppearanceMode.anime,
                              );
                            },
                            constraints: const BoxConstraints(minWidth: 52, minHeight: 34),
                            borderRadius: BorderRadius.circular(8),
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('经典', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('蓝调', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
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
                          subtitle: (_notifOverride ?? (_user?.notificationEnabled ?? true))
                              ? Text('每天 ${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')} 提醒',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary))
                              : null,
                          trailing: Switch(
                            value: _notifOverride ?? (_user?.notificationEnabled ?? true),
                            onChanged: _toggleNotification,
                          ),
                          onTap: (_notifOverride ?? (_user?.notificationEnabled ?? true)) ? _pickReminderTime : null,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.slow_motion_video_rounded, color: Theme.of(context).colorScheme.primary),
                          title: const Text('慢放速度'),
                          subtitle: Row(
                            children: [
                              const Text('0.2x', style: TextStyle(fontSize: 11)),
                              Expanded(
                                child: Slider(
                                  value: _slowSpeed.clamp(0.2, 0.8),
                                  min: 0.2,
                                  max: 0.8,
                                  divisions: 12,
                                  label: '${_slowSpeed}x',
                                  onChanged: _setSlowSpeed,
                                ),
                              ),
                              const Text('0.8x', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text('${_slowSpeed}x',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary)),
                            ],
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(s.changePassword),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _changePassword,
                        ),
                        const Divider(height: 1, indent: 56),
                        // TTS 语音测试
                        ListTile(
                          leading: const Icon(Icons.record_voice_over_rounded),
                          title: const Text('TTS 语音测试'),
                          subtitle: const Text('检测语音引擎是否可用'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _testTts,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.system_update_rounded, color: Theme.of(context).colorScheme.primary),
                          title: const Text('检查更新'),
                          subtitle: Text(_appVersion.isEmpty ? '检查是否有新版本可升级' : '当前版本 $_appVersion'),
                          trailing: _checkingUpdate
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: _checkingUpdate ? null : _checkAppUpdate,
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                          title: Text('账户删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          subtitle: const Text('永久删除账户及所有数据'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _confirmDeleteAccount,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _legalLink(context, '《用户协议》', '${AppConfig.serverRoot}/app/terms.html'),
                        _legalLink(context, '《隐私政策》', '${AppConfig.serverRoot}/app/privacy.html'),
                        _legalLink(context, '《退款政策》', '${AppConfig.serverRoot}/app/refund.html'),
                        _legalLink(context, '《特定商取引法》', '${AppConfig.serverRoot}/app/tokusho.html'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _legalLink(BuildContext context, String label, String url) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LegalWebViewPage(title: label.replaceAll('《', '').replaceAll('》', ''), url: url),
      )),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _AvatarEditorDialog extends StatefulWidget {
  final File file;
  const _AvatarEditorDialog({required this.file});

  @override
  State<_AvatarEditorDialog> createState() => _AvatarEditorDialogState();
}

class _AvatarEditorDialogState extends State<_AvatarEditorDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.value = Matrix4.identity()..scale(1.2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('渲染失败');
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('截图失败');
      if (!mounted) return;
      Navigator.pop(context, byteData.buffer.asUint8List());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像处理失败：$e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxCropSize = MediaQuery.of(context).size.width - 88;
    final cropSize = maxCropSize.clamp(220.0, 280.0);
    return AlertDialog(
      title: const Text('编辑头像'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _repaintKey,
            child: ClipOval(
              child: Container(
                width: cropSize,
                height: cropSize,
                color: Colors.black12,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: SizedBox(
                    width: cropSize,
                    height: cropSize,
                    child: Image.file(widget.file, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('双指缩放和拖动位置后保存', style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.cloud_upload_rounded),
          label: Text(_saving ? '上传中' : '保存头像'),
        ),
      ],
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
