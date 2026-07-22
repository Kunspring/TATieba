import 'dart:async';

import 'dart:math' as math;

import '../models/tieba_post.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_favorite_service.dart';
import 'data_saver_service.dart';
import 'forum_recent_service.dart';
import 'browse_distill_service.dart';

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

      var newPosts = feed.posts
          .where((p) => _rememberSessionId(p.id))
          .toList();

      if (newPosts.isNotEmpty) {
        newPosts = await _rankAndDrop(newPosts);
        if (newPosts.isEmpty) continue;
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

  // -- client-side re-ranking --

  /// 三维度打分：相关性、质量、时效，按权重合成。
  static double _scorePost(
    TiebaPost post, {
    required Map<String, double> forumAffinity,
    required Set<String> recentForums,
    required double maxAffinity,
  }) {
    // ---- 相关性 0..1 ----
    double relevance = 0.0;
    final affinity = forumAffinity[post.barName] ?? 0.0;
    if (maxAffinity > 0) {
      relevance += (affinity / maxAffinity) * 0.7;
    }
    // 最近访问的吧也有信号（即使没有浏览时长）
    if (recentForums.contains(post.barName)) {
      relevance += 0.3;
    }
    relevance = relevance.clamp(0.0, 1.0);

    // ---- 质量 0..1 ----
    double quality = 0.3; // 底线分
    if (post.replyCount >= 100) {
      quality += 0.3;
    } else if (post.replyCount >= 20) {
      quality += 0.2;
    } else if (post.replyCount >= 5) {
      quality += 0.1;
    }
    if (post.likes >= 50) {
      quality += 0.15;
    } else if (post.likes >= 10) {
      quality += 0.08;
    }
    if (post.contentPreview.length >= 30) {
      quality += 0.1;
    }
    if (post.cover != null && post.cover!.isNotEmpty) {
      quality += 0.05;
    }
    if (post.video != null) {
      quality += 0.08;
    }
    quality = quality.clamp(0.0, 1.0);

    // ---- 时效 0..1 ----
    double recency = 0.5;
    final hours = DateTime.now().difference(post.createdAt).inHours;
    if (hours < 3) {
      recency += 0.3;
    } else if (hours < 12) {
      recency += 0.2;
    } else if (hours < 24) {
      recency += 0.1;
    } else if (hours > 168) {
      recency -= 0.15;
    }
    recency = recency.clamp(0.0, 1.0);

    return relevance * 0.5 + quality * 0.3 + recency * 0.2;
  }

  static Future<List<TiebaPost>> _rankAndDrop(List<TiebaPost> posts) async {
    if (posts.length <= 5) return posts;

    // 聚合用户兴趣信号
    final affinity = await BrowseDistillService.instance.getForumAffinity();
    final maxAffinity = affinity.values.isEmpty
        ? 1.0
        : affinity.values.map((v) => v.toDouble()).reduce(math.max);
    final forumAffinity = affinity.map((k, v) => MapEntry(k, v.toDouble()));

    final recent = await ForumRecentService.getRecent();
    final recentSet = recent.toSet();

    // 打分
    final scored = <({TiebaPost post, double score})>[];
    for (final post in posts) {
      scored.add((
        post: post,
        score: _scorePost(
          post,
          forumAffinity: forumAffinity,
          recentForums: recentSet,
          maxAffinity: maxAffinity,
        ),
      ));
    }

    // 多样性惩罚：同一吧后续帖逐步降权
    final forumCount = <String, int>{};
    for (var i = 0; i < scored.length; i++) {
      final item = scored[i];
      final f = item.post.barName;
      final seen = forumCount[f] ?? 0;
      if (seen > 0) {
        final penalty = (seen * 0.06).clamp(0.0, 0.18);
        scored[i] = (post: item.post, score: item.score - penalty);
      }
      forumCount[f] = seen + 1;
    }

    // 重排
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 去掉尾部低分帖（底 25%，但至少保留 60%）
    final cutIndex = (posts.length * 0.75).ceil();
    final minKeep = (posts.length * 0.6).ceil();
    final keepCount = math.max(cutIndex, minKeep);

    return scored.take(keepCount).map((s) => s.post).toList();
  }
}
