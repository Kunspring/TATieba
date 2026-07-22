import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/forum_recent_service.dart';
import '../utils/app_resume_refresh.dart';
import '../services/sign_in_reminder_service.dart';
import '../services/sign_in_progress_service.dart';
import '../services/tieba_account_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../utils/forum_section_index.dart';
import '../utils/image_url_helper.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import '../widgets/kaomoji_loader.dart';

enum _ForumViewMode { list, grid }

class ForumBrowsePage extends StatefulWidget {
  final ValueChanged<String> onSelectBar;

  const ForumBrowsePage({super.key, required this.onSelectBar});

  @override
  State<ForumBrowsePage> createState() => _ForumBrowsePageState();
}

class _ForumBrowsePageState extends State<ForumBrowsePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _refreshTriggerPullDistance = 58.0;
  static const _refreshIndicatorBody = 36.0;
  static const _refreshGapBelowAppBar = 6.0;
  static const _scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  final _scrollCtrl = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};

  List<FollowedBar> _followedBars = [];
  List<String> _recentNames = [];
  bool _loading = true;
  bool _signingIn = false;
  bool _signedInToday = false;
  _ForumViewMode _viewMode = _ForumViewMode.grid;

  // 从后台回前台自动刷新所需的状态记录。
  DateTime? _bgPausedAt;
  DateTime? _lastResumeRefreshAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _bgPausedAt;
      _bgPausedAt = null;
      final now = DateTime.now();
      final awayLongEnough = pausedAt != null &&
          now.difference(pausedAt) >= kResumeRefreshMinInterval;
      final throttleOk = _lastResumeRefreshAt == null ||
          now.difference(_lastResumeRefreshAt!) >= kResumeRefreshMinInterval;
      if (awayLongEnough && throttleOk) {
        // 离开较久，重新拉取关注吧/最近进入，保证"打开即见新内容"。
        _lastResumeRefreshAt = now;
        unawaited(_refreshData());
      } else {
        // 间隔过短：仅同步轻量的签到状态，避免无谓的全量请求。
        unawaited(_refreshSignInStatus());
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _bgPausedAt ??= DateTime.now();
    }
  }

  /// 供应用回到前台时主动刷新（外部统一驱动亦可调用）。
  void refresh() {
    if (!mounted) return;
    unawaited(_refreshData());
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadFollowedBars(),
      _loadRecent(),
      _refreshSignInStatus(),
    ]);
  }

  Future<void> _refreshSignInStatus() async {
    final signed = await SignInReminderService.instance.hasSignedInToday();
    if (mounted) setState(() => _signedInToday = signed);
  }

  Future<void> _loadRecent() async {
    final names = await ForumRecentService.getRecent();
    if (mounted) setState(() => _recentNames = names);
  }

  Future<void> _loadFollowedBars() async {
    setState(() => _loading = true);
    final bars = await TiebaAccountService.fetchFollowedBars();
    if (mounted) {
      setState(() {
        _followedBars = bars;
        _loading = false;
      });
    }
  }

  /// 下拉刷新：已有列表时不切全页 loading，避免闪屏。
  Future<void> _refreshData() async {
    if (_followedBars.isEmpty) {
      await _loadFollowedBars();
    } else {
      final bars = await TiebaAccountService.fetchFollowedBars();
      if (mounted) setState(() => _followedBars = bars);
    }
    await _loadRecent();
    await _refreshSignInStatus();
  }

  double _refreshIndicatorExtent(BuildContext context) =>
      glassTopInset(context) + _refreshGapBelowAppBar + _refreshIndicatorBody;

  void _openBar(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    ForumRecentService.recordVisit(trimmed);
    setState(() {
      _recentNames = [
        trimmed,
        ..._recentNames.where((n) => n != trimmed),
      ].take(ForumRecentService.maxCount).toList();
    });
    widget.onSelectBar(trimmed);
  }

  Future<void> _confirmUnfollow(String barName) async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('取消关注', style: AppFonts.title(color: colors.textPrimary)),
        content: Text(
          '确定不再关注「$barName」吗？',
          style: AppFonts.body(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消关注'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await TiebaAccountService.unfollowBar(barName);
    if (!mounted) return;
    if (ok) {
      await _loadFollowedBars();
      if (!mounted) return;
      showAppToast(context, '已取消关注', type: AppToastType.info);
    } else {
      showAppToast(context, '取消关注失败，请稍后重试', type: AppToastType.error);
    }
  }

  List<FollowedBar> get _visibleFollowed => _followedBars;

  Map<String, List<FollowedBar>> get _groupedVisible {
    final grouped = groupFollowedBarsBySection(_visibleFollowed);
    _sectionKeys.removeWhere((key, _) => !grouped.containsKey(key));
    for (final key in grouped.keys) {
      _sectionKeys.putIfAbsent(key, GlobalKey.new);
    }
    return grouped;
  }

  List<String> get _sectionOrder => sortedForumSectionKeys(_groupedVisible);

  bool get _showIndexRail =>
      _viewMode == _ForumViewMode.list && _sectionOrder.length > 2;

  Future<void> _signInAll() async {
    if (!await SignInReminderService.instance.hasNotificationPermission()) {
      final granted = await SignInReminderService.instance
          .requestNotificationPermission();
      if (!granted && mounted) {
        showAppToast(
          context,
          '未开启通知权限，签到进度将无法在通知栏显示',
          type: AppToastType.warning,
        );
      }
    }

    setState(() => _signingIn = true);
    final progress = SignInProgressService.instance;
    final bars = await TiebaAccountService.fetchFollowedBars();
    await progress.start(bars.length);
    if (mounted && bars.isNotEmpty) {
      showAppToast(context, '签到已开始，可在通知栏查看进度', type: AppToastType.info);
    }

    List<SignInResult> results;
    try {
      results = await TiebaAccountService.signInAllBars(
        onProgress: (event) async {
          if (event.signing) {
            await progress.updateSigning(
              current: event.index,
              total: event.total,
              barName: event.barName,
              successCount: event.successCount,
            );
          } else {
            await progress.updateSigning(
              current: event.index + 1,
              total: event.total,
              barName: event.barName,
              successCount: event.successCount,
            );
            if (event.success == false) {
              await progress.showFailure(
                barName: event.barName,
                message: event.message ?? '签到失败',
              );
            }
          }
        },
      );
    } finally {
      if (bars.isEmpty) {
        await progress.dismiss();
      }
    }

    if (!mounted) return;
    setState(() => _signingIn = false);

    if (results.isEmpty) {
      if (bars.isEmpty && mounted) {
        showAppToast(context, '暂无关注吧', type: AppToastType.info);
      }
      return;
    }

    final successCount = results.where((r) => r.success).length;
    final failed = results.where((r) => !r.success).toList();
    if (successCount > 0) {
      await SignInReminderService.instance.markSignedInToday();
    }
    await progress.complete(
      successCount: successCount,
      total: results.length,
      failedCount: failed.length,
    );
    await _refreshSignInStatus();
    if (!mounted) return;
    final colors = context.appColors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('签到结果', style: AppFonts.title(color: colors.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${results.length} 个吧，成功 $successCount 个${failed.isEmpty ? '' : '，失败 ${failed.length} 个'}',
                style: AppFonts.body(color: colors.textSecondary),
              ),
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: failed
                          .map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 16,
                                    color: colors.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      r.message,
                                      style: AppFonts.bodySmall(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _jumpToSection(String key) {
    final ctx = _sectionKeys[key]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 80;
    final refreshExtent = _refreshIndicatorExtent(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        companionLayoutKey: 'forum',
        title: Text('进吧', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtrl,
            physics: _scrollPhysics,
            cacheExtent: 500,
            slivers: [
              CupertinoSliverRefreshControl(
                onRefresh: _refreshData,
                refreshTriggerPullDistance: _refreshTriggerPullDistance,
                refreshIndicatorExtent: refreshExtent,
                builder: _refreshIndicatorBuilder(colors),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (!_signedInToday || _signingIn) ...[
                      _SummaryCard(
                        colors: colors,
                        barCount: _followedBars.length,
                        signedInToday: _signedInToday,
                        signingIn: _signingIn,
                        onSignInAll: _followedBars.isEmpty ? null : _signInAll,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _ViewModeToolbar(
                      colors: colors,
                      viewMode: _viewMode,
                      onViewModeChanged: (mode) =>
                          setState(() => _viewMode = mode),
                    ),
                    if (_recentNames.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _RecentStrip(
                        colors: colors,
                        bars: recentFollowedBars(
                          recentNames: _recentNames,
                          followed: _followedBars,
                        ),
                        onTap: _openBar,
                      ),
                    ],
                  ]),
                ),
              ),
              if (_loading && _followedBars.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: PersistentAppLoading(message: '加载关注吧…')),
                )
              else if (_followedBars.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.forum_outlined,
                    message: '还没有关注贴吧',
                    actionLabel: '去登录',
                    onAction: () => Navigator.of(context).pushNamed('/login'),
                  ),
                )
              else
                ..._buildFollowedSlivers(colors),
              SliverPadding(padding: EdgeInsets.only(bottom: bottomInset)),
            ],
          ),
          if (_showIndexRail)
            Positioned(
              right: 2,
              top: topInset + 160,
              bottom: bottomInset + 8,
              child: _SectionIndexRail(
                colors: colors,
                keys: _sectionOrder,
                onTap: _jumpToSection,
              ),
            ),
          if (_signingIn)
            Positioned(
              left: 16,
              right: 16,
              top: topInset + 12,
              child: _SigningBanner(colors: colors),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFollowedSlivers(AppColorScheme colors) {
    final bars = _visibleFollowed;

    if (_viewMode == _ForumViewMode.grid) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.86,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _ForumGridTile(
                bar: bars[i],
                colors: colors,
                onTap: () => _openBar(bars[i].name),
                onLongPress: () => _confirmUnfollow(bars[i].name),
              ),
              childCount: bars.length,
            ),
          ),
        ),
      ];
    }

    final grouped = _groupedVisible;
    final order = _sectionOrder;
    final slivers = <Widget>[];
    for (final key in order) {
      final sectionBars = grouped[key] ?? const [];
      if (sectionBars.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          key: _sectionKeys[key],
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, _showIndexRail ? 28 : 16, 6),
            child: Text(
              key,
              style: AppFonts.caption(
                color: colors.primary,
              ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, _showIndexRail ? 28 : 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _ForumListTile(
                bar: sectionBars[i],
                colors: colors,
                onTap: () => _openBar(sectionBars[i].name),
                onLongPress: () => _confirmUnfollow(sectionBars[i].name),
              ),
              childCount: sectionBars.length,
            ),
          ),
        ),
      );
    }
    return slivers;
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
            key: const ValueKey('forum-refresh-spinner'),
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

class _SummaryCard extends StatelessWidget {
  final AppColorScheme colors;
  final int barCount;
  final bool signedInToday;
  final bool signingIn;
  final VoidCallback? onSignInAll;

  const _SummaryCard({
    required this.colors,
    required this.barCount,
    required this.signedInToday,
    required this.signingIn,
    this.onSignInAll,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryLight,
              borderRadius: AppDecorations.borderRadiusMd,
            ),
            child: Icon(Icons.forum_rounded, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已关注 $barCount 个吧',
                  style: AppFonts.title(color: colors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  signedInToday ? '今日已完成一键签到' : '支持一键签到全部关注吧',
                  style: AppFonts.caption(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: signingIn ? null : onSignInAll,
            child: Text(signingIn ? '签到中…' : '一键签到'),
          ),
        ],
      ),
    );
  }
}

class _ViewModeToolbar extends StatelessWidget {
  final AppColorScheme colors;
  final _ForumViewMode viewMode;
  final ValueChanged<_ForumViewMode> onViewModeChanged;

  const _ViewModeToolbar({
    required this.colors,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSegmentTabs<_ForumViewMode>(
      selected: viewMode,
      onChanged: onViewModeChanged,
      options: const [
        GlassSegmentOption(value: _ForumViewMode.grid, label: '宫格'),
        GlassSegmentOption(value: _ForumViewMode.list, label: '列表'),
      ],
    );
  }
}

class _RecentStrip extends StatelessWidget {
  final AppColorScheme colors;
  final List<FollowedBar> bars;
  final ValueChanged<String> onTap;

  const _RecentStrip({
    required this.colors,
    required this.bars,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近进入', style: AppFonts.caption(color: colors.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: bars.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final bar = bars[i];
              return _ForumGridTile(
                bar: bar,
                colors: colors,
                compact: true,
                width: 72,
                onTap: () => onTap(bar.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ForumGridTile extends StatelessWidget {
  final FollowedBar bar;
  final AppColorScheme colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final double? width;

  const _ForumGridTile({
    required this.bar,
    required this.colors,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 52.0 : 56.0;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: _BarAvatar(bar: bar, colors: colors),
          ),
        ),
        SizedBox(height: compact ? 6 : 10),
        Text(
          bar.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppFonts.caption(color: colors.textPrimary),
        ),
      ],
    );

    if (compact) {
      return SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: AppDecorations.borderRadiusLg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Center(child: content),
            ),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Center(child: content),
      ),
    );
  }
}

class _ForumListTile extends StatelessWidget {
  final FollowedBar bar;
  final AppColorScheme colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ForumListTile({
    required this.bar,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: _BarAvatar(bar: bar, colors: colors),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                bar.name,
                style: AppFonts.body(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionIndexRail extends StatelessWidget {
  final AppColorScheme colors;
  final List<String> keys;
  final ValueChanged<String> onTap;

  const _SectionIndexRail({
    required this.colors,
    required this.keys,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: keys
              .map(
                (key) => GestureDetector(
                  onTap: () => onTap(key),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Text(
                      key,
                      style: AppFonts.label(
                        color: colors.textMuted,
                      ).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SigningBanner extends StatelessWidget {
  final AppColorScheme colors;

  const _SigningBanner({required this.colors});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '正在签到，可在通知栏查看进度',
              style: AppFonts.caption(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarAvatar extends StatelessWidget {
  final FollowedBar bar;
  final AppColorScheme colors;

  const _BarAvatar({required this.bar, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (bar.avatar.isNotEmpty) {
      final cacheWidth = ImageUrlHelper.memCacheWidth(context);
      return CachedNetworkImage(
        imageUrl: bar.avatar,
        fit: BoxFit.cover,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth,
        fadeInDuration: const Duration(milliseconds: 200),
        errorWidget: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final colors = this.colors;
    return Container(
      color: colors.surfaceMuted,
      child: Icon(Icons.forum_rounded, color: colors.textSecondary, size: 22),
    );
  }
}
