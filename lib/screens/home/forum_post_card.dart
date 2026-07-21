import '../../widgets/post_card.dart';

/// 收藏等场景使用的帖子卡片（与首页 PostCard 样式一致）。
class ForumPostCard extends PostCard {
  const ForumPostCard({
    super.key,
    required super.post,
    required super.onTap,
    super.onToggleFavorite,
    super.index,
  });
}
