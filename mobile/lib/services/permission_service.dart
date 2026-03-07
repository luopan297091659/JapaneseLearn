import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Android 权限管理服务
class PermissionService {
  /// 请求音频相关权限（麦克风、存储）
  static Future<bool> requestAudioPermissions() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ 使用 READ_MEDIA_AUDIO，低版本使用 READ_EXTERNAL_STORAGE
    List<Permission> permissions = [
      Permission.microphone,  // TTS/STT 需要
      if (Platform.isAndroid && _isAndroid13OrHigher())
        Permission.audio
      else
        Permission.storage,
    ];

    final statuses = await permissions.request();

    // 检查是否所有权限都被授予
    final allGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    if (!allGranted) {
      // 有权限被拒绝，检查是否为"永久拒绝"
      for (final status in statuses.values) {
        if (status.isDenied) {
          print('【权限】某些权限被不了：${status}');
        } else if (status.isPermanentlyDenied) {
          print('【权限】权限被永久拒绝，需要跳转到设置');
          // 用户可能需要手动在设置中启用权限
          openAppSettings();
        }
      }
    }

    return allGranted;
  }

  /// 检查是否已获得特定权限
  static Future<bool> hasPermission(Permission permission) async {
    if (!Platform.isAndroid) return true;
    final status = await permission.status;
    return status.isGranted;
  }

  /// 请求存储权限（用于音频缓存）
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    Permission permission;
    if (_isAndroid13OrHigher()) {
      // Android 13+ 使用 READ_MEDIA_AUDIO
      permission = Permission.audio;
    } else if (_isAndroid11OrHigher()) {
      // Android 11-12 使用 manageExternalStorage（需要特殊权限）
      permission = Permission.storage;
    } else {
      // Android 10- 使用 WRITE_EXTERNAL_STORAGE
      permission = Permission.storage;
    }

    final status = await permission.request();
    return status.isGranted;
  }

  /// 请求麦克风权限（用于 TTS 和语音识别）
  static Future<bool> requestMicrophonePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.microphone.request();
    if (status.isDenied) {
      print('【权限】麦克风权限被拒绝');
    } else if (status.isPermanentlyDenied) {
      print('【权限】麦克风权限被永久拒绝，请在设置中启用');
      openAppSettings();
    }
    return status.isGranted;
  }

  /// 检查 Android 版本
  static bool _isAndroid13OrHigher() {
    return Platform.isAndroid && int.parse(Platform.version.split('.')[0]) >= 13;
  }

  static bool _isAndroid11OrHigher() {
    return Platform.isAndroid && int.parse(Platform.version.split('.')[0]) >= 11;
  }

  /// 打开应用设置页面
  static Future<void> openPermissionSettings() async {
    await openAppSettings();
  }
}
