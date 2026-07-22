import 'package:flutter/material.dart';
import '../models/tieba_post.dart';
import '../services/tieba_favorite_service.dart';
import '../services/app_ui_context.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_icons.dart';
import '../theme/app_glass.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import 'detail/post_detail_page.dart';
import 'home/forum_post_card.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<TiebaPost> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final favs = await TiebaFavoriteService.loadFavoritePosts();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text('我的收藏', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: LoadingFadeView(
        loading: _loading,
        child: _favorites.isEmpty
            ? AppEmptyState(icon: AppIcons.bookmarkBorder, message: '还没有收藏的帖子')
            : RefreshIndicator(
                onRefresh: _loadFavorites,
                child: ListView.builder(
                  cacheExtent: 0,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    glassTopInset(context) + 8,
                    16,
                    24,
                  ),
                  itemCount: _favorites.length,
                  itemBuilder: (_, i) {
                    final post = _favorites[i];
                    return Dismissible(
                      key: ValueKey(post.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        final ok = await TiebaFavoriteService.removeFavorite(
                          post,
                        );
                        if (!context.mounted) return false;
                        if (ok) {
                          showAppToast(
                            context,
                            '已取消收藏',
                            type: AppToastType.info,
                          );
                          return true;
                        }
                        showAppToast(
                          context,
                          '取消收藏失败，请稍后重试',
                          type: AppToastType.error,
                        );
                        return false;
                      },
                      onDismissed: (_) {
                        setState(() {
                          _favorites.removeWhere((p) => p.id == post.id);
                        });
                      },
                      child: ForumPostCard(
                        post: post,
                        onTap: () {
                          Navigator.of(context).push(
                            uiPageRoute(
                              name: AppUiRouteNames.postDetail,
                              arguments: {
                                'tid': post.id,
                                if (post.title.isNotEmpty) 'title': post.title,
                                if (post.barName.isNotEmpty)
                                  'bar_name': post.barName,
                              },
                              builder: (_) => PostDetailPage(post: post),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
