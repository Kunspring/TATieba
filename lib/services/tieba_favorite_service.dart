import 'package:shared_preferences/shared_preferences.dart';

import '../models/tieba_post.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';

/// 本地收藏：仅保存帖子 ID，查看收藏时再按 ID 拉取详情。
class TiebaFavoriteService {
  static const _prefsKey = 'local_favorites_v1';

  static List<String>? _idCache;
  static List<TiebaPost>? _postCache;

  static void invalidateCache() {
    _idCache = null;
    _postCache = null;
  }

  static Future<List<String>> getFavoriteIds() async {
    if (_idCache != null) return List.unmodifiable(_idCache!);
    final prefs = await SharedPreferences.getInstance();
    _idCache = prefs.getStringList(_prefsKey) ?? [];
    return List.unmodifiable(_idCache!);
  }

  static Future<Set<String>> getFavoriteIdSet() async {
    return (await getFavoriteIds()).toSet();
  }

  static Future<int> getFavoriteCount() async {
    return (await getFavoriteIds()).length;
  }

  static Future<bool> isFavorited(String postId) async {
    return (await getFavoriteIds()).contains(postId);
  }

  static Future<void> applyFavoriteStatus(TiebaPost post) async {
    final ids = await getFavoriteIdSet();
    post.isFavorited = ids.contains(post.id);
  }

  static Future<void> applyFavoriteStatuses(Iterable<TiebaPost> posts) async {
    final ids = await getFavoriteIdSet();
    for (final post in posts) {
      post.isFavorited = ids.contains(post.id);
    }
  }

  /// 返回内存中已加载的收藏帖（可能为空）；计数请用 [getFavoriteCount]。
  static Future<List<TiebaPost>> getFavorites() async {
    return List.unmodifiable(_postCache ?? const []);
  }

  /// 按本地收藏的帖子 ID 重新拉取详情。
  static Future<List<TiebaPost>> loadFavoritePosts() async {
    final ids = await getFavoriteIds();
    if (ids.isEmpty) {
      _postCache = [];
      return [];
    }

    final bduss = await TiebaAccountService.getBduss();
    final stoken = await TiebaAccountService.getStoken();
    final bdussVal = (bduss != null && bduss.isNotEmpty) ? bduss : null;

    final posts = <TiebaPost>[];
    final staleIds = <String>[];

    for (final id in ids) {
      try {
        final detail = await TiebaClient.fetchPostDetail(
          id,
          bduss: bdussVal,
          stoken: stoken,
        );
        if (detail != null) {
          detail.post.isFavorited = true;
          posts.add(detail.post);
        } else {
          staleIds.add(id);
        }
      } catch (_) {
        staleIds.add(id);
      }
    }

    if (staleIds.isNotEmpty) {
      final cleaned = ids.where((id) => !staleIds.contains(id)).toList();
      await _saveIds(cleaned);
    }

    _postCache = posts;
    return List.unmodifiable(posts);
  }

  static Future<bool?> toggleFavorite(TiebaPost post) async {
    final ids = List<String>.from(await getFavoriteIds());
    if (ids.contains(post.id)) {
      ids.remove(post.id);
      await _saveIds(ids);
      post.isFavorited = false;
      _postCache?.removeWhere((p) => p.id == post.id);
      return false;
    }

    ids.insert(0, post.id);
    await _saveIds(ids);
    post.isFavorited = true;
    _postCache ??= [];
    _postCache!.removeWhere((p) => p.id == post.id);
    _postCache!.insert(0, post);
    return true;
  }

  static Future<bool> removeFavorite(TiebaPost post) async {
    final ids = List<String>.from(await getFavoriteIds());
    if (!ids.remove(post.id)) return false;
    await _saveIds(ids);
    post.isFavorited = false;
    _postCache?.removeWhere((p) => p.id == post.id);
    return true;
  }

  static Future<void> _saveIds(List<String> ids) async {
    _idCache = List.from(ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, ids);
  }
}
