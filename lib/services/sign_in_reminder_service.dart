import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app_shell_controller.dart';
import 'message_notification_service.dart';
import 'tieba_account_service.dart';

/// 贴吧签到提醒：按用户设定时间推送，并结合「今日是否已签」决定是否提醒。
class SignInReminderService extends ChangeNotifier {
  SignInReminderService._();

  static final SignInReminderService instance = SignInReminderService._();

  static const _enabledKey = 'sign_in_reminder_enabled';
  static const _hourKey = 'sign_in_reminder_hour';
  static const _minuteKey = 'sign_in_reminder_minute';
  static const _lastSignInDateKey = 'sign_in_last_date';
  static const _lastNotifyDateKey = 'sign_in_reminder_notified_date';

  static const notificationId = 74001;
  static const channelId = 'sign_in_reminder';
  static const payloadOpenForum = 'sign_in_reminder';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _pluginReady = false;
  bool _timezoneReady = false;
  bool _enabled = false;
  int _hour = 9;
  int _minute = 0;

  bool get enabled => _enabled;
  int get hour => _hour;
  int get minute => _minute;
  TimeOfDay get reminderTime => TimeOfDay(hour: _hour, minute: _minute);

  String get reminderTimeLabel {
    final h = _hour.toString().padLeft(2, '0');
    final m = _minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static Future<void> bootstrap() async {
    await instance.loadPrefs();
  }

  /// 原生通知插件 + 时区库：仅在 idle 或用户开启提醒时加载，避免启动卡顿。
  static Future<void> ensureNativeReady() async {
    await instance._ensurePluginReady();
    if (!instance._enabled) return;
    await instance._ensureTimezoneReady();
    await instance.syncSchedule();
  }

  static Future<void> initialize() async {
    await bootstrap();
    await ensureNativeReady();
  }

  /// 供签到进度等其它通知复用插件初始化。
  static Future<void> ensurePluginReady() async {
    await instance._ensurePluginReady();
  }

  /// 全 App 共用一个 [FlutterLocalNotificationsPlugin]，避免多实例未初始化。
  static FlutterLocalNotificationsPlugin get sharedPlugin => instance._plugin;

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _hour = prefs.getInt(_hourKey) ?? 9;
    _minute = prefs.getInt(_minuteKey) ?? 0;
    notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    if (value) {
      final granted = await requestNotificationPermission();
      if (!granted) return false;
      final loggedIn = await TiebaAccountService.isBound();
      if (!loggedIn) return false;
    }

    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    notifyListeners();
    await syncSchedule();
    return true;
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    _hour = time.hour;
    _minute = time.minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, _hour);
    await prefs.setInt(_minuteKey, _minute);
    notifyListeners();
    if (_enabled) {
      await syncSchedule();
    }
  }

  Future<bool> hasSignedInToday() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastSignInDateKey);
    return last == _todayKey();
  }

  Future<void> markSignedInToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSignInDateKey, _todayKey());
    await syncSchedule();
  }

  Future<void> onLoginChanged() async {
    if (!await TiebaAccountService.isBound()) {
      await _cancelScheduled();
      _enabled = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
      notifyListeners();
      return;
    }
    await syncSchedule();
  }

  Future<void> onAppResume() async {
    if (!_enabled || !await TiebaAccountService.isBound()) return;
    scheduler.SchedulerBinding.instance.scheduleTask(
      () => unawaited(_onAppResumeIdle()),
      scheduler.Priority.idle,
    );
  }

  Future<void> _onAppResumeIdle() async {
    if (!_enabled || !await TiebaAccountService.isBound()) return;
    if (await hasSignedInToday()) return;

    final now = DateTime.now();
    final reminder = DateTime(now.year, now.month, now.day, _hour, _minute);
    if (now.isBefore(reminder)) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_lastNotifyDateKey) == _todayKey()) return;

    await _showNotification(title: '贝占口巴签到提醒', body: '今天还没有签到，打开 App 一键签到吧');
    await prefs.setString(_lastNotifyDateKey, _todayKey());
  }

  Future<void> syncSchedule() async {
    try {
      await _ensureInitialized();
      await _cancelScheduled();

      if (!_enabled || !await TiebaAccountService.isBound()) return;
      if (await hasSignedInToday()) return;

      final scheduled = _nextReminder();
      final details = _notificationDetails();
      await _plugin.zonedSchedule(
        notificationId,
        '贝占口巴签到提醒',
        '今天还没有签到，打开 App 一键签到吧',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payloadOpenForum,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SignInReminderService.syncSchedule failed: $e\n$st');
      }
    }
  }

  Future<void> _ensurePluginReady() async {
    if (_pluginReady) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationResponse,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SignInReminderService plugin init failed: $e\n$st');
      }
      return;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          '签到提醒',
          description: '每日贴吧签到提醒',
          importance: Importance.defaultImportance,
        ),
      );
    }

    _pluginReady = true;
  }

  Future<void> _ensureTimezoneReady() async {
    if (_timezoneReady) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SignInReminderService timezone fallback: $e');
      }
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    _timezoneReady = true;
  }

  Future<void> _ensureInitialized() async {
    await _ensurePluginReady();
    await _ensureTimezoneReady();
  }

  /// 当前是否已允许发送通知（不加载时区库，避免卡顿）。
  Future<bool> hasNotificationPermission() async {
    await _ensurePluginReady();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.areNotificationsEnabled() ?? true;
    }
    if (Platform.isIOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final settings = await iosPlugin?.checkPermissions();
      return settings?.isEnabled ?? false;
    }
    return true;
  }

  /// 向用户申请通知权限（Android 13+ / iOS）。
  Future<bool> requestNotificationPermission() async {
    await _ensurePluginReady();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? true;
    }
    if (Platform.isIOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        '签到提醒',
        channelDescription: '每日贴吧签到提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  tz.TZDateTime _nextReminder() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _hour,
      _minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await _plugin.show(
      notificationId,
      title,
      body,
      _notificationDetails(),
      payload: payloadOpenForum,
    );
  }

  Future<void> _cancelScheduled() async {
    await _ensureInitialized();
    await _plugin.cancel(notificationId);
  }

  static String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (MessageNotificationService.instance.handlePayload(response.payload)) {
      return;
    }
    if (response.payload != payloadOpenForum) return;
    AppShellController.instance.selectTab(AppShellTab.forum);
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    if (MessageNotificationService.instance.handlePayload(response.payload)) {
      return;
    }
    if (response.payload != payloadOpenForum) return;
    AppShellController.instance.selectTab(AppShellTab.forum);
  }
}
