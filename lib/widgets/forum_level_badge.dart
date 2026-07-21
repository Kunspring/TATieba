import 'package:flutter/material.dart';

import '../theme/app_decorations.dart';

import '../theme/app_fonts.dart';

import '../utils/forum_level_style.dart';

/// 紧凑的吧内等级标签，用于评论/帖子流昵称旁。

class ForumLevelBadge extends StatelessWidget {
  final int? forumLevel;

  final String? forumLevelName;

  final bool compact;

  const ForumLevelBadge({
    super.key,

    this.forumLevel,

    this.forumLevelName,

    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!ForumLevelStyle.hasLevel(
      level: forumLevel,

      levelName: forumLevelName,
    )) {
      return const SizedBox.shrink();
    }

    final level = forumLevel ?? 0;

    final style = ForumLevelStyle.forLevel(level);

    final label = ForumLevelStyle.displayLabel(
      level: forumLevel,

      levelName: forumLevelName,
    );

    return _ForumLevelChip(style: style, label: label, compact: compact);
  }
}

/// 带吧名前缀的等级标签（个人页 / 楼主信息块）。

class ForumLevelBadgeDetailed extends StatelessWidget {
  final int? forumLevel;

  final String? forumLevelName;

  final String? forumBarName;

  const ForumLevelBadgeDetailed({
    super.key,

    this.forumLevel,

    this.forumLevelName,

    this.forumBarName,
  });

  @override
  Widget build(BuildContext context) {
    if (!ForumLevelStyle.hasLevel(
      level: forumLevel,

      levelName: forumLevelName,
    )) {
      return const SizedBox.shrink();
    }

    final level = forumLevel ?? 0;

    final style = ForumLevelStyle.forLevel(level);

    final label = ForumLevelStyle.displayLabel(
      level: forumLevel,

      levelName: forumLevelName,
    );

    final caption = forumBarName?.trim().isNotEmpty == true
        ? forumBarName!.trim()
        : '吧内';

    return _ForumLevelChip(
      style: style,

      label: label,

      caption: caption,

      compact: false,
    );
  }
}

class _ForumLevelChip extends StatelessWidget {
  final ForumLevelStyle style;

  final String label;

  final String? caption;

  final bool compact;

  const _ForumLevelChip({
    required this.style,

    required this.label,

    this.caption,

    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = style.backgroundColor;

    final textStyle = AppFonts.caption(color: accent).copyWith(
      fontSize: compact ? 10 : null,

      fontWeight: compact ? FontWeight.w600 : FontWeight.w700,

      height: 1.2,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,

        vertical: compact ? 2 : 5,
      ),

      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),

        borderRadius: compact
            ? AppDecorations.borderRadiusSm
            : AppDecorations.borderRadiusMd,

        border: Border.all(color: accent.withValues(alpha: 0.55), width: 0.6),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          if (caption != null) ...[
            Text(caption!, style: textStyle),

            SizedBox(width: compact ? 3 : 4),
          ],

          Text(
            label,

            style: textStyle,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
