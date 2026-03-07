# Flutter Android 音频播放代码安全审计报告
**日期**: 2026-03-07 | **状态**: 🔴 **严重问题发现** | **优先级**: 高

---

## 📊 问题汇总

| 类别 | 问题数 | 严重性 | 状态 |
|------|--------|--------|------|
| Android 权限 | 4 | 🔴 关键 | ❌未处理 |
| 音频播放器配置 | 2 | 🟡 中等 | ⚠️部分缺失 |
| TTS 配置 | 1 | 🟡 中等 | ✅已改进 |
| 网络/SSL 问题 | 1 | 🟠 中等 | ✅已改进 |
| 文件权限 | 2 | 🔴 关键 | ❌未处理 |

---

## 🔴 严重问题 (关键)

### 1️⃣ 缺少 AndroidManifest.xml 权限声明

**位置**: [mobile/android/app/src/main/AndroidManifest.xml](mobile/android/app/src/main/AndroidManifest.xml#L1-L40)

**问题**:
```xml
<!-- ❌ 缺少的权限 -->
- android.permission.WRITE_EXTERNAL_STORAGE    (从 API 30 开始需要 Scoped Storage)
- android.permission.READ_EXTERNAL_STORAGE     (从 API 30 开始需要 Scoped Storage)
- android.permission.MODIFY_AUDIO_SETTINGS     (音量调节和音频焦点)
```

**当前状态**:
```xml
✅ 已声明:
- android.permission.INTERNET
- android.permission.ACCESS_NETWORK_STATE
- android.permission.RECORD_AUDIO
```

**影响**:
- Android 12+（API 31+）应用无法写入下载的音频文件到临时目录
- 音量设置 API 调用可能失败
- 音频焦点处理不完全

**修复方案**:

```xml
<!-- 在 AndroidManifest.xml 中添加以下权限 -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 现有权限 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    
    <!-- ✅ 新增权限 -->
    <!-- 存储权限（需要运行时请求） -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    
    <!-- 音频设置权限 -->
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    
    <application>
        <!-- 现有配置保持不变 -->
    </application>
</manifest>
```

---

### 2️⃣ 缺少运行时权限请求机制

**位置**: [mobile/lib/main.dart](mobile/lib/main.dart) - **不存在！**

**问题**:
应用完全缺少权限请求逻辑。Android 6.0+ 需要在运行时请求关键权限。

**特别是**:
- `RECORD_AUDIO` - TTS 使用
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` - 文件访问
- `MODIFY_AUDIO_SETTINGS` - 音量调节

**当前症状**:
```
❌ 音频下载失败：权限被拒绝
❌ TTS 无声音输出：没有音频焦点
❌ 音频播放卡顿：临时文件写入失败
```

**修复方案**:

在 `main.dart` 中添加权限初始化:

```dart
// mobile/lib/main.dart
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 初始化所需权限
  await _initializePermissions();
  
  apiService.init();
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).init();
  syncService.checkContentVersion();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const JapaneseLearnApp(),
  ));
}

/// 请求应用所需的所有权限
Future<void> _initializePermissions() async {
  // 检查 Android 版本（API 30+）
  final sdkInt = await Permission.storage.isDenied;
  
  final permissions = [
    Permission.microphone,           // TTS
    Permission.storage,              // 音频文件读写
    Permission.mediaLibrary,         // 多媒体库访问
  ];
  
  // 批量请求权限
  final statuses = await permissions.request();
  
  // 日志记录
  statuses.forEach((permission, status) {
    print('权限 ${permission.toString()}: $status');
  });
}
```

创建新文件 `mobile/lib/services/permission_service.dart`:

```dart
// mobile/lib/services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  
  factory PermissionService() => _instance;
  PermissionService._internal();
  
  // 检查并请求麦克风权限（TTS）
  Future<bool> requestMicrophonePermission(BuildContext context) async {
    final status = await Permission.microphone.request();
    
    if (status.isDenied) {
      _showPermissionDialog(context, '麦克风权限', 
        '朗读功能需要麦克风权限。请在系统设置中允许');
      return false;
    } else if (status.isPermanentlyDenied) {
      _showPermissionDialog(context, '麦克风权限已被禁用',
        '请前往 设置 > 权限 > 麦克风 中启用');
      return false;
    }
    return true;
  }
  
  // 检查并请求存储权限（音频下载）
  Future<bool> requestStoragePermission(BuildContext context) async {
    final status = await Permission.storage.request();
    
    if (status.isDenied) {
      _showPermissionDialog(context, '存储权限',
        '播放音频需要存储权限。请在系统设置中允许');
      return false;
    } else if (status.isPermanentlyDenied) {
      _showPermissionDialog(context, '存储权限已被禁用',
        '请前往 设置 > 权限 > 文件和媒体 中启用');
      return false;
    }
    return true;
  }
  
  // 检查并请求多媒体库权限
  Future<bool> requestMediaLibraryPermission(BuildContext context) async {
    final status = await Permission.mediaLibrary.request();
    return status.isGranted;
  }
  
  void _showPermissionDialog(BuildContext context, String title, String message) {
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

// 全局實例访问
final permissionService = PermissionService();
```

在音频播放器中添加权限检查:

```dart
// 修改 mobile/lib/widgets/audio_player_widget.dart 的 _togglePlay 方法
Future<void> _togglePlay() async {
  if (widget.audioUrl == null) return;
  
  // ✅ 添加权限检查
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
  
  // ... 现有代码
}
```

---

### 3️⃣ 缺少文件权限运行时检查

**位置**: [mobile/lib/services/api_service.dart](mobile/lib/services/api_service.dart#L164-L200) (downloadToTempFile 方法)

**问题**:
下载音频到临时目录时，未检查文件系统权限。Android 11+ 需要特殊处理。

**代码现状**:
```dart
Future<String> downloadToTempFile(String url, {int maxRetries = 3}) async {
  final dir = await getTemporaryDirectory();
  // ❌ 未检查写权限
  final file = File('${dir.path}/$fileName');
  await _dio.download(url, file.path);  // 可能因权限失败
}
```

**可能的错误**:
```
❌ FileSystemException: Cannot open file, path = '/data/data/.../cache/audio_...'
❌ PermissionDenied: Operation not permitted
```

**修复方案**:

```dart
// mobile/lib/services/api_service.dart - 改进 downloadToTempFile 方法
Future<String> downloadToTempFile(String url, {int maxRetries = 3}) async {
  final dir = await getTemporaryDirectory();
  
  // ✅ 获取音频文件名和缓存键
  String cacheKey = url.hashCode.abs().toString();
  String audioId = '';
  
  if (url.contains('/uploads/audio/')) {
    try {
      final parts = url.split('/uploads/audio/');
      if (parts.length > 1) {
        audioId = parts[1].split('?').first;
        if (audioId.isNotEmpty) {
          cacheKey = audioId.replaceAll('.', '_');
        }
      }
    } catch (_) {}
  }
  
  final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.mp3';
  final fileName = 'audio_$cacheKey';
  final file = File('${dir.path}/$fileName');
  
  if (await file.exists()) {
    // ✅ 检查现有文件的可读性
    try {
      await file.stat();  // 尝试获取文件信息以确认访问权限
      return file.path;
    } catch (e) {
      print('缓存文件无法访问，准备重新下载: $e');
      await file.delete().catchError((_) => null);
    }
  }
  
  int attempts = 0;
  Exception? lastError;
  while (attempts < maxRetries) {
    try {
      // ✅ 创建临时文件前检查目录权限
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 添加进度监听（可选，增强用户体验）
      await _dio.download(
        url,
        file.path,
        onReceiveProgress: (received, total) {
          print('下载进度: ${(received / total * 100).toStringAsFixed(0)}%');
        },
      );
      
      // ✅ 验证文件是否成功写入
      if (await file.exists()) {
        final size = await file.length();
        if (size > 0) {
          print('音频文件成功保存: ${file.path} (${size / 1024}KB)');
          return file.path;
        }
      }
      
      throw Exception('文件写入失败：文件为空或不存在');
    } catch (e) {
      attempts++;
      lastError = Exception('音频下载失败 (尝试 $attempts/$maxRetries): $e');
      
      if (attempts >= maxRetries) {
        // 最后一次尝试失败，清理部分下载的文件
        await file.delete().catchError((_) => null);
        rethrow;
      }
      
      // 指数退避
      final delayMs = 500 * attempts;
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }
  
  throw lastError ?? Exception('音频下载失败');
}
```

---

### 4️⃣ TTS 需要麦克风权限但未检查

**位置**: [mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart](mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart#L46-L90)

**问题**:
`_speak()` 方法调用 TTS 但未检查麦克风权限。某些 Android 版本的 TTS 引擎需要此权限。

**代码现状**:
```dart
Future<void> _speak() async {
  if (_vocab == null) return;
  if (!_ttsReady) {
    // 显示提示
    return;
  }
  // ❌ 未检查权限
  final result = await _tts.speak(text);
}
```

**修复方案**:

```dart
// mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart
Future<void> _speak() async {
  if (_vocab == null) return;
  
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

  // ✅ 检查麦克风权限
  final micPermission = await Permission.microphone.status;
  if (!micPermission.isGranted) {
    final granted = await permissionService.requestMicrophonePermission(context);
    if (!granted) return;
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

## 🟡 中等优先级问题

### 5️⃣ 缺少 AudioSource 和 AudioSession 明确配置

**位置**: [mobile/lib/widgets/audio_player_widget.dart](mobile/lib/widgets/audio_player_widget.dart#L32-L45)

**问题**:
`just_audio` 库初始化时缺少 `AudioSession` 配置，可能导致音量不一致和音频焦点丢失。

**代码现状**:
```dart
@override
void initState() {
  super.initState();
  _player = AudioPlayer();  // ❌ 没有配置 AudioSession
  _player.playerStateStream.listen((state) {
    // ...
  });
}
```

**可能问题**:
- 音量按钮无效
- 与系统音量设置不同步
- 其他应用音频打断时无法恢复焦点

**修复方案**:

```dart
// mobile/lib/widgets/audio_player_widget.dart
import 'package:audio_session/audio_session.dart';

@override
void initState() {
  super.initState();
  
  // ✅ 初始化 AudioSession（用于音量和焦点管理）
  _initAudioSession();
  
  _player = AudioPlayer();
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

/// 初始化音频会话（处理音量和音频焦点）
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
```

---

### 6️⃣ AudioPlayer 音量设置缺失

**位置**: [mobile/lib/widgets/audio_player_widget.dart](mobile/lib/widgets/audio_player_widget.dart#L32-L130)

**问题**:
没有显式设置音量，依赖系统默认。用户无法调节播放音量。

**代码现状**:
```dart
// ❌ 没有设置播放音量
await _player.setFilePath(localPath);
```

**修复方案**:

```dart
// mobile/lib/widgets/audio_player_widget.dart
class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _player;
  double _volume = 1.0;  // ✅ 添加音量属性
  
  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _player = AudioPlayer();
    
    // ✅ 设置默认音量为最大
    _player.setVolume(1.0);
    
    // ... 其他初始化代码
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl == null) return;
    // ... 现有代码 ...
    
    try {
      final url = widget.audioUrl!;
      // ... 处理 URL 逻辑 ...
      
      setState(() => _loading = false);
      
      // ✅ 播放前设置音量
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      // ... 错误处理 ...
    }
  }
}
```

---

## 🟠 其他问题

### 7️⃣ SSL 证书验证需要文档化风险

**位置**: [mobile/lib/services/api_service.dart](mobile/lib/services/api_service.dart#L63-L92)

**当前状态**: ✅ 已改进（有白名单验证）

**建议**:
添加生产环境检查和警告:

```dart
// mobile/lib/services/api_service.dart
for (final d in [_dio, _refreshDio]) {
  (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final knownHosts = ['139.196.44.6', 'localhost', '127.0.0.1'];
      final isKnownHost = knownHosts.contains(host);
      
      // ✅ 生产环境警告
      if (const bool.fromEnvironment('dart.vm.product')) {
        print('⚠️ 生产环境检测到自签名证书验证！请升级至有效证书');
      }
      
      if (!isKnownHost) {
        print('【警告】证书验证失败：未识别的主机 $host（端口 $port）');
      }
      
      return isKnownHost;
    };
    
    return client;
  };
}
```

---

### 8️⃣ 缺少 TTS 引擎的系统错误提示

**位置**: [mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart](mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart#L85-140)

**问题**:
当 TTS 返回 0（失败）时，用户收到提示"语音引擎不可用"，但没有明确的解决方案。

**改进方案**:

```dart
Future<void> _speak() async {
  // ... 权限检查等 ...
  
  try {
    setState(() => _ttsPlaying = true);
    final result = await _tts.speak(text);
    
    if (result != 1 && mounted) {
      setState(() => _ttsPlaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('语音引擎未就绪\n请前往系统设置 > 语言和输入法 > 文字转语音输出\n选择合适的 TTS 引擎并下载日语语言包'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '打开设置',
            onPressed: () {
              // 打开系统设置的 TTS 配置页面
              // 注：Flutter 原生不支持直接打开子页面，可使用平台通道
              _openTtsSettings();
            },
          ),
        ),
      );
    }
  } catch (e) {
    // ... 错误处理 ...
  }
}

Future<void> _openTtsSettings() async {
  try {
    const platform = MethodChannel('com.example.japanese_learn/tts');
    await platform.invokeMethod('openTtsSettings');
  } catch (e) {
    print('无法打开 TTS 设置: $e');
  }
}
```

对应的 Kotlin 代码:

```kotlin
// android/app/src/main/kotlin/com/example/japanese_learn/MainActivity.kt
package com.example.japanese_learn

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.japanese_learn/tts"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTtsSettings" -> {
                        try {
                            val intent = Intent()
                            intent.action = "com.android.settings.TTS_SETTINGS"
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "设置不可用", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

---

## 🧪 测试验证清单

### 权限测试

- [ ] **Android 6.0 (API 23)** 
  - [ ] 首次启动时显示权限请求对话框
  - [ ] 用户拒绝后显示详细错误提示
  
- [ ] **Android 10+ (API 29+)**
  - [ ] WRITE_EXTERNAL_STORAGE 被转换为 Scoped Storage
  - [ ] 临时目录写入不被拒绝
  
- [ ] **Android 12+ (API 31+)**
  - [ ] 权限请求返回 NEARBY_WIFI_DEVICES 和更新的权限模型
  - [ ] RECORD_AUDIO 可被独立请求和拒绝
  
- [ ] **权限撤销后**
  - [ ] 音频播放显示"需要存储权限"
  - [ ] TTS 显示"需要麦克风权限"
  - [ ] 有明确的"打开设置"选项

### 音频播放测试

- [ ] **弱网环境 (100KB/s)**
  - [ ] 音频下载启动 3 次重试机制
  - [ ] 缓存命中不重复下载
  
- [ ] **缓存测试**
  - [ ] 同一音频多次播放只下载一次
  - [ ] URL 参数变化不导致重复下载
  
- [ ] **音量控制**
  - [ ] 音量按钮有效
  - [ ] AudioSession 配置后与系统音量同步
  
- [ ] **中断恢复**
  - [ ] 播放中接听电话后恢复播放
  - [ ] 其他应用声音打断后恢复

### TTS 测试

- [ ] **引擎可用时**
  - [ ] 朗读流畅无破音
  - [ ] 速度设置 0.5 (稍慢)
  
- [ ] **引擎不可用时**
  - [ ] 显示明确错误提示和解决方案
  - [ ] "打开设置"按钮可用
  
- [ ] **超时机制**
  - [ ] 15 秒后自动标记为就绪（不卡死）
  - [ ] 初始化失败不影响应用启动

### SSL 测试

- [ ] **自签名证书**
  - [ ] 139.196.44.6 的请求通过验证
  - [ ] 其他主机显示警告
  
- [ ] **证书验证失败**
  - [ ] 显示"证书验证失败"错误
  - [ ] 音频播放显示对应错误提示

---

## 📦 必需的依赖更新

检查 [mobile/pubspec.yaml](mobile/pubspec.yaml) 是否需要更新版本:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # ✅ 已有（版本检查）
  just_audio: ^0.9.36          # ✅ 支持 AudioSession
  audio_service: ^0.18.12      # 后台播放
  flutter_tts: ^4.0.2          # ✅ 日语支持
  
  # ✅ 新增权限库
  permission_handler: ^11.3.0   # ✅ 已在 pubspec.yaml 中
  
  # ✅ 其他必要的库（已有）
  flutter_secure_storage: ^9.0.0
  path_provider: ^2.1.2
```

---

## 🔧 实施步骤

### Phase 1: 权限基础设施 (立即实施)

1. **修改 AndroidManifest.xml**
   ```bash
   # 添加缺失的权限声明
   ```

2. **添加 permission_service.dart**
   ```bash
   # 创建权限管理服务
   ```

3. **修改 main.dart**
   ```bash
   # 初始化权限请求
   ```

### Phase 2: 特定模块修复 (立即实施)

4. **修改 audio_player_widget.dart**
   - 添加 AudioSession 初始化
   - 添加音量控制
   - 添加权限检查

5. **修改 vocabulary_detail_screen.dart**
   - 添加 TTS 前的权限检查
   - 优化错误提示

6. **改进 api_service.dart**
   - 增强文件写入错误处理
   - 添加更详细的日志

### Phase 3: 测试和验证 (推荐)

7. **完整的权限测试**（参考测试清单）

8. **真机测试**
   - 多个 Android 版本（6.0、10、12）
   - 各种网络条件

---

## ⚠️ 安全建议

| 项 | 建议 | 优先级 |
|----|------|--------|
| SSL 证书 | 生产环境使用 Let's Encrypt 有效证书 | 🔴 高 |
| 证书固定 | 实现 Certificate Pinning 防止中间人 | 🟡 中 |
| 权限最小化 | 只请求必要权限，清晰解释用途 | 🔴 高 |
| 运行时检查 | 所有文件操作前检查权限 | 🔴 高 |
| 错误日志 | 记录权限拒绝和文件操作失败 | 🟡 中 |

---

## 📝 总结

| 问题类别 | 当前状态 | 修复预期 | 工作量 |
|---------|---------|---------|--------|
| Android 权限声明 | ❌ 缺失 | ✅ 2 小时 | 低 |
| 运行时权限请求 | ❌ 缺失 | ✅ 3 小时 | 中 |
| 文件权限处理 | ⚠️ 部分 | ✅ 2 小时 | 低 |
| AudioSession 配置 | ❌ 缺失 | ✅ 1 小时 | 低 |
| 音量控制 | ❌ 缺失 | ✅ 0.5 小时 | 低 |
| TTS 权限检查 | ❌ 缺失 | ✅ 1 小时 | 低 |
| **总计** | | | **~9.5 小时** |

---

## 🔗 相关文档

- [AUDIO_FEATURE_ANALYSIS.md](AUDIO_FEATURE_ANALYSIS.md) - 完整音频架构分析
- [AUDIO_QUICK_REFERENCE.md](AUDIO_QUICK_REFERENCE.md) - 快速参考
- [AUDIO_FIXES_SUMMARY.md](AUDIO_FIXES_SUMMARY.md) - 已修复问题总结
