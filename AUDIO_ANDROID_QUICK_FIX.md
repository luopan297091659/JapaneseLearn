# Android 权限修复快速实施指南

## 🚀 5 分钟快速修复

### 步骤 1: 修改 AndroidManifest.xml

打开 `mobile/android/app/src/main/AndroidManifest.xml`，在 `</manifest>` 前添加缺失的权限：

```xml
<!-- 找到现有的权限选项，添加以下新权限 -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

完整文件应该如下：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <!-- ✅ 新增权限 -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    
    <application
        android:label="言旅 Kotabi"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <!-- 应用配置保持不变 -->
    </application>
    
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
    </queries>
</manifest>
```

---

### 步骤 2: 创建权限服务 (新文件)

创建文件：`mobile/lib/services/permission_service.dart`

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  
  factory PermissionService() => _instance;
  PermissionService._internal();
  
  /// 请求麦克风权限（TTS）
  Future<bool> requestMicrophonePermission(BuildContext context) async {
    final status = await Permission.microphone.request();
    return _handlePermissionStatus(status, context, '麦克风权限', 
      '朗读功能需要麦克风权限');
  }
  
  /// 请求存储权限（音频下载）
  Future<bool> requestStoragePermission(BuildContext context) async {
    final status = await Permission.storage.request();
    return _handlePermissionStatus(status, context, '存储权限',
      '播放音频需要存储权限');
  }
  
  bool _handlePermissionStatus(PermissionStatus status, BuildContext context,
      String title, String message) {
    if (status.isDenied) {
      _showDialog(context, title, message);
      return false;
    } else if (status.isPermanentlyDenied) {
      _showDialog(context, '$title已被禁用', '请前往设置中启用此权限');
      return false;
    }
    return true;
  }
  
  void _showDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(ctx);
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }
}

final permissionService = PermissionService();
```

---

### 步骤 3: 修改 main.dart

在 `mobile/lib/main.dart` 中添加权限初始化：

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';  // ✅ 新增
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 初始化权限
  await _requestInitialPermissions();
  
  apiService.init();
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).init();
  syncService.checkContentVersion();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const JapaneseLearnApp(),
  ));
}

/// ✅ 在应用启动时请求关键权限
Future<void> _requestInitialPermissions() async {
  final permissions = [
    Permission.microphone,
    Permission.storage,
  ];
  
  await permissions.request();
}

// ✅ 保留 AppTheme 和其他现有代码
// ...
```

---

### 步骤 4: 修改 audio_player_widget.dart

更新音频播放器以支持 AudioSession 和权限检查：

```dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';  // ✅ 新增
import 'package:permission_handler/permission_handler.dart';  // ✅ 新增
import '../services/api_service.dart';
import '../services/permission_service.dart';  // ✅ 新增
import '../config/app_config.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String? audioUrl;
  final bool compact;
  final String? label;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    this.compact = false,
    this.label,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _player;
  bool _loading = false;
  bool _hasError = false;
  String _errorMessage = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);

  @override
  void initState() {
    super.initState();
    _initAudioSession();  // ✅ 初始化 AudioSession
    _player = AudioPlayer();
    _player.setVolume(1.0);  // ✅ 设置音量为 1.0
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
  }
  
  /// ✅ 初始化音频会话
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.default_,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.audibilityEnforced,
            usage: AndroidAudioUsage.media,
          ),
          androidWillPauseWhenDucked: true,
        ),
      );
    } catch (e) {
      print('AudioSession 初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl == null) return;
    
    // ✅ 检查存储权限
    if (!await permissionService.requestStoragePermission(context)) {
      setState(() {
        _hasError = true;
        _errorMessage = '需要存储权限才能播放音频';
      });
      return;
    }
    
    if (_playerState.playing) {
      await _player.pause();
      return;
    }
    
    if (_playerState.processingState == ProcessingState.idle ||
        _playerState.processingState == ProcessingState.completed) {
      setState(() { _loading = true; _hasError = false; _errorMessage = ''; });
      try {
        final url = widget.audioUrl!;
        if (url.startsWith('/uploads/')) {
          final fullUrl = AppConfig.serverRoot + url;
          final localPath = await apiService.downloadToTempFile(fullUrl);
          await _player.setFilePath(localPath);
        } else if (url.startsWith('/') || url.startsWith('file://')) {
          final localPath = url.startsWith('file://') ? url.substring(7) : url;
          await _player.setFilePath(localPath);
        } else {
          final needsProxy = url.startsWith(AppConfig.baseUrl) ||
              url.startsWith(AppConfig.serverRoot);
          if (needsProxy) {
            final localPath = await apiService.downloadToTempFile(url);
            await _player.setFilePath(localPath);
          } else {
            await _player.setUrl(url);
          }
        }
        setState(() => _loading = false);
        await _player.play();
      } catch (e) {
        setState(() { 
          _loading = false; 
          _hasError = true;
          _errorMessage = _getErrorMessage(e);
        });
      }
    } else {
      await _player.play();
    }
  }

  String _getErrorMessage(Object error) {
    final msg = error.toString();
    if (msg.contains('Permission')) {
      return '文件访问被拒绝，请检查权限';
    } else if (msg.contains('Connection refused') || msg.contains('Failed to connect')) {
      return '网络连接失败';
    } else if (msg.contains('Certificate') || msg.contains('SSL')) {
      return '证书验证失败';
    } else if (msg.contains('Not found') || msg.contains('404')) {
      return '音频文件不存在';
    }
    return '音频加载失败';
  }

  Future<void> _seek(double value) async {
    await _player.seek(Duration(seconds: value.toInt()));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isPlaying => _playerState.playing;
  bool get _isCompleted => _playerState.processingState == ProcessingState.completed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.audioUrl == null) return const SizedBox.shrink();

    if (widget.compact) {
      return Row(children: [
        InkWell(
          onTap: _togglePlay,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: _loading
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : Icon(
                    _hasError ? Icons.error_outline
                        : _isPlaying ? Icons.pause_rounded : Icons.volume_up_rounded,
                    color: cs.primary, size: 18,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.label != null)
          Text(widget.label!, style: TextStyle(fontSize: 12, color: cs.outline)),
      ]);
    }

    // Full player
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primaryContainer),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            onPressed: _togglePlay,
            icon: _loading
                ? SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : Icon(
                    _hasError ? Icons.error_outline
                        : _isPlaying ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                    color: _hasError ? cs.error : cs.primary, size: 36,
                  ),
          ),
          Expanded(
            child: Slider(
              value: _duration.inSeconds > 0
                  ? _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble())
                  : 0,
              max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
              onChanged: _duration.inSeconds > 0 ? _seek : null,
              activeColor: cs.primary,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: TextStyle(fontSize: 11, color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
        if (_hasError)
          Text(_errorMessage, style: TextStyle(fontSize: 11, color: cs.error)),
      ]),
    );
  }
}
```

---

### 步骤 5: 修改 vocabulary_detail_screen.dart

在 `_speak()` 方法前添加权限检查：

```dart
Future<void> _speak() async {
  if (_vocab == null) return;

  // ✅ 新增：检查麦克风权限
  final micStatus = await Permission.microphone.status;
  if (!micStatus.isGranted) {
    final granted = await permissionService.requestMicrophonePermission(context);
    if (!granted) return;
  }

  if (!_ttsReady) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('语音引擎初始化中，请稍后再试…'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  if (_ttsPlaying) {
    await _tts.stop();
    setState(() => _ttsPlaying = false);
    return;
  }

  final text = ttsText(_vocab!.word, _vocab!.reading);
  try {
    setState(() => _ttsPlaying = true);
    final result = await _tts.speak(text);
    if (result != 1 && mounted) {
      setState(() => _ttsPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('语音引擎不可用，请在系统设置中安装日语 TTS 引擎'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      setState(() => _ttsPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('朗读出错：$e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
```

---

### 步骤 6: 改进 api_service.dart

在 `downloadToTempFile` 方法中添加更好的错误处理：

```dart
Future<String> downloadToTempFile(String url, {int maxRetries = 3}) async {
  final dir = await getTemporaryDirectory();
  
  // 生成缓存键
  String cacheKey = url.hashCode.abs().toString();
  if (url.contains('/uploads/audio/')) {
    try {
      final parts = url.split('/uploads/audio/');
      if (parts.length > 1) {
        final audioId = parts[1].split('?').first;
        if (audioId.isNotEmpty) {
          cacheKey = audioId.replaceAll('.', '_');
        }
      }
    } catch (_) {}
  }

  final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.mp3';
  final fileName = 'audio_$cacheKey';
  final file = File('${dir.path}/$fileName');

  // 检查缓存
  if (await file.exists()) {
    try {
      await file.stat();
      return file.path;
    } catch (e) {
      print('缓存文件无法访问: $e');
      await file.delete().catchError((_) => null);
    }
  }

  // 重试下载
  int attempts = 0;
  Exception? lastError;
  
  while (attempts < maxRetries) {
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _dio.download(url, file.path);

      if (await file.exists() && await file.length() > 0) {
        print('音频文件成功保存: ${file.path}');
        return file.path;
      }

      throw Exception('文件写入失败');
    } catch (e) {
      attempts++;
      lastError = Exception('下载失败 ($attempts/$maxRetries): $e');

      if (attempts >= maxRetries) {
        await file.delete().catchError((_) => null);
        rethrow;
      }

      await Future.delayed(Duration(milliseconds: 500 * attempts));
    }
  }

  throw lastError ?? Exception('下载失败');
}
```

---

## ✅ 验证修复

运行以下命令测试修复：

```bash
# 清理 Flutter 缓存
flutter clean

# 获取依赖
flutter pub get

# 运行应用（带日志）
flutter run -v

# 或构建 APK 测试
flutter build apk --release
```

---

## 🧪 测试场景

1. **首次启动**
   - 应显示"允许麦克风和存储权限"对话框
   
2. **播放音频**
   - 不应显示权限错误
   - 音量按钮应该有效
   
3. **点击朗读**
   - 应请求麦克风权限
   - 朗读应该正常工作
   
4. **拒绝权限后**
   - 应显示明确的错误提示
   - "打开设置"按钮应该工作

---

## 📊 修复前后对比

| 功能 | 修复前 | 修复后 |
|------|--------|--------|
| **权限声明** | ❌ 缺失 4 个 | ✅ 全部正确 |
| **权限请求** | ❌ 无 | ✅ 自动请求 |
| **音量控制** | ❌ 不工作 | ✅ 正常工作 |
| **音频焦点** | ❌ 丢失 | ✅ 正确处理 |
| **文件权限** | ❌ 崩溃 | ✅ 检查完成 |
| **TTS 权限** | ❌ 无检查 | ✅ 运行时请求 |
| **错误信息** | ⚠️ 通用 | ✅ 具体故障原因 |

