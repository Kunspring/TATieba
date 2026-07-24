import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/tieba_post.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_performance.dart';
import '../utils/cover_image_cache.dart';
import '../utils/format_relative_time.dart';
import '../utils/forum_level_style.dart';
import '../utils/open_user_home.dart';
import '../services/app_shell_controller.dart';
import '../utils/save_network_image.dart';
import 'app_fade_in.dart';
import 'user_avatar.dart';
import 'post_video_tile.dart';
import 'forum_level_badge.dart';

class PostCard extends StatelessWidget {
  final TiebaPost post;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final int? index;

  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onToggleFavorite,
    this.index,
  });

  String _formatCount(int count) {
    if (count <= 0) return '';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  Widget _buildAuthorRow(BuildContext context, AppColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => openUserHome(
              context,
              authorAvatar: post.authorAvatar,
              userName: post.author,
              barName: post.barName,
            ),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                UserAvatar(
                  imageUrl: post.authorAvatar,
                  radius: 18,
                  name: post.author,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    post.author,
                    style: AppFonts.caption(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ForumLevelStyle.hasLevel(
                  level: post.authorForumLevel,
                  levelName: post.authorForumLevelName,
                )) ...[
                  const SizedBox(width: 6),
                  ForumLevelBadge(
                    forumLevel: post.authorForumLevel,
                    forumLevelName: post.authorForumLevelName,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (post.barName.isNotEmpty) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => AppShellController.instance.openBar(post.barName),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                post.barName,
                style: AppFonts.label(color: colors.primary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImages(BuildContext context, AppColorScheme colors, int? cacheWidth) {
    if (post.video != null) {
      return GestureDetector(
        onLongPress: () => saveNetworkImage(context, post.cover!),
        child: ClipRRect(
          borderRadius: AppDecorations.borderRadiusMd,
          child: AspectRatio(
            aspectRatio: post.video!.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: post.cover!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: cacheWidth,
                  maxWidthDiskCache: cacheWidth,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                VideoPlayOverlay(
                  duration: post.video!.duration > 0
                      ? post.video!.duration
                      : null,
                  playSize: 44,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (post.covers.isNotEmpty) {
      return _buildMultiImages(context, colors, cacheWidth);
    }

    return _buildSingleImage(context, colors, cacheWidth);
  }

  Widget _buildSingleImage(BuildContext context, AppColorScheme colors, int? cacheWidth) {
    return GestureDetector(
      onLongPress: () => saveNetworkImage(context, post.cover!),
      child: ClipRRect(
        borderRadius: AppDecorations.borderRadiusMd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final imgWidth = constraints.maxWidth * 0.6;
            return CachedNetworkImage(
              imageUrl: post.cover!,
              fit: BoxFit.cover,
              width: imgWidth,
              height: imgWidth * 0.75,
              memCacheWidth: (imgWidth * 2).ceil(),
              maxWidthDiskCache: (imgWidth * 2).ceil(),
              fadeInDuration: Duration.zero,
              errorWidget: (_, _, _) => Container(
                color: Colors.grey.withValues(alpha: 0.2),
                height: imgWidth * 0.75,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMultiImages(BuildContext context, AppColorScheme colors, int? cacheWidth) {
    final images = post.covers.take(3).toList();
    return Row(
      children: List.generate(images.length, (i) {
        final isLast = i == images.length - 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8),
            child: GestureDetector(
              onLongPress: () => saveNetworkImage(context, images[i]),
              child: ClipRRect(
                borderRadius: AppDecorations.borderRadiusMd,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    memCacheWidth: cacheWidth,
                    maxWidthDiskCache: cacheWidth,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, _, _) => Container(
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomRow(BuildContext context, AppColorScheme colors) {
    return Row(
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 15, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          _formatCount(post.replyCount),
          style: AppFonts.numeric(color: colors.textMuted),
        ),
        const SizedBox(width: 14),
        Icon(Icons.schedule_rounded, size: 14, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          formatRelativeTime(post.createdAt),
          style: AppFonts.label(color: colors.textMuted),
        ),
        if (onToggleFavorite != null) ...[
          const Spacer(),
          _FavoriteButton(
            isFavorited: post.isFavorited,
            onTap: onToggleFavorite!,
            activeColor: colors.accent,
            mutedColor: colors.textMuted,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = AppDecorations.borderRadiusXl;
    final coverCacheWidth = CoverImageCache.memCacheWidth(context);
    final contentPreview = post.contentPreview;

    Widget card = RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: radius,
            border: Border.all(color: colors.borderLight, width: 0.5),
            boxShadow: AppDecorations.softShadow(colors, blur: 4),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAuthorRow(context, colors),
                    const SizedBox(height: 14),
                    Text(
                      post.title,
                      style: AppFonts.title(color: colors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contentPreview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        contentPreview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.body(color: colors.textSecondary),
                      ),
                    ],
                    if (post.cover != null && post.cover!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildImages(context, colors, coverCacheWidth),
                    ],
                    const SizedBox(height: 14),
                    _buildBottomRow(context, colors),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (AppPerformance.listItemFadeIn && index != null) {
      card = AppFadeIn(
        delay: Duration(milliseconds: 40 * (index! % 10)),
        child: card,
      );
    }
    return card;
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorited;
  final VoidCallback onTap;
  final Color activeColor;
  final Color mutedColor;

  const _FavoriteButton({
    required this.isFavorited,
    required this.onTap,
    required this.activeColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isFavorited ? 1.0 : 0.88,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Icon(
          isFavorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 22,
          color: isFavorited ? activeColor : mutedColor,
        ),
      ),
    );
  }
}
