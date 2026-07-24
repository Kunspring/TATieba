import 'dart:async';

import '../models/tieba_post.dart';
import '../models/tieba_private_message.dart';
import '../utils/post_content_plain.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_ws_client.dart';

/// 聚合私信（WebSocket）与 @/回复（HTTP）消息源。
///
/// 维护一个持久化 WS 连接，在多次拉取操作间复用，避免每次建连/断连。
/// 连接在空闲 [idleTimeout] 后自动断开。
class TiebaMessageService {
  TiebaMessageService._();

  // ---- feed cache ----

  static Future<MessageFeedSnapshot>? _inflightFetch;
  static MessageFeedSnapshot? _cachedFeed;
  static DateTime? _cachedFeedAt;
  static const _feedCacheTtl = Duration(seconds: 45);

  static void invalidateFeedCache() {
    _cachedFeed = null;
    _cachedFeedAt = null;
  }

  static Future<MessageFeedSnapshot> fetchFeed({bool force = false}) async {
    if (!force &&
        _cachedFeed != null &&
        _cachedFeedAt != null &&
        DateTime.now().difference(_cachedFeedAt!) < _feedCacheTtl) {
      return _cachedFeed!;
    }

    final existing = _inflightFetch;
    if (existing != null) return existing;

    final future = _fetchFeedImpl();
    _inflightFetch = future;
    try {
      return await future;
    } finally {
      if (identical(_inflightFetch, future)) {
        _inflightFetch = null;
      }
    }
  }

  static Future<MessageFeedSnapshot> _fetchFeedImpl() async {
    final bduss = await TiebaAccountService.getBduss();
    if (bduss == null || bduss.isEmpty) {
      return const MessageFeedSnapshot();
    }
    final stoken = await TiebaAccountService.getStoken() ?? '';

    final atFuture = TiebaClient.getAts(pn: 1, bduss: bduss, stoken: stoken);
    final replyFuture = TiebaClient.getReplys(
      pn: 1,
      bduss: bduss,
      stoken: stoken,
    );
    final privateFuture = _fetchPrivateChats(bduss: bduss, stoken: stoken);

    final results = await Future.wait([atFuture, replyFuture, privateFuture]);

    final ats = results[0] as List<AtItem>;
    final replies = results[1] as List<ReplyItem>;
    final privateResult = results[2] as _PrivateFetchResult;

    final snapshot = MessageFeedSnapshot(
      privateChats: privateResult.chats,
      privateError: privateResult.error,
      privateFetchAttempted: true,
      ats: ats
          .map(
            (e) => AtItemRef(
              text: _displayText(e.text),
              fname: e.fname,
              tid: e.tid,
              pid: e.pid,
              replyerName: _userLabel(e.replyer),
              createTime: e.createTime,
            ),
          )
          .toList(),
      replies: replies
          .map(
            (e) => ReplyItemRef(
              text: _displayText(e.text),
              fname: e.fname,
              tid: e.tid,
              pid: e.pid,
              replyerName: _userLabel(e.replyer),
              createTime: e.createTime,
            ),
          )
          .toList(),
    );
    _cachedFeed = snapshot;
    _cachedFeedAt = DateTime.now();
    return snapshot;
  }

  // ---- WS connection management ----

  static TiebaWsClient? _ws;
  static bool _wsReady = false;
  static Future<void>? _connecting;
  static Timer? _idleTimer;
  static List<TiebaWsGroupInfo> _cachedGroups = const [];
  static int _cachedSelfUserId = 0;
  static const _idleTimeout = Duration(minutes: 5);

  /// 获取可复用的已连接 WS 客户端。
  /// 若尚未连接，会自动建连并缓存 groups 和 selfUserId。
  static Future<TiebaWsClient> _ensureConnected() async {
    if (_ws != null && _wsReady) {
      _resetIdleTimer();
      return _ws!;
    }

    if (_connecting != null) {
      await _connecting;
      if (_ws != null && _wsReady) return _ws!;
    }

    final completer = Completer<void>();
    _connecting = completer.future;

    try {
      final bduss = await TiebaAccountService.getBduss();
      if (bduss == null || bduss.isEmpty) throw StateError('Not logged in');
      final stoken = await TiebaAccountService.getStoken() ?? '';

      final client = TiebaWsClient();
      final groups = await client.connect(bduss: bduss, stoken: stoken);
      _ws = client;
      _wsReady = true;
      _cachedGroups = groups;

      var selfUserId = 0;
      try {
        final profile = await TiebaClient.fetchSelfProfile(bduss: bduss);
        if (profile != null) {
          selfUserId = int.tryParse(profile['user_id']?.toString() ?? '') ?? 0;
        }
      } catch (_) {}
      _cachedSelfUserId = selfUserId;

      _resetIdleTimer();
      return client;
    } finally {
      _connecting = null;
      completer.complete();
    }
  }

  static void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _closeWs);
  }

  static Future<void> _closeWs() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _wsReady = false;
    _cachedGroups = const [];
    _cachedSelfUserId = 0;
    if (_ws != null) {
      await _ws!.close();
    }
    _ws = null;
    _connecting = null;
  }

  /// 登出或切后台时主动断开 WS 连接。
  static Future<void> disposeConnection() async {
    await _closeWs();
    invalidateFeedCache();
  }

  /// 强制重连（下次操作时自动建连即可）。
  static void invalidateConnection() {
    _wsReady = false;
  }

  // ---- private chat ----

  static Future<_PrivateFetchResult> _fetchPrivateChats({
    required String bduss,
    required String stoken,
  }) async {
    try {
      final client = await _ensureConnected();
      return _PrivateFetchResult(
        chats: await client.fetchPrivateChats(
          groups: _cachedGroups,
          selfUserId: _cachedSelfUserId,
        ),
      );
    } on TiebaWsException catch (e) {
      _invalidateOnError();
      return _PrivateFetchResult(error: e.message);
    } catch (e) {
      _invalidateOnError();
      return _PrivateFetchResult(error: e.toString());
    }
  }

  /// 私信详情页按需拉取完整聊天记录。
  static Future<List<TiebaPrivateMessage>> fetchPrivateChatHistory({
    required int groupId,
    int lastMsgId = 0,
  }) async {
    if (groupId <= 0) return const [];

    try {
      final client = await _ensureConnected();

      TiebaWsGroupInfo? matched;
      for (final g in _cachedGroups) {
        if (g.groupId == groupId) {
          matched = g;
          break;
        }
      }
      final group = matched ??
          TiebaWsGroupInfo(
            groupId: groupId,
            groupType: 6,
            lastMsgId: lastMsgId,
          );

      return await client.fetchGroupMessageHistory(
        group: group,
        selfUserId: _cachedSelfUserId,
      );
    } on TiebaWsException {
      _invalidateOnError();
      return const [];
    } catch (_) {
      _invalidateOnError();
      return const [];
    }
  }

  /// 发送私信文本。若 groupId 为 0 则先创建会话再发送。
  /// 返回 (groupId, msgId)。
  static Future<({int groupId, int msgId})> sendPrivateMessage({
    int groupId = 0,
    int peerUserId = 0,
    required String content,
  }) async {
    final client = await _ensureConnected();
    var resolvedGroupId = groupId;
    if (resolvedGroupId <= 0) {
      if (peerUserId <= 0) {
        throw ArgumentError('peerUserId required when groupId is 0');
      }
      resolvedGroupId = await client.createPrivateChatGroup(peerUserId);
      // 加入缓存以便后续复用
      final alreadyCached = _cachedGroups.any((g) => g.groupId == resolvedGroupId);
      if (!alreadyCached) {
        _cachedGroups = [
          ..._cachedGroups,
          TiebaWsGroupInfo(
            groupId: resolvedGroupId,
            groupType: 6,
            lastMsgId: 0,
          ),
        ];
      }
    }
    final msgId = await client.sendGroupMessage(resolvedGroupId, content);
    return (groupId: resolvedGroupId, msgId: msgId);
  }

  /// WS 出错时标记连接失效，下次操作自动重连。
  static void _invalidateOnError() {
    _wsReady = false;
    _ws = null;
  }

  // ---- helpers ----

  static String _userLabel(UserBrief user) {
    final nick = user.nickName?.trim();
    if (nick != null && nick.isNotEmpty) return nick;
    return user.userName;
  }

  static String _displayText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final plain = PostContentPlain.from(trimmed);
    return plain.isNotEmpty ? plain : trimmed;
  }

  static Future<PrivateChatLookup> lookupPrivateChatForPeer({
    int? peerUserId,
    String? portrait,
    String? peerName,
  }) async {
    final feed = await fetchFeed();
    if (feed.privateFetchAttempted && feed.privateError != null) {
      return PrivateChatLookup(error: feed.privateError);
    }
    return PrivateChatLookup(
      conversation: matchPrivateChat(
        feed.privateChats,
        peerUserId: peerUserId,
        portrait: portrait,
        peerName: peerName,
      ),
    );
  }

  static PrivateChatConversation? matchPrivateChat(
    List<PrivateChatConversation> chats, {
    int? peerUserId,
    String? portrait,
    String? peerName,
  }) {
    final normalizedPortrait = portrait?.trim() ?? '';
    final normalizedPeerId = peerUserId ?? 0;

    for (final chat in chats) {
      if (normalizedPeerId > 0 && chat.peerUserId == normalizedPeerId) {
        return chat;
      }
      if (normalizedPortrait.isNotEmpty &&
          chat.peerPortrait != null &&
          chat.peerPortrait == normalizedPortrait) {
        return chat;
      }
    }

    final normalizedName = peerName?.trim() ?? '';
    if (normalizedName.isNotEmpty) {
      final matches = chats
          .where((chat) => chat.peerName == normalizedName)
          .toList();
      if (matches.length == 1) return matches.first;
    }

    return null;
  }
}

class _PrivateFetchResult {
  final List<PrivateChatConversation> chats;
  final String? error;

  const _PrivateFetchResult({this.chats = const [], this.error});
}
