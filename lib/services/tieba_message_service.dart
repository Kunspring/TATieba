import '../models/tieba_post.dart';
import '../models/tieba_private_message.dart';
import '../utils/post_content_plain.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_ws_client.dart';

/// 聚合私信（WebSocket）与 @/回复（HTTP）消息源。
class TiebaMessageService {
  TiebaMessageService._();

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

  /// 私信详情页按需拉取完整聊天记录。
  static Future<List<TiebaPrivateMessage>> fetchPrivateChatHistory({
    required int groupId,
    int lastMsgId = 0,
  }) async {
    if (groupId <= 0) return const [];

    final bduss = await TiebaAccountService.getBduss();
    if (bduss == null || bduss.isEmpty) return const [];
    final stoken = await TiebaAccountService.getStoken() ?? '';

    final client = TiebaWsClient();
    try {
      final groups = await client.connect(bduss: bduss, stoken: stoken);
      TiebaWsGroupInfo? matched;
      for (final g in groups) {
        if (g.groupId == groupId) {
          matched = g;
          break;
        }
      }
      final group =
          matched ??
          TiebaWsGroupInfo(
            groupId: groupId,
            groupType: 6,
            lastMsgId: lastMsgId,
          );

      var selfUserId = 0;
      final profile = await TiebaClient.fetchSelfProfile(bduss: bduss);
      if (profile != null) {
        selfUserId = int.tryParse(profile['user_id']?.toString() ?? '') ?? 0;
      }

      return await client.fetchGroupMessageHistory(
        group: group,
        selfUserId: selfUserId,
      );
    } on TiebaWsException {
      return const [];
    } catch (_) {
      return const [];
    } finally {
      await client.close();
    }
  }

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

  /// 按 userId / portrait 在已拉取的私信列表中查找会话。
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

  static Future<_PrivateFetchResult> _fetchPrivateChats({
    required String bduss,
    required String stoken,
  }) async {
    final client = TiebaWsClient();
    try {
      final groups = await client.connect(bduss: bduss, stoken: stoken);

      var selfUserId = 0;
      final profile = await TiebaClient.fetchSelfProfile(bduss: bduss);
      if (profile != null) {
        selfUserId = int.tryParse(profile['user_id']?.toString() ?? '') ?? 0;
      }

      return _PrivateFetchResult(
        chats: await client.fetchPrivateChats(
          groups: groups,
          selfUserId: selfUserId,
        ),
      );
    } on TiebaWsException catch (e) {
      return _PrivateFetchResult(error: e.message);
    } catch (e) {
      return _PrivateFetchResult(error: e.toString());
    } finally {
      await client.close();
    }
  }
}

class _PrivateFetchResult {
  final List<PrivateChatConversation> chats;
  final String? error;

  const _PrivateFetchResult({this.chats = const [], this.error});
}
