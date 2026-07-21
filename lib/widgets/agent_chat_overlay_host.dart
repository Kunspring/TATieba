import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../screens/agent_chat_page.dart';
import '../screens/agent_config_page.dart';
import '../services/app_shell_controller.dart';
import '../services/app_theme_service.dart';
import '../services/app_ui_context.dart';
import '../services/volume_key_service.dart';
import '../theme/app_colors.dart';
import 'agent_companion/agent_companion_controller.dart';
import 'agent_ripple_overlay.dart';

/// 持久 Overlay 承载对话页：开/关只做转场，不 push/pop 重建页面。
class AgentChatOverlayHost extends StatefulWidget {
  const AgentChatOverlayHost({super.key});

  @override
  State<AgentChatOverlayHost> createState() => _AgentChatOverlayHostState();
}

class _AgentChatOverlayHostState extends State<AgentChatOverlayHost>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _openDuration = Duration(milliseconds: 720);
  static const _closeDuration = Duration(milliseconds: 480);

  bool _linked = false;
  bool _open = false;
  AgentCompanionController? _companion;
  StreamSubscription<void>? _volumeSub;

  late final AnimationController _transition;
  late final CurvedAnimation _openProgress;
  OverlayEntry? _overlayEntry;
  final _chatKey = GlobalKey();
  final _chatNavKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transition = AnimationController(
      vsync: this,
      duration: _openDuration,
      reverseDuration: _closeDuration,
    );
    _openProgress = CurvedAnimation(
      parent: _transition,
      curve: AgentRippleOverlay.expandCurve,
      reverseCurve: AgentRippleOverlay.collapseCurve,
    );
    _transition.addListener(_rebuildOverlay);
    _transition.addStatusListener(_onTransitionStatus);

    _volumeSub = VolumeKeyService.volumeDownStream.listen((_) {
      if (!VolumeKeyService.consumeVolumeDownEvent()) return;
      _toggleOverlay();
    });
    if (!kIsWeb) {
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
    }
    appRouteLifecycleObserver.addListener(_onNavigatorChanged);
    AppThemeService.instance.addListener(_onThemeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _linkShellCallbacks();
      _ensureOverlay();
      SchedulerBinding.instance.scheduleTask(_prewarmChatPage, Priority.idle);
    });
  }

  Future<void> _prewarmChatPage() async {
    if (!mounted) return;
    _ensureOverlay();
    _rebuildOverlay();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    AgentCompanionScope.maybeOf(context)?.onAgentOverlayWillOpen?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_open) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    _transition.removeListener(_rebuildOverlay);
    _transition.removeStatusListener(_onTransitionStatus);
    _openProgress.dispose();
    _transition.dispose();
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    AppThemeService.instance.removeListener(_onThemeChanged);
    appRouteLifecycleObserver.removeListener(_onNavigatorChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    }
    _volumeSub?.cancel();
    _unlinkShellCallbacks();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_open) return false;
    return _handleAgentChatBack();
  }

  bool _handleAgentChatBack() {
    if (!_open && !_transition.isAnimating) return false;
    final nav = _chatNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    _closeOverlay();
    return true;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!VolumeKeyService.handleVolumeDownKey(event)) return false;
    if (!VolumeKeyService.consumeVolumeDownEvent()) return true;
    _toggleOverlay();
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _linkShellCallbacks();
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && _open) {
      AgentCompanionScope.maybeOf(context)?.onAgentOverlayOpened?.call();
    } else if (status == AnimationStatus.dismissed && !_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _releaseStuckCompanionFlags();
      });
    }
  }

  void _rebuildOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _ensureOverlay() {
    if (_overlayEntry != null) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureOverlay());
      return;
    }

    _overlayEntry = OverlayEntry(builder: (context) => _buildOverlay(context));
    overlay.insert(_overlayEntry!);
  }

  Widget _buildOverlay(BuildContext context) {
    final progress = _openProgress.value;
    final interceptTouches = _open || _transition.isAnimating;
    final chatShell = ColoredBox(
      color: context.appColors.scaffold,
      child: Navigator(
        key: _chatNavKey,
        onGenerateRoute: (settings) {
          if (settings.name == AppUiRouteNames.agentConfig) {
            return uiPageRoute<bool>(
              name: AppUiRouteNames.agentConfig,
              builder: (_) => const AgentConfigPage(),
            );
          }
          return MaterialPageRoute<void>(
            settings: const RouteSettings(
              name: AppUiRouteNames.agentChatOverlay,
            ),
            builder: (_) => AgentChatPage(key: _chatKey),
          );
        },
      ),
    );

    if (!interceptTouches) {
      return AgentRippleOverlay(progress: 0, child: chatShell);
    }

    final visualProgress = progress <= 0 ? 0.001 : progress;
    if (_transition.status == AnimationStatus.completed && progress >= 0.99) {
      return chatShell;
    }

    return AgentRippleOverlay(progress: visualProgress, child: chatShell);
  }

  void _linkShellCallbacks() {
    if (!mounted) return;
    final companion = AgentCompanionScope.maybeOf(context);
    if (companion == null) return;
    _companion = companion;
    companion.onNavigateToChat = _openOverlay;
    final shell = AppShellController.instance;
    shell.onOpenAgentChat = _openOverlay;
    shell.onCloseAgentChat = _closeOverlay;
    shell.handleAgentChatBack = _handleAgentChatBack;
    shell.onDismissChatForNavigation = _forceCloseOverlay;
    shell.onDismissChatForNavigationInstant = _forceCloseOverlayInstant;
    shell.isAgentChatOpen = () => _open;
    companion.onReleaseNavigationBlockers = _releaseStuckCompanionFlags;
    _linked = true;
  }

  void _unlinkShellCallbacks() {
    final companion = _companion;
    if (companion?.onNavigateToChat == _openOverlay) {
      companion?.onNavigateToChat = null;
    }
    final shell = AppShellController.instance;
    if (shell.onOpenAgentChat == _openOverlay) {
      shell.onOpenAgentChat = null;
    }
    if (shell.onCloseAgentChat == _closeOverlay) {
      shell.onCloseAgentChat = null;
    }
    if (shell.handleAgentChatBack == _handleAgentChatBack) {
      shell.handleAgentChatBack = null;
    }
    if (shell.onDismissChatForNavigation == _forceCloseOverlay) {
      shell.onDismissChatForNavigation = null;
    }
    if (shell.onDismissChatForNavigationInstant == _forceCloseOverlayInstant) {
      shell.onDismissChatForNavigationInstant = null;
    }
    if (shell.isAgentChatOpen != null) {
      shell.isAgentChatOpen = null;
    }
    if (companion?.onReleaseNavigationBlockers == _releaseStuckCompanionFlags) {
      companion?.onReleaseNavigationBlockers = null;
    }
    _linked = false;
  }

  void _onThemeChanged() {
    if (!mounted) return;
    if (_open) return;
    _releaseStuckCompanionFlags();
  }

  void _onNavigatorChanged() {
    if (!mounted || _open) return;
    _releaseStuckCompanionFlags();
  }

  void _releaseStuckCompanionFlags() {
    if (!mounted || _open) return;
    final companion = AgentCompanionScope.maybeOf(context);
    if (companion == null) return;
    if (companion.agentChatOpen) {
      companion.updateContext(
        tabIndex: companion.tabIndex,
        selectedBar: companion.selectedBar,
        agentChatOpen: false,
      );
    }
  }

  void _syncCompanionChatOpen(bool open) {
    if (!mounted || !_linked) return;
    final companion = AgentCompanionScope.maybeOf(context);
    if (companion == null) return;
    companion.updateContext(
      tabIndex: companion.tabIndex,
      selectedBar: companion.selectedBar,
      agentChatOpen: open,
    );
    AppUiContextService.instance.updateShell(
      tabIndex: companion.tabIndex,
      selectedBar: companion.selectedBar,
      agentChatOpen: open,
      quickChatOpen: companion.quickChatOpen,
    );
  }

  void _openOverlay() {
    if (_open) return;
    _ensureOverlay();
    _open = true;
    _syncCompanionChatOpen(true);
    _runOpenTransition();
  }

  void _runOpenTransition() {
    if (!mounted || !_open) return;
    if (_overlayEntry == null) {
      _ensureOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) => _runOpenTransition());
      return;
    }
    _rebuildOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) return;
      AgentCompanionScope.maybeOf(context)?.onAgentOverlayWillOpen?.call();
    });
    _transition.forward(from: 0);
  }

  void _closeOverlay() {
    if (!_open && !_transition.isAnimating) return;
    _open = false;
    FocusManager.instance.primaryFocus?.unfocus();
    _chatNavKey.currentState?.popUntil((route) => route.isFirst);
    _syncCompanionChatOpen(false);
    if (_transition.status == AnimationStatus.completed) {
      _transition.reverse();
    } else {
      _transition.reverse(from: _transition.value);
    }
  }

  void _forceCloseOverlay() {
    if (!_open && !_transition.isAnimating) {
      _releaseStuckCompanionFlags();
      return;
    }
    _open = false;
    FocusManager.instance.primaryFocus?.unfocus();
    _chatNavKey.currentState?.popUntil((route) => route.isFirst);
    _syncCompanionChatOpen(false);
    _transition.reverse(from: _transition.value);
  }

  void _forceCloseOverlayInstant() {
    if (!_open && _transition.value <= 0) {
      _releaseStuckCompanionFlags();
      return;
    }
    _open = false;
    FocusManager.instance.primaryFocus?.unfocus();
    _chatNavKey.currentState?.popUntil((route) => route.isFirst);
    _syncCompanionChatOpen(false);
    _transition.value = 0;
    _rebuildOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _releaseStuckCompanionFlags();
    });
  }

  void _toggleOverlay() {
    if (_open) {
      _closeOverlay();
    } else {
      _openOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
