import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_colors.dart';
import '../utils/markdown_media.dart';
import '../utils/tieba_emoticon.dart';

/// 评论/回复正文：纯文本走轻量 [Text]，含图链码块等再走 [Markdown]。
abstract final class CommentContentBody {
  CommentContentBody._();

  static final _richPatterns = <RegExp>[
    RegExp(r'!\[[^\]]*\]\([^)]+\)'),
    RegExp(r'\[[^\]]+\]\([^)]+\)'),
    RegExp(r'\[video[^\]]*\]\([^)]+\)', caseSensitive: false),
    RegExp(r'`'),
    RegExp(r'\*\*'),
    RegExp(r'^#{1,6}\s', multiLine: true),
    RegExp(r'<[^>]+>'),
    TiebaEmoticon.bracketPattern,
  ];

  static bool needsRichRender(String content) {
    if (content.isEmpty) return false;
    for (final pattern in _richPatterns) {
      if (pattern.hasMatch(content)) return true;
    }
    return false;
  }

  static Widget build({
    required BuildContext context,
    required String content,
    required TextStyle baseStyle,
    required void Function(String url) onImageTap,
    double fontScale = 1.0,
    bool selectable = false,
  }) {
    if (content.isEmpty) return const SizedBox.shrink();

    if (!needsRichRender(content)) {
      final style = baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 14) * fontScale,
        height: 1.55,
      );
      if (selectable) {
        return SelectableText(content, style: style);
      }
      return Text(content, style: style);
    }

    final colors = context.appColors;
    // 必须用 MarkdownBody 而非 Markdown：顶层 Markdown 内部会再包一层 ListView，
    // 嵌在 SliverList 里会形成「ListView 套 SliverList」的嵌套滚动视图，导致 sliver
    // 在滚动时反复重测条目高度、滚动位置一跳一跳（观感即「加载内容导致布局突变」）。
    // MarkdownBody 只生成 Column、无嵌套滚动视图；fitContent:false 让块级图片拿到
    // 完整宽度，AspectRatio 才能据此预留高度、避免图片加载后撑开布局。
    return MarkdownBody(
      data: content,
      shrinkWrap: true,
      fitContent: false,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * fontScale),
        a: TextStyle(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
        img: const TextStyle(),
        code: TextStyle(
          backgroundColor: colors.surfaceMuted,
          fontSize: 13 * fontScale,
        ),
      ),
      sizedImageBuilder: (config) => buildMarkdownMedia(
        context,
        config: config,
        onImageTap: onImageTap,
        fontScale: fontScale,
      ),
    );
  }
}
