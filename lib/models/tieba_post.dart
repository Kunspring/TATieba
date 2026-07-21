import '../utils/json_parse.dart';
import '../utils/post_content_plain.dart';
import 'tieba_video.dart';

class TiebaPost {
  final String id;
  final String title;
  final String author;
  final String? authorAvatar;
  final String? authorPortrait;
  String? cover;
  String content;
  final String barName;
  final int? fid;
  final int replyCount;
  final DateTime createdAt;
  int likes;
  bool isLiked;
  bool isFavorited;
  TiebaVideo? video;
  int? authorForumLevel;
  String? authorForumLevelName;

  String? _contentPreviewCache;
  String? _contentPreviewSource;

  /// 列表卡片用的纯文本摘要，按 [content] 缓存避免重复正则。
  String get contentPreview {
    if (_contentPreviewCache != null && _contentPreviewSource == content) {
      return _contentPreviewCache!;
    }
    final preview = PostContentPlain.from(content);
    _contentPreviewSource = content;
    _contentPreviewCache = preview;
    return preview;
  }

  TiebaPost({
    required this.id,
    required this.title,
    required this.author,
    this.authorAvatar,
    this.authorPortrait,
    this.cover,
    required this.content,
    required this.barName,
    this.fid,
    required this.replyCount,
    required this.createdAt,
    required this.likes,
    this.isLiked = false,
    this.isFavorited = false,
    this.video,
    this.authorForumLevel,
    this.authorForumLevelName,
  });

  factory TiebaPost.fromJson(Map<String, dynamic> json) {
    return TiebaPost(
      id: json['id']?.toString() ?? '',
      title: parseOptionalString(json['title']) ?? '无标题',
      author: parseOptionalString(json['author']) ?? '匿名',
      authorAvatar: parseOptionalString(json['author_avatar']),
      authorPortrait: parseOptionalString(json['author_portrait']),
      cover: parseOptionalString(json['cover']),
      content: parseOptionalString(json['content']) ?? '',
      barName: parseOptionalString(json['bar_name']) ?? '',
      fid: parseOptionalInt(json['fid']),
      replyCount: parseOptionalInt(json['reply_count']) ?? 0,
      createdAt:
          DateTime.tryParse(parseOptionalString(json['created_at']) ?? '') ??
          DateTime.now(),
      likes: parseOptionalInt(json['likes']) ?? 0,
      isLiked: json['is_liked'] == true,
      isFavorited: json['is_favorited'] == true,
      video: json['video'] is Map
          ? TiebaVideo.fromJson(Map<String, dynamic>.from(json['video'] as Map))
          : null,
      authorForumLevel: parseOptionalInt(json['author_forum_level']),
      authorForumLevelName: parseOptionalString(
        json['author_forum_level_name'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'author_avatar': authorAvatar,
    'author_portrait': authorPortrait,
    'cover': cover,
    'content': content,
    'bar_name': barName,
    'fid': fid,
    'reply_count': replyCount,
    'created_at': createdAt.toIso8601String(),
    'likes': likes,
    'is_liked': isLiked,
    'is_favorited': isFavorited,
    if (video != null) 'video': video!.toJson(),
    if (authorForumLevel != null) 'author_forum_level': authorForumLevel,
    if (authorForumLevelName != null)
      'author_forum_level_name': authorForumLevelName,
  };
}

class TiebaPageResult {
  final List<TiebaPost> items;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;

  const TiebaPageResult({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  factory TiebaPageResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => TiebaPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final total = json['total'] is int
        ? json['total'] as int
        : int.tryParse(json['total']?.toString() ?? '') ?? items.length;
    final offset = json['offset'] is int
        ? json['offset'] as int
        : int.tryParse(json['offset']?.toString() ?? '') ?? 0;
    final limit = json['limit'] is int
        ? json['limit'] as int
        : int.tryParse(json['limit']?.toString() ?? '') ?? items.length;
    final hasMore = json['has_more'] is bool
        ? json['has_more'] as bool
        : offset + items.length < total;
    return TiebaPageResult(
      items: items,
      total: total,
      offset: offset,
      limit: limit,
      hasMore: hasMore,
    );
  }
}

class TiebaPostDetail {
  final TiebaPost post;
  final List<TiebaComment> comments;
  final bool hasMore;
  final int totalComments;
  final String? firstPostPid;

  const TiebaPostDetail({
    required this.post,
    required this.comments,
    this.hasMore = false,
    this.totalComments = 0,
    this.firstPostPid,
  });

  factory TiebaPostDetail.fromJson(Map<String, dynamic> json) {
    final comments = (json['comments'] as List? ?? [])
        .whereType<Map>()
        .map((e) => TiebaComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return TiebaPostDetail(
      post: TiebaPost.fromJson(
        Map<String, dynamic>.from(json['post'] is Map ? json['post'] : {}),
      ),
      comments: comments,
      hasMore: json['has_more'] == true || json['has_more'] == 1,
      totalComments:
          parseOptionalInt(json['total_comments']) ?? comments.length,
      firstPostPid: parseOptionalString(json['first_post_pid']),
    );
  }
}

class TiebaComment {
  final String id;
  final String author;
  final String? authorAvatar;
  final String content;
  final DateTime createdAt;
  final int floor;
  int likes;
  bool isLiked;
  final int? forumLevel;
  final String? forumLevelName;
  final List<TiebaSubComment> subComments;
  final int subPostNumber;

  TiebaComment({
    required this.id,
    required this.author,
    this.authorAvatar,
    required this.content,
    required this.createdAt,
    required this.floor,
    required this.likes,
    this.isLiked = false,
    this.forumLevel,
    this.forumLevelName,
    this.subComments = const [],
    this.subPostNumber = 0,
  });

  factory TiebaComment.fromJson(Map<String, dynamic> json) {
    return TiebaComment(
      id: json['id']?.toString() ?? '',
      author: parseOptionalString(json['author']) ?? '匿名',
      authorAvatar: parseOptionalString(json['author_avatar']),
      content: parseOptionalString(json['content']) ?? '',
      createdAt:
          DateTime.tryParse(parseOptionalString(json['created_at']) ?? '') ??
          DateTime.now(),
      floor: parseOptionalInt(json['floor']) ?? 0,
      likes: parseOptionalInt(json['likes']) ?? 0,
      forumLevel: parseOptionalInt(json['forum_level']),
      forumLevelName: parseOptionalString(json['forum_level_name']),
      subComments: (json['sub_comments'] as List? ?? [])
          .whereType<Map>()
          .map((e) => TiebaSubComment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      subPostNumber: parseOptionalInt(json['sub_post_number']) ?? 0,
    );
  }
}

class TiebaSubComment {
  final String id;
  final String author;
  final String? authorAvatar;
  final String content;
  final DateTime createdAt;
  int likes;
  bool isLiked;
  final int? forumLevel;
  final String? forumLevelName;

  TiebaSubComment({
    required this.id,
    required this.author,
    this.authorAvatar,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.isLiked = false,
    this.forumLevel,
    this.forumLevelName,
  });

  factory TiebaSubComment.fromJson(Map<String, dynamic> json) {
    return TiebaSubComment(
      id: json['id']?.toString() ?? '',
      author: parseOptionalString(json['author']) ?? '匿名',
      authorAvatar: parseOptionalString(json['author_avatar']),
      content: parseOptionalString(json['content']) ?? '',
      createdAt:
          DateTime.tryParse(parseOptionalString(json['created_at']) ?? '') ??
          DateTime.now(),
      likes: parseOptionalInt(json['likes']) ?? 0,
      isLiked: json['is_liked'] == true || json['is_liked'] == 1,
      forumLevel: parseOptionalInt(json['forum_level']),
      forumLevelName: parseOptionalString(json['forum_level_name']),
    );
  }
}

class UserBrief {
  final int userId;
  final String userName;
  final String? portrait;
  final String? nickName;

  const UserBrief({
    required this.userId,
    required this.userName,
    this.portrait,
    this.nickName,
  });
}

class AtItem {
  final String text;
  final String fname;
  final int tid;
  final int pid;
  final UserBrief replyer;
  final bool isComment;
  final bool isThread;
  final int createTime;

  const AtItem({
    required this.text,
    required this.fname,
    required this.tid,
    required this.pid,
    required this.replyer,
    required this.isComment,
    required this.isThread,
    required this.createTime,
  });

  factory AtItem.fromJson(Map<String, dynamic> json) {
    return AtItem(
      text: json['content']?.toString() ?? '',
      fname: json['fname']?.toString() ?? '',
      tid: int.tryParse(json['thread_id']?.toString() ?? '') ?? 0,
      pid: int.tryParse(json['post_id']?.toString() ?? '') ?? 0,
      replyer: UserBrief(
        userId: int.tryParse(json['replyer']?['id']?.toString() ?? '') ?? 0,
        userName: json['replyer']?['name']?.toString() ?? '',
        portrait: json['replyer']?['portrait']?.toString(),
        nickName: json['replyer']?['name_show']?.toString(),
      ),
      isComment: (json['is_floor']?.toString() ?? '0') == '1',
      isThread: (json['is_first_post']?.toString() ?? '0') == '1',
      createTime: int.tryParse(json['time']?.toString() ?? '0') ?? 0,
    );
  }
}

class ReplyItem {
  final String text;
  final String fname;
  final int tid;
  final int pid;
  final int ppid;
  final UserBrief replyer;
  final UserBrief? postUser;
  final UserBrief? threadAuthor;
  final bool isComment;
  final int createTime;

  const ReplyItem({
    required this.text,
    required this.fname,
    required this.tid,
    required this.pid,
    required this.ppid,
    required this.replyer,
    this.postUser,
    this.threadAuthor,
    required this.isComment,
    required this.createTime,
  });
}
