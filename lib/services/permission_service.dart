import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// 权限管理服务（Android / iOS）
class PermissionService {
  /// 请求音频相关权限（麦克风 + 存储）
  /// 用于需要同时录音和访问文件的功能
  static Future<bool> requestAudioPermissions() async {
    final permissions = <Permission>[
      Permission.microphone, // 录音与语音输入
      if (Platform.isAndroid) Permission.storage,
      if (Platform.isIOS) Permission.speech,
    ];

    final statuses = await permissions.request();

    final allGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    if (!allGranted) {
      for (final status in statuses.values) {
        if (status.isDenied) {
          print('【权限】某些权限被拒绝：$status');
        } else if (status.isPermanentlyDenied) {
          print('【权限】权限被永久拒绝，需要跳转到设置');
          openAppSettings();
        }
      }
    }

    return allGranted;
  }

  /// 检查是否已获得特定权限
  static Future<bool> hasPermission(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  /// 请求存储权限（用于音频缓存）
  ///  注意：临时目录（getTemporaryDirectory）不需要存储权限，
  ///  此方法用于访问外部存储的场景。
  static Future<bool> requestStoragePermission() async {
    final status = Platform.isIOS
        ? await Permission.photos.request()
        : await Permission.storage.request();
    return status.isGranted;
  }

  /// 请求麦克风权限（仅用于语音识别 STT，TTS 不需要）
  static Future<bool> requestMicrophonePermission() async {
    final micStatus = await Permission.microphone.request();
    PermissionStatus speechStatus = PermissionStatus.granted;
    if (Platform.isIOS) {
      speechStatus = await Permission.speech.request();
    }

    if (micStatus.isDenied || speechStatus.isDenied) {
      print('【权限】麦克风权限被拒绝');
    } else if (micStatus.isPermanentlyDenied || speechStatus.isPermanentlyDenied) {
      print('【权限】麦克风权限被永久拒绝，请在设置中启用');
      openAppSettings();
    }
    return micStatus.isGranted && speechStatus.isGranted;
  }

  /// 打开应用设置页面
  static Future<void> openPermissionSettings() async {
    await openAppSettings();
  }
}
