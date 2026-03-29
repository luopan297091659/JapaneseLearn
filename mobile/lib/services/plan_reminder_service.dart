import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class PlanReminderService {
  PlanReminderService._();
  static final PlanReminderService instance = PlanReminderService._();

  static const int _dailyReminderId = 9001;
  static const String _enabledKey = 'study_plan_daily_reminder_enabled_v1';
  static const String _hourKey = 'study_plan_daily_reminder_hour_v1';
  static const String _minuteKey = 'study_plan_daily_reminder_minute_v1';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    } catch (_) {
      // fallback to plugin default if timezone db lookup fails
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermissionIfNeeded() async {
    await init();

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? true;
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? true;
    }

    final macImpl = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    if (macImpl != null) {
      final granted = await macImpl.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? true;
    }

    return true;
  }

  tz.TZDateTime _nextAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> scheduleDailyReminder({
    required String planName,
    int hour = 20,
    int minute = 0,
  }) async {
    await init();
    final ok = await requestPermissionIfNeeded();
    if (!ok) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await prefs.setInt(_hourKey, hour);
    await prefs.setInt(_minuteKey, minute);

    const androidDetails = AndroidNotificationDetails(
      'study_plan_daily_channel',
      '学习计划每日提醒',
      channelDescription: '提醒用户按计划进行每日学习',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.zonedSchedule(
      _dailyReminderId,
      '学习计划提醒',
      '今天的「$planName」还没完成，花几分钟继续推进吧',
      _nextAt(hour, minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<({int hour, int minute})> getReminderTime() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_hourKey) ?? 20;
    final minute = prefs.getInt(_minuteKey) ?? 0;
    return (hour: hour, minute: minute);
  }

  Future<void> saveReminderTime({required int hour, required int minute}) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour);
    await prefs.setInt(_minuteKey, minute);
  }

  Future<void> cancelDailyReminder() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await _plugin.cancel(_dailyReminderId);
  }

  Future<void> syncByPlanState({required bool hasActivePlan, String? activePlanName}) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_hourKey) ?? 20;
    final minute = prefs.getInt(_minuteKey) ?? 0;

    if (!hasActivePlan) {
      await cancelDailyReminder();
      return;
    }

    await scheduleDailyReminder(
      planName: (activePlanName == null || activePlanName.isEmpty) ? '学习计划' : activePlanName,
      hour: hour,
      minute: minute,
    );
  }
}
