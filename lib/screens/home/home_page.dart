import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../models/bar_forum_context.dart';
import '../../models/tieba_post.dart';
import '../../utils/app_lifecycle_gate.dart';
import '../../utils/list_update_scheduler.dart';
import '../../utils/scroll_load_trigger.dart';
import '../../utils/scroll_settle.dart';
import '../../utils/app_resume_refresh.dart';
import '../../services/home_feed_session.dart';
import '../../services/app_shell_controller.dart';
import '../../services/app_ui_context.dart';
import '../../services/data_saver_service.dart';
import '../../services/tieba_account_service.dart';
import '../../services/tieba_client.dart';
import '../../services/tieba_crawler_service.dart';
import '../../services/tieba_favorite_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_glass.dart';

import '../../widgets/app_empty_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/splash_overlay.dart';
import '../../widgets/bar_forum_header.dart';
import '../../widgets/kaomoji_loader.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/agent_companion/agent_companion_controller.dart';
import '../../utils/cover_image_cache.dart';
import '../../utils/image_preloader.dart';
import '../../widgets/post_card.dart';
import '../detail/post_detail_page.dart';
import '../login_hub_page.dart';

class HomePage extends StatefulWidget {
  final String? selectedBar;
  final VoidCallback? onClearBar;

  const HomePage({
    super.key,
    this.selectedBar,
    this.onClearBar,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );
  static const _refreshTriggerPullDistance = 58.0;
  static const _refreshIndicatorBody = 36.0;
  static const _refreshGapBelowAppBar = 6.0;

  double _refreshIndicatorExtent(BuildContext context) =>
      glassTopInset(context) + _refreshGapBelowAppBar + _refreshIndicatorBody;

  final _scrollController = ScrollController();
  late final ScrollLoadTrigger _scrollLoadTrigger = ScrollLoadTrigger(
    onNearEnd: _loadMore,
  );
  final _loadingMoreNotifier = ValueNotifier(false);
  List<TiebaPost> _posts = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _isLoggedIn = false;
  int _barPage = 0;
  bool? _barFollowed;
  bool _barFollowLoading = false;
  bool _barSigningIn = false;
  BarForumContext? _barContext;
  bool _barContextLoading = false;
  BarFrsTab _barTab = BarFrsTab.latest;
  Timer? _backgroundPersistTimer;
  static const _backgroundPersistDelay = Duration(milliseconds: 1200);

  // 打开 App（冷启动/从后台回前台）自动刷新首页所需的节流与状态记录。
  DateTime? _bgPausedAt;
  DateTime? _lastAutoRefreshAt;
  // 与"打开即刷新"的统一节流保持一致：从后台回前台超过该间隔才静默刷新。
  static const _autoRefreshMinInterval = kResumeRefreshMinInterval;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollLoadTrigger.attach(_scrollController);
    _bootstrap();
  }

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    if (widget.selectedBar != old.selectedBar) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _backgroundPersistTimer?.cancel();
    unawaited(HomeFeedSession.flush(_bar));
    _scrollLoadTrigger.dispose();
    _loadingMoreNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatOpen =
        AgentCompanionScope.maybeOf(context)?.agentChatOpen ?? false;
    if (chatOpen) {
      if (state != AppLifecycleState.resumed) {
        _haltScrollSilently();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _backgroundPersistTimer?.cancel();
      _maybeAutoRefreshOnResume();
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _bgPausedAt ??= DateTime.now();
      _haltScrollAndLoads();
      _scheduleBackgroundPersist();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _bgPausedAt ??= DateTime.now();
      _scheduleBackgroundPersist();
    }
  }

  // 从后台回前台时，若离开时间较长（或超过节流间隔）则静默刷新首页。
  void _maybeAutoRefreshOnResume() {
    if (AgentCompanionScope.maybeOf(context)?.agentChatOpen ?? false) return;
    final pausedAt = _bgPausedAt;
    _bgPausedAt = null;
    if (pausedAt == null) return;
    if (DateTime.now().difference(pausedAt) >= _autoRefreshMinInterval) {
      _autoRefresh();
    }
  }

  // 静默后台刷新首页：先展示已有内容，刷新完成后无感更新，不弹骨架屏。
  // force=true 用于冷启动，忽略节流限制；force=false 用于回前台，受节流保护。
  void _autoRefresh([bool force = false]) {
    if (!mounted || !AppLifecycleGate.isActive) return;
    if (_loading || _loadingMoreNotifier.value) return;
    final now = DateTime.now();
    if (!force &&
        _lastAutoRefreshAt != null &&
        now.difference(_lastAutoRefreshAt!) < _autoRefreshMinInterval) {
      return;
    }
    _lastAutoRefreshAt = now;
    unawaited(_loadPosts());
  }

  void _scheduleBackgroundPersist() {
    _backgroundPersistTimer?.cancel();
    _backgroundPersistTimer = Timer(_backgroundPersistDelay, () {
      if (!mounted || AppLifecycleGate.isActive) return;
      _persistSession();
    });
  }

  void _haltScrollSilently() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.isScrollingNotifier.value) {
      _scrollController.jumpTo(_scrollController.offset);
    }
  }

  void _haltScrollAndLoads() {
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      if (_scrollController.position.isScrollingNotifier.value) {
        _scrollController.jumpTo(offset);
      }
    }
    if (_loadingMoreNotifier.value) {
      _loadingMoreNotifier.value = false;
    }
  }

  String? get _bar => widget.selectedBar;
  bool get _isSingleBar => _bar != null;

  Future<void> _bootstrap() async {
    final loggedIn = await TiebaAccountService.isBound();
    if (!mounted) return;

    final snapshot = await HomeFeedSession.load(_bar);
    if (!mounted) return;

    final shouldAutoLoad =
        (snapshot == null || snapshot.posts.isEmpty) &&
        (loggedIn || widget.selectedBar != null);

    setState(() {
      _isLoggedIn = loggedIn;
      _loading = shouldAutoLoad;
      _loadingMoreNotifier.value = false;
      _barFollowed = null;
      _barContext = null;
      _barTab = BarFrsTab.latest;
      _barContextLoading = false;
      if (snapshot != null && snapshot.posts.isNotEmpty) {
        _posts = snapshot.posts;
        _hasMore = snapshot.hasMore;
        _barPage = snapshot.barPage;
        if (!_isSingleBar && snapshot.crawlerState != null) {
          TiebaCrawlerService.restoreState(snapshot.crawlerState!);
        }
      } else {
        _posts = [];
        _hasMore = true;
        _barPage = 0;
      }
    });

    if (shouldAutoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPosts();
      });
    } else if (!_isSingleBar && _posts.isNotEmpty) {
      _scheduleRecommendLevelEnrich();
    }

    // 冷启动且已有缓存内容时，首帧后静默刷新首页：既保证秒开，又让内容保持最新。
    if (!shouldAutoLoad && _posts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoRefresh(true);
      });
    }

    final offset = snapshot?.scrollOffset ?? 0;
    if (offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(offset.clamp(0.0, max));
      });
    }

    if (loggedIn && _isSingleBar) {
      _loadBarContext();
    } else if (_isSingleBar) {
      _loadBarContext(loggedIn: false);
    }

    // 有缓存数据即刻通知开屏；无缓存则等 _loadPosts 网络回调
    if (!shouldAutoLoad) {
      SplashOverlay.ready.value = true;
    }
  }

  Future<void> _loadBarContext({bool? loggedIn}) async {
    if (!_isSingleBar || _bar == null) return;
    final isLoggedIn = loggedIn ?? _isLoggedIn;
    setState(() => _barContextLoading = true);
    BarForumContext? ctx;
    if (isLoggedIn) {
      ctx = await TiebaAccountService.fetchBarForumContext(_bar!);
    } else {
      ctx = await TiebaClient.fetchBarForumContext(_bar!, followed: false);
    }
    if (!mounted) return;
    setState(() {
      _barContext = ctx;
      _barContextLoading = false;
      if (ctx != null) _barFollowed = ctx.followed;
    });
  }

  Widget? _buildBarForumHeader(AppColorScheme colors) {
    if (!_isSingleBar) return null;
    final ctx = _barContext;
    if (ctx == null) {
      if (!_barContextLoading) return null;
      return const SizedBox(
        height: 140,
        child: Center(child: KaomojiLoader(size: 36)),
      );
    }
    return BarForumHeader(
      forumContext: ctx.copyWith(followed: _barFollowed ?? ctx.followed),
      selectedTab: _barTab,
      loading: _loading && _posts.isEmpty,
      followLoading: _barFollowLoading,
      signingIn: _barSigningIn,
      loggedIn: _isLoggedIn,
      onTabChanged: _onBarTabChanged,
      onToggleFollow: _toggleBarFollow,
      onSignIn: _signInCurrentBar,
      onOpenPinned: _openPinnedThread,
    );
  }

  List<Widget> _barHeaderSlivers(AppColorScheme colors, double topPad) {
    final header = _buildBarForumHeader(colors);
    if (header == null) return [];
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, topPad, 16, 0),
        sliver: SliverToBoxAdapter(child: header),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  Future<void> _toggleBarFollow() async {
    if (_bar == null || _barFollowLoading) return;
    if (!_isLoggedIn) {
      final result = await Navigator.of(context).pushNamed('/login');
      if (result == true) {
        await _loadPostsWithLoginCheck();
      }
      return;
    }
    setState(() => _barFollowLoading = true);
    final bar = _bar!;
    final wasFollowed = _barFollowed ?? false;
    final ok = wasFollowed
        ? await TiebaAccountService.unfollowBar(bar)
        : await TiebaAccountService.followBar(bar);
    if (!mounted) return;
    setState(() {
      _barFollowLoading = false;
      if (ok) {
        _barFollowed = !wasFollowed;
        _barContext = _barContext?.copyWith(followed: _barFollowed ?? false);
      }
    });
    if (ok) {
      _loadBarContext();
      showAppToast(
        context,
        wasFollowed ? '已取消关注' : '已关注',
        type: wasFollowed ? AppToastType.info : AppToastType.success,
      );
    } else {
      showAppToast(context, '操作失败，请稍后重试', type: AppToastType.error);
    }
  }

  Future<void> _signInCurrentBar() async {
    if (_bar == null || _barSigningIn) return;
    if (!_isLoggedIn) {
      final result = await Navigator.of(context).pushNamed('/login');
      if (result == true) await _loadPostsWithLoginCheck();
      return;
    }
    setState(() => _barSigningIn = true);
    final result = await TiebaAccountService.signInBar(_bar!);
    if (!mounted) return;
    setState(() {
      _barSigningIn = false;
      if (result.success) {
        _barContext = _barContext?.copyWith(signedToday: true);
        _loadBarContext();
      }
    });
    showAppToast(
      context,
      result.message,
      type: result.success ? AppToastType.success : AppToastType.error,
    );
  }

  void _onBarTabChanged(BarFrsTab tab) {
    if (!_isSingleBar || _barTab == tab) return;
    setState(() {
      _barTab = tab;
      _barPage = 0;
      _posts = [];
      _loading = true;
      _hasMore = true;
    });
    _loadBarPosts();
  }

  void _openPinnedThread(BarForumThreadBrief item) {
    if (_bar == null) return;
    final post = TiebaPost(
      id: item.id,
      title: item.title,
      author: '',
      content: '',
      barName: _bar!,
      replyCount: 0,
      createdAt: DateTime.now(),
      likes: 0,
    );
    AppShellController.instance.dismissChatForNavigation();
    Navigator.of(context).push(
      uiPageRoute(
        name: AppUiRouteNames.postDetail,
        arguments: {
          'tid': post.id,
          'title': post.title,
          'bar_name': post.barName,
        },
        builder: (_) =>
            PostDetailPage(post: post, posts: _posts, initialIndex: 0),
      ),
    );
  }

  void _preloadImages(List<TiebaPost> posts) {
    if (posts.isEmpty) return;
    final urls = <String>[];
    for (final p in posts) {
      if (p.cover != null && p.cover!.isNotEmpty) urls.add(p.cover!);
      if (p.covers.isNotEmpty) urls.addAll(p.covers);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ImagePreloader.warm(context, urls,
          maxWidth: CoverImageCache.memCacheWidth(context));
    });
  }

  void _persistSession() {
    if (_posts.isEmpty) return;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    HomeFeedSession.save(
      _bar,
      HomeFeedSnapshot(
        posts: _posts,
        hasMore: _hasMore,
        barPage: _barPage,
        scrollOffset: offset,
        crawlerState: _isSingleBar ? null : TiebaCrawlerService.exportState(),
      ),
    );
  }

  void _scheduleRecommendLevelEnrich() {
    if (_isSingleBar || _posts.isEmpty) return;
    final needsLevel = _posts.any(
      (post) =>
          (post.authorForumLevel == null || post.authorForumLevel! <= 0) &&
          (post.authorForumLevelName?.trim().isEmpty ?? true),
    );
    if (!needsLevel) return;

    final levelsBefore = _posts
        .map((post) => post.authorForumLevel)
        .toList(growable: false);
    TiebaCrawlerService.enrichForumLevels(_posts).then((_) {
      if (!mounted) return;
      var changed = false;
      for (var i = 0; i < _posts.length && i < levelsBefore.length; i++) {
        if (levelsBefore[i] != _posts[i].authorForumLevel) {
          changed = true;
          break;
        }
      }
      if (!changed) return;
      runWhenScrollSettled(_scrollController, () {
        if (!mounted) return;
        setState(() {});
      });
    });
  }

  Future<void> _loadPostsWithLoginCheck() async {
    final loggedIn = await TiebaAccountService.isBound();
    if (!mounted) return;
    setState(() => _isLoggedIn = loggedIn);
    if (loggedIn && _isSingleBar) {
      await _loadBarContext();
    }
  }

  /// 供帖子详情页"下滑看下一篇"使用的加载回调（与推荐流同一份数据）。
  Future<List<TiebaPost>> Function()? _buildLoadMore() {
    if (!_hasMore) return null;
    return () async {
      if (!_hasMore) return <TiebaPost>[];
      final more = await TiebaCrawlerService.loadMorePosts();
      if (!mounted) return <TiebaPost>[];
      setState(() {
        _posts.addAll(more);
        _hasMore = TiebaCrawlerService.hasMore;
      });
      _preloadImages(more);
      _persistSession();
      return more;
    };
  }

  Future<void> _loadPosts() async {
    final refreshing = _posts.isNotEmpty;
    if (_isSingleBar) {
      _barPage = 0;
      await _loadBarPosts(refresh: refreshing);
    } else {
      await _loadCrawlerPosts(refresh: refreshing);
    }
  }

  Future<void> _loadCrawlerPosts({bool refresh = false}) async {
    if (!refresh) {
      setState(() {
        _loading = true;
        _hasMore = true;
      });
    } else {
      setState(() => _hasMore = true);
    }
    try {
      final posts = await TiebaCrawlerService.loadInitialPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
        _hasMore = TiebaCrawlerService.hasMore;
      });
      _preloadImages(posts);
      SplashOverlay.ready.value = true;
      _scheduleRecommendLevelEnrich();
      _persistSession();
      _scheduleScrollCheck();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
      });
      SplashOverlay.ready.value = true;
    }
  }

  Future<List<TiebaPost>> _fetchBarPage(String bar, int page, String? bduss) {
    return TiebaClient.fetchBarThreads(
      bar,
      page: page,
      bduss: bduss,
      isGood: _barTab.isGood,
    );
  }

  Future<void> _loadBarPosts({
    bool append = false,
    bool refresh = false,
  }) async {
    if (!append) {
      if (!refresh) {
        setState(() => _loading = true);
      }
    }
    try {
      final bduss = await TiebaAccountService.getBduss() ?? '';
      final bdussVal = bduss.isNotEmpty ? bduss : null;

      if (!append) {
        final initialPages = DataSaverService.instance.enabled ? 1 : 3;
        final fetches = List.generate(
          initialPages,
          (i) => _fetchBarPage(_bar!, i + 1, bdussVal),
        );
        final results = await Future.wait(fetches);
        if (!mounted) return;

        final seen = <String>{};
        var posts = <TiebaPost>[];
        var highestPage = 0;
        for (int i = 0; i < results.length; i++) {
          for (final p in results[i]) {
            if (seen.add(p.id)) posts.add(p);
          }
          if (results[i].isNotEmpty) highestPage = i + 1;
        }

        if (!mounted) return;
        scheduleIdleUpdate(() async {
          if (!mounted) return;
          setState(() {
            _posts = [];
            _barPage = highestPage;
            _loading = false;
            _hasMore = results.last.isNotEmpty;
          });
          SplashOverlay.ready.value = true;
          await _appendPostsChunked(posts);
          _preloadImages(posts);
          if (!mounted) return;
          _patchFavoriteStatusLater(posts);
          _persistSession();
        });
        if (!DataSaverService.instance.enabled) {
          _loadRecommendations();
        }
      } else {
        var page = _barPage + 1;
        var fresh = <TiebaPost>[];
        var pagesTried = 0;
        while (pagesTried < 50) {
          pagesTried++;
          final batch = await _fetchBarPage(_bar!, page, bdussVal);
          if (!mounted) return;
          if (batch.isEmpty) {
            setState(() => _hasMore = false);
            _loadingMoreNotifier.value = false;
            return;
          }
          final existingIds = _posts.map((p) => p.id).toSet();
          fresh = batch.where((p) => existingIds.add(p.id)).toList();
          _barPage = page;
          if (fresh.isNotEmpty) break;
          page++;
        }
        if (!mounted) {
          _loadingMoreNotifier.value = false;
          return;
        }
        scheduleIdleUpdate(() async {
          if (!mounted) return;
          setState(() => _hasMore = fresh.isNotEmpty);
          if (fresh.isNotEmpty) {
            await _appendPostsChunked(fresh);
            _preloadImages(fresh);
          }
          if (!mounted) return;
          _loadingMoreNotifier.value = false;
          _persistSession();
          _scheduleScrollCheck();
        });
        _patchFavoriteStatusLater(fresh);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _loadingMoreNotifier.value = false;
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final bduss = await TiebaAccountService.getBduss() ?? '';
      final feed = await TiebaClient.fetchPersonalized(
        loadType: 1,
        page: 1,
        bduss: bduss.isNotEmpty ? bduss : null,
      );
      final recs = feed.posts;
      if (recs.isNotEmpty && mounted) {
        final existingIds = _posts.map((p) => p.id).toSet();
        final newRecs = recs.where((r) => existingIds.add(r.id)).toList();
        if (newRecs.isNotEmpty) {
          scheduleIdleUpdate(() async {
            if (!mounted) return;
            await _appendPostsChunked(newRecs);
            if (!mounted) return;
            _persistSession();
          });
          _patchFavoriteStatusLater(newRecs);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (!AppLifecycleGate.isActive ||
        _loadingMoreNotifier.value ||
        !_hasMore ||
        _loading) {
      return;
    }
    _loadingMoreNotifier.value = true;
    if (_isSingleBar && _bar != null) {
      await _loadBarPosts(append: true);
      if (!mounted) {
        _loadingMoreNotifier.value = false;
        return;
      }
    } else {
      try {
        var added = 0;
        final newPosts = <TiebaPost>[];
        final maxRounds = DataSaverService.instance.enabled ? 3 : 8;
        for (
          var round = 0;
          round < maxRounds && TiebaCrawlerService.hasMore;
          round++
        ) {
          final more = await TiebaCrawlerService.loadMorePosts();
          if (!mounted) {
            _loadingMoreNotifier.value = false;
            return;
          }
          if (more.isNotEmpty) {
            newPosts.addAll(more);
            added += more.length;
            break;
          }
          if (!TiebaCrawlerService.hasMore) break;
        }
        if (!mounted) {
          _loadingMoreNotifier.value = false;
          return;
        }
        scheduleIdleUpdate(() async {
          if (!mounted) return;
          setState(() => _hasMore = TiebaCrawlerService.hasMore);
          if (newPosts.isNotEmpty) {
            await _appendPostsChunked(newPosts);
            _preloadImages(newPosts);
          }
          if (!mounted) return;
          _loadingMoreNotifier.value = false;
          if (added > 0) {
            _persistSession();
            _scheduleScrollCheck();
            _scheduleRecommendLevelEnrich();
            _patchFavoriteStatusLater(newPosts);
          }
        });
      } catch (_) {
        if (!mounted) return;
        scheduleIdleUpdate(() {
          if (!mounted) return;
          setState(() => _hasMore = TiebaCrawlerService.hasMore);
          _loadingMoreNotifier.value = false;
        });
      }
    }
  }

  void _commitPosts(void Function() apply) {
    if (!mounted) return;
    setState(apply);
  }

  Future<void> _appendPostsChunked(
    List<TiebaPost> posts, {
    bool waitForScrollIdle = false,
  }) async {
    if (posts.isEmpty) return;
    await appendListInFrames(
      target: _posts,
      items: posts,
      mounted: () => mounted,
      commit: _commitPosts,
      scrollController: _scrollController,
      waitForScrollIdle: waitForScrollIdle,
    );
  }

  void _scheduleScrollCheck() {
    _scrollLoadTrigger.checkAfterLayout();
  }

  Future<void> _syncFavoriteStatus(List<TiebaPost> posts) async {
    try {
      final favIds = await TiebaFavoriteService.getFavoriteIdSet();
      for (final post in posts) {
        post.isFavorited = favIds.contains(post.id);
      }
    } catch (_) {}
  }

  void _patchFavoriteStatusLater(List<TiebaPost> posts) {
    if (posts.isEmpty) return;
    unawaited(_syncFavoriteStatus(posts));
  }

  Future<void> _onToggleFavorite(TiebaPost post) async {
    final nowFav = await TiebaFavoriteService.toggleFavorite(post);
    if (!mounted) return;
    if (nowFav == null) {
      showAppToast(context, '操作失败，请稍后重试', type: AppToastType.error);
    } else {
      showAppToast(
        context,
        nowFav ? '已收藏' : '已取消收藏',
        type: nowFav ? AppToastType.success : AppToastType.info,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        companionLayoutKey: _isSingleBar ? 'home-bar' : 'home',
        titleText: _isSingleBar ? _bar : '首页',
        title: Text(
          _isSingleBar ? _bar! : '首页',
          style: AppFonts.title(color: colors.textPrimary),
        ),
        leading: _isSingleBar
            ? GestureDetector(
                onTap: widget.onClearBar,
                child: Icon(Icons.arrow_back_rounded, color: colors.primary),
              )
            : null,
        actions: [
          if (!_isSingleBar && !_isLoggedIn)
            GestureDetector(
              onTap: () async {
                final result = await Navigator.of(context).pushNamed('/login');
                if (result == true) _loadPostsWithLoginCheck();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('登录', style: AppFonts.body(color: colors.primary)),
              ),
            ),
        ],
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(AppColorScheme colors) {
    return LoadingFadeView(
      loading: _loading && _posts.isEmpty,
      blockInteraction: false,
      loadingWidget: const FeedSkeleton(),
      child: _buildLoadedBody(colors),
    );
  }

  Widget _buildLoadedBody(AppColorScheme colors) {
    final bottomPad = MediaQuery.paddingOf(context).bottom + 88;
    final topPad = glassTopInset(context) + 8;
    final refreshExtent = _refreshIndicatorExtent(context);
    if (_posts.isEmpty && !_isSingleBar && !_isLoggedIn) {
      return AppEmptyState(
        icon: Icons.person_outline,
        message: '请先登录，或从下方进吧选择贴吧浏览',
        actionLabel: '登录',
        onAction: () async {
          final result = await Navigator.of(context).push<bool>(
            uiPageRoute(
              name: AppUiRouteNames.loginHub,
              builder: (_) => const LoginHubPage(),
            ),
          );
          if (result == true) _loadPostsWithLoginCheck();
        },
      );
    }

    if (_posts.isEmpty) {
      final headerTop =
          _isSingleBar && _barHeaderSlivers(colors, topPad).isNotEmpty
          ? 0.0
          : topPad;
      return CustomScrollView(
        physics: _scrollPhysics,
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: _loadPosts,
            refreshTriggerPullDistance: _refreshTriggerPullDistance,
            refreshIndicatorExtent: refreshExtent,
            builder: _refreshIndicatorBuilder(colors),
          ),
          ..._barHeaderSlivers(colors, topPad),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, headerTop, 16, bottomPad),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.swipe_down_rounded,
                message: _isLoggedIn || _isSingleBar
                    ? '下拉刷新加载内容'
                    : '请先登录，或从下方进吧选择贴吧浏览',
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      cacheExtent: 800,
      physics: _scrollPhysics,
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: _loadPosts,
          refreshTriggerPullDistance: _refreshTriggerPullDistance,
          refreshIndicatorExtent: refreshExtent,
          builder: _refreshIndicatorBuilder(colors),
        ),
        ..._barHeaderSlivers(colors, topPad),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            _isSingleBar ? 0 : topPad,
            16,
            bottomPad,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _posts.length) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _loadingMoreNotifier,
                    builder: (context, loadingMore, _) {
                      return LoadMoreFooter(loading: loadingMore, active: true);
                    },
                  );
                }
                final post = _posts[index];
                return PostCard(
                  key: ValueKey(post.id),
                  post: post,
                  index: index,
                  onTap: () {
                    AppShellController.instance.dismissChatForNavigation();
                    // 用嵌套 Navigator 的 context push：导航栏常驻、返回回推荐流。
                    Navigator.of(context).push(
                      uiPageRoute(
                        name: AppUiRouteNames.postDetail,
                        arguments: <String, dynamic>{
                          'tid': post.id,
                          if (post.title.isNotEmpty) 'title': post.title,
                          if (post.barName.isNotEmpty) 'bar_name': post.barName,
                          if (post.author.isNotEmpty) 'author': post.author,
                        },
                        builder: (_) => PostDetailPage(
                          post: post,
                          posts: _posts,
                          initialIndex: index,
                          onLoadMore: _buildLoadMore(),
                        ),
                      ),
                    );
                  },
                  onToggleFavorite: () => _onToggleFavorite(post),
                );
              },
              childCount: _posts.length + (_hasMore ? 1 : 0),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
      ],
    );
  }

  RefreshControlIndicatorBuilder _refreshIndicatorBuilder(
    AppColorScheme colors,
  ) {
    return (
      BuildContext context,
      RefreshIndicatorMode refreshState,
      double pulledExtent,
      double refreshTriggerPullDistance,
      double refreshIndicatorExtent,
    ) {
      final height = pulledExtent.clamp(0.0, refreshIndicatorExtent);
      if (height <= 0 && refreshState == RefreshIndicatorMode.inactive) {
        return const SizedBox.shrink();
      }

      final topInset = glassTopInset(context);
      final indicatorTop = topInset + _refreshGapBelowAppBar;

      final Widget indicator;
      switch (refreshState) {
        case RefreshIndicatorMode.refresh:
          indicator = KaomojiLoader(
            key: const ValueKey('home-refresh-spinner'),
            size: 32,
            color: colors.primary,
          );
        case RefreshIndicatorMode.done:
          indicator = Icon(
            Icons.check_rounded,
            size: 22,
            color: colors.primary,
          );
        case RefreshIndicatorMode.armed:
        case RefreshIndicatorMode.drag:
        case RefreshIndicatorMode.inactive:
          final progress = (pulledExtent / refreshTriggerPullDistance).clamp(
            0.0,
            1.0,
          );
          indicator = Transform.rotate(
            angle: progress * math.pi,
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 22,
              color: colors.textSecondary.withValues(
                alpha: 0.35 + progress * 0.65,
              ),
            ),
          );
      }

      return SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: indicatorTop,
              height: _refreshIndicatorBody,
              child: Center(child: indicator),
            ),
          ],
        ),
      );
    };
  }
}
