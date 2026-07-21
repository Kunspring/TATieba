import 'markdown_media.dart';
import 'tieba_emoticon.dart';

/// 帖子 Markdown 正文 → 列表卡片 / 摘要用的纯文本。
abstract final class PostContentPlain {
  PostContentPlain._();

  static String from(String raw) {
    var text = raw;
    if (text.isEmpty) return '';

    text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (m) =>
          _tokenForImageMarkdown(alt: m.group(1) ?? '', url: m.group(2) ?? ''),
    );
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) =>
          _tokenForImageMarkdown(alt: m.group(1) ?? '', url: m.group(2) ?? ''),
    );
    text = text.replaceAll(
      RegExp(r'\[video[^\]]*\]\([^)]+\)', caseSensitive: false),
      '[视频]',
    );
    text = text.replaceAllMapped(TiebaEmoticon.bracketPattern, (match) {
      final name = match.group(1)!;
      if (name == '图片/表情') return name;
      if (TiebaEmoticon.urlForName(name) != null) return '[表情]';
      return match.group(0)!;
    });
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text.replaceAll(RegExp(r'`{1,3}([^`]+)`{1,3}'), r'$1');
    text = text.replaceAll(RegExp(r'\*{1,2}([^*]+)\*{1,2}'), r'$1');
    text = text.replaceAll(RegExp(r'#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'\r\n?'), '\n');
    text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  static String _tokenForImageMarkdown({
    required String alt,
    required String url,
  }) {
    if (isVideoMarkdownAlt(alt)) return '[视频]';
    if (_isEmoticonMarkdown(alt, url)) return '[表情]';
    return '[图片]';
  }

  static bool _isEmoticonMarkdown(String alt, String url) {
    if (alt == 'emoticon' || alt == '表情') return true;
    return url.contains('image_emoticon') || url.contains('/tb/editor/images/');
  }
}
