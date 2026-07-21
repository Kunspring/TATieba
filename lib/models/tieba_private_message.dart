class TiebaWsGroupInfo {
  final int groupId;
  final int groupType;
  final int lastMsgId;

  const TiebaWsGroupInfo({
    required this.groupId,
    required this.groupType,
    required this.lastMsgId,
  });

  bool get isPrivateChat => groupType == 6;
}

class TiebaPrivateMessage {
  final int msgId;
  final int msgType;
  final String text;
  final int userId;
  final String userName;
  final String? portrait;
  final int createTime;

  const TiebaPrivateMessage({
    required this.msgId,
    required this.msgType,
    required this.text,
    required this.userId,
    required this.userName,
    this.portrait,
    required this.createTime,
  });
}

class PrivateChatConversation {
  final int groupId;
  final int peerUserId;
  final String peerName;
  final String? peerPortrait;
  final TiebaPrivateMessage? lastMessage;
  final List<TiebaPrivateMessage> messages;

  const PrivateChatConversation({
    required this.groupId,
    required this.peerUserId,
    required this.peerName,
    this.peerPortrait,
    this.lastMessage,
    this.messages = const [],
  });
}

class PrivateChatLookup {
  final PrivateChatConversation? conversation;
  final String? error;

  const PrivateChatLookup({this.conversation, this.error});
}

class MessageFeedSnapshot {
  final List<PrivateChatConversation> privateChats;
  final List<AtItemRef> ats;
  final List<ReplyItemRef> replies;
  final String? privateError;
  final bool privateFetchAttempted;

  const MessageFeedSnapshot({
    this.privateChats = const [],
    this.ats = const [],
    this.replies = const [],
    this.privateError,
    this.privateFetchAttempted = false,
  });
}

/// 轻量 @ 条目，供消息页展示（避免 messages_page 直接依赖完整模型构造）。
class AtItemRef {
  final String text;
  final String fname;
  final int tid;
  final int pid;
  final String replyerName;
  final int createTime;

  const AtItemRef({
    required this.text,
    required this.fname,
    required this.tid,
    required this.pid,
    required this.replyerName,
    required this.createTime,
  });
}

class ReplyItemRef {
  final String text;
  final String fname;
  final int tid;
  final int pid;
  final String replyerName;
  final int createTime;

  const ReplyItemRef({
    required this.text,
    required this.fname,
    required this.tid,
    required this.pid,
    required this.replyerName,
    required this.createTime,
  });
}
