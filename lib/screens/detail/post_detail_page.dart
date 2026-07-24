import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/tieba_post.dart';
import '../../services/tieba_account_service.dart';
import '../../services/tieba_client.dart';
import '../../services/tieba_favorite_service.dart';
import '../../services/app_shell_controller.dart';
import '../../services/browse_distill_service.dart';
import '../../services/browse_history_service.dart';
import '../../services/app_ui_context.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_glass.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_feature_guide.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/comment_content_body.dart';
import '../../widgets/favorite_bookmark_ribbon.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/pull_to_favorite_refresh.dart';
import '../../widgets/user_level_badges.dart';
import '../../widgets/forum_level_badge.dart';
import '../../widgets/post_video_tile.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/format_relative_time.dart';
import '../../utils/forum_level_style.dart';
import '../../utils/open_user_home.dart';
import '../../utils/post_content_plain.dart';
import '../../utils/post_detail_scroll_coordinator.dart';
import '../../utils/list_update_scheduler.dart';
import '../../utils/scroll_load_trigger.dart';
import '../../utils/scroll_settle.dart';
import '../../widgets/two_finger_scale_detector.dart';

List<TiebaSubComment> _mergeSubCommentsById(
  List<TiebaSubComment> current,
  List<TiebaSubComment> more,
) {
  final ids = current.map((c) => c.id).toSet();
  final merged = List<TiebaSubComment>.from(current);
  for (final comment in more) {
    if (ids.add(comment.id)) merged.add(comment);
  }
  return merged;
}

Widget _copyOnLongPress(BuildContext context, String rawContent, Widget child) {
  return GestureDetector(
    onLongPress: () {
      final plain = PostContentPlain.from(rawContent);
      Clipboard.setData(ClipboardData(text: plain));
      showAppToast(context, '已复制', type: AppToastType.success);
    },
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}

class PostDetailPage extends StatefulWidget {
  final TiebaPost post;
  final List<TiebaPost>? posts;
  final int initialIndex;
  final Future<List<TiebaPost>> Function()? onLoadMore;

  const PostDetailPage({
    super.key,
    required this.post,
    this.posts,
    this.initialIndex = 0,
    this.onLoadMore,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late PageController _pageController;
  late PostDetailScrollDelegate _scrollDelegate;
  late int _currentIndex;
  late List<TiebaPost> _posts;
  bool _loadingMore = false;
  bool _hasMore = true;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _replySending = false;
  final _replyRefreshNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    AppShellController.hideBottomNav.value = true;
    _currentIndex = widget.initialIndex;
    _posts = widget.posts != null ? List.from(widget.posts!) : [widget.post];
    _hasMore = widget.posts != null && widget.onLoadMore != null;
    _pageController = PageController(initialPage: _currentIndex);
    _scrollDelegate = PostDetailScrollDelegate(pageController: _pageController);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_posts.length > 1) {
        await AppFeatureGuide.showPostSwipeGuideIfNeeded(
          context,
          enabled: true,
        );
      }
    });
  }

  @override
  void dispose() {
    AppShellController.hideBottomNav.value = false;
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _replyRefreshNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);
    if (_hasMore && !_loadingMore && i == _posts.length) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMore || !_hasMore || widget.onLoadMore == null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await widget.onLoadMore!();
      if (!mounted) return;
      if (more.isEmpty) {
        _hasMore = false;
      } else {
        setState(() => _posts.addAll(more));
      }
    } catch (_) {
      _hasMore = false;
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _submitReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _replySending) return;

    final bduss = await TiebaAccountService.getBduss();
    if (bduss == null || bduss.isEmpty) {
      if (mounted) {
        showAppToast(context, '请先登录后再操作', type: AppToastType.warning);
      }
      return;
    }

    setState(() => _replySending = true);
    _replyCtrl.clear();

    try {
      final post = _posts[_currentIndex];
      final tbs = await TiebaAccountService.refreshTbs();
      if (tbs.isEmpty) {
        if (mounted) {
          showAppToast(context, '登录状态失效', type: AppToastType.error);
        }
        return;
      }
      final showName = TiebaAccountService.localSnapshot?.displayName;
      final stoken = await TiebaAccountService.getStoken();
      final result = await TiebaClient.replyPost(
        tid: post.id,
        content: text,
        bduss: bduss,
        tbs: tbs,
        fname: post.barName,
        fid: post.fid,
        showName: showName,
        stoken: stoken,
      );
      final errorCode = result['error_code'];
      if (errorCode != null && errorCode != 0) {
        final errorMsg = result['error_msg']?.toString() ?? '回复失败';
        if (mounted) {
          showAppToast(context, errorMsg, type: AppToastType.error);
        }
      } else {
        if (mounted) {
          showAppToast(context, '回复成功', type: AppToastType.success);
          _replyRefreshNotifier.value++;
        }
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '回复失败', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _replySending = false);
    }
  }

  Widget _buildReplyBar(AppColorScheme colors) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: glassSurface(
            colors: colors,
            borderRadius: BorderRadius.circular(28),
            strong: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    focusNode: _replyFocus,
                    enabled: !_replySending,
                    minLines: 1,
                    maxLines: 5,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.newline,
                    style: AppFonts.body(color: colors.textPrimary).copyWith(
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    decoration: InputDecoration(
                      hintText: '发表评论…',
                      hintStyle:
                          AppFonts.body(color: colors.textMuted).copyWith(
                            height: 1.0,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _replySending
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      )
                    : ListenableBuilder(
                        listenable: _replyCtrl,
                        builder: (context, _) {
                          final canSend =
                              _replyCtrl.text.trim().isNotEmpty;
                          return _CapsuleSendButton(
                            colors: colors,
                            enabled: canSend,
                            onSend: _submitReply,
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final post = _posts[math.min(_currentIndex, _posts.length - 1)];

    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: GlassAppBar(
        companionLayoutKey: 'post-detail',
        titleText: post.barName.isNotEmpty ? post.barName : '帖子详情',
        title: Text(
          post.barName.isNotEmpty ? post.barName : '帖子详情',
          style: AppFonts.title(color: colors.textPrimary),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _posts.length > 1
                ? PostDetailScrollCoordinator(
                    delegate: _scrollDelegate,
                    child: PageView.builder(
                      controller: _pageController,
                      physics: CoordinatedPageScrollPhysics(
                        delegate: _scrollDelegate,
                      ),
                      allowImplicitScrolling: true,
                      itemCount: _posts.length + (_hasMore ? 1 : 0),
                      onPageChanged: _onPageChanged,
                      itemBuilder: (_, i) {
                        if (i == _posts.length) {
                          return const AppLoadingPage(message: '加载中…');
                        }
                        return _PostDetailBody(
                          post: _posts[i],
                          key: ValueKey(_posts[i].id),
                          isActivePage: i == _currentIndex,
                          replyRefreshNotifier: _replyRefreshNotifier,
                          onFavoriteChanged: () {
                            if (mounted) setState(() {});
                          },
                        );
                      },
                    ),
                  )
                : _PostDetailBody(
                    post: widget.post,
                    replyRefreshNotifier: _replyRefreshNotifier,
                    onFavoriteChanged: () {
                      if (mounted) setState(() {});
                    },
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: _buildReplyBar(colors),
          ),
        ],
      ),
    );
  }
}

class _PostDetailBody extends StatefulWidget {
  final TiebaPost post;
  final bool isActivePage;
  final ValueNotifier<int>? replyRefreshNotifier;
  final VoidCallback? onFavoriteChanged;

  const _PostDetailBody({
    super.key,
    required this.post,
    this.isActivePage = true,
    this.replyRefreshNotifier,
    this.onFavoriteChanged,
  });

  @override
  State<_PostDetailBody> createState() => _PostDetailBodyState();
}

enum CommentSort { hot, asc, desc }

class _PostDetailBodyState extends State<_PostDetailBody>
    with AutomaticKeepAliveClientMixin {
  static const _floatingBarPad = 80.0;
  CommentSort _commentSort = CommentSort.hot;
  bool _postLiking = false;
  OverlayEntry? _likeEffectOverlay;
  final _scrollController = ScrollController();
  late final ScrollLoadTrigger _scrollLoadTrigger = ScrollLoadTrigger(
    onNearEnd: _loadMoreComments,
    threshold: 300,
  );
  TiebaPostDetail? _detail;
  List<TiebaComment> _comments = [];
  bool _onlyAuthor = false;
  bool _loading = true;
  bool _error = false;
  int _page = 1;
  bool _hasMore = false;
  final _loadingMoreNotifier = ValueNotifier(false);
  final _fontScaleNotifier = ValueNotifier(1.0);
  PostDetailScrollDelegate? _scrollDelegate;
  int? _authorForumLevel;
  String? _authorForumLevelName;
  String? _authorForumBarName;
  bool _loadingAuthorLevels = false;
  int _bookmarkEntranceTrigger = 0;
  bool _pullFavoriteInProgress = false;
  bool _pullTargetAddFavorite = false;
  bool _pinnedBookmarkInstant = false;
  bool _pullFromUserDrag = false;
  VoidCallback? _replyRefreshListener;

  TiebaPost get _favoritePost => _detail?.post ?? widget.post;

  List<TiebaComment> get _filteredComments {
    if (!_onlyAuthor) return _comments;
    final author = _detail?.post.author ?? widget.post.author;
    return _comments.where((c) => c.author == author).toList();
  }

  @override
  bool get wantKeepAlive => widget.isActivePage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollDelegate = PostDetailScrollCoordinator.maybeOf(context);
    _syncScrollDelegateAttachment();
  }

  @override
  void didUpdateWidget(covariant _PostDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActivePage != widget.isActivePage) {
      _syncScrollDelegateAttachment();
    }
    if (oldWidget.post.isFavorited != widget.post.isFavorited) {
      _syncFavoritePosts();
      if (!oldWidget.post.isFavorited && widget.post.isFavorited) {
        _bookmarkEntranceTrigger++;
      }
    }
  }

  void _syncScrollDelegateAttachment() {
    if (widget.isActivePage) {
      _scrollDelegate?.attachVertical(_scrollController);
    } else {
      _scrollDelegate?.detachVertical(_scrollController);
    }
  }

  void _syncFavoritePosts([bool? favorited]) {
    final value = favorited ?? widget.post.isFavorited;
    widget.post.isFavorited = value;
    _detail?.post.isFavorited = value;
  }

  void _onFavoriteStateChanged({bool animateEntrance = false}) {
    _syncFavoritePosts(_favoritePost.isFavorited);
    widget.onFavoriteChanged?.call();
    if (!mounted) return;
    setState(() {
      if (animateEntrance && _favoritePost.isFavorited) {
        _bookmarkEntranceTrigger++;
      }
    });
  }

  bool _trackPullToFavoriteDrag(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        notification.metrics.pixels < notification.metrics.minScrollExtent) {
      _pullFromUserDrag = true;
    } else if (notification is ScrollEndNotification &&
        notification.dragDetails == null) {
      _pullFromUserDrag = false;
    }
    return false;
  }

  Future<void> _pullToFavorite() async {
    if (_pullFavoriteInProgress || !_pullFromUserDrag) return;
    final wasFavorited = _favoritePost.isFavorited;
    setState(() {
      _pullFavoriteInProgress = true;
      _pullTargetAddFavorite = !wasFavorited;
    });
    try {
      final result = await PullToFavoriteRefresh.handleRefresh(
        context,
        post: _favoritePost,
        onChanged: () {
          _onFavoriteStateChanged(animateEntrance: false);
          if (_favoritePost.isFavorited) {
            setState(() => _pinnedBookmarkInstant = true);
          }
        },
      );
      if (!mounted) return;
      if (result && !wasFavorited && !_pinnedBookmarkInstant) {
        setState(() => _pinnedBookmarkInstant = true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _pullFavoriteInProgress = false;
          _pullTargetAddFavorite = false;
          _pullFromUserDrag = false;
        });
        if (_pinnedBookmarkInstant) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pinnedBookmarkInstant = false);
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    BrowseDistillService.instance.recordPreview(widget.post);
    TiebaFavoriteService.applyFavoriteStatus(widget.post).then((_) {
      if (mounted) setState(() {});
    });
    _syncUiForeground();
    _loadDetail();
    _scrollLoadTrigger.attach(_scrollController);
    _replyRefreshListener = () => _loadDetail();
    widget.replyRefreshNotifier?.addListener(_replyRefreshListener!);
  }

  void _syncUiForeground() {
    final post = _detail?.post ?? widget.post;
    AppUiContextService.instance.setForegroundExtras({
      'tid': post.id,
      if (post.title.isNotEmpty) 'title': post.title,
      if (post.barName.isNotEmpty) 'bar_name': post.barName,
      if (post.author.isNotEmpty) 'author': post.author,
      if (_comments.isNotEmpty) 'comment_count': _comments.length,
    });
  }

  @override
  void dispose() {
    if (_replyRefreshListener != null) {
      widget.replyRefreshNotifier?.removeListener(_replyRefreshListener!);
    }
    _scrollDelegate?.detachVertical(_scrollController);
    _loadingMoreNotifier.dispose();
    _fontScaleNotifier.dispose();
    AppUiContextService.instance.setForegroundExtras(null);
    _scrollLoadTrigger.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _commitDetail(void Function() apply) {
    if (!mounted) return;
    setState(apply);
  }

  Future<void> _appendCommentsChunked(List<TiebaComment> comments) async {
    if (comments.isEmpty) return;
    await appendListInFrames(
      target: _comments,
      items: comments,
      mounted: () => mounted,
      commit: _commitDetail,
      scrollController: _scrollController,
      firstChunk: 10,
      chunkSize: 8,
    );
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = false;
      _page = 1;
      _hasMore = false;
    });
    try {
      final bduss = await TiebaAccountService.getBduss() ?? '';
      final stoken = await TiebaAccountService.getStoken();
      final detail = await TiebaClient.fetchPostDetail(
        widget.post.id,
        bduss: bduss,
        stoken: stoken,
        sort: _commentSort.index,
      );
      if (!mounted) return;
      if (detail != null) {
        if (detail.post.content.isEmpty) {
          detail.post.content = widget.post.content;
        }
        detail.post.cover ??= widget.post.cover;
        widget.post.likes = detail.post.likes;
        widget.post.isLiked = detail.post.isLiked;
        final allComments = detail.comments;
        setState(() {
          _detail = detail;
          _comments = allComments.take(12).toList(growable: true);
          _hasMore = detail.hasMore;
          _loading = false;
          _authorForumLevel = null;
          _authorForumLevelName = null;
          _authorForumBarName = null;
          _loadingAuthorLevels = _canLoadAuthorLevels(detail.post);
        });
        if (allComments.length > 12) {
          unawaited(_appendCommentsChunked(allComments.sublist(12)));
        }
        unawaited(TiebaFavoriteService.applyFavoriteStatus(detail.post));
        if (_loadingAuthorLevels) {
          _loadAuthorLevels(detail.post);
        }
        BrowseDistillService.instance.recordDetail(detail);
        unawaited(BrowseHistoryService.instance.recordView(detail.post));
        _syncUiForeground();
      } else {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  bool _canLoadAuthorLevels(TiebaPost post) {
    final portrait =
        post.authorPortrait ??
        TiebaClient.portraitFromAvatarUrl(post.authorAvatar);
    final barName = post.barName.trim();
    return portrait != null && portrait.isNotEmpty && barName.isNotEmpty;
  }

  Future<void> _loadAuthorLevels(TiebaPost post) async {
    final portrait =
        post.authorPortrait ??
        TiebaClient.portraitFromAvatarUrl(post.authorAvatar);
    final barName = post.barName.trim();
    if (portrait == null || portrait.isEmpty || barName.isEmpty) {
      if (mounted) setState(() => _loadingAuthorLevels = false);
      return;
    }

    final bduss = await TiebaAccountService.getBduss() ?? '';
    final stoken = await TiebaAccountService.getStoken();
    final forumLevel = await TiebaClient.fetchUserForumLevel(
      barName: barName,
      portrait: portrait,
      bduss: bduss,
      stoken: stoken,
    );

    if (!mounted) return;
    runWhenScrollSettled(_scrollController, () {
      if (!mounted) return;
      setState(() {
        final rawForumLevel = forumLevel?['forum_level'];
        _authorForumLevel = rawForumLevel is int
            ? rawForumLevel
            : int.tryParse(rawForumLevel?.toString() ?? '');
        _authorForumLevelName = forumLevel?['forum_level_name']?.toString();
        _authorForumBarName = forumLevel?['bar_name']?.toString();
        _loadingAuthorLevels = false;
      });
    });
  }

  Future<void> _loadMoreComments() async {
    if (!_hasMore || _loadingMoreNotifier.value || _loading) return;
    _loadingMoreNotifier.value = true;
    final nextPage = _page + 1;
    try {
      final bduss = await TiebaAccountService.getBduss() ?? '';
      final stoken = await TiebaAccountService.getStoken();
      final detail = await TiebaClient.fetchPostDetail(
        widget.post.id,
        page: nextPage,
        bduss: bduss,
        stoken: stoken,
        sort: _commentSort.index,
      );
      if (!mounted) {
        _loadingMoreNotifier.value = false;
        return;
      }
      final existingIds = _comments.map((c) => c.id).toSet();
      final fresh = detail == null
          ? const <TiebaComment>[]
          : detail.comments.where((c) => existingIds.add(c.id)).toList();
      _loadingMoreNotifier.value = false;
      if (detail != null) {
        setState(() {
          _page = detail.comments.isNotEmpty ? nextPage : _page;
          _hasMore = detail.hasMore;
        });
      } else {
        setState(() => _hasMore = false);
      }
      if (fresh.isNotEmpty) {
        await _appendCommentsChunked(fresh);
      }
      if (mounted) {
        _scrollLoadTrigger.checkAfterLayout();
      }
    } catch (_) {
      if (!mounted) return;
      _loadingMoreNotifier.value = false;
      showAppToast(context, '评论加载失败，请稍后重试', type: AppToastType.error);
    }
  }

  Future<bool> _ensureLoggedIn() async {
    final bduss = await TiebaAccountService.getBduss();
    if (bduss != null && bduss.isNotEmpty) return true;
    if (mounted) {
      showAppToast(context, '请先登录后再操作', type: AppToastType.warning);
    }
    return false;
  }

  Future<void> _toggleCommentLike(TiebaComment comment) async {
    await _toggleAgreeTarget(
      pid: comment.id,
      isLiked: comment.isLiked,
      likes: comment.likes,
      notifyParent: false,
      onApply: (liked, likes) {
        comment.isLiked = liked;
        comment.likes = likes;
      },
      agree: () async {
        final creds = await _likeCredentials();
        if (creds == null) return '登录状态失效，请重新登录';
        return TiebaClient.agreeCommentMessage(
          tid: widget.post.id,
          pid: comment.id,
          bduss: creds.bduss,
          tbs: creds.tbs,
          stoken: creds.stoken,
        );
      },
      undo: () async {
        final creds = await _likeCredentials();
        if (creds == null) return '登录状态失效，请重新登录';
        return TiebaClient.undoAgreeCommentMessage(
          tid: widget.post.id,
          pid: comment.id,
          bduss: creds.bduss,
          tbs: creds.tbs,
          stoken: creds.stoken,
        );
      },
      invalidMessage: '无法点赞该评论',
    );
  }

  Future<void> _toggleSubCommentLike(TiebaSubComment sub) async {
    await _toggleAgreeTarget(
      pid: sub.id,
      isLiked: sub.isLiked,
      likes: sub.likes,
      notifyParent: false,
      onApply: (liked, likes) {
        sub.isLiked = liked;
        sub.likes = likes;
      },
      agree: () async {
        final creds = await _likeCredentials();
        if (creds == null) return '登录状态失效，请重新登录';
        return TiebaClient.agreeSubCommentMessage(
          tid: widget.post.id,
          pid: sub.id,
          bduss: creds.bduss,
          tbs: creds.tbs,
          stoken: creds.stoken,
        );
      },
      undo: () async {
        final creds = await _likeCredentials();
        if (creds == null) return '登录状态失效，请重新登录';
        return TiebaClient.undoAgreeSubCommentMessage(
          tid: widget.post.id,
          pid: sub.id,
          bduss: creds.bduss,
          tbs: creds.tbs,
          stoken: creds.stoken,
        );
      },
      invalidMessage: '无法点赞该回复',
    );
  }

  bool _isValidPostId(String id) {
    final text = id.trim();
    return text.isNotEmpty && int.tryParse(text) != null;
  }

  Future<({String bduss, String tbs, String? stoken})?>
  _likeCredentials() async {
    if (!await _ensureLoggedIn()) return null;
    final bduss = await TiebaAccountService.getBduss() ?? '';
    final stoken = await TiebaAccountService.getStoken();
    final tbs = await TiebaAccountService.refreshTbs();
    if (tbs.isEmpty) return null;
    return (bduss: bduss, tbs: tbs, stoken: stoken);
  }

  Future<void> _toggleAgreeTarget({
    required String pid,
    required bool isLiked,
    required int likes,
    required void Function(bool liked, int likes) onApply,
    required Future<String?> Function() agree,
    required Future<String?> Function() undo,
    required String invalidMessage,
    bool notifyParent = true,
  }) async {
    if (!_isValidPostId(pid)) {
      if (mounted) {
        showAppToast(context, invalidMessage, type: AppToastType.warning);
      }
      return;
    }
    final previousLiked = isLiked;
    final previousLikes = likes;
    final nextLiked = !previousLiked;
    var nextLikes = previousLikes + (nextLiked ? 1 : -1);
    if (nextLikes < 0) nextLikes = 0;
    onApply(nextLiked, nextLikes);
    if (notifyParent && mounted) setState(() {});
    try {
      final error = previousLiked ? await undo() : await agree();
      if (error != null && mounted) {
        onApply(previousLiked, previousLikes);
        if (notifyParent) setState(() {});
        showAppToast(context, error, type: AppToastType.error);
      }
    } catch (_) {
      if (mounted) {
        onApply(previousLiked, previousLikes);
        if (notifyParent) setState(() {});
        showAppToast(context, '点赞失败', type: AppToastType.error);
      }
    }
  }

  Future<void> _syncPostLikeCount(TiebaPost post) async {
    final bduss = await TiebaAccountService.getBduss() ?? '';
    final stoken = await TiebaAccountService.getStoken();
    final detail = await TiebaClient.fetchPostDetail(
      post.id,
      bduss: bduss,
      stoken: stoken,
      page: 1,
    );
    if (!mounted || detail == null) return;
    setState(() {
      post.likes = detail.post.likes;
      post.isLiked = detail.post.isLiked;
      if (_detail != null) {
        _detail!.post.likes = detail.post.likes;
        _detail!.post.isLiked = detail.post.isLiked;
      }
      widget.post.likes = detail.post.likes;
      widget.post.isLiked = detail.post.isLiked;
    });
  }

  Future<void> _togglePostLike(TiebaPost post) async {
    final creds = await _likeCredentials();
    if (creds == null) {
      if (mounted) {
        showAppToast(context, '登录状态失效，请重新登录', type: AppToastType.warning);
      }
      return;
    }
    final previousLiked = post.isLiked;
    final previousLikes = post.likes;
    final nextLiked = !previousLiked;
    var nextLikes = previousLikes + (nextLiked ? 1 : -1);
    if (nextLikes < 0) nextLikes = 0;
    setState(() {
      post.isLiked = nextLiked;
      post.likes = nextLikes;
    });
    try {
      final error = previousLiked
          ? await TiebaClient.undoAgreePostMessage(
              tid: post.id,
              bduss: creds.bduss,
              tbs: creds.tbs,
              stoken: creds.stoken,
            )
          : await TiebaClient.agreePostMessage(
              tid: post.id,
              bduss: creds.bduss,
              tbs: creds.tbs,
              stoken: creds.stoken,
            );
      if (error != null && mounted) {
        setState(() {
          post.isLiked = previousLiked;
          post.likes = previousLikes;
        });
        showAppToast(context, error, type: AppToastType.error);
      } else if (mounted) {
        await _syncPostLikeCount(post);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          post.isLiked = previousLiked;
          post.likes = previousLikes;
        });
        showAppToast(context, '点赞失败', type: AppToastType.error);
      }
    }
  }

  Future<void> _onPostDoubleTap(TiebaPost post) async {
    if (_postLiking) return;
    setState(() => _postLiking = true);
    try {
      await _togglePostLike(post);
    } finally {
      if (mounted) setState(() => _postLiking = false);
    }
  }

  void _showLikeEffect(Offset globalPosition) {
    HapticFeedback.lightImpact();
    _likeEffectOverlay?.remove();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final local = overlayBox.globalToLocal(globalPosition);
    _likeEffectOverlay = OverlayEntry(
      builder: (_) => _LikeEffectAnimation(
        position: local,
        onDone: () => _likeEffectOverlay?.remove(),
      ),
    );
    overlay.insert(_likeEffectOverlay!);
  }

  void _openImage(String url) {
    Navigator.of(context).push(
      uiPageRoute(
        name: AppUiRouteNames.imageViewer,
        arguments: {'url': url},
        builder: (_) => ImageViewerPage(imageUrl: url),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;

    if (_error) {
      return AppEmptyState(
        icon: Icons.error_outline,
        message: '加载失败',
        actionLabel: '重试',
        onAction: _loadDetail,
      );
    }

    if (_loading && _detail == null) {
      return PostDetailSkeleton(colors: colors);
    }
    if (_detail != null) {
      return _buildDetailBody(context, colors);
    }
    return _buildLoadingPreview(context, colors);
  }

  Widget _buildLoadingPreview(BuildContext context, AppColorScheme colors) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildPostPreviewCard(context, colors)),
      ],
    );
  }

  Widget _buildPostPreviewCard(BuildContext context, AppColorScheme colors) {
    final post = widget.post;
    final preview = PostContentPlain.from(
      post.content,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderLight, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openUserHome(
              context,
              authorAvatar: post.authorAvatar,
              userName: post.author,
              barName: post.barName,
            ),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                UserAvatar(
                  imageUrl: post.authorAvatar,
                  radius: 20,
                  name: post.author,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.author,
                        style: AppFonts.caption(
                          color: colors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatRelativeTime(post.createdAt),
                        style: AppFonts.label(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(post.title, style: AppFonts.headline(color: colors.textPrimary)),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailBody(BuildContext context, AppColorScheme colors) {
    final scrollView = NotificationListener<ScrollNotification>(
      onNotification: _trackPullToFavoriteDrag,
      child: CustomScrollView(
        controller: _scrollController,
        physics: AlwaysScrollableScrollPhysics(
          parent: _scrollDelegate != null
              ? CoordinatedVerticalScrollPhysics(delegate: _scrollDelegate!)
              : const PullToFavoriteScrollPhysics(),
        ),
        cacheExtent: 800,
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: _pullToFavorite,
            refreshTriggerPullDistance:
                PullToFavoriteRefresh.triggerPullDistance,
            refreshIndicatorExtent: PullToFavoriteRefresh.indicatorExtent(
              context,
            ),
            builder: PullToFavoriteRefresh.indicatorBuilder(
              showWhileRefreshing:
                  _pullTargetAddFavorite && _pullFavoriteInProgress,
              hideBookmark: _favoritePost.isFavorited,
            ),
          ),
          SliverToBoxAdapter(child: _buildPostContent(context, _detail!.post)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text(
                    '评论',
                    style: AppFonts.caption(color: colors.textSecondary),
                  ),
                  const Spacer(),
                  _SortChip(
                    label: '热门',
                    selected: _commentSort == CommentSort.hot,
                    onTap: () {
                      if (_commentSort != CommentSort.hot) {
                        _commentSort = CommentSort.hot;
                        _loadDetail();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  _SortChip(
                    label: '正序',
                    selected: _commentSort == CommentSort.asc,
                    onTap: () {
                      if (_commentSort != CommentSort.asc) {
                        _commentSort = CommentSort.asc;
                        _loadDetail();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  _SortChip(
                    label: '倒序',
                    selected: _commentSort == CommentSort.desc,
                    onTap: () {
                      if (_commentSort != CommentSort.desc) {
                        _commentSort = CommentSort.desc;
                        _loadDetail();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _SortChip(
                    label: '只看楼主',
                    selected: _onlyAuthor,
                    onTap: () => setState(() => _onlyAuthor = !_onlyAuthor),
                  ),
                ],
              ),
            ),
          ),
          if (_filteredComments.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _CommentFloorDivider(colors: colors),
              ),
            ),
          if (_filteredComments.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.chat_bubble_outline,
                message: _onlyAuthor ? '楼主暂无回复' : '暂无评论',
              ),
            )
          else ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final comment = _filteredComments[i];
                  return _CommentTile(
                    key: ValueKey(comment.id),
                    comment: comment,
                    tid: widget.post.id,
                    barName: widget.post.barName,
                    fontScaleNotifier: _fontScaleNotifier,
                    onImageTap: _openImage,
                    onLike: () => _toggleCommentLike(comment),
                    onShowLikeEffect: _showLikeEffect,
                    onSubCommentLike: _toggleSubCommentLike,
                    showBottomDivider: i < _filteredComments.length - 1,
                  );
                },
                childCount: _filteredComments.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                findChildIndexCallback: (Key key) {
                  if (key is ValueKey<String>) {
                    final index = _filteredComments.indexWhere(
                      (c) => c.id == key.value,
                    );
                    return index >= 0 ? index : null;
                  }
                  return null;
                },
              ),
            ),
            if (_hasMore)
              SliverToBoxAdapter(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _loadingMoreNotifier,
                  builder: (context, loadingMore, _) {
                    return LoadMoreFooter(loading: loadingMore, active: true);
                  },
                ),
              ),
          ],
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + _floatingBarPad,
            ),
          ),
        ],
      ),
    );
    final body = Stack(
      clipBehavior: Clip.none,
      children: [
        scrollView,
        Positioned(
          top: 0,
          right: FavoriteBookmarkLayout.edgeInset,
          child: PinnedFavoriteBookmark(
            visible: _favoritePost.isFavorited,
            entranceTrigger: _bookmarkEntranceTrigger,
            instant: _pinnedBookmarkInstant,
          ),
        ),
      ],
    );
    return TwoFingerScaleDetector(
      scaleNotifier: _fontScaleNotifier,
      onScaleChanged: (scale) => _fontScaleNotifier.value = scale,
      child: body,
    );
  }

  Widget _buildPostContent(BuildContext context, TiebaPost post) {
    return ValueListenableBuilder<double>(
      valueListenable: _fontScaleNotifier,
      builder: (context, fontScale, _) {
        final colors = context.appColors;
        TextStyle s(TextStyle base) =>
            base.copyWith(fontSize: (base.fontSize ?? 14) * fontScale);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: GestureDetector(
            onDoubleTapDown: (d) => _showLikeEffect(d.globalPosition),
            onDoubleTap: () => _onPostDoubleTap(post),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.borderLight, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(
                              imageUrl: post.authorAvatar,
                              radius: 20,
                              name: post.author,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          post.author,
                                          style: s(
                                            AppFonts.caption(
                                              color: colors.textPrimary,
                                            ).copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_loadingAuthorLevels ||
                                          ForumLevelStyle.hasLevel(
                                            level: _authorForumLevel,
                                            levelName: _authorForumLevelName,
                                          )) ...[
                                        const SizedBox(width: 6),
                                        UserLevelBadges(
                                          scope: UserLevelBadgeScope.forum,
                                          inline: true,
                                          loading: _loadingAuthorLevels,
                                          forumLevelLabel:
                                              _authorForumLevelName,
                                          forumLevel: _authorForumLevel,
                                          forumBarName: _authorForumBarName,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    formatRelativeTime(post.createdAt),
                                    style: s(
                                      AppFonts.label(color: colors.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  post.title,
                  style: s(AppFonts.headline(color: colors.textPrimary)),
                ),
                if (post.content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _copyOnLongPress(
                    context,
                    post.content,
                    CommentContentBody.build(
                      context: context,
                      content: post.content,
                      baseStyle: AppFonts.body(color: colors.textPrimary),
                      onImageTap: _openImage,
                      fontScale: fontScale,
                    ),
                  ),
                ] else if (post.video != null &&
                    post.video!.src.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PostVideoTile(
                    videoUrl: post.video!.src,
                    coverUrl: post.video!.coverSrc,
                    duration: post.video!.duration > 0
                        ? post.video!.duration
                        : null,
                    aspectRatio: post.video!.aspectRatio,
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _AnimatedLikeButton(
                    isLiked: post.isLiked,
                    likes: post.likes,
                    busy: _postLiking,
                    showZeroCount: true,
                    iconSize: 24,
                    countStyle: s(AppFonts.label(color: colors.textMuted)),
                    onToggle: () async {
                      setState(() => _postLiking = true);
                      try {
                        await _togglePostLike(post);
                      } finally {
                        if (mounted) setState(() => _postLiking = false);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

class _CommentTile extends StatefulWidget {
  final TiebaComment comment;
  final String tid;
  final String barName;
  final ValueNotifier<double> fontScaleNotifier;
  final void Function(String url) onImageTap;
  final Future<void> Function() onLike;
  final Future<void> Function(TiebaSubComment sub)? onSubCommentLike;
  final void Function(Offset globalPosition) onShowLikeEffect;
  final bool showBottomDivider;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.tid,
    required this.barName,
    required this.fontScaleNotifier,
    required this.onImageTap,
    required this.onLike,
    required this.onShowLikeEffect,
    this.onSubCommentLike,
    this.showBottomDivider = true,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _liking = false;
  late bool _isLiked;
  late int _likes;

  /// 与顶栏「头像 + 间距」对齐，正文略缩进。
  static const _bodyLeftInset = 52.0;

  @override
  void initState() {
    super.initState();
    _syncLikeFromComment();
  }

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.id != widget.comment.id ||
        oldWidget.comment.isLiked != widget.comment.isLiked ||
        oldWidget.comment.likes != widget.comment.likes) {
      _syncLikeFromComment();
    }
  }

  void _syncLikeFromComment() {
    _isLiked = widget.comment.isLiked;
    _likes = widget.comment.likes;
  }

  Future<void> _handleLike() async {
    if (_liking) return;
    setState(() {
      _isLiked = !_isLiked;
      _likes += _isLiked ? 1 : -1;
      if (_likes < 0) _likes = 0;
      _liking = true;
    });
    await widget.onLike();
    if (!mounted) return;
    setState(() {
      _syncLikeFromComment();
      _liking = false;
    });
  }

  Widget _buildSubComment(TiebaSubComment sub, double fontScale) {
    final colors = context.appColors;
    TextStyle s(TextStyle base) =>
        base.copyWith(fontSize: (base.fontSize ?? 13) * fontScale);
    return GestureDetector(
      onTap: () => openUserHome(
        context,
        authorAvatar: sub.authorAvatar,
        userName: sub.author,
        barName: widget.barName,
      ),
      behavior: HitTestBehavior.opaque,
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '${sub.author}：',
              style: s(AppFonts.caption(color: colors.primary)),
            ),
            TextSpan(
              text: sub.content,
              style: s(AppFonts.bodySmall(color: colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.fontScaleNotifier,
      builder: (context, fontScale, _) {
        final colors = context.appColors;
        TextStyle s(TextStyle base) =>
            base.copyWith(fontSize: (base.fontSize ?? 14) * fontScale);

        return RepaintBoundary(
          child: GestureDetector(
            onDoubleTapDown: (d) => widget.onShowLikeEffect(d.globalPosition),
            onDoubleTap: _handleLike,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => openUserHome(
                          context,
                          authorAvatar: widget.comment.authorAvatar,
                          userName: widget.comment.author,
                          barName: widget.barName,
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            UserAvatar(
                              imageUrl: widget.comment.authorAvatar,
                              radius: 14,
                              name: widget.comment.author,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.comment.author,
                                style: s(
                                  AppFonts.caption(
                                    color: colors.textPrimary,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ForumLevelBadge(
                              forumLevel: widget.comment.forumLevel,
                              forumLevelName: widget.comment.forumLevelName,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _AnimatedLikeButton(
                      isLiked: _isLiked,
                      likes: _likes,
                      busy: _liking,
                      iconSize: 22,
                      countStyle: s(AppFonts.label(color: colors.textMuted)),
                      onToggle: _handleLike,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(_bodyLeftInset, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _copyOnLongPress(
                      context,
                      widget.comment.content,
                      CommentContentBody.build(
                        context: context,
                        content: widget.comment.content,
                        baseStyle: AppFonts.body(color: colors.textPrimary),
                        onImageTap: widget.onImageTap,
                        fontScale: fontScale,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Text(
                            formatRelativeTime(widget.comment.createdAt),
                            style: s(AppFonts.label(color: colors.textMuted)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.borderLight.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#${widget.comment.floor}',
                              style: s(
                                AppFonts.numeric(
                                  color: colors.textMuted,
                                ).copyWith(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.comment.subComments.isNotEmpty ||
                  widget.comment.subPostNumber >
                      widget.comment.subComments.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: _SubCommentSurface(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var i = 0;
                          i < widget.comment.subComments.take(2).length;
                          i++
                        ) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 8),
                            Divider(
                              height: 1,
                              color: colors.border.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _buildSubComment(
                            widget.comment.subComments[i],
                            fontScale,
                          ),
                        ],
                        if (widget.comment.subPostNumber >
                            widget.comment.subComments.length) ...[
                          if (widget.comment.subComments.isNotEmpty)
                            const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  uiPageRoute(
                                    name: AppUiRouteNames.subComments,
                                    arguments: {
                                      'tid': widget.tid,
                                      'pid': widget.comment.id,
                                    },
                                    builder: (_) => SubCommentsPage(
                                      tid: widget.tid,
                                      pid: widget.comment.id,
                                      barName: widget.barName,
                                      totalCount: widget.comment.subPostNumber,
                                      seedComments: widget.comment.subComments,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                '查看全部回复 (${widget.comment.subPostNumber})',
                                style: s(AppFonts.label(color: colors.primary)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (widget.showBottomDivider)
                _CommentFloorDivider(colors: colors),
              if (!widget.showBottomDivider) const SizedBox(height: 14),
            ],
          ),
          ),
        );
      },
    );
  }
}

/// 子评论灰色底容器。
class _SubCommentSurface extends StatelessWidget {
  const _SubCommentSurface({required this.colors, required this.child});

  final AppColorScheme colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.58),
        borderRadius: AppDecorations.borderRadiusMd,
        border: Border.all(
          color: colors.borderLight.withValues(alpha: 0.55),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

/// 评论楼层之间的分隔线（比默认 [Divider] 更易辨认）。
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppFonts.label(
            color: selected ? colors.primary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _CommentFloorDivider extends StatelessWidget {
  const _CommentFloorDivider({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        Container(height: 1, color: colors.border.withValues(alpha: 0.9)),
        const SizedBox(height: 0),
        Container(
          height: 3,
          color: colors.surfaceMuted.withValues(alpha: 0.28),
        ),
      ],
    );
  }
}

class SubCommentsPage extends StatefulWidget {
  final String tid;
  final String pid;
  final String barName;
  final int totalCount;
  final List<TiebaSubComment> seedComments;

  const SubCommentsPage({
    super.key,
    required this.tid,
    required this.pid,
    required this.barName,
    required this.totalCount,
    this.seedComments = const [],
  });

  @override
  State<SubCommentsPage> createState() => _SubCommentsPageState();
}

class _SubCommentsPageState extends State<SubCommentsPage> {
  final _scrollController = ScrollController();
  late final ScrollLoadTrigger _scrollLoadTrigger = ScrollLoadTrigger(
    onNearEnd: _loadMore,
    threshold: 300,
  );
  final _comments = <TiebaSubComment>[];
  bool _loadingMore = false;
  bool _initialLoading = true;
  String? _errorMessage;
  int _page = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _comments.addAll(widget.seedComments);
    _hasMore = widget.totalCount > _comments.length;
    _scrollLoadTrigger.attach(_scrollController);
    _loadMore(isInitial: true);
  }

  @override
  void dispose() {
    _scrollLoadTrigger.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool isInitial = false}) async {
    if (_loadingMore || (!_hasMore && !isInitial)) return;
    setState(() {
      _loadingMore = true;
      _errorMessage = null;
    });
    final nextPage = _page + 1;
    try {
      final bduss = await TiebaAccountService.getBduss();
      final stoken = await TiebaAccountService.getStoken();
      final more = await TiebaClient.fetchMoreSubComments(
        widget.tid,
        widget.pid,
        bduss: bduss,
        stoken: stoken,
        page: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        final merged = _mergeSubCommentsById(_comments, more);
        _comments
          ..clear()
          ..addAll(merged);
        _loadingMore = false;
        _initialLoading = false;
        if (more.isEmpty) {
          _hasMore = false;
        } else {
          _hasMore = _comments.length < widget.totalCount;
        }
      });
      _scrollLoadTrigger.checkAfterLayout();
      _maybePrefetch();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _initialLoading = false;
        _errorMessage = '加载失败，请重试';
      });
    }
  }

  void _maybePrefetch() {
    if (!mounted || _loadingMore || !_hasMore) return;
    if (_comments.length >= widget.totalCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingMore || !_hasMore) return;
      if (!_scrollController.hasClients) {
        _loadMore();
        return;
      }
      if (_scrollController.position.maxScrollExtent < 240) {
        _loadMore();
      }
    });
  }

  void _openImage(String url) {
    Navigator.of(context).push(
      uiPageRoute(
        name: AppUiRouteNames.imageViewer,
        arguments: {'url': url},
        builder: (_) => ImageViewerPage(imageUrl: url),
        fullscreenDialog: true,
      ),
    );
  }

  Future<({String bduss, String tbs, String? stoken})?>
  _likeCredentials() async {
    final bduss = await TiebaAccountService.getBduss();
    if (bduss == null || bduss.isEmpty) {
      if (mounted) {
        showAppToast(context, '请先登录后再操作', type: AppToastType.warning);
      }
      return null;
    }
    final stoken = await TiebaAccountService.getStoken();
    final tbs = await TiebaAccountService.refreshTbs();
    if (tbs.isEmpty) {
      if (mounted) {
        showAppToast(context, '登录状态失效，请重新登录', type: AppToastType.warning);
      }
      return null;
    }
    return (bduss: bduss, tbs: tbs, stoken: stoken);
  }

  Future<void> _toggleSubLike(TiebaSubComment sub) async {
    final pid = sub.id.trim();
    if (pid.isEmpty || int.tryParse(pid) == null) {
      if (mounted) {
        showAppToast(context, '无法点赞该回复', type: AppToastType.warning);
      }
      return;
    }
    final creds = await _likeCredentials();
    if (creds == null) return;

    final previousLiked = sub.isLiked;
    final previousLikes = sub.likes;
    final nextLiked = !previousLiked;
    var nextLikes = previousLikes + (nextLiked ? 1 : -1);
    if (nextLikes < 0) nextLikes = 0;
    sub.isLiked = nextLiked;
    sub.likes = nextLikes;
    try {
      final error = previousLiked
          ? await TiebaClient.undoAgreeSubCommentMessage(
              tid: widget.tid,
              pid: pid,
              bduss: creds.bduss,
              tbs: creds.tbs,
              stoken: creds.stoken,
            )
          : await TiebaClient.agreeSubCommentMessage(
              tid: widget.tid,
              pid: pid,
              bduss: creds.bduss,
              tbs: creds.tbs,
              stoken: creds.stoken,
            );
      if (error != null && mounted) {
        sub.isLiked = previousLiked;
        sub.likes = previousLikes;
        showAppToast(context, error, type: AppToastType.error);
      }
    } catch (_) {
      if (mounted) {
        sub.isLiked = previousLiked;
        sub.likes = previousLikes;
        showAppToast(context, '点赞失败', type: AppToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget body;
    if (_initialLoading && _comments.isEmpty) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_errorMessage != null && _comments.isEmpty) {
      body = AppEmptyState(
        icon: Icons.error_outline,
        message: _errorMessage!,
        actionLabel: '重试',
        onAction: () => _loadMore(isInitial: true),
      );
    } else if (_comments.isEmpty) {
      body = const AppEmptyState(
        icon: Icons.chat_bubble_outline,
        message: '暂无楼中楼回复',
      );
    } else {
      body = ListView.builder(
        controller: _scrollController,
        cacheExtent: 800,
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 16,
        ),
        itemCount: _comments.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _comments.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final sub = _comments[i];
          return RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: i < _comments.length - 1 ? 8 : 0,
              ),
              child: _SubCommentSurface(
                colors: colors,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => openUserHome(
                              context,
                              authorAvatar: sub.authorAvatar,
                              userName: sub.author,
                              barName: widget.barName,
                            ),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                UserAvatar(
                                  imageUrl: sub.authorAvatar,
                                  radius: 12,
                                  name: sub.author,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    sub.author,
                                    style: AppFonts.caption(
                                      color: colors.textPrimary,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ForumLevelBadge(
                                  forumLevel: sub.forumLevel,
                                  forumLevelName: sub.forumLevelName,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          formatRelativeTime(sub.createdAt),
                          style: AppFonts.label(color: colors.textMuted),
                        ),
                        const SizedBox(width: 8),
                        _SubCommentLikeButton(
                          sub: sub,
                          onToggle: () => _toggleSubLike(sub),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _copyOnLongPress(
                      context,
                      sub.content,
                      CommentContentBody.build(
                        context: context,
                        content: sub.content,
                        baseStyle: AppFonts.bodySmall(color: colors.textPrimary),
                        onImageTap: _openImage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: GlassAppBar(
        title: Text(
          '回复 (${widget.totalCount})',
          style: AppFonts.title(color: colors.textPrimary),
        ),
      ),
      body: body,
    );
  }
}

class _SubCommentLikeButton extends StatefulWidget {
  final TiebaSubComment sub;
  final Future<void> Function() onToggle;

  const _SubCommentLikeButton({required this.sub, required this.onToggle});

  @override
  State<_SubCommentLikeButton> createState() => _SubCommentLikeButtonState();
}

class _SubCommentLikeButtonState extends State<_SubCommentLikeButton> {
  bool _busy = false;
  late bool _isLiked;
  late int _likes;

  @override
  void initState() {
    super.initState();
    _syncFromSub();
  }

  @override
  void didUpdateWidget(covariant _SubCommentLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sub.id != widget.sub.id ||
        oldWidget.sub.isLiked != widget.sub.isLiked ||
        oldWidget.sub.likes != widget.sub.likes) {
      _syncFromSub();
    }
  }

  void _syncFromSub() {
    _isLiked = widget.sub.isLiked;
    _likes = widget.sub.likes;
  }

  Future<void> _handleToggle() async {
    if (_busy) return;
    setState(() {
      _isLiked = !_isLiked;
      _likes += _isLiked ? 1 : -1;
      if (_likes < 0) _likes = 0;
      _busy = true;
    });
    await widget.onToggle();
    if (!mounted) return;
    setState(() {
      _syncFromSub();
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _AnimatedLikeButton(
      isLiked: _isLiked,
      likes: _likes,
      busy: _busy,
      iconSize: 18,
      countStyle: AppFonts.label(color: colors.textMuted),
      onToggle: _handleToggle,
    );
  }
}

class _AnimatedLikeButton extends StatefulWidget {
  final bool isLiked;
  final int likes;
  final bool busy;
  final bool showZeroCount;
  final double iconSize;
  final TextStyle? countStyle;
  final Future<void> Function() onToggle;

  const _AnimatedLikeButton({
    required this.isLiked,
    required this.likes,
    required this.onToggle,
    this.busy = false,
    this.showZeroCount = false,
    this.iconSize = 16,
    this.countStyle,
  });

  @override
  State<_AnimatedLikeButton> createState() => _AnimatedLikeButtonState();
}

class _AnimatedLikeButtonState extends State<_AnimatedLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28), weight: 38),
      TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.0), weight: 62),
    ]).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.busy) return;
    _bounceCtrl.forward(from: 0);
    await widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeColor = widget.isLiked ? colors.primary : colors.textMuted;
    final countStyle = (widget.countStyle ?? AppFonts.label(color: activeColor))
        .copyWith(
          color: activeColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final countGap = widget.iconSize <= 18 ? 4.0 : 5.0;
    final countSlotWidth = widget.iconSize <= 18 ? 26.0 : 32.0;
    final showCount = widget.likes > 0 || widget.showZeroCount;

    return GestureDetector(
        onTap: widget.busy ? null : _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: ColorFiltered(
                    key: ValueKey(widget.isLiked),
                    colorFilter: ColorFilter.mode(activeColor, BlendMode.srcIn),
                    child: Image.asset(
                      widget.isLiked
                          ? 'assets/icons/like_filled.png'
                          : 'assets/icons/like_outline.png',
                      width: widget.iconSize,
                      height: widget.iconSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              SizedBox(width: countGap),
              SizedBox(
                width: countSlotWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: showCount
                        ? Text(
                            '${widget.likes}',
                            key: ValueKey(widget.likes),
                            style: countStyle,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          )
                        : SizedBox(
                            key: ValueKey('empty-${widget.isLiked}'),
                            height: countStyle.fontSize,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _CapsuleSendButton extends StatelessWidget {
  final AppColorScheme colors;
  final bool enabled;
  final VoidCallback onSend;

  const _CapsuleSendButton({
    required this.colors,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = enabled
        ? colors.primary
        : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD4D7DC));
    final fg = enabled
        ? (isDark ? colors.scaffold : Colors.white)
        : colors.textMuted;

    return DecoratedBox(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onSend : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(Icons.arrow_upward_rounded, size: 20, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _LikeEffectAnimation extends StatefulWidget {
  final Offset position;
  final VoidCallback onDone;

  const _LikeEffectAnimation({
    required this.position,
    required this.onDone,
  });

  @override
  State<_LikeEffectAnimation> createState() => _LikeEffectAnimationState();
}

class _LikeEffectAnimationState extends State<_LikeEffectAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scale = Tween<double>(begin: 0.6, end: 1.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.9, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.15, 1.0, curve: Curves.easeOut)),
    );
    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 56;
    return Positioned(
      left: widget.position.dx - size / 2,
      top: widget.position.dy - size / 2,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Image.asset(
              'assets/icons/like_filled.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
