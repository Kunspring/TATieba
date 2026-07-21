import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../utils/forum_level_style.dart';
import 'forum_level_badge.dart';

/// 等级展示场景：个人/用户主页仅账号等级；帖子流与阅读页仅吧等级。
enum UserLevelBadgeScope { profile, forum }

/// 账号等级 / 吧等级标签。
class UserLevelBadges extends StatelessWidget {
  final UserLevelBadgeScope scope;
  final String? growthLevelLabel;
  final String? forumLevelLabel;
  final int? forumLevel;
  final String? forumBarName;
  final bool loading;
  final int loadingPlaceholderCount;
  final bool inline;

  const UserLevelBadges({
    super.key,
    this.scope = UserLevelBadgeScope.profile,
    this.growthLevelLabel,
    this.forumLevelLabel,
    this.forumLevel,
    this.forumBarName,
    this.loading = false,
    this.loadingPlaceholderCount = 1,
    this.inline = false,
  });

  bool get _showGrowth =>
      scope == UserLevelBadgeScope.profile &&
      growthLevelLabel?.isNotEmpty == true;

  bool get _showForum =>
      scope == UserLevelBadgeScope.forum &&
      ForumLevelStyle.hasLevel(level: forumLevel, levelName: forumLevelLabel);

  bool get _hasAny => _showGrowth || _showForum;

  @override
  Widget build(BuildContext context) {
    if (!loading && !_hasAny) return const SizedBox.shrink();

    final colors = context.appColors;
    final placeholderCount = loadingPlaceholderCount.clamp(1, 2);

    if (inline) {
      if (loading) {
        return _InlineBadgeSkeleton(colors: colors);
      }
      if (!_hasAny) return const SizedBox.shrink();
      if (_showGrowth) {
        return _InlineBadge(label: growthLevelLabel!, colors: colors);
      }
      return ForumLevelBadge(
        forumLevel: forumLevel,
        forumLevelName: forumLevelLabel,
        compact: true,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [...previousChildren, ?currentChild],
          );
        },
        child: loading
            ? _BadgeSkeletonRow(
                key: const ValueKey('level-badges-loading'),
                count: placeholderCount,
                colors: colors,
              )
            : Wrap(
                key: const ValueKey('level-badges-content'),
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_showGrowth)
                    _Badge(
                      caption: '账号',
                      label: growthLevelLabel!,
                      colors: colors,
                    ),
                  if (_showForum)
                    ForumLevelBadgeDetailed(
                      forumLevel: forumLevel,
                      forumLevelName: forumLevelLabel,
                      forumBarName: forumBarName,
                    ),
                ],
              ),
      ),
    );
  }
}

class _InlineBadgeSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const _InlineBadgeSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 22,
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.85),
        borderRadius: AppDecorations.borderRadiusSm,
        border: Border.all(color: colors.borderLight.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  final String label;
  final AppColorScheme colors;

  const _InlineBadge({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primaryLight.withValues(alpha: 0.45),
        borderRadius: AppDecorations.borderRadiusSm,
        border: Border.all(color: colors.borderLight, width: 0.6),
      ),
      child: Text(
        label,
        style: AppFonts.caption(
          color: colors.textPrimary,
        ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

class _BadgeSkeletonRow extends StatelessWidget {
  final int count;
  final AppColorScheme colors;

  const _BadgeSkeletonRow({
    super.key,
    required this.count,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: List.generate(count, (_) => _BadgeSkeleton(colors: colors)),
    );
  }
}

class _BadgeSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const _BadgeSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 28,
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.85),
        borderRadius: AppDecorations.borderRadiusMd,
        border: Border.all(color: colors.borderLight.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String caption;
  final String label;
  final AppColorScheme colors;

  const _Badge({
    required this.caption,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryLight.withValues(alpha: 0.45),
        borderRadius: AppDecorations.borderRadiusMd,
        border: Border.all(color: colors.borderLight, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption, style: AppFonts.caption(color: colors.textMuted)),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppFonts.caption(
              color: colors.textPrimary,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
