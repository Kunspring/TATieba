import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tieba_private_message.dart';
import '../utils/app_lifecycle_gate.dart';
import 'app_shell_controller.dart';
import 'sign_in_reminder_service.dart';
import 'tieba_account_service.dart';
import 'tieba_message_service.dart';

String _encodeWatermarkMap(Map<String, int> map) => jsonEncode(map);

/// 私信 / @ / 回复 本地通知（轮询 + 角标，接近 IM App 体验）。
class MessageNotificationService extends ChangeNotifier {
  MessageNotificationService._();

  static final MessageNotificationService instance =
      MessageNotificationService._();

  static const _enabledKey = 'msg_notify_enabled';
  static const _privateKey = 'msg_notify_private';
  static const _atKey = 'msg_notify_at';
  static const _replyKey = 'msg_notify_reply';
  static const _watermarkKey = 'msg_notify_watermarks_v1';

  static const channelId = 'tieba_messages';
  static const payloadPrefix = 'message|';
  static const payloadTab = '${payloadPrefix}tab';
  static const payloadPrivatePrefix = '${payloadPrefix}private|';
  static const payloadAtPrefix = '${payloadPrefix}at|';
  static const payloadReplyPrefix = '${payloadPrefix}reply|';

  static const _baseNotificationId = 75000;
  static const _atNotificationId = 75100;
  static const _replyNotificationId = 75101;

  FlutterLocalNotificationsPlugin get _plugin =>
      SignInReminderService.sharedPlugin;

  bool _channelsReady = false;
  bool _nativeStackReady = false;
  String? _pendingLaunchPayload;
  bool _enabled = true;
  bool _notifyPrivate = true;
  bool _notifyAt = true;
  bool _notifyReply = true;
  int _unreadCount = 0;
  int _foregroundTabIndex = 0;
  int? _foregroundPrivateGroupId;
  Timer? _pollTimer;
  bool _polling = false;
  bool _hasBaseline = false;
  DateTime? _lastPollFinishedAt;
  static const _minPollGap = Duration(seconds: 20);

  bool get enabled => _enabled;
  bool get notifyPrivate => _notifyPrivate;
  bool get notifyAt => _notifyAt;
  bool get notifyReply => _notifyReply;
  int get unreadCount => _unreadCount;
  final ValueNotifier<int> unreadBadge = ValueNotifier(0);

  static Future<void> bootstrap() async {
    await instance.loadPrefs();
    await instance._loadWatermarks();
  }

  /// 原生通道与轮询：全部延后到 idle，不抢首屏/滚动。
  static Future<void> ensureNativeReady() async {
    if (instance._nativeStackReady) return;
    instance._nativeStackReady = true;

    await SignInReminderService.ensurePluginReady();
    await instance._ensureChannels();
    unawaited(instance._captureLaunchNotification());

    if (!instance._enabled || !await TiebaAccountService.isBound()) return;

    instance._startForegroundPolling();
    instance.schedulePollIdle(silentBaseline: !instance._hasBaseline);
  }

  void schedulePollIdle({required bool silentBaseline}) {
    scheduler.SchedulerBinding.instance.scheduleTask(
      () => unawaited(pollNow(silentBaseline: silentBaseline)),
      scheduler.Priority.idle,
    );
  }

  /// 冷启动从通知点进 App 时，在 Shell 就绪后跳转。
  void consumePendingLaunchPayload() {
    final payload = _pendingLaunchPayload;
    if (payload == null || payload.isEmpty) return;
    _pendingLaunchPayload = null;
    scheduler.SchedulerBinding.instance.addPostFrameCallback((_) {
      handlePayload(payload);
    });
  }

  static Future<void> initialize() async {
    await bootstrap();
    await ensureNativeReady();
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _notifyPrivate = prefs.getBool(_privateKey) ?? true;
    _notifyAt = prefs.getBool(_atKey) ?? true;
    _notifyReply = prefs.getBool(_replyKey) ?? true;
    notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    if (value) {
      final granted = await SignInReminderService.instance
          .requestNotificationPermission();
      if (!granted) return false;
      if (!await TiebaAccountService.isBound()) return false;
    }
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    notifyListeners();
    if (value) {
      await SignInReminderService.ensurePluginReady();
      await _ensureChannels();
      _startForegroundPolling();
      schedulePollIdle(silentBaseline: !_hasBaseline);
    } else {
      _stopPolling();
      await _clearBadgeNotifications();
    }
    return true;
  }

  Future<void> setNotifyPrivate(bool value) async {
    _notifyPrivate = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privateKey, value);
    notifyListeners();
  }

  Future<void> setNotifyAt(bool value) async {
    _notifyAt = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_atKey, value);
    notifyListeners();
  }

  Future<void> setNotifyReply(bool value) async {
    _notifyReply = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_replyKey, value);
    notifyListeners();
  }

  void setForegroundTab(int index) {
    _foregroundTabIndex = index;
    if (index == 2) {
      _foregroundPrivateGroupId = null;
    }
  }

  void setForegroundPrivateChat(int? groupId) {
    _foregroundPrivateGroupId = groupId;
  }

  Future<void> onLoginChanged() async {
    if (!await TiebaAccountService.isBound()) {
      _hasBaseline = false;
      _unreadCount = 0;
      unreadBadge.value = 0;
      _stopPolling();
      await _saveWatermarks({});
      await _clearBadgeNotifications();
      notifyListeners();
      return;
    }
    _hasBaseline = false;
    if (_enabled) {
      _startForegroundPolling();
      schedulePollIdle(silentBaseline: true);
    }
  }

  void onAppResume() {
    _stopPolling();
    _startForegroundPolling();
    if (_enabled) {
      schedulePollIdle(silentBaseline: false);
    }
  }

  void onAppPaused() {
    _pollTimer?.cancel();
    _startBackgroundPolling();
  }

  void _startForegroundPolling() {
    if (!_enabled) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      pollNow();
    });
  }

  Future<void> onMessagesTabVisible({MessageFeedSnapshot? feed}) async {
    final resolved = feed ?? await TiebaMessageService.fetchFeed();
    final watermarks = await _loadWatermarksMap();
    if (resolved.ats.isNotEmpty) {
      watermarks['at'] = resolved.ats.first.createTime;
    }
    if (resolved.replies.isNotEmpty) {
      watermarks['reply'] = resolved.replies.first.createTime;
    }
    await _saveWatermarks(
      watermarks,
      activePrivateGroupIds: _privateGroupIds(resolved),
    );
    await _recomputeUnreadFromFeed(resolved);
  }

  Future<void> markPrivateChatOpened(PrivateChatConversation chat) async {
    final watermarks = await _loadWatermarksMap();
    final last = chat.lastMessage;
    if (last != null) {
      watermarks['private:${chat.groupId}'] = last.msgId;
    }
    await _saveWatermarks(watermarks);
    _foregroundPrivateGroupId = chat.groupId;
    TiebaMessageService.invalidateFeedCache();
    schedulePollIdle(silentBaseline: false);
  }

  Future<void> pollNow({bool silentBaseline = false}) async {
    if (_polling) return;
    if (!_enabled || !await TiebaAccountService.isBound()) return;

    final last = _lastPollFinishedAt;
    if (!silentBaseline &&
        last != null &&
        DateTime.now().difference(last) < _minPollGap) {
      return;
    }

    _polling = true;
    try {
      final feed = await TiebaMessageService.fetchFeed();
      if (!_hasBaseline || silentBaseline) {
        await _applyBaselineFromFeed(feed);
        _hasBaseline = true;
        await _recomputeUnreadFromFeed(feed);
        return;
      }
      await _processNewItems(feed);
      await _recomputeUnreadFromFeed(feed);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MessageNotificationService poll failed: $e');
      }
    } finally {
      _polling = false;
      _lastPollFinishedAt = DateTime.now();
    }
  }

  bool handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return false;
    if (payload == payloadTab) {
      AppShellController.instance.selectTab(AppShellTab.messages);
      return true;
    }
    if (payload.startsWith(payloadPrivatePrefix)) {
      final parts = payload.split('|');
      if (parts.length >= 3) {
        final groupId = int.tryParse(parts[2]) ?? 0;
        final peerName = parts.length >= 4 ? Uri.decodeComponent(parts[3]) : '';
        AppShellController.instance.openPrivateChat(
          groupId: groupId,
          peerName: peerName,
        );
        return true;
      }
    }
    if (payload.startsWith(payloadAtPrefix) ||
        payload.startsWith(payloadReplyPrefix)) {
      final parts = payload.split('|');
      if (parts.length >= 4) {
        final tid = int.tryParse(parts[2]) ?? 0;
        final barName = Uri.decodeComponent(parts[3]);
        final title = parts.length >= 5 ? Uri.decodeComponent(parts[4]) : null;
        AppShellController.instance.selectTab(AppShellTab.messages);
        AppShellController.instance.openPost(
          tid: tid.toString(),
          barName: barName,
          title: title,
        );
        return true;
      }
    }
    return false;
  }

  void _startBackgroundPolling() {
    _pollTimer?.cancel();
    if (!_enabled) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      pollNow();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _processNewItems(MessageFeedSnapshot feed) async {
    final watermarks = await _loadWatermarksMap();
    var changed = false;

    if (_notifyPrivate) {
      for (final chat in feed.privateChats) {
        final last = chat.lastMessage;
        if (last == null) continue;
        final key = 'private:${chat.groupId}';
        final seen = watermarks[key] ?? 0;
        if (last.msgId <= seen) continue;

        if (!_shouldSuppressPrivate(chat.groupId)) {
          await _showPrivateNotification(chat, last);
        }
        watermarks[key] = last.msgId;
        changed = true;
      }
    }

    if (_notifyAt && feed.ats.isNotEmpty) {
      final top = feed.ats.first;
      final seen = watermarks['at'] ?? 0;
      if (top.createTime > seen) {
        if (!_shouldSuppressInteractive()) {
          await _showAtNotification(top);
        }
        watermarks['at'] = top.createTime;
        changed = true;
      }
    }

    if (_notifyReply && feed.replies.isNotEmpty) {
      final top = feed.replies.first;
      final seen = watermarks['reply'] ?? 0;
      if (top.createTime > seen) {
        if (!_shouldSuppressInteractive()) {
          await _showReplyNotification(top);
        }
        watermarks['reply'] = top.createTime;
        changed = true;
      }
    }

    if (changed) {
      await _saveWatermarks(
        watermarks,
        activePrivateGroupIds: _privateGroupIds(feed),
      );
    }
  }

  bool _shouldSuppressPrivate(int groupId) {
    if (!AppLifecycleGate.isActive) return false;
    if (_foregroundTabIndex == 2 && _foregroundPrivateGroupId == groupId) {
      return true;
    }
    return false;
  }

  bool _shouldSuppressInteractive() {
    if (!AppLifecycleGate.isActive) return false;
    return _foregroundTabIndex == 2;
  }

  Future<void> _applyBaselineFromFeed(MessageFeedSnapshot feed) async {
    final watermarks = <String, int>{};
    for (final chat in feed.privateChats) {
      final last = chat.lastMessage;
      if (last != null) {
        watermarks['private:${chat.groupId}'] = last.msgId;
      }
    }
    if (feed.ats.isNotEmpty) {
      watermarks['at'] = feed.ats.first.createTime;
    }
    if (feed.replies.isNotEmpty) {
      watermarks['reply'] = feed.replies.first.createTime;
    }
    await _saveWatermarks(
      watermarks,
      activePrivateGroupIds: _privateGroupIds(feed),
    );
  }

  Future<void> _recomputeUnreadFromFeed(MessageFeedSnapshot feed) async {
    final watermarks = await _loadWatermarksMap();
    var count = 0;

    for (final chat in feed.privateChats) {
      final last = chat.lastMessage;
      if (last == null) continue;
      final seen = watermarks['private:${chat.groupId}'] ?? 0;
      if (last.msgId > seen) count++;
    }
    if (feed.ats.isNotEmpty) {
      final seen = watermarks['at'] ?? 0;
      if (feed.ats.first.createTime > seen) count++;
    }
    if (feed.replies.isNotEmpty) {
      final seen = watermarks['reply'] ?? 0;
      if (feed.replies.first.createTime > seen) count++;
    }

    if (_unreadCount == count) return;
    _unreadCount = count;
    unreadBadge.value = count;
    notifyListeners();
  }

  Future<void> _showPrivateNotification(
    PrivateChatConversation chat,
    TiebaPrivateMessage last,
  ) async {
    await SignInReminderService.ensurePluginReady();
    await _ensureChannels();
    final preview = _previewText(last.text);
    final id = _privateNotificationId(chat.groupId);
    final payload =
        '$payloadPrivatePrefix${chat.groupId}|${Uri.encodeComponent(chat.peerName)}';

    await _plugin.show(
      id,
      chat.peerName,
      preview,
      _messageDetails(
        ticker: '${chat.peerName}：$preview',
        groupKey: 'private_${chat.groupId}',
      ),
      payload: payload,
    );
  }

  Future<void> _showAtNotification(AtItemRef item) async {
    await SignInReminderService.ensurePluginReady();
    await _ensureChannels();
    final body = _formatInteractiveBody(
      item.replyerName,
      item.fname,
      item.text,
    );
    final payload =
        '$payloadAtPrefix${item.tid}|${Uri.encodeComponent(item.fname)}|${Uri.encodeComponent(_previewText(item.text, max: 40))}';

    await _plugin.show(
      _atNotificationId,
      '有人@了你',
      body,
      _messageDetails(ticker: body, groupKey: 'tieba_interactive'),
      payload: payload,
    );
  }

  Future<void> _showReplyNotification(ReplyItemRef item) async {
    await SignInReminderService.ensurePluginReady();
    await _ensureChannels();
    final body = _formatInteractiveBody(
      item.replyerName,
      item.fname,
      item.text,
    );
    final payload =
        '$payloadReplyPrefix${item.tid}|${Uri.encodeComponent(item.fname)}|${Uri.encodeComponent(_previewText(item.text, max: 40))}';

    await _plugin.show(
      _replyNotificationId,
      '收到新回复',
      body,
      _messageDetails(ticker: body, groupKey: 'tieba_interactive'),
      payload: payload,
    );
  }

  String _formatInteractiveBody(String name, String bar, String text) {
    final preview = _previewText(text);
    final barLabel = bar.trim().isEmpty ? '贴吧' : bar.trim();
    return '$name · $barLabel：$preview';
  }

  String _previewText(String raw, {int max = 80}) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '[消息]';
    if (collapsed.length <= max) return collapsed;
    return '${collapsed.substring(0, max)}…';
  }

  int _privateNotificationId(int groupId) =>
      _baseNotificationId + (groupId.abs() % 4000);

  NotificationDetails _messageDetails({
    required String ticker,
    required String groupKey,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        '消息通知',
        channelDescription: '私信、@与回复提醒',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        ticker: ticker,
        groupKey: groupKey,
        styleInformation: BigTextStyleInformation(ticker),
        visibility: NotificationVisibility.private,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  Future<void> _clearBadgeNotifications() async {
    if (!_channelsReady) {
      await SignInReminderService.ensurePluginReady();
    }
    final watermarks = await _loadWatermarksMap();
    final cancels = <Future<void>>[
      _plugin.cancel(_atNotificationId),
      _plugin.cancel(_replyNotificationId),
    ];
    for (final key in watermarks.keys) {
      if (!key.startsWith('private:')) continue;
      final groupId = int.tryParse(key.substring('private:'.length));
      if (groupId == null) continue;
      cancels.add(_plugin.cancel(_privateNotificationId(groupId)));
    }
    await Future.wait(cancels);
  }

  Future<void> _ensureChannels() async {
    if (_channelsReady) return;
    await SignInReminderService.ensurePluginReady();

    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          '消息通知',
          description: '私信、@与回复提醒',
          importance: Importance.high,
        ),
      );
    }

    _channelsReady = true;
  }

  Future<void> _captureLaunchNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final payload = details?.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return;
      _pendingLaunchPayload = payload;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MessageNotificationService launch payload failed: $e');
      }
    }
  }

  Future<Map<String, int>> _loadWatermarksMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_watermarkKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), _asInt(value)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadWatermarks() async {
    final map = await _loadWatermarksMap();
    _hasBaseline = map.isNotEmpty;
  }

  Future<void> _saveWatermarks(
    Map<String, int> map, {
    Iterable<int>? activePrivateGroupIds,
  }) async {
    if (activePrivateGroupIds != null) {
      final allowed = activePrivateGroupIds.map((id) => 'private:$id').toSet();
      map.removeWhere(
        (key, _) => key.startsWith('private:') && !allowed.contains(key),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = await compute(_encodeWatermarkMap, map);
    await prefs.setString(_watermarkKey, encoded);
  }

  static Iterable<int> _privateGroupIds(MessageFeedSnapshot feed) =>
      feed.privateChats.map((chat) => chat.groupId);

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
