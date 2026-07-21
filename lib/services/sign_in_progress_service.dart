import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'sign_in_reminder_service.dart';

/// 一键签到进度通知（贴吧 Lite 风格：通知栏进度 + 失败单独展示）。
class SignInProgressService {
  SignInProgressService._();

  static final SignInProgressService instance = SignInProgressService._();

  static const progressNotificationId = 74002;
  static const channelId = 'sign_in_progress';
  static const _failIdBase = 74100;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  int _failSeq = 0;

  Future<void> start(int total) async {
    await SignInReminderService.ensurePluginReady();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          '签到进度',
          description: '一键签到进行中的进度',
          importance: Importance.low,
        ),
      );
    }
    _failSeq = 0;
    await _showProgress(
      title: '贴吧签到',
      body: total > 0 ? '即将开始签到 · 共 $total 个吧' : '暂无关注吧',
      current: 0,
      total: total > 0 ? total : 1,
      indeterminate: total <= 0,
    );
  }

  Future<void> updateSigning({
    required int current,
    required int total,
    required String barName,
    required int successCount,
  }) async {
    final idx = current + 1;
    await _showProgress(
      title: '贴吧签到',
      body: '正在签到 $idx/$total · $barName · 已成功 $successCount',
      current: current,
      total: total,
    );
  }

  Future<void> showFailure({
    required String barName,
    required String message,
  }) async {
    await SignInReminderService.ensurePluginReady();
    final id = _failIdBase + (_failSeq++ % 100);
    await _plugin.show(
      id,
      '签到失败 · $barName',
      message,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '签到进度',
          channelDescription: '一键签到进行中的进度',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> complete({
    required int successCount,
    required int total,
    required int failedCount,
  }) async {
    final body = failedCount > 0
        ? '签到完成 · 成功 $successCount/$total，失败 $failedCount 个'
        : '签到完成 · 全部成功 $successCount/$total';
    await _plugin.show(
      progressNotificationId,
      '贴吧签到',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '签到进度',
          channelDescription: '一键签到进行中的进度',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: false,
          autoCancel: true,
          showProgress: false,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> dismiss() async {
    await SignInReminderService.ensurePluginReady();
    await _plugin.cancel(progressNotificationId);
  }

  Future<void> _showProgress({
    required String title,
    required String body,
    required int current,
    required int total,
    bool indeterminate = false,
  }) async {
    await _plugin.show(
      progressNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '签到进度',
          channelDescription: '一键签到进行中的进度',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: total,
          progress: indeterminate ? 0 : current.clamp(0, total),
          indeterminate: indeterminate,
        ),
        iOS: DarwinNotificationDetails(
          subtitle: indeterminate ? null : '$current/$total',
        ),
      ),
    );
  }
}

/// 一键签到进度回调。
class SignInProgressEvent {
  final int index;
  final int total;
  final String barName;
  final bool signing;
  final bool? success;
  final String? message;
  final int successCount;

  const SignInProgressEvent({
    required this.index,
    required this.total,
    required this.barName,
    required this.signing,
    this.success,
    this.message,
    required this.successCount,
  });
}

typedef SignInProgressCallback =
    Future<void> Function(SignInProgressEvent event);
