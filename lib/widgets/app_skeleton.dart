import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_glass.dart';
import 'kaomoji_loader.dart';

/// 骨架屏基础条块。形状贴近真实文本行，避免内容到达后明显跳动。
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final AppColorScheme colors;

  const SkeletonLine({
    super.key,
    required this.width,
    required this.colors,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// 帖子卡骨架，形状贴近 [PostCard] / [ForumPostCard]。
class PostCardSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const PostCardSkeleton({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              SkeletonLine(width: 88, colors: colors, height: 10),
            ],
          ),
          const SizedBox(height: 14),
          SkeletonLine(width: double.infinity, colors: colors, height: 12),
          const SizedBox(height: 8),
          SkeletonLine(width: 220, colors: colors, height: 10),
        ],
      ),
    );
  }
}

/// 论坛行骨架，形状贴近 [_UserForumRow] 的高度。
class ForumRowSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const ForumRowSkeleton({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: AppDecorations.borderRadiusMd,
      ),
    );
  }
}

/// 评论骨架，形状贴近评论 cell（头像 + 昵称行 + 正文行）。
class CommentSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const CommentSkeleton({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 120, colors: colors, height: 10),
                const SizedBox(height: 8),
                SkeletonLine(width: double.infinity, colors: colors, height: 10),
                const SizedBox(height: 6),
                SkeletonLine(width: 180, colors: colors, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页信息流加载态骨架：保留项目特色的颜文字加载器，下方叠加帖子卡灰块预览。
/// 适配 [LoadingFadeView] 的居中全屏约束（内部用 [SizedBox.expand] 占位）。
class FeedSkeleton extends StatelessWidget {
  final int count;

  const FeedSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox.expand(
      child: Column(
        children: [
          const SizedBox(height: 56),
          const KaomojiLoader(size: 40),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < count; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PostCardSkeleton(colors: colors),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
