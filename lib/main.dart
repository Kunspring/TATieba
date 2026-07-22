import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme/app_colors.dart';
import 'theme/app_decorations.dart';
import 'theme/app_fonts.dart';
import 'theme/app_glass.dart';
import 'screens/forum_browse_page.dart';
import 'screens/home/home_page.dart';
import 'screens/messages_page.dart';
import 'screens/profile_page.dart';
import 'screens/login_hub_page.dart';
import 'screens/qr_login_page.dart';
import 'screens/web_login_page.dart';
import 'utils/app_lifecycle_gate.dart';
import 'models/tieba_post.dart';
import 'screens/detail/post_detail_page.dart';
import 'services/app_shell_controller.dart';
import 'services/app_theme_service.dart';
import 'services/app_ui_context.dart';
import 'services/data_saver_service.dart';
import 'services/browse_distill_service.dart';
import 'services/agent_memory_service.dart';
import 'services/agent_voice_service.dart';
import 'services/message_notification_service.dart';
import 'services/sign_in_reminder_service.dart';
import 'services/forum_recent_service.dart';
import 'services/tieba_favorite_service.dart';
import 'services/tieba_account_service.dart';
import 'theme/app_performance.dart';
import 'utils/debounced_callback.dart';
import 'widgets/app_feature_guide.dart';
import 'widgets/agent_companion/agent_companion_controller.dart';
import 'widgets/root_shell_host.dart';
import 'widgets/app_error_page.dart';

/// 诊断用掉帧记录器（性能排查期开启）。每 3 秒汇报一次窗口内：
/// - buildSlow：主线程(build)超 16ms 的帧数 → 指向定时器/GC/解析等主线程尖峰
/// - rasterSlow：raster 线程超 16ms 的帧数 → 指向图片纹理上传/模糊等 GPU 侧尖峰
/// 跑 `flutter run --profile`，用一分钟，把控制台 [JANK] 行贴回即可定位。
const bool kTraceJank = true;

void _installJankTracer() {
  if (!kTraceJank) return;
  var total = 0;
  var buildSlow = 0;
  var rasterSlow = 0;
  var buildMax = 0;
  var rasterMax = 0;
  WidgetsBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    for (final t in timings) {
      total++;
      final b = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      if (b > 16000) {
        buildSlow++;
        if (b > buildMax) buildMax = b;
      }
      if (r > 16000) {
        rasterSlow++;
        if (r > rasterMax) rasterMax = r;
      }
    }
  });
  Timer.periodic(const Duration(seconds: 3), (_) {
    if (total == 0) return;
    debugPrint(
      '[JANK] frames=$total buildSlow(>16ms)=$buildSlow '
      'rasterSlow(>16ms)=$rasterSlow '
      'buildMax=${buildMax ~/ 1000}ms rasterMax=${rasterMax ~/ 1000}ms',
    );
    total = 0;
    buildSlow = 0;
    rasterSlow = 0;
    buildMax = 0;
    rasterMax = 0;
  });
}

void _reportFatal(Object error, StackTrace? stack) {
  // 全局崩溃兜底汇聚点：runZonedGuarded 未捕获的异步错误与 FlutterError
  // 都会走到这里。当前仅打印并保留扩展点；如需上报（Sentry 等）在此接入，
  // 注意避免阻塞 UI。
  debugPrint('[FATAL] ${error.toString()}');
  if (stack != null) debugPrint(stack.toString());
}

Color _startupScaffoldColor() {
  return AppThemeService.instance.resolvedMode == ThemeMode.dark
      ? AppColors.darkScaffold
      : AppColors.scaffold;
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installJankTracer();
    PaintingBinding.instance.imageCache.maximumSize =
        AppPerformance.imageCacheMaxEntries;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        AppPerformance.imageCacheMaxBytes;
    await AppThemeService.instance.load();
    AppSystemUi.apply(
      AppThemeService.instance.resolvedMode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light,
    );
    runApp(ColoredBox(color: _startupScaffoldColor(), child: const TiebaApp()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initStartupWork());
    });
  }, (error, stack) {
    // 兜底：zone 内未捕获的异步错误（网络回调、timer、future 等）。
    _reportFatal(error, stack);
  });

  // 框架层错误（build/layout/paint 阶段抛出的异常汇聚于此）。
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
    _reportFatal(details.exception, details.stack);
  };

  // 用友好错误页替换 Flutter 默认红屏（ErrorWidget.builder）。
  ErrorWidget.builder = (details) {
    return AppErrorPage(
      details: details,
      onRetry: () {
        try {
          appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
        } catch (_) {
          // 导航栈不可用时尽力而为，忽略。
        }
      },
    );
  };
}

Future<void> _initDeferredPrefs() async {
  await TiebaAccountService.warmFromDisk();
  await DataSaverService.instance.load();
  await BrowseDistillService.instance.loadPrefs();
  await AgentMemoryService.instance.loadPrefs();
  await AgentVoiceService.instance.loadPrefs();
}

/// 首帧后后台加载，不阻塞进入首页。
Future<void> _initStartupWork() async {
  AppSystemUi.apply(
    AppThemeService.instance.resolvedMode == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light,
  );

  await _initDeferredPrefs();

  try {
    await SignInReminderService.bootstrap();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Startup] SignInReminderService.bootstrap failed: $e\n$st');
    }
  }
  try {
    await MessageNotificationService.bootstrap();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint(
        '[Startup] MessageNotificationService.bootstrap failed: $e\n$st',
      );
    }
  }

  SchedulerBinding.instance.scheduleTask(
    () => unawaited(_initNotificationNativeStack()),
    Priority.idle,
  );
}

Future<void> _initNotificationNativeStack() async {
  try {
    await SignInReminderService.ensureNativeReady();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Startup] SignInReminderService native failed: $e\n$st');
    }
  }
  try {
    await MessageNotificationService.ensureNativeReady();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Startup] MessageNotificationService native failed: $e\n$st');
    }
  }
}

class TiebaApp extends StatefulWidget {
  const TiebaApp({super.key});

  @override
  State<TiebaApp> createState() => _TiebaAppState();
}

class _TiebaAppState extends State<TiebaApp> with WidgetsBindingObserver {
  late final AgentCompanionController _companion;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _companion = AgentCompanionController();
    AppThemeService.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppThemeService.instance.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _companion.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
    AppSystemUi.apply(
      AppThemeService.instance.resolvedMode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        AppLifecycleGate.setActive(true);
        _companion.resumeFromBackground();
        SignInReminderService.instance.onAppResume();
        MessageNotificationService.instance.onAppResume();
      case AppLifecycleState.inactive:
        _companion.pauseForBackground();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        AppLifecycleGate.setActive(false);
        MessageNotificationService.instance.onAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentCompanionScope(
      controller: _companion,
      child: MaterialApp(
        title: '贝占口巴',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRouteLifecycleObserver],
        theme: _themeFor(Brightness.light),
        darkTheme: _themeFor(Brightness.dark),
        themeMode: AppThemeService.instance.themeMode,
        builder: (context, child) {
          final colors = Theme.of(context).extension<AppColorScheme>()!;
          return ColoredBox(
            color: colors.scaffold,
            child: RootShellHost(child: child),
          );
        },
        home: const MainScaffold(),
        routes: {
          '/login': (_) => const LoginHubPage(),
          '/qr-login': (_) => const QrLoginPage(),
          '/web-login': (_) => const WebLoginPage(),
        },
      ),
    );
  }

  ThemeData _themeFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return _darkTheme ??= _buildTheme(Brightness.dark);
    }
    return _lightTheme ??= _buildTheme(Brightness.light);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final appColorScheme = isDark ? AppColorScheme.dark : AppColorScheme.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: appColorScheme.scaffold,
      extensions: [appColorScheme],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: appColorScheme.primary,
        onPrimary: isDark ? appColorScheme.scaffold : Colors.white,
        secondary: appColorScheme.textSecondary,
        onSecondary: appColorScheme.scaffold,
        surface: appColorScheme.card,
        onSurface: appColorScheme.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: appColorScheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: AppSystemUi.overlayFor(brightness),
        titleTextStyle: AppFonts.title(color: appColorScheme.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: appColorScheme.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.borderRadiusLg,
          side: BorderSide(color: appColorScheme.borderLight, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: appColorScheme.divider,
        thickness: 0.5,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: appColorScheme.primary,
          foregroundColor: isDark ? appColorScheme.scaffold : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.borderRadiusMd,
          ),
          textStyle: AppFonts.button(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: appColorScheme.textSecondary,
          textStyle: AppFonts.button(color: appColorScheme.textSecondary),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: appColorScheme.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.borderRadiusLg,
        ),
        titleTextStyle: AppFonts.title(color: appColorScheme.textPrimary),
        contentTextStyle: AppFonts.body(color: appColorScheme.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: appColorScheme.surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: AppDecorations.borderRadiusMd,
          borderSide: BorderSide(color: appColorScheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppDecorations.borderRadiusMd,
          borderSide: BorderSide(color: appColorScheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppDecorations.borderRadiusMd,
          borderSide: BorderSide(color: appColorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: AppFonts.body(color: appColorScheme.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.borderRadiusMd,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: _CustomPageTransitionBuilder(),
          TargetPlatform.android: _CustomPageTransitionBuilder(),
          TargetPlatform.iOS: _CustomPageTransitionBuilder(),
          TargetPlatform.macOS: _CustomPageTransitionBuilder(),
          TargetPlatform.linux: _CustomPageTransitionBuilder(),
        },
      ),
    );
  }
}

class _CustomPageTransitionBuilder extends PageTransitionsBuilder {
  const _CustomPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final _tabIndexNotifier = ValueNotifier<int>(0);
  int _loginKey = 0;
  String? _selectedBar;
  bool _companionLinked = false;
  bool _shellLinked = false;
  final _navSnapNotifier = ValueNotifier<bool>(false);
  bool _navAnimating = false;
  Timer? _companionSyncTimer;
  Timer? _navAnimEndTimer;
  final _profileKey = GlobalKey<ProfilePageState>();
  final _messagesKey = GlobalKey<MessagesPageState>();
  final _tabLoaded = [true, false, false, false];

  late final DebouncedCallback _debouncedTabRefresh = DebouncedCallback(
    callback: _runDebouncedTabRefresh,
    delay: const Duration(milliseconds: 450),
  );
  int? _pendingRefreshTab;

  late Widget _forumTab;
  late Widget _messagesTab;
  late Widget _profileTab;
  final _homeNavKey = GlobalKey<NavigatorState>();
  List<Page<dynamic>> _homePages = const [];
  bool _homeAutoOpened = false;
  int _homeAutoOpenSeq = 0;
  late final Widget _homeTab;
  late List<Widget> _tabs;

  static const _placeholderTab = SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _homePages = [_homeFeedPage()];
    _homeTab = _buildHomeNavigator();
    AppShellController.instance.onOpenPostInHome = _openPostInHome;
    _rebuildHomeTab();
    _refreshTabs();
    AppShellController.instance.addListener(_onShellCommand);
    SchedulerBinding.instance.scheduleTask(_preloadLazyTabs, Priority.idle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MessageNotificationService.instance.consumePendingLaunchPayload();
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        unawaited(AppFeatureGuide.showMainGuidesIfNeeded(context));
      });
    });
  }

  void _preloadLazyTabs() {
    if (!mounted) return;
    unawaited(_preloadLazyTabAt(1));
  }

  Future<void> _preloadLazyTabAt(int index) async {
    if (!mounted || index > 3 || _tabLoaded[index]) return;

    await Future<void>.delayed(Duration(milliseconds: 320 * (index - 1)));

    if (!mounted || _tabLoaded[index]) return;
    switch (index) {
      case 1:
        _forumTab = ForumBrowsePage(onSelectBar: _onSelectBar);
      case 2:
        _messagesTab = MessagesPage(key: _messagesKey);
      case 3:
        _profileTab = ProfilePage(
          key: _profileKey,
          onLoginChanged: _onLoginChanged,
        );
    }
    _tabLoaded[index] = true;
    _refreshTabs();
    setState(() {});

    if (index < 3) {
      unawaited(_preloadLazyTabAt(index + 1));
    }
  }

  @override
  void dispose() {
    _debouncedTabRefresh.dispose();
    _companionSyncTimer?.cancel();
    _navAnimEndTimer?.cancel();
    _tabIndexNotifier.dispose();
    _navSnapNotifier.dispose();
    AppShellController.instance.removeListener(_onShellCommand);
    super.dispose();
  }

  void _ensureTabLoaded(int index) {
    if (index < 0 || index > 3 || _tabLoaded[index]) return;
    _tabLoaded[index] = true;
    switch (index) {
      case 1:
        _forumTab = ForumBrowsePage(onSelectBar: _onSelectBar);
      case 2:
        _messagesTab = MessagesPage(key: _messagesKey);
      case 3:
        _profileTab = ProfilePage(
          key: _profileKey,
          onLoginChanged: _onLoginChanged,
        );
    }
    _refreshTabs();
  }

  void _scheduleTabRefresh(int index) {
    _pendingRefreshTab = index;
    _debouncedTabRefresh();
  }

  void _runDebouncedTabRefresh() {
    if (!mounted) return;
    final tab = _pendingRefreshTab;
    _pendingRefreshTab = null;
    if (tab == null || tab != _currentIndex) return;
    switch (tab) {
      case 2:
        _messagesKey.currentState?.refresh();
      case 3:
        _profileKey.currentState?.refresh();
    }
  }

  void _rebuildProfileTab() {
    if (!_tabLoaded[3]) return;
    _profileTab = ProfilePage(
      key: _profileKey,
      onLoginChanged: _onLoginChanged,
    );
  }

  void _rebuildHomeTab() {
    _homePages = [
      _homeFeedPage(),
    ];
  }

  /// 首页嵌套 Navigator 的根路由：推荐流列表。
  /// 推荐流为根、帖子详情为子路由 —— 导航栏留在 Scaffold 始终可见，
  /// 打开帖子不覆盖导航栏，返回即 pop 回推荐流。
  Page<dynamic> _homeFeedPage() => MaterialPage<dynamic>(
        key: ValueKey('home-$_loginKey-${_selectedBar ?? ''}'),
        name: AppUiRouteNames.homeFeed,
        child: HomePage(
          key: ValueKey('home-$_loginKey-${_selectedBar ?? ''}'),
          selectedBar: _selectedBar,
          onClearBar: _onClearBar,
          onOpenPost: _openPostInHome,
          onAutoOpenPost: _requestAutoOpenPost,
        ),
      );

  Widget _buildHomeNavigator() => Navigator(
        key: _homeNavKey,
        observers: [appRouteLifecycleObserver],
        pages: _homePages,
        onDidRemovePage: (page) {
          setState(() => _homePages.remove(page));
        },
      );

  /// [AppShellController.onOpenPostInHome] 的实现：把帖子打开到首页嵌套 Navigator。
  void _openPostInHome({
    required TiebaPost post,
    required List<TiebaPost> posts,
    required int initialIndex,
    required Future<List<TiebaPost>> Function()? onLoadMore,
  }) {
    _pushHomePost(
      post: post,
      posts: posts,
      initialIndex: initialIndex,
      onLoadMore: onLoadMore,
    );
    AppShellController.instance.selectTab(AppShellTab.home);
  }

  void _pushHomePost({
    required TiebaPost post,
    required List<TiebaPost> posts,
    required int initialIndex,
    required Future<List<TiebaPost>> Function()? onLoadMore,
  }) {
    if (_homeNavKey.currentState == null) return;
    _homeAutoOpenSeq++;
    _homePages = [
      ..._homePages,
      MaterialPage<dynamic>(
        key: ValueKey('post-${post.id}-$_homeAutoOpenSeq'),
        name: AppUiRouteNames.postDetail,
        arguments: <String, dynamic>{
          'tid': post.id,
          if (post.title.isNotEmpty) 'title': post.title,
          if (post.barName.isNotEmpty) 'bar_name': post.barName,
          if (post.author.isNotEmpty) 'author': post.author,
        },
        child: PostDetailPage(
          post: post,
          posts: posts,
          initialIndex: initialIndex,
          onLoadMore: onLoadMore,
        ),
      ),
    ];
    setState(() {});
  }

  /// 冷启动自动打开首帖（仅一次）：App 默认进入"阅读帖子"，像打开抖音直接刷视频。
  void _requestAutoOpenPost({
    required TiebaPost post,
    required List<TiebaPost> posts,
    required int initialIndex,
    required Future<List<TiebaPost>> Function()? onLoadMore,
  }) {
    if (_homeAutoOpened) return;
    if (_currentIndex != 0) return;
    if (_homeNavKey.currentState == null) return;
    if (_homePages.length > 1) return;
    _homeAutoOpened = true;
    _pushHomePost(
      post: post,
      posts: posts,
      initialIndex: initialIndex,
      onLoadMore: onLoadMore,
    );
  }

  void _refreshTabs() {
    _tabs = [
      RepaintBoundary(child: _homeTab),
      RepaintBoundary(child: _tabLoaded[1] ? _forumTab : _placeholderTab),
      RepaintBoundary(child: _tabLoaded[2] ? _messagesTab : _placeholderTab),
      RepaintBoundary(child: _tabLoaded[3] ? _profileTab : _placeholderTab),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shellLinked) {
      _shellLinked = true;
      final shell = AppShellController.instance;
      shell.onLoginChanged = _onLoginChanged;
      shell.onActionToast = (message) {
        AgentCompanionScope.of(context).showToast(message, AppToastType.info);
      };
    }
    if (_companionLinked) return;
    _companionLinked = true;
    _syncCompanion();
  }

  void _onShellCommand() {
    if (!mounted) return;
    final commands = AppShellController.instance.drainCommands();
    if (commands.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final cmd in commands) {
        _executeShellCommand(cmd);
      }
    });
  }

  void _executeShellCommand(AppShellCommand cmd) {
    final shell = AppShellController.instance;
    switch (cmd) {
      case SelectTabCommand(:final tab):
        shell.runAfterNavigationPrep(() {
          _onTabSelected(switch (tab) {
            AppShellTab.home => 0,
            AppShellTab.forum => 1,
            AppShellTab.messages => 2,
            AppShellTab.profile => 3,
          });
        });
      case OpenBarCommand(:final barName):
        shell.runAfterNavigationPrep(() {
          _onSelectBar(barName);
        });
      case ClearBarFilterCommand():
        shell.runAfterNavigationPrep(() {
          _onClearBar();
        });
      case OpenPostCommand(:final post):
        shell.navigateToPost(post);
      case OpenRouteCommand(:final route):
        shell.navigateToRoute(route);
      case OpenAgentChatCommand():
        shell.onOpenAgentChat?.call();
      case CloseAgentChatCommand():
        shell.onCloseAgentChat?.call();
      case NavigateBackCommand():
        shell.maybePop();
      case OpenPrivateChatCommand(:final groupId, :final peerName):
        shell.runAfterNavigationPrep(() {
          _onTabSelected(2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _messagesKey.currentState?.openPrivateChatFromNotification(
              groupId: groupId,
              peerName: peerName,
            );
          });
        });
    }
  }

  void _syncCompanion() {
    final companion = AgentCompanionScope.of(context);
    companion.updateContext(
      tabIndex: _currentIndex,
      selectedBar: _selectedBar,
      agentChatOpen: companion.agentChatOpen,
    );
    AppUiContextService.instance.updateShell(
      tabIndex: _currentIndex,
      selectedBar: _selectedBar,
      agentChatOpen: companion.agentChatOpen,
      quickChatOpen: companion.quickChatOpen,
      clearSelectedBar: _selectedBar == null,
    );
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;

    // 上一次切换动画未结束时再点其它 Tab → 直接对齐，避免指示条/文字动画叠在一起闪。
    final interrupting = _navAnimating;

    if (!_tabLoaded[index]) {
      _ensureTabLoaded(index);
    }

    _currentIndex = index;
    _tabIndexNotifier.value = index;
    _setNavSnapSelection(interrupting);

    _navAnimating = true;
    _navAnimEndTimer?.cancel();
    _navAnimEndTimer = Timer(GlassBottomNav.selectionAnimDuration, () {
      if (!mounted) return;
      _navAnimating = false;
      _setNavSnapSelection(false);
    });

    MessageNotificationService.instance.setForegroundTab(index);
    if (index == 2 || index == 3) {
      _scheduleTabRefresh(index);
    }
    _scheduleCompanionSync();
  }

  void _setNavSnapSelection(bool value) {
    if (_navSnapNotifier.value == value) return;
    _navSnapNotifier.value = value;
  }

  void _scheduleCompanionSync() {
    _companionSyncTimer?.cancel();
    _companionSyncTimer = Timer(const Duration(milliseconds: 48), () {
      if (!mounted) return;
      _syncCompanion();
    });
  }

  void _onLoginChanged() {
    TiebaFavoriteService.invalidateCache();
    SignInReminderService.instance.onLoginChanged();
    MessageNotificationService.instance.onLoginChanged();
    setState(() {
      _loginKey++;
      _rebuildHomeTab();
      _rebuildProfileTab();
      if (_tabLoaded[1]) {
        _forumTab = ForumBrowsePage(onSelectBar: _onSelectBar);
      }
      _refreshTabs();
    });
    if (_tabLoaded[3]) {
      _profileKey.currentState?.refresh();
    }
    if (_tabLoaded[2]) {
      _messagesKey.currentState?.refresh();
    }
  }

  void _onSelectBar(String bar) {
    ForumRecentService.recordVisit(bar);
    _navAnimEndTimer?.cancel();
    _navAnimating = false;
    _setNavSnapSelection(true);
    setState(() {
      _selectedBar = bar;
      _currentIndex = 0;
      _tabIndexNotifier.value = 0;
      _rebuildHomeTab();
      _rebuildProfileTab();
      _refreshTabs();
    });
    _syncCompanion();
  }

  void _onClearBar() {
    _navAnimEndTimer?.cancel();
    _navAnimating = false;
    _setNavSnapSelection(true);
    setState(() {
      _selectedBar = null;
      _rebuildHomeTab();
      _rebuildProfileTab();
      _refreshTabs();
    });
    _syncCompanion();
  }

  String _companionLayoutKeyFor(int index) {
    return switch (index) {
      0 => _selectedBar != null ? 'home-bar' : 'home',
      1 => 'forum',
      2 => 'messages',
      3 => 'profile',
      _ => 'home',
    };
  }

  @override
  Widget build(BuildContext context) {
    final companion = AgentCompanionScope.of(context);
    return ListenableBuilder(
      listenable: companion,
      builder: (context, _) {
        final agentChatOpen = companion.agentChatOpen;
        final homeNavState = _homeNavKey.currentState;
        final homeNavCanPop =
            _currentIndex == 0 && (homeNavState?.canPop() ?? false);
        return PopScope(
          canPop: !agentChatOpen &&
              !homeNavCanPop &&
              (_selectedBar == null || _currentIndex != 0),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (agentChatOpen) {
              AppShellController.instance.handleAgentChatBack?.call();
              return;
            }
            final nav = _homeNavKey.currentState;
            if (_currentIndex == 0 && nav != null && nav.canPop()) {
              nav.pop();
              return;
            }
            if (_selectedBar != null && _currentIndex == 0) {
              _onClearBar();
            }
          },
          child: ValueListenableBuilder<int>(
            valueListenable: _tabIndexNotifier,
            builder: (context, tabIndex, _) {
              return Scaffold(
                backgroundColor: Theme.of(
                  context,
                ).extension<AppColorScheme>()!.scaffold,
                extendBody: true,
                body: CompanionLayoutScope(
                  activeLayoutKey: _companionLayoutKeyFor(tabIndex),
                  child: IndexedStack(
                    index: tabIndex,
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        TickerMode(enabled: tabIndex == i, child: _tabs[i]),
                    ],
                  ),
                ),
                bottomNavigationBar: RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable:
                        MessageNotificationService.instance.unreadBadge,
                    builder: (context, unread, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _navSnapNotifier,
                        builder: (context, snapSelection, _) {
                          return GlassBottomNav(
                            selectedIndex: tabIndex,
                            snapSelection: snapSelection,
                            onDestinationSelected: _onTabSelected,
                            items: [
                              const GlassNavItem(
                                icon: Icons.home_rounded,
                                label: '首页',
                              ),
                              const GlassNavItem(
                                icon: Icons.explore_rounded,
                                label: '进吧',
                              ),
                              GlassNavItem(
                                icon: Icons.chat_bubble_rounded,
                                label: '消息',
                                badgeCount: unread,
                              ),
                              const GlassNavItem(
                                icon: Icons.person_rounded,
                                label: '个人',
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
