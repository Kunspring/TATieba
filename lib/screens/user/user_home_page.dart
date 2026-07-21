import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../models/tieba_post.dart';
import '../../models/tieba_private_message.dart';
import '../../models/tieba_user_profile.dart';
import '../../models/user_followed_forum.dart';
import '../../services/tieba_account_service.dart';
import '../../services/tieba_client.dart';
import '../../services/app_shell_controller.dart';
import '../../services/tieba_favorite_service.dart';
import '../../services/tieba_message_service.dart';
import '../../services/message_notification_service.dart';
import '../../services/app_ui_context.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_glass.dart';
import '../../utils/scroll_load_trigger.dart';
import '../../utils/scroll_settle.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/kaomoji_loader.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/user_level_badges.dart';
import '../detail/post_detail_page.dart';
import '../home/forum_post_card.dart';
import '../messages/private_chat_detail_page.dart';

/// 用户主页：资料头 + 帖子 / 关注的吧 Tab。
class UserHomePage extends StatefulWidget {
  final String? portrait;
  final String? userName;
  final String? barName;
  final bool isSelf;

  const UserHomePage({
    super.key,
    this.portrait,
    this.userName,
    this.barName,
    this.isSelf = false,
  });

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  TiebaUserProfile? _profile;
  bool _loadingProfile = true;
  bool _loadingLevels = false;
  String? _error;
  String? _bduss;
  String? _stoken;
  String? _previewName;
  String? _previewPortrait;
  bool _openingPrivateMessage = false;
  bool _followLoading = false;
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      animationDuration: const Duration(milliseconds: 280),
    );
    _previewPortrait = widget.portrait;
    _previewName = widget.userName;
    _prepareSession();
    _bootstrapPreview();
    _loadProfile();
  }

  Future<void> _prepareSession() async {
    _bduss = await TiebaAccountService.getBduss();
    _stoken = await TiebaAccountService.getStoken();
    if (!mounted) return;
    setState(() => _sessionReady = true);
  }

  Future<void> _bootstrapPreview() async {
    var portrait = widget.portrait;
    var name = widget.userName?.trim();
    if (widget.isSelf) {
      portrait ??= await TiebaAccountService.getPortrait();
      name ??= await TiebaAccountService.getTiebaName();
      name ??= await TiebaAccountService.getTiebaUserName();
    }
    if (!mounted) return;
    setState(() {
      if (portrait?.isNotEmpty == true) _previewPortrait = portrait;
      if (name?.isNotEmpty == true) _previewName = name;
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _loadingLevels = true;
      _error = null;
    });
    _bduss ??= await TiebaAccountService.getBduss();
    _stoken ??= await TiebaAccountService.getStoken();
    final portraitHint = _previewPortrait ?? widget.portrait ?? '';

    final profileFuture = widget.isSelf && (_bduss?.isNotEmpty ?? false)
        ? TiebaClient.fetchSelfProfile(bduss: _bduss!)
        : TiebaClient.fetchUserProfile(
            bduss: _bduss,
            stoken: _stoken,
            portrait: widget.portrait,
            userName: widget.userName,
          );
    final levelsFuture = _fetchLevels(portrait: portraitHint);

    final raw = await profileFuture;
    if (!mounted) return;
    if (raw == null) {
      setState(() {
        _loadingProfile = false;
        _loadingLevels = false;
        _error = '无法加载用户资料';
      });
      return;
    }

    var profile = TiebaUserProfile.fromApi(raw);
    setState(() {
      _profile = profile;
      _loadingProfile = false;
    });

    final resolvedPortrait = profile.portrait.isNotEmpty
        ? profile.portrait
        : portraitHint;
    final growthFromProfile = raw['growth_level'];
    _LevelFetch? levels;
    if (growthFromProfile is int && growthFromProfile > 0) {
      levels = _LevelFetch(growth: growthFromProfile);
    } else {
      levels = await levelsFuture;
    }
    if (resolvedPortrait.isNotEmpty &&
        (portraitHint.isEmpty || resolvedPortrait != portraitHint)) {
      levels =
          await _fetchLevels(
            portrait: resolvedPortrait,
            userId: profile.userId,
          ) ??
          levels;
    } else if (profile.userId?.isNotEmpty == true &&
        (levels?.growth == null || levels!.growth! <= 0)) {
      levels =
          await _fetchLevels(
            portrait: resolvedPortrait.isNotEmpty ? resolvedPortrait : null,
            userId: profile.userId,
          ) ??
          levels;
    }

    if (!mounted || _profile == null) return;
    if (levels != null) {
      profile = profile.copyWith(
        growthLevel: levels.growth,
        forumLevel: levels.forumLevel,
        forumLevelName: levels.forumLevelName,
        forumLevelBarName: levels.forumLevelBarName,
      );
    }

    if (!widget.isSelf && (_bduss?.isNotEmpty ?? false)) {
      final followPortrait = profile.portrait.isNotEmpty
          ? profile.portrait
          : portraitHint;
      if (followPortrait.isNotEmpty) {
        final followed = await TiebaAccountService.fetchUserIsFollowedByMe(
          portrait: followPortrait,
          userId: profile.userId,
        );
        if (followed != null) {
          profile = profile.copyWith(isFollowedByMe: followed);
        }
      }
    }

    if (!mounted || _profile == null) return;
    setState(() {
      _profile = profile;
      _loadingLevels = false;
    });
  }

  Future<_LevelFetch?> _fetchLevels({String? portrait, String? userId}) async {
    final normalizedPortrait = portrait?.trim() ?? '';
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedPortrait.isEmpty && normalizedUserId.isEmpty) {
      return null;
    }

    int? growth;
    if (normalizedPortrait.isNotEmpty || normalizedUserId.isNotEmpty) {
      growth = await TiebaClient.fetchUserGrowthLevel(
        portrait: normalizedPortrait.isNotEmpty ? normalizedPortrait : null,
        userId: normalizedUserId.isNotEmpty ? normalizedUserId : null,
        bduss: _bduss,
        stoken: _stoken,
      );
    }

    int? forumLevel;
    String? forumLevelName;
    final barName = widget.barName?.trim();
    if (barName != null &&
        barName.isNotEmpty &&
        normalizedPortrait.isNotEmpty) {
      final barLevel = await TiebaClient.fetchUserForumLevel(
        barName: barName,
        portrait: normalizedPortrait,
        bduss: _bduss,
        stoken: _stoken,
      );
      if (barLevel != null) {
        forumLevel = int.tryParse(barLevel['forum_level']?.toString() ?? '');
        forumLevelName = barLevel['forum_level_name']?.toString();
      }
    }

    if (growth == null && forumLevel == null) return null;
    return _LevelFetch(
      growth: growth,
      forumLevel: forumLevel,
      forumLevelName: forumLevelName,
      forumLevelBarName: barName,
    );
  }

  Future<void> _openPrivateMessage(TiebaUserProfile profile) async {
    if (!await TiebaAccountService.isBound()) {
      if (!mounted) return;
      showAppToast(context, '请先登录后再发私信', type: AppToastType.warning);
      return;
    }

    setState(() => _openingPrivateMessage = true);
    try {
      final peerUserId = int.tryParse(profile.userId ?? '') ?? 0;
      final lookup = await TiebaMessageService.lookupPrivateChatForPeer(
        peerUserId: peerUserId > 0 ? peerUserId : null,
        portrait: profile.portrait.isNotEmpty ? profile.portrait : null,
        peerName: profile.displayName,
      );

      if (!mounted) return;
      if (lookup.error != null) {
        showAppToast(context, '私信加载失败', type: AppToastType.error);
        return;
      }

      final chat =
          lookup.conversation ??
          PrivateChatConversation(
            groupId: 0,
            peerUserId: peerUserId,
            peerName: profile.displayName,
            peerPortrait: profile.portrait.isNotEmpty ? profile.portrait : null,
            messages: const [],
          );

      if (chat.groupId > 0) {
        MessageNotificationService.instance.setForegroundPrivateChat(
          chat.groupId,
        );
        await MessageNotificationService.instance.markPrivateChatOpened(chat);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        uiPageRoute(
          name: AppUiRouteNames.privateChat,
          arguments: {'peer_name': chat.peerName},
          builder: (_) => PrivateChatDetailPage(conversation: chat),
        ),
      );
      if (chat.groupId > 0) {
        MessageNotificationService.instance.setForegroundPrivateChat(null);
      }
    } finally {
      if (mounted) setState(() => _openingPrivateMessage = false);
    }
  }

  Future<void> _toggleUserFollow(TiebaUserProfile profile) async {
    if (_followLoading) return;
    if (!await TiebaAccountService.isBound()) {
      if (!mounted) return;
      showAppToast(context, '请先登录后再关注', type: AppToastType.warning);
      return;
    }

    final portrait = profile.portrait.trim();
    if (portrait.isEmpty) {
      if (!mounted) return;
      showAppToast(context, '无法识别该用户', type: AppToastType.error);
      return;
    }

    final wasFollowed = profile.isFollowedByMe ?? false;
    setState(() => _followLoading = true);
    final ok = wasFollowed
        ? await TiebaAccountService.unfollowUser(portrait)
        : await TiebaAccountService.followUser(portrait);
    if (!mounted) return;
    setState(() {
      _followLoading = false;
      if (ok && _profile != null) {
        _profile = _profile!.copyWith(isFollowedByMe: !wasFollowed);
      }
    });
    if (!ok) {
      showAppToast(
        context,
        wasFollowed ? '取消关注失败，请稍后重试' : '关注失败，请稍后重试',
        type: AppToastType.error,
      );
      return;
    }
    showAppToast(
      context,
      wasFollowed ? '已取消关注' : '已关注',
      type: wasFollowed ? AppToastType.info : AppToastType.success,
    );
  }

  String get _portrait =>
      _profile?.portrait ?? _previewPortrait ?? widget.portrait ?? '';

  String get _pageTitle {
    final fromProfile = _profile?.displayName.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
    final preview = _previewName?.trim();
    if (preview != null && preview.isNotEmpty) return preview;
    final userName = widget.userName?.trim();
    if (userName != null && userName.isNotEmpty) return userName;
    return '用户主页';
  }

  String? get _previewAvatarUrl {
    final portrait = _previewPortrait ?? widget.portrait ?? '';
    if (portrait.isEmpty) return null;
    if (portrait.startsWith('http')) return portrait;
    return 'https://himg.bdimg.com/sys/portrait/item/$portrait';
  }

  bool get _showProfileActions =>
      !widget.isSelf && (_bduss?.isNotEmpty ?? false);

  /// 资料、登录态就绪后再拉取帖子列表，避免 bduss 未就绪时请求失败后不重试。
  bool get _postListReady {
    if (_loadingProfile || !_sessionReady) return false;
    return _portrait.isNotEmpty ||
        (_profile?.userId?.isNotEmpty ?? false) ||
        (widget.userName?.trim().isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topInset = glassTopInset(context);
    final profileError = _error != null && _profile == null;

    if (profileError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          companionLayoutKey: 'user-home',
          titleText: _pageTitle,
          title: Text(
            _pageTitle,
            style: AppFonts.title(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topInset + 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppEmptyState(
                icon: Icons.person_off_outlined,
                message: _error!,
                actionLabel: '重试',
                onAction: _loadProfile,
              ),
            ),
          ],
        ),
      );
    }

    final profileExpandedHeight = _profile != null
        ? _ProfileHeader.expandedHeightFor(
            _profile!,
            showActions: _showProfileActions,
          )
        : _ProfileHeaderPreview.expandedHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        companionLayoutKey: 'user-home',
        titleText: _pageTitle,
        title: Text(
          _pageTitle,
          style: AppFonts.title(color: colors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          final handle = NestedScrollView.sliverOverlapAbsorberHandleFor(
            context,
          );
          return [
            SliverOverlapAbsorber(
              handle: handle,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: topInset + 8)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _CollapsingProfileHeaderDelegate(
                      maxExtent: profileExpandedHeight,
                      minExtent: _ProfileHeader.collapsedHeight,
                      childBuilder: (progress) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _profile != null
                              ? _ProfileHeader(
                                  key: ValueKey(_profile!.portrait),
                                  profile: _profile!,
                                  loadingLevels: _loadingLevels,
                                  collapseProgress: progress,
                                  showActions: _showProfileActions,
                                  privateMessageLoading: _openingPrivateMessage,
                                  followLoading: _followLoading,
                                  onPrivateMessage: () =>
                                      _openPrivateMessage(_profile!),
                                  onToggleFollow: () =>
                                      _toggleUserFollow(_profile!),
                                )
                              : _ProfileHeaderPreview(
                                  key: const ValueKey('user-home-preview'),
                                  avatarUrl: _previewAvatarUrl,
                                  displayName: _previewName,
                                  loading: _loadingProfile,
                                  collapseProgress: progress,
                                ),
                        ),
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyTabBarDelegate(
                      tabBar: GlassTabBar(
                        controller: _tabCtrl,
                        tabs: const ['帖子', '关注的吧'],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabCtrl,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          clipBehavior: Clip.hardEdge,
          children: [
            _UserPostListTab(
              key: const ValueKey('user-home-tab-posts'),
              portrait: _portrait,
              userId: _profile?.userId,
              userName: widget.userName ?? _profile?.userName,
              ownerDisplayName: _profile?.displayName,
              ownerAvatarUrl: _profile?.avatarUrl,
              bduss: _bduss,
              stoken: _stoken,
              identityReady: _postListReady,
              threadsOnly: true,
            ),
            _UserForumListTab(
              key: const ValueKey('user-home-tab-forums'),
              portrait: _portrait,
              userId: _profile?.userId,
              userName: widget.userName ?? _profile?.userName,
              bduss: _bduss,
              stoken: _stoken,
              identityReady: _postListReady,
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelFetch {
  final int? growth;
  final int? forumLevel;
  final String? forumLevelName;
  final String? forumLevelBarName;

  const _LevelFetch({
    this.growth,
    this.forumLevel,
    this.forumLevelName,
    this.forumLevelBarName,
  });
}

class _CollapsingProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double _maxExtent;
  final double _minExtent;
  final Widget Function(double collapseProgress) childBuilder;

  _CollapsingProfileHeaderDelegate({
    required double maxExtent,
    required double minExtent,
    required this.childBuilder,
  }) : _maxExtent = maxExtent,
       _minExtent = minExtent;

  @override
  double get maxExtent => _maxExtent;

  @override
  double get minExtent => _minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final progress = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final height = (maxExtent - shrinkOffset).clamp(minExtent, maxExtent);

    return SizedBox(
      height: height,
      child: ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _QuantizedCollapseChild(
            progress: progress,
            builder: childBuilder,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingProfileHeaderDelegate oldDelegate) {
    return oldDelegate._maxExtent != _maxExtent ||
        oldDelegate._minExtent != _minExtent;
  }
}

class _QuantizedCollapseChild extends StatefulWidget {
  final double progress;
  final Widget Function(double progress) builder;

  const _QuantizedCollapseChild({
    required this.progress,
    required this.builder,
  });

  @override
  State<_QuantizedCollapseChild> createState() =>
      _QuantizedCollapseChildState();
}

class _QuantizedCollapseChildState extends State<_QuantizedCollapseChild> {
  static const _steps = 24;
  late double _displayProgress;

  @override
  void initState() {
    super.initState();
    _displayProgress = _quantize(widget.progress);
  }

  @override
  void didUpdateWidget(covariant _QuantizedCollapseChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _quantize(widget.progress);
    if (next != _displayProgress) {
      setState(() => _displayProgress = next);
    }
  }

  double _quantize(double value) =>
      (value.clamp(0.0, 1.0) * _steps).round() / _steps;

  @override
  Widget build(BuildContext context) => widget.builder(_displayProgress);
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final GlassTabBar tabBar;

  _StickyTabBarDelegate({required this.tabBar});

  @override
  double get minExtent => tabBar.preferredSize.height + 8;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: Colors.transparent, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}

class _ProfileHeaderPreview extends StatelessWidget {
  static const expandedHeight = 212.0;

  final String? avatarUrl;
  final String? displayName;
  final bool loading;
  final double collapseProgress;

  const _ProfileHeaderPreview({
    super.key,
    this.avatarUrl,
    this.displayName,
    this.loading = false,
    this.collapseProgress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = displayName?.trim();
    final t = collapseProgress.clamp(0.0, 1.0);
    final avatarRadius = lerpDouble(28, 18, t)!;
    final detailOpacity = (1 - t * 0.4).clamp(0.0, 1.0);

    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                imageUrl: avatarUrl,
                radius: avatarRadius,
                name: name ?? '用户',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name?.isNotEmpty == true ? name! : '用户',
                            style: AppFonts.title(
                              color: colors.textPrimary,
                            ).copyWith(fontSize: lerpDouble(17, 15, t)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (detailOpacity > 0.05) ...[
                          Opacity(
                            opacity: detailOpacity,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: UserLevelBadges(
                                scope: UserLevelBadgeScope.profile,
                                loading: true,
                                inline: true,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (detailOpacity > 0.05) ...[
                      Opacity(
                        opacity: detailOpacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            _SkeletonLine(width: 88, colors: colors),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (loading && detailOpacity > 0.2)
                Opacity(
                  opacity: detailOpacity,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
          if (detailOpacity > 0.05) ...[
            Opacity(
              opacity: detailOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _SkeletonLine(
                    width: double.infinity,
                    colors: colors,
                    height: 10,
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _SkeletonStatCell(colors: colors),
                      _StatDivider(colors: colors),
                      _SkeletonStatCell(colors: colors),
                      _StatDivider(colors: colors),
                      _SkeletonStatCell(colors: colors),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final AppColorScheme colors;

  const _SkeletonLine({
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

class _SkeletonStatCell extends StatelessWidget {
  final AppColorScheme colors;

  const _SkeletonStatCell({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          _SkeletonLine(width: 36, colors: colors, height: 14),
          const SizedBox(height: 6),
          _SkeletonLine(width: 28, colors: colors, height: 10),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  static const collapsedHeight = 76.0;

  final TiebaUserProfile profile;
  final bool loadingLevels;
  final double collapseProgress;
  final bool showActions;
  final bool privateMessageLoading;
  final bool followLoading;
  final VoidCallback? onPrivateMessage;
  final VoidCallback? onToggleFollow;

  const _ProfileHeader({
    super.key,
    required this.profile,
    this.loadingLevels = false,
    this.collapseProgress = 0,
    this.showActions = false,
    this.privateMessageLoading = false,
    this.followLoading = false,
    this.onPrivateMessage,
    this.onToggleFollow,
  });

  static double expandedHeightFor(
    TiebaUserProfile profile, {
    bool showActions = false,
  }) {
    var height = 224.0;
    if (profile.intro?.trim().isNotEmpty == true) height += 34;
    if (showActions) height += 52;
    return height;
  }

  String _formatCount(int count) {
    if (count <= 0) return '0';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = collapseProgress.clamp(0.0, 1.0);
    final avatarRadius = lerpDouble(28, 18, t)!;
    final detailOpacity = (1 - t * 0.4).clamp(0.0, 1.0);
    final statsOpacity = (1 - t * 1.1).clamp(0.0, 1.0);
    final hasIntro = profile.intro?.trim().isNotEmpty == true;
    final hasLevels = loadingLevels || profile.growthLevelLabel != null;

    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                imageUrl: profile.avatarUrl,
                radius: avatarRadius,
                name: profile.displayName,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName,
                            style: AppFonts.title(
                              color: colors.textPrimary,
                            ).copyWith(fontSize: lerpDouble(17, 15, t)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasLevels && detailOpacity > 0.05) ...[
                          Opacity(
                            opacity: detailOpacity,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: UserLevelBadges(
                                scope: UserLevelBadgeScope.profile,
                                loading: loadingLevels,
                                growthLevelLabel: profile.growthLevelLabel,
                                inline: true,
                              ),
                            ),
                          ),
                        ],
                        if (profile.isVip && detailOpacity > 0.2) ...[
                          Opacity(
                            opacity: detailOpacity,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (detailOpacity > 0.05) ...[
                      Opacity(
                        opacity: detailOpacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.userName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '@${profile.userName}',
                                style: AppFonts.caption(
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                            if (profile.forumAgeLabel != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                profile.forumAgeLabel!,
                                style: AppFonts.caption(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (t > 0.55)
                _CompactStats(
                  postCount: _formatCount(profile.postCount),
                  fanCount: _formatCount(profile.fanCount),
                  colors: colors,
                  opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                ),
            ],
          ),
          if (hasIntro && detailOpacity > 0.05) ...[
            Opacity(
              opacity: detailOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    profile.intro!.trim(),
                    style: AppFonts.bodySmall(color: colors.textSecondary),
                    maxLines: t > 0.35 ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          if (showActions && detailOpacity > 0.05) ...[
            Opacity(
              opacity: detailOpacity,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileActionButton(
                        colors: colors,
                        label: '私信',
                        icon: Icons.mail_outline_rounded,
                        loading: privateMessageLoading,
                        enabled:
                            onPrivateMessage != null && !privateMessageLoading,
                        filled: false,
                        onTap: onPrivateMessage,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ProfileActionButton(
                        colors: colors,
                        label: profile.isFollowedByMe == true ? '已关注' : '关注',
                        icon: profile.isFollowedByMe == true
                            ? Icons.person_rounded
                            : Icons.person_add_outlined,
                        loading: followLoading,
                        enabled: onToggleFollow != null && !followLoading,
                        filled: profile.isFollowedByMe != true,
                        onTap: onToggleFollow,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (statsOpacity > 0.05) ...[
            Opacity(
              opacity: statsOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Divider(height: 1, color: colors.divider),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatCell(
                        label: '发帖',
                        value: _formatCount(profile.postCount),
                        colors: colors,
                      ),
                      _StatDivider(colors: colors),
                      _StatCell(
                        label: '粉丝',
                        value: _formatCount(profile.fanCount),
                        colors: colors,
                      ),
                      _StatDivider(colors: colors),
                      _StatCell(
                        label: '关注',
                        value: _formatCount(profile.followCount),
                        colors: colors,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final AppColorScheme colors;
  final String label;
  final IconData icon;
  final bool loading;
  final bool enabled;
  final bool filled;
  final VoidCallback? onTap;

  const _ProfileActionButton({
    required this.colors,
    required this.label,
    required this.icon,
    this.loading = false,
    this.enabled = true,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final bg = filled
        ? colors.primary.withValues(alpha: active ? 0.12 : 0.06)
        : colors.surfaceMuted.withValues(alpha: 0.65);
    final fg = filled
        ? (active ? colors.primary : colors.textMuted)
        : (active ? colors.textSecondary : colors.textMuted);

    return Material(
      color: bg,
      borderRadius: AppDecorations.borderRadiusMd,
      child: InkWell(
        onTap: active && !loading ? onTap : null,
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

class _CompactStats extends StatelessWidget {
  final String postCount;
  final String fanCount;
  final AppColorScheme colors;
  final double opacity;

  const _CompactStats({
    required this.postCount,
    required this.fanCount,
    required this.colors,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            postCount,
            style: AppFonts.numeric(
              color: colors.textPrimary,
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            '粉丝 $fanCount',
            style: AppFonts.caption(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  final AppColorScheme colors;

  const _StatDivider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(width: 1, thickness: 1, color: colors.divider),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final AppColorScheme colors;

  const _StatCell({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppFonts.numeric(
              color: colors.textPrimary,
            ).copyWith(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppFonts.caption(color: colors.textMuted)),
        ],
      ),
    );
  }
}

class _UserPostListTab extends StatefulWidget {
  final String portrait;
  final String? userId;
  final String? userName;
  final String? ownerDisplayName;
  final String? ownerAvatarUrl;
  final String? bduss;
  final String? stoken;
  final bool identityReady;
  final bool threadsOnly;

  const _UserPostListTab({
    super.key,
    required this.portrait,
    this.userId,
    this.userName,
    this.ownerDisplayName,
    this.ownerAvatarUrl,
    required this.bduss,
    required this.stoken,
    this.identityReady = true,
    required this.threadsOnly,
  });

  @override
  State<_UserPostListTab> createState() => _UserPostListTabState();
}

class _UserPostListTabState extends State<_UserPostListTab>
    with AutomaticKeepAliveClientMixin {
  static const _scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  ScrollController? _fallbackScrollCtrl;
  late final ScrollLoadTrigger _loadTrigger = ScrollLoadTrigger(
    onNearEnd: _loadMore,
  );

  final _posts = <TiebaPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.identityReady) {
      _loadInitial();
    } else {
      _loading = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollTrigger();
  }

  void _attachScrollTrigger() {
    final primary = PrimaryScrollController.maybeOf(context);
    final ScrollController controller =
        primary ?? (_fallbackScrollCtrl ??= ScrollController());
    _loadTrigger.attach(controller);
  }

  @override
  void didUpdateWidget(covariant _UserPostListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.portrait != widget.portrait ||
        oldWidget.userName != widget.userName ||
        oldWidget.ownerDisplayName != widget.ownerDisplayName;
    final sessionChanged =
        oldWidget.bduss != widget.bduss || oldWidget.stoken != widget.stoken;
    final becameReady = !oldWidget.identityReady && widget.identityReady;

    if (becameReady ||
        widget.identityReady && (identityChanged || sessionChanged)) {
      _loadInitial();
    }
  }

  @override
  void dispose() {
    _loadTrigger.dispose();
    _fallbackScrollCtrl?.dispose();
    super.dispose();
  }

  bool get _hasIdentity =>
      widget.portrait.isNotEmpty ||
      (widget.userId?.isNotEmpty ?? false) ||
      (widget.userName?.trim().isNotEmpty ?? false);

  List<TiebaPost> _withOwnerIdentity(List<TiebaPost> items) {
    final name = widget.ownerDisplayName?.trim();
    if (name == null || name.isEmpty) return items;
    final avatar = widget.ownerAvatarUrl;
    final portrait = widget.portrait.isNotEmpty ? widget.portrait : null;
    return items.map((post) {
      if (post.author.isNotEmpty &&
          post.author != '匿名' &&
          post.author != '用户') {
        return post;
      }
      return TiebaPost(
        id: post.id,
        title: post.title,
        author: name,
        authorAvatar: post.authorAvatar ?? avatar,
        authorPortrait: post.authorPortrait ?? portrait,
        cover: post.cover,
        content: post.content,
        barName: post.barName,
        fid: post.fid,
        replyCount: post.replyCount,
        createdAt: post.createdAt,
        likes: post.likes,
        isLiked: post.isLiked,
        isFavorited: post.isFavorited,
        video: post.video,
        authorForumLevel: post.authorForumLevel,
        authorForumLevelName: post.authorForumLevelName,
      );
    }).toList();
  }

  Future<void> _loadInitial() async {
    if (!widget.identityReady || !_hasIdentity) {
      if (!widget.identityReady) {
        setState(() => _loading = true);
      } else {
        setState(() {
          _loading = false;
          _hasMore = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    final items = _withOwnerIdentity(
      await TiebaClient.fetchUserPosts(
        portrait: widget.portrait.isNotEmpty ? widget.portrait : null,
        userId: widget.userId,
        userName: widget.userName,
        page: 1,
        threadsOnly: widget.threadsOnly,
        bduss: widget.bduss,
        stoken: widget.stoken,
      ),
    );
    if (!mounted) return;
    setState(() {
      _posts
        ..clear()
        ..addAll(items);
      _loading = false;
      _hasMore = items.length >= 20;
      _page = 1;
    });
    _patchFavoriteStatusLater(items);
  }

  void _patchFavoriteStatusLater(List<TiebaPost> posts) {
    if (posts.isEmpty) return;
    unawaited(TiebaFavoriteService.applyFavoriteStatuses(posts));
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || !_hasIdentity) {
      return;
    }
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final items = _withOwnerIdentity(
      await TiebaClient.fetchUserPosts(
        portrait: widget.portrait.isNotEmpty ? widget.portrait : null,
        userId: widget.userId,
        userName: widget.userName,
        page: nextPage,
        threadsOnly: widget.threadsOnly,
        bduss: widget.bduss,
        stoken: widget.stoken,
      ),
    );
    if (!mounted) return;
    scheduleIdleUpdate(() {
      if (!mounted) return;
      setState(() {
        final ids = _posts.map((p) => p.id).toSet();
        _posts.addAll(items.where((p) => ids.add(p.id)));
        _loadingMore = false;
        _page = nextPage;
        _hasMore = items.length >= 20;
      });
    });
    _patchFavoriteStatusLater(items);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom + 24;
    final overlapHandle = NestedScrollView.sliverOverlapAbsorberHandleFor(
      context,
    );

    if (_loading) {
      return CustomScrollView(
        key: PageStorageKey('user-home-loading-${widget.threadsOnly}'),
        physics: _scrollPhysics,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PostCardSkeleton(colors: context.appColors),
                ),
                childCount: 3,
              ),
            ),
          ),
        ],
      );
    }

    if (_posts.isEmpty) {
      return CustomScrollView(
        key: PageStorageKey('user-home-empty-${widget.threadsOnly}'),
        physics: _scrollPhysics,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.article_outlined,
              message: widget.threadsOnly ? '暂无帖子' : '暂无回复',
              actionLabel: '刷新',
              onAction: _loadInitial,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: CustomScrollView(
        key: PageStorageKey('user-home-posts-${widget.threadsOnly}'),
        physics: _scrollPhysics,
        cacheExtent: 500,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _posts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: KaomojiLoader(size: 36)),
                    );
                  }
                  final post = _posts[index];
                  return ForumPostCard(
                    post: post,
                    index: index,
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
                  );
                },
                childCount: _posts.length + (_loadingMore ? 1 : 0),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserForumListTab extends StatefulWidget {
  final String portrait;
  final String? userId;
  final String? userName;
  final String? bduss;
  final String? stoken;
  final bool identityReady;

  const _UserForumListTab({
    super.key,
    required this.portrait,
    this.userId,
    this.userName,
    required this.bduss,
    required this.stoken,
    this.identityReady = true,
  });

  @override
  State<_UserForumListTab> createState() => _UserForumListTabState();
}

class _UserForumListTabState extends State<_UserForumListTab>
    with AutomaticKeepAliveClientMixin {
  static const _scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  ScrollController? _fallbackScrollCtrl;
  late final ScrollLoadTrigger _loadTrigger = ScrollLoadTrigger(
    onNearEnd: _loadMore,
  );

  final _forums = <UserFollowedForum>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.identityReady) {
      _loadInitial();
    } else {
      _loading = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollTrigger();
  }

  void _attachScrollTrigger() {
    final primary = PrimaryScrollController.maybeOf(context);
    final ScrollController controller =
        primary ?? (_fallbackScrollCtrl ??= ScrollController());
    _loadTrigger.attach(controller);
  }

  @override
  void didUpdateWidget(covariant _UserForumListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.portrait != widget.portrait ||
        oldWidget.userName != widget.userName;
    final sessionChanged =
        oldWidget.bduss != widget.bduss || oldWidget.stoken != widget.stoken;
    final becameReady = !oldWidget.identityReady && widget.identityReady;

    if (becameReady ||
        widget.identityReady && (identityChanged || sessionChanged)) {
      _loadInitial();
    }
  }

  @override
  void dispose() {
    _loadTrigger.dispose();
    _fallbackScrollCtrl?.dispose();
    super.dispose();
  }

  int? get _resolvedUserId => int.tryParse(widget.userId?.trim() ?? '');

  bool get _hasIdentity =>
      widget.portrait.isNotEmpty ||
      (_resolvedUserId ?? 0) > 0 ||
      (widget.userName?.trim().isNotEmpty ?? false);

  Future<void> _loadInitial() async {
    if (!widget.identityReady || !_hasIdentity) {
      if (!widget.identityReady) {
        setState(() => _loading = true);
      } else {
        setState(() {
          _loading = false;
          _hasMore = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
    });
    final uid = _resolvedUserId ?? 0;
    final result = await TiebaClient.fetchUserFollowForums(
      userId: uid,
      portrait: widget.portrait.isNotEmpty ? widget.portrait : null,
      userName: widget.userName,
      page: 1,
      bduss: widget.bduss,
      stoken: widget.stoken,
    );
    if (!mounted) return;
    setState(() {
      _forums
        ..clear()
        ..addAll(result.items);
      _loading = false;
      _hasMore = result.hasMore;
      _page = 1;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || !_hasIdentity) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final uid = _resolvedUserId ?? 0;
    final result = await TiebaClient.fetchUserFollowForums(
      userId: uid,
      portrait: widget.portrait.isNotEmpty ? widget.portrait : null,
      userName: widget.userName,
      page: nextPage,
      bduss: widget.bduss,
      stoken: widget.stoken,
    );
    if (!mounted) return;
    setState(() {
      final ids = _forums.map((f) => f.name).toSet();
      _forums.addAll(result.items.where((f) => ids.add(f.name)));
      _loadingMore = false;
      _page = nextPage;
      _hasMore = result.hasMore;
    });
  }

  void _openForum(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    AppShellController.instance.openBar(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;
    final bottomPad = MediaQuery.paddingOf(context).bottom + 24;
    final overlapHandle = NestedScrollView.sliverOverlapAbsorberHandleFor(
      context,
    );

    if (_loading) {
      return CustomScrollView(
        key: const PageStorageKey('user-home-forums-loading'),
        physics: _scrollPhysics,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ForumRowSkeleton(colors: colors),
                ),
                childCount: 6,
              ),
            ),
          ),
        ],
      );
    }

    if (_forums.isEmpty) {
      return CustomScrollView(
        key: const PageStorageKey('user-home-forums-empty'),
        physics: _scrollPhysics,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.forum_outlined,
              message: widget.bduss?.isNotEmpty == true
                  ? '暂无关注的吧'
                  : '登录后可查看关注的吧',
              actionLabel: '刷新',
              onAction: _loadInitial,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: CustomScrollView(
        key: const PageStorageKey('user-home-forums'),
        physics: _scrollPhysics,
        cacheExtent: 500,
        slivers: [
          SliverOverlapInjector(handle: overlapHandle),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _forums.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: KaomojiLoader(size: 36)),
                    );
                  }
                  final forum = _forums[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _UserForumRow(
                      forum: forum,
                      colors: colors,
                      onTap: () => _openForum(forum.name),
                    ),
                  );
                },
                childCount: _forums.length + (_loadingMore ? 1 : 0),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserForumRow extends StatelessWidget {
  final UserFollowedForum forum;
  final AppColorScheme colors;
  final VoidCallback onTap;

  const _UserForumRow({
    required this.forum,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card.withValues(alpha: 0.72),
      borderRadius: AppDecorations.borderRadiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppDecorations.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.forum_rounded,
                  color: colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  forum.name.endsWith('吧') ? forum.name : '${forum.name}吧',
                  style: AppFonts.body(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (forum.level > 0) ...[
                Text(
                  'Lv.${forum.level}',
                  style: AppFonts.caption(color: colors.textMuted),
                ),
                const SizedBox(width: 4),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumRowSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const _ForumRowSkeleton({required this.colors});

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

class _PostCardSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const _PostCardSkeleton({required this.colors});

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
              _SkeletonLine(width: 88, colors: colors, height: 10),
            ],
          ),
          const SizedBox(height: 14),
          _SkeletonLine(width: double.infinity, colors: colors, height: 12),
          const SizedBox(height: 8),
          _SkeletonLine(width: 220, colors: colors, height: 10),
        ],
      ),
    );
  }
}
