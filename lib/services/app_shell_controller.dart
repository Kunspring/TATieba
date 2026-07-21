import 'package:flutter/material.dart';

import '../models/tieba_post.dart';
import '../screens/agent_config_page.dart';
import '../screens/detail/post_detail_page.dart';
import '../screens/favorites_page.dart';
import '../screens/login_hub_page.dart';
import '../screens/settings_page.dart';
import 'app_theme_service.dart';
import 'app_ui_context.dart';

/// 全局 Navigator，用于 AI 从任意上下文 push 页面。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 监听根 Navigator 路由变化（如帖子详情 pop）。
final AppRouteLifecycleObserver appRouteLifecycleObserver =
    AppRouteLifecycleObserver();

class AppRouteLifecycleObserver extends NavigatorObserver {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    AppUiContextService.instance.onRouteRemoved(route);
    _notify();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    AppUiContextService.instance.onRoutePushed(route);
    _notify();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    AppUiContextService.instance.onRouteRemoved(route);
    _notify();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null) {
      AppUiContextService.instance.onRouteRemoved(oldRoute);
    }
    if (newRoute != null) {
      AppUiContextService.instance.onRoutePushed(newRoute);
    }
    _notify();
  }
}

enum AppShellTab { home, forum, messages, profile }

enum AppShellRoute { favorites, settings, login, agentConfig }

sealed class AppShellCommand {
  const AppShellCommand();
}

class SelectTabCommand extends AppShellCommand {
  final AppShellTab tab;
  const SelectTabCommand(this.tab);
}

class OpenBarCommand extends AppShellCommand {
  final String barName;
  const OpenBarCommand(this.barName);
}

class ClearBarFilterCommand extends AppShellCommand {
  const ClearBarFilterCommand();
}

class OpenPostCommand extends AppShellCommand {
  final TiebaPost post;
  const OpenPostCommand(this.post);
}

class OpenRouteCommand extends AppShellCommand {
  final AppShellRoute route;
  const OpenRouteCommand(this.route);
}

class OpenAgentChatCommand extends AppShellCommand {
  const OpenAgentChatCommand();
}

class CloseAgentChatCommand extends AppShellCommand {
  const CloseAgentChatCommand();
}

class NavigateBackCommand extends AppShellCommand {
  const NavigateBackCommand();
}

class OpenPrivateChatCommand extends AppShellCommand {
  final int groupId;
  final String? peerName;

  const OpenPrivateChatCommand({required this.groupId, this.peerName});
}

/// 应用壳层命令总线：AI 工具入队，[MainScaffold] 与 overlay 消费。
class AppShellController extends ChangeNotifier {
  AppShellController._();

  static final AppShellController instance = AppShellController._();

  final List<AppShellCommand> _pending = [];

  VoidCallback? onLoginChanged;
  VoidCallback? onOpenAgentChat;
  VoidCallback? onCloseAgentChat;

  /// 系统返回键：先 pop 对话内子页，再收起对话 overlay。
  bool Function()? handleAgentChatBack;

  /// 打开设置/帖子等页面前立即收起对话层，避免目标页被全屏 overlay 挡住。
  VoidCallback? onDismissChatForNavigation;

  /// 应用切后台时无动画移除对话路由，避免与系统退出动画争抢 GPU。
  VoidCallback? onDismissChatForNavigationInstant;
  void Function(String message)? onActionToast;
  bool Function()? isAgentChatOpen;

  List<AppShellCommand> drainCommands() {
    if (_pending.isEmpty) return const [];
    final copy = List<AppShellCommand>.from(_pending);
    _pending.clear();
    return copy;
  }

  void _enqueue(AppShellCommand cmd, {String? toast}) {
    _pending.add(cmd);
    if (toast != null && toast.isNotEmpty) {
      onActionToast?.call(toast);
    }
    notifyListeners();
  }

  void selectTab(AppShellTab tab, {String? toast}) {
    _enqueue(SelectTabCommand(tab), toast: toast);
  }

  void openBar(String barName, {String? toast}) {
    final name = barName.trim();
    if (name.isEmpty) return;
    _enqueue(OpenBarCommand(name), toast: toast ?? '已打开「$name」吧');
  }

  void clearBarFilter({String? toast}) {
    _enqueue(const ClearBarFilterCommand(), toast: toast ?? '已回到首页推荐');
  }

  void openPost({
    required String tid,
    String? title,
    String? barName,
    String? author,
    int? replyCount,
    String? toast,
  }) {
    final id = tid.trim();
    if (id.isEmpty) return;
    final post = TiebaPost(
      id: id,
      title: title?.trim().isNotEmpty == true ? title!.trim() : '帖子',
      author: author?.trim().isNotEmpty == true ? author!.trim() : '匿名',
      content: '',
      barName: barName?.trim() ?? '',
      replyCount: replyCount ?? 0,
      createdAt: DateTime.now(),
      likes: 0,
    );
    navigateToPost(post, toast: toast ?? '已打开帖子');
  }

  void openRoute(AppShellRoute route, {String? toast}) {
    navigateToRoute(route, toast: toast);
  }

  void openAgentChat({String? toast}) {
    _enqueue(const OpenAgentChatCommand(), toast: toast);
  }

  void closeAgentChat({String? toast}) {
    _enqueue(const CloseAgentChatCommand(), toast: toast);
  }

  void navigateBack({String? toast}) {
    _enqueue(const NavigateBackCommand(), toast: toast);
  }

  void openPrivateChat({
    required int groupId,
    String? peerName,
    String? toast,
  }) {
    if (groupId <= 0) return;
    _enqueue(
      OpenPrivateChatCommand(groupId: groupId, peerName: peerName),
      toast: toast,
    );
  }

  Future<void> setThemeMode(String mode) async {
    final parsed = switch (mode.trim().toLowerCase()) {
      'light' || '白天' || '日间' => ThemeMode.light,
      'dark' || '夜间' || '黑夜' => ThemeMode.dark,
      'system' || '跟随系统' => ThemeMode.system,
      _ => null,
    };
    if (parsed == null) return;
    await AppThemeService.instance.setThemeMode(parsed);
  }

  void dismissChatForNavigation() {
    onDismissChatForNavigation?.call();
  }

  void dismissChatForNavigationInstant() {
    onDismissChatForNavigationInstant?.call();
  }

  NavigatorState? get _navigator => appNavigatorKey.currentState;

  /// 助手触发的导航：先关对话 overlay，再清掉帖子详情等子路由，最后执行 [action]。
  void runAfterNavigationPrep(VoidCallback action) {
    final nav = _navigator;
    if (nav == null) return;

    void popOverlayRoutesAndRun() {
      if (nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
      }
      action();
    }

    final chatOpen = isAgentChatOpen?.call() == true;
    if (chatOpen) {
      dismissChatForNavigation();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!nav.mounted) return;
        popOverlayRoutesAndRun();
      });
      return;
    }

    dismissChatForNavigation();
    popOverlayRoutesAndRun();
  }

  void navigateToPost(TiebaPost post, {String? toast}) {
    runAfterNavigationPrep(() {
      final nav = _navigator;
      if (nav == null) return;
      if (toast != null && toast.isNotEmpty) {
        onActionToast?.call(toast);
      }
      nav.push(
        uiPageRoute(
          name: AppUiRouteNames.postDetail,
          arguments: {
            'tid': post.id,
            if (post.title.isNotEmpty) 'title': post.title,
            if (post.barName.isNotEmpty) 'bar_name': post.barName,
            if (post.author.isNotEmpty) 'author': post.author,
          },
          builder: (_) => PostDetailPage(post: post),
        ),
      );
    });
  }

  void navigateToRoute(AppShellRoute route, {String? toast}) {
    runAfterNavigationPrep(() {
      final nav = _navigator;
      if (nav == null) return;
      if (toast != null && toast.isNotEmpty) {
        onActionToast?.call(toast);
      }
      switch (route) {
        case AppShellRoute.favorites:
          nav.push(
            uiPageRoute(
              name: AppUiRouteNames.favorites,
              builder: (_) => const FavoritesPage(),
            ),
          );
        case AppShellRoute.settings:
          nav.push(
            uiPageRoute(
              name: AppUiRouteNames.settings,
              builder: (_) =>
                  SettingsPage(onLoginChanged: onLoginChanged ?? () {}),
            ),
          );
        case AppShellRoute.login:
          nav.push(
            uiPageRoute(
              name: AppUiRouteNames.loginHub,
              builder: (_) => const LoginHubPage(),
            ),
          );
        case AppShellRoute.agentConfig:
          nav.push(
            uiPageRoute(
              name: AppUiRouteNames.agentConfig,
              builder: (_) => const AgentConfigPage(),
            ),
          );
      }
    });
  }

  @Deprecated('Use navigateToPost')
  void pushPost(TiebaPost post) => navigateToPost(post);

  bool maybePop() {
    final nav = _navigator;
    if (nav == null || !nav.canPop()) return false;
    nav.pop();
    return true;
  }
}
