import '../models/tieba_post.dart';
import 'post_content_plain.dart';

/// 将帖子 Markdown/富文本转为适合 Agent 阅读的纯文本。
abstract final class AgentPostReader {
  AgentPostReader._();

  static const maxBodyChars = 6000;
  static const maxCommentChars = 420;
  static const maxComments = 36;
  static const maxHotComments = 8;

  static String plainText(String raw) => PostContentPlain.from(raw);

  static String clip(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }

  static Map<String, dynamic> buildReadPayload({
    required TiebaPostDetail detail,
    required List<TiebaComment> comments,
    String? focus,
    required int commentPagesFetched,
    required bool hasMoreComments,
  }) {
    final post = detail.post;
    final bodyPlain = plainText(post.content);
    final bodyTruncated = bodyPlain.length > maxBodyChars;
    final hasVideo = post.video != null && post.video!.src.isNotEmpty;

    final mappedComments = comments.take(maxComments).map(_mapComment).toList();
    final hotComments = [...comments]
      ..sort((a, b) => b.likes.compareTo(a.likes));
    final mappedHot = hotComments
        .where((c) => c.content.trim().isNotEmpty)
        .take(maxHotComments)
        .map(_mapComment)
        .toList();

    final excerpt = clip(bodyPlain, 220);

    return {
      'tid': post.id,
      'title': post.title,
      'author': post.author,
      'bar_name': post.barName,
      'reply_count': detail.totalComments,
      'has_video': hasVideo,
      if (focus != null && focus.isNotEmpty) 'focus': focus,
      'body_plain': bodyTruncated ? clip(bodyPlain, maxBodyChars) : bodyPlain,
      if (bodyTruncated) 'body_truncated': true,
      'body_excerpt': excerpt,
      'comments_included': mappedComments.length,
      'comment_pages_fetched': commentPagesFetched,
      if (hasMoreComments) 'has_more_comments': true,
      'comments': mappedComments,
      if (mappedHot.isNotEmpty) 'hot_comments': mappedHot,
      'reading_summary': _readingSummary(
        title: post.title,
        bodyPlain: bodyPlain,
        commentCount: detail.totalComments,
        includedComments: mappedComments.length,
        focus: focus,
        hasVideo: hasVideo,
      ),
      'agent_note':
          '这是完整阅读包，请基于 body_plain 与 comments 理解后再回答用户；'
          '不要假装读过未返回的内容；关键词搜索不能代替本工具。',
    };
  }

  static Map<String, dynamic> _mapComment(TiebaComment comment) {
    final plain = clip(plainText(comment.content), maxCommentChars);
    final subs = comment.subComments
        .where((s) => s.content.trim().isNotEmpty)
        .take(3)
        .map(
          (s) => {
            'author': s.author,
            'content': clip(plainText(s.content), 180),
            'likes': s.likes,
          },
        )
        .toList();
    return {
      'floor': comment.floor,
      'author': comment.author,
      'likes': comment.likes,
      'content': plain,
      if (subs.isNotEmpty) 'sub_comments': subs,
      if (comment.subPostNumber > subs.length) 'more_sub_replies': true,
    };
  }

  static String _readingSummary({
    required String title,
    required String bodyPlain,
    required int commentCount,
    required int includedComments,
    String? focus,
    required bool hasVideo,
  }) {
    final bits = <String>[
      if (title.trim().isNotEmpty) '《$title》',
      if (hasVideo) '含视频',
      if (bodyPlain.isNotEmpty) '正文约 ${bodyPlain.length} 字' else '正文较短或仅有媒体',
      '评论共 $commentCount 条，已读 $includedComments 条',
      if (focus != null && focus.isNotEmpty) '关注：$focus',
    ];
    return bits.join(' · ');
  }
}

List<TiebaComment> mergeAgentReadComments(
  List<TiebaComment> current,
  List<TiebaComment> more,
) {
  final ids = current.map((c) => c.id).toSet();
  final merged = List<TiebaComment>.from(current);
  for (final comment in more) {
    if (ids.add(comment.id)) merged.add(comment);
  }
  return merged;
}
