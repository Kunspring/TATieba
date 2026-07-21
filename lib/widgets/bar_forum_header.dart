import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/bar_forum_context.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../utils/forum_level_style.dart';
import 'forum_level_badge.dart';
import 'kaomoji_loader.dart';

class BarForumHeader extends StatelessWidget {
  const BarForumHeader({
    super.key,
    required this.forumContext,
    required this.selectedTab,
    required this.loading,
    required this.followLoading,
    required this.signingIn,
    required this.loggedIn,
    required this.onTabChanged,
    required this.onToggleFollow,
    required this.onSignIn,
    required this.onOpenPinned,
  });

  final BarForumContext forumContext;
  final BarFrsTab selectedTab;
  final bool loading;
  final bool followLoading;
  final bool signingIn;
  final bool loggedIn;
  final ValueChanged<BarFrsTab> onTabChanged;
  final VoidCallback onToggleFollow;
  final VoidCallback onSignIn;
  final ValueChanged<BarForumThreadBrief> onOpenPinned;

  @override
  Widget build(BuildContext buildContext) {
    final colors = buildContext.appColors;
    final ctx = forumContext;
    final showLevel =
        loggedIn &&
        ForumLevelStyle.hasLevel(
          level: ctx.forumLevel,
          levelName: ctx.forumLevelName,
        );
    final showExp = loggedIn && ctx.levelUpExp > 0;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BarAvatar(url: ctx.avatarUrl, colors: colors),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ctx.barName,
                        style: AppFonts.title(
                          color: colors.textPrimary,
                        ).copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ctx.slogan?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 5),
                        Text(
                          ctx.slogan!.trim(),
                          style: AppFonts.bodySmall(color: colors.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (ctx.memberCount != null && ctx.memberCount! > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.groups_rounded,
                              size: 14,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatCount(ctx.memberCount!)} 吧友',
                              style: AppFonts.label(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (loggedIn) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      colors: colors,
                      label: ctx.signedToday == true ? '已签到' : '签到',
                      icon: ctx.signedToday == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.edit_calendar_outlined,
                      loading: signingIn,
                      enabled: ctx.signedToday != true && !signingIn,
                      filled: ctx.signedToday != true,
                      onTap: onSignIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      colors: colors,
                      label: ctx.followed ? '已关注' : '关注',
                      icon: ctx.followed
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      loading: followLoading,
                      enabled: !followLoading,
                      filled: !ctx.followed,
                      onTap: onToggleFollow,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showLevel || showExp) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted.withValues(alpha: 0.55),
                  borderRadius: AppDecorations.borderRadiusMd,
                  border: Border.all(
                    color: colors.borderLight.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '我的吧内',
                          style: AppFonts.caption(color: colors.textMuted),
                        ),
                        const Spacer(),
                        if (showLevel)
                          ForumLevelBadgeDetailed(
                            forumLevel: ctx.forumLevel,
                            forumLevelName: ctx.forumLevelName.isNotEmpty
                                ? ctx.forumLevelName
                                : null,
                            forumBarName: ctx.barName,
                          ),
                      ],
                    ),
                    if (showExp) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: AppDecorations.borderRadiusPill,
                        child: LinearProgressIndicator(
                          value: ctx.expProgress,
                          minHeight: 5,
                          backgroundColor: colors.card.withValues(alpha: 0.8),
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '经验 ${ctx.currentExp} / ${ctx.levelUpExp}',
                        style: AppFonts.label(color: colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          Divider(height: 1, color: colors.divider.withValues(alpha: 0.7)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GlassSegmentTabs<BarFrsTab>(
              selected: selectedTab,
              onChanged: onTabChanged,
              options: const [
                GlassSegmentOption(value: BarFrsTab.latest, label: '最新'),
                GlassSegmentOption(value: BarFrsTab.good, label: '精华'),
              ],
            ),
          ),
          if (ctx.pinnedThreads.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                '置顶',
                style: AppFonts.caption(color: colors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            ...ctx.pinnedThreads
                .take(4)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: _HighlightTile(
                      colors: colors,
                      title: item.title,
                      onTap: () => onOpenPinned(item),
                    ),
                  ),
                ),
          ],
          if (ctx.forumRule?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: _ForumRuleBlock(
                colors: colors,
                rule: ctx.forumRule!.trim(),
              ),
            )
          else
            const SizedBox(height: 14),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: KaomojiLoader(size: 24, color: colors.primary),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

class _BarAvatar extends StatelessWidget {
  const _BarAvatar({required this.url, required this.colors});

  final String? url;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderLight.withValues(alpha: 0.6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: 64,
          height: 64,
          child: url != null && url!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  memCacheWidth: 128,
                  maxWidthDiskCache: 128,
                  errorWidget: (_, _, _) => _placeholder(),
                )
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: colors.surfaceMuted,
      child: Icon(Icons.forum_rounded, color: colors.textSecondary, size: 28),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.colors,
    required this.label,
    required this.icon,
    required this.loading,
    required this.enabled,
    required this.filled,
    required this.onTap,
  });

  final AppColorScheme colors;
  final String label;
  final IconData icon;
  final bool loading;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? colors.primary.withValues(alpha: enabled ? 0.12 : 0.06)
        : colors.surfaceMuted.withValues(alpha: 0.65);
    final fg = filled
        ? (enabled ? colors.primary : colors.textMuted)
        : (enabled ? colors.textSecondary : colors.textMuted);

    return Material(
      color: bg,
      borderRadius: AppDecorations.borderRadiusMd,
      child: InkWell(
        onTap: enabled && !loading ? onTap : null,
        borderRadius: AppDecorations.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                KaomojiLoader(size: 18, color: fg)
              else ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppFonts.caption(
                    color: fg,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.colors,
    required this.title,
    required this.onTap,
  });

  final AppColorScheme colors;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceMuted.withValues(alpha: 0.35),
      borderRadius: AppDecorations.borderRadiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDecorations.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: AppDecorations.borderRadiusSm,
                ),
                child: Text(
                  '置顶',
                  style: AppFonts.label(
                    color: colors.primary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.bodySmall(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumRuleBlock extends StatefulWidget {
  const _ForumRuleBlock({required this.colors, required this.rule});

  final AppColorScheme colors;
  final String rule;

  @override
  State<_ForumRuleBlock> createState() => _ForumRuleBlockState();
}

class _ForumRuleBlockState extends State<_ForumRuleBlock> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Material(
      color: colors.surfaceMuted.withValues(alpha: 0.45),
      borderRadius: AppDecorations.borderRadiusMd,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: AppDecorations.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.gavel_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '吧规',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.rule,
                style: AppFonts.bodySmall(color: colors.textPrimary),
                maxLines: _expanded ? null : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
