import 'dart:async';

import 'package:flutter/material.dart';
import '../constants/app_info.dart';
import '../models/tieba_post.dart';
import '../services/tieba_account_service.dart';
import '../services/tieba_client.dart';
import '../services/app_shell_controller.dart';
import '../services/app_ui_context.dart';
import '../services/tieba_favorite_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_icons.dart';
import '../theme/app_glass.dart';
import '../utils/agent_kaomoji_mood.dart';
import '../widgets/agent_kaomoji.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_toast.dart';
import '../widgets/user_avatar.dart';
import '../widgets/user_level_badges.dart';
import '../utils/app_resume_refresh.dart';
import '../utils/open_user_home.dart';
import 'agent_config_page.dart';
import 'browse_history_page.dart';
import 'favorites_page.dart';
import 'home/forum_post_card.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onLoginChanged;

  const ProfilePage({super.key, required this.onLoginChanged});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  String? _displayName;
  String? _accountName;
  String? _avatarUrl;
  int? _growthLevel;
  bool _isLoggedIn = false;
  bool _sessionResolved = false;
  List<TiebaPost> _favorites = [];
  bool _loadingFavs = true;

  // 从后台回前台自动刷新所需的状态记录。
  DateTime? _bgPausedAt;
  DateTime? _lastResumeRefreshAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyLocalSnapshot();
    _loadUserInfo();
    _bootstrapFavorites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        // 离开较久，重新拉取个人资料与收藏，保证"打开即见新内容"。
        _lastResumeRefreshAt = now;
        unawaited(refresh());
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _bgPausedAt ??= DateTime.now();
    }
  }

  void _applyLocalSnapshot() {
    final snapshot = TiebaAccountService.localSnapshot;
    if (snapshot == null) return;
    _isLoggedIn = true;
    _displayName = snapshot.displayName;
    _accountName = snapshot.accountName;
    _avatarUrl = snapshot.avatarUrl;
    _sessionResolved = true;
  }

  Future<void> refresh() async {
    await _loadUserInfo();
    await _loadFavorites(showLoading: false);
  }

  void _openFavoritePost(TiebaPost post) {
    AppShellController.instance.navigateToPost(post);
  }

  String? _cachedPortrait;
  String? _cachedUserId;

  Future<void> _loadUserInfo() async {
    await TiebaAccountService.warmFromDisk();
    final loggedIn = await TiebaAccountService.isBound();

    if (!loggedIn) {
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _displayName = null;
          _accountName = null;
          _avatarUrl = null;
          _growthLevel = null;
          _sessionResolved = true;
        });
      }
      return;
    }

    String? displayName = _displayName;
    String? accountName = _accountName;
    String? avatar = _avatarUrl;

    accountName ??= await TiebaAccountService.getTiebaUserName();
    final cachedNick = await TiebaAccountService.getTiebaName();
    final bduss = await TiebaAccountService.getBduss();
    final profile = bduss != null && bduss.isNotEmpty
        ? await TiebaClient.fetchSelfProfile(bduss: bduss)
        : null;

    if (profile != null) {
      final nick = profile['nick_name']?.toString().trim();
      final userName = profile['user_name']?.toString().trim();
      if (userName?.isNotEmpty == true) accountName = userName;
      if (nick != null && nick.isNotEmpty) {
        displayName = nick;
      } else if (userName?.isNotEmpty == true) {
        displayName = userName;
      }
      final portrait = profile['portrait']?.toString();
      _cachedPortrait = portrait;
      _cachedUserId = profile['user_id']?.toString();
      avatar = TiebaAccountService.portraitToUrl(portrait);
    }

    displayName ??= cachedNick?.isNotEmpty == true ? cachedNick : accountName;

    if (avatar == null) {
      final portrait = await TiebaAccountService.getPortrait();
      avatar = TiebaAccountService.portraitToUrl(portrait);
    }

    if (mounted) {
      setState(() {
        _isLoggedIn = true;
        _displayName = displayName;
        _accountName = accountName;
        _avatarUrl = avatar;
        _sessionResolved = true;
      });
      await _loadLevelInfo(portrait: _cachedPortrait, userId: _cachedUserId);
    }
  }

  Future<void> _loadLevelInfo({String? portrait, String? userId}) async {
    final bduss = await TiebaAccountService.getBduss();
    final stoken = await TiebaAccountService.getStoken();
    final growth = await TiebaClient.fetchUserGrowthLevel(
      portrait: portrait,
      userId: userId,
      bduss: bduss,
      stoken: stoken,
    );

    if (!mounted) return;
    setState(() => _growthLevel = growth);
  }

  String? get _growthLevelLabel {
    final level = _growthLevel;
    if (level == null || level <= 0) return null;
    return 'Lv.$level';
  }

  Future<void> _bootstrapFavorites() async {
    final cached = await TiebaFavoriteService.getFavorites();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _favorites = List.from(cached);
        _loadingFavs = false;
      });
    }
    await _loadFavorites(showLoading: _favorites.isEmpty);
  }

  Future<void> _loadFavorites({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loadingFavs = true);
    }
    final favs = await TiebaFavoriteService.loadFavoritePosts();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _loadingFavs = false;
    });
  }

  Future<void> _logout() async {
    await TiebaAccountService.unbind();
    TiebaFavoriteService.invalidateCache();
    if (!mounted) return;
    widget.onLoginChanged();
    showAppToast(context, '已退出', type: AppToastType.info);
    _loadUserInfo();
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('退出后需要重新扫码登录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _logout();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.appColors;

    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // GlassBottomNav: 8 + 44 + 8 内边距 + 8 底边距 ≈ 68，再留一点呼吸间距。
    final bottomInset = MediaQuery.paddingOf(context).bottom + 80;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        companionLayoutKey: 'profile',
        title: Text('个人', style: AppFonts.title(color: colors.textPrimary)),
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUserCard(colors),
            const SizedBox(height: 24),
            Text('通用', style: AppFonts.title(color: colors.textPrimary)),
            const SizedBox(height: 10),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: AppSettingsIcon(color: colors.textPrimary),
                    title: Text(
                      '设置',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        uiPageRoute(
                          name: AppUiRouteNames.settings,
                          builder: (_) => SettingsPage(
                            onLoginChanged: widget.onLoginChanged,
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: colors.divider),
                  ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AgentKaomoji(
                            mood: AgentKaomojiMood.neutral,
                            size: 14,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      '助手设置',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        uiPageRoute(
                          name: AppUiRouteNames.agentConfig,
                          builder: (_) => const AgentConfigPage(),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: colors.divider),
                  ListTile(
                    leading: Icon(
                      Icons.history_rounded,
                      color: colors.textPrimary,
                      size: 22,
                    ),
                    title: Text(
                      '浏览记录',
                      style: AppFonts.body(color: colors.textPrimary),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        uiPageRoute(
                          name: AppUiRouteNames.browseHistory,
                          builder: (_) => const BrowseHistoryPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('我的收藏', style: AppFonts.title(color: colors.textPrimary)),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      uiPageRoute(
                        name: AppUiRouteNames.favorites,
                        builder: (_) => const FavoritesPage(),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: AppFonts.caption(color: colors.textSecondary),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textMuted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingFavs && _favorites.isEmpty)
              const SizedBox(height: 120, child: PersistentAppLoading())
            else if (_favorites.isEmpty)
              _FavoritesEmptyHint(colors: colors)
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_favorites.length.clamp(0, 5), (i) {
                  final post = _favorites[i];
                  return ForumPostCard(
                    post: post,
                    onTap: () => _openFavoritePost(post),
                  );
                }),
              ),
            const SizedBox(height: 28),
            _ProfileFooter(colors: colors),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(AppColorScheme colors) {
    if (!_sessionResolved) {
      return _ProfileUserCardSkeleton(colors: colors);
    }

    if (_isLoggedIn) {
      return GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => openUserHome(context, isSelf: true),
                borderRadius: AppDecorations.borderRadiusLg,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UserAvatar(
                      imageUrl: _avatarUrl,
                      radius: 26,
                      name: _displayName,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _displayName ?? '用户',
                            style: AppFonts.title(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_accountName?.isNotEmpty == true &&
                              _accountName != _displayName)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '@$_accountName',
                                style: AppFonts.caption(
                                  color: colors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '已登录',
                                    style: AppFonts.caption(
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                              if (_growthLevelLabel != null)
                                UserLevelBadges(
                                  scope: UserLevelBadgeScope.profile,
                                  growthLevelLabel: _growthLevelLabel,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: _confirmLogout,
              tooltip: '退出',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.logout_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 36,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text('未登录', style: AppFonts.title(color: colors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            '登录后可收藏帖子并查看个人主页',
            style: AppFonts.body(color: colors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final result = await Navigator.of(context).pushNamed('/login');
              if (result == true && mounted) {
                await refresh();
              }
            },
            icon: const Icon(Icons.login_rounded),
            label: const Text('登录'),
          ),
        ],
      ),
    );
  }
}

class _ProfileUserCardSkeleton extends StatelessWidget {
  final AppColorScheme colors;

  const _ProfileUserCardSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    final block = colors.surfaceMuted.withValues(alpha: 0.85);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: block, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: AppDecorations.borderRadiusSm,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 72,
                  height: 12,
                  decoration: BoxDecoration(
                    color: block.withValues(alpha: 0.75),
                    borderRadius: AppDecorations.borderRadiusSm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesEmptyHint extends StatelessWidget {
  final AppColorScheme colors;

  const _FavoritesEmptyHint({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.bookmarkBorder, size: 36, color: colors.textMuted),
          const SizedBox(height: 12),
          Text('还没有收藏的帖子', style: AppFonts.body(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

class _ProfileFooter extends StatelessWidget {
  final AppColorScheme colors;

  const _ProfileFooter({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: colors.divider),
        const SizedBox(height: 20),
        Text(
          AppInfo.fullLabel,
          style: AppFonts.caption(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '收藏仅保存在本机，卸载应用或清除数据后将无法恢复。',
          style: AppFonts.label(color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '感谢 贴吧 Lite、aiotieba 等开源项目的参考与支持。',
          style: AppFonts.label(color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
