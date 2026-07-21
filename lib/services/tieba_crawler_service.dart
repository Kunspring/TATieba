import 'dart:async';

import '../models/tieba_post.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_favorite_service.dart';
import 'data_saver_service.dart';

class TiebaCrawlerService {
  static final Set<String> _sessionIds = {};
  static final List<String> _sessionIdOrder = [];
  static const _maxSessionIds = 4000;
  static bool _initialLoaded = false;
  static int _loadMorePage = 1;
  static bool _recommendHasMore = true;

  static void resetPagination() {
    _initialLoaded = false;
    _loadMorePage = 1;
    _recommendHasMore = true;
    _sessionIds.clear();
    _sessionIdOrder.clear();
  }

  static Map<String, dynamic> exportState() => {
    'session_ids': _sessionIds.toList(),
    'initial_loaded': _initialLoaded,
    'load_more_page': _loadMorePage,
    'recommend_has_more': _recommendHasMore,
  };

  static void restoreState(Map<String, dynamic> state) {
    _sessionIds
      ..clear()
      ..addAll((state['session_ids'] as List? ?? []).map((e) => e.toString()));
    _sessionIdOrder
      ..clear()
      ..addAll(_sessionIds);
    _trimSessionIds();
    _initialLoaded = state['initial_loaded'] == true;
    _loadMorePage = state['load_more_page'] is int
        ? state['load_more_page'] as int
        : int.tryParse(state['load_more_page']?.toString() ?? '') ?? 1;
    _recommendHasMore = state['recommend_has_more'] != false;
  }

  static Future<List<TiebaPost>> loadInitialPosts({
    void Function(int current, int total, String barName)? onProgress,
  }) async {
    resetPagination();
    return _loadNextPage(onProgress: onProgress);
  }

  static Future<List<TiebaPost>> loadMorePosts({
    void Function(int current, int total, String barName)? onProgress,
  }) async {
    if (!_recommendHasMore) return [];
    return _loadNextPage(onProgress: onProgress);
  }

  static bool get hasMore => _recommendHasMore;

  static Future<List<TiebaPost>> _loadNextPage({
    void Function(int current, int total, String barName)? onProgress,
  }) async {
    if (!_recommendHasMore) return [];

    final bduss = await TiebaAccountService.getBduss() ?? '';
    if (bduss.isEmpty) {
      _recommendHasMore = false;
      return [];
    }

    final maxAttempts = DataSaverService.instance.enabled ? 5 : 24;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!_recommendHasMore) break;

      final feed = await _fetchRecommendPage(bduss);
      _recommendHasMore = feed.hasMore;

      if (feed.posts.isEmpty) {
        if (!_recommendHasMore) break;
        continue;
      }

      final newPosts = feed.posts
          .where((p) => _rememberSessionId(p.id))
          .toList();

      if (newPosts.isNotEmpty) {
        unawaited(_syncFavoriteStatus(newPosts));
        unawaited(_enrichForumLevels(newPosts, bduss));
        return newPosts;
      }

      if (!_recommendHasMore) break;
    }

    // 多页均为重复帖时，避免 UI 在底部无限触发加载。
    if (_recommendHasMore) {
      _recommendHasMore = false;
    }

    return [];
  }

  static Future<PersonalizedFeedPage> _fetchRecommendPage(String bduss) async {
    if (!_initialLoaded) {
      _initialLoaded = true;
      return TiebaClient.fetchPersonalized(loadType: 1, page: 1, bduss: bduss);
    }

    final page = _loadMorePage;
    _loadMorePage++;
    return TiebaClient.fetchPersonalized(loadType: 2, page: page, bduss: bduss);
  }

  static Future<void> _syncFavoriteStatus(List<TiebaPost> posts) async {
    try {
      final favIds = await TiebaFavoriteService.getFavoriteIdSet();
      for (final post in posts) {
        post.isFavorited = favIds.contains(post.id);
      }
    } catch (_) {}
  }

  static Future<void> _enrichForumLevels(
    List<TiebaPost> posts,
    String bduss,
  ) async {
    if (posts.isEmpty) return;
    final needsLevel = posts.any(
      (post) =>
          (post.authorForumLevel == null || post.authorForumLevel! <= 0) &&
          (post.authorForumLevelName?.trim().isEmpty ?? true),
    );
    if (!needsLevel) return;

    final stoken = await TiebaAccountService.getStoken();
    final dataSaver = DataSaverService.instance.enabled;
    await TiebaClient.enrichPostsForumLevels(
      posts,
      bduss: bduss,
      stoken: stoken,
      maxConcurrent: dataSaver ? 2 : 5,
      maxLookups: dataSaver ? 8 : null,
    );
  }

  static Future<void> enrichForumLevels(List<TiebaPost> posts) async {
    final bduss = await TiebaAccountService.getBduss() ?? '';
    if (bduss.isEmpty || posts.isEmpty) return;
    await _enrichForumLevels(posts, bduss);
  }

  static Future<TiebaPostDetail?> crawlPostDetail(
    String tid, {
    int page = 1,
    String? bduss,
    String? stoken,
  }) async {
    return TiebaClient.fetchPostDetail(
      tid,
      page: page,
      bduss: bduss,
      stoken: stoken,
    );
  }

  static Future<List<TiebaSubComment>> loadMoreSubComments(
    String tid,
    String pid, {
    String? bduss,
    String? stoken,
    int page = 1,
  }) async {
    return TiebaClient.fetchMoreSubComments(
      tid,
      pid,
      bduss: bduss,
      stoken: stoken,
      page: page,
    );
  }

  static Future<void> clearCache() async {
    _sessionIds.clear();
    _sessionIdOrder.clear();
    resetPagination();
  }

  static bool _rememberSessionId(String id) {
    if (_sessionIds.contains(id)) return false;
    while (_sessionIds.length >= _maxSessionIds && _sessionIdOrder.isNotEmpty) {
      final dropped = _sessionIdOrder.removeAt(0);
      _sessionIds.remove(dropped);
    }
    _sessionIds.add(id);
    _sessionIdOrder.add(id);
    return true;
  }

  static void _trimSessionIds() {
    while (_sessionIds.length > _maxSessionIds && _sessionIdOrder.isNotEmpty) {
      final dropped = _sessionIdOrder.removeAt(0);
      _sessionIds.remove(dropped);
    }
  }
}
