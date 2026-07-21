import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_glass_config.dart';
import '../../theme/glass_app_bar_layout.dart';
import '../../widgets/agent_kaomoji.dart';
import '../../widgets/app_toast.dart';
import '../../utils/app_lifecycle_gate.dart';
import '../../utils/debounced_callback.dart';
import '../../services/app_shell_controller.dart';
import 'agent_companion_controller.dart';

/// 全局陪伴层：颜文字、气泡与碎碎念输入框。
class AgentCompanionOverlay extends StatelessWidget {
  const AgentCompanionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AgentCompanionScope.maybeOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }

    final top = MediaQuery.paddingOf(context).top;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.showBarCompanion) {
          return const SizedBox.shrink();
        }
        return LifecycleTickerGate(
          child: Positioned(
            top: top,
            left: 0,
            right: 0,
            child: UnconstrainedBox(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              constrainedAxis: Axis.horizontal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CompanionSlide(
                    motion: controller.layoutMotion,
                    child: _DockedCompanion(
                      controller: controller,
                      colors: context.appColors,
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

/// 顶栏颜文字水平滑动：Tab/页面切换时平滑位移，首帧对齐不闪。
class _CompanionSlide extends StatefulWidget {
  final ValueListenable<({double offsetX, bool snap})> motion;
  final Widget child;

  const _CompanionSlide({required this.motion, required this.child});

  @override
  State<_CompanionSlide> createState() => _CompanionSlideState();
}

class _CompanionSlideState extends State<_CompanionSlide>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 360);

  late final AnimationController _ctrl;
  Animation<double> _anim = const AlwaysStoppedAnimation(0);
  double _displayX = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration);
    widget.motion.addListener(_onMotion);
    final initial = widget.motion.value;
    _displayX = initial.offsetX;
  }

  @override
  void didUpdateWidget(covariant _CompanionSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.motion, widget.motion)) {
      oldWidget.motion.removeListener(_onMotion);
      widget.motion.addListener(_onMotion);
      _applyMotion(widget.motion.value, force: true);
    }
  }

  @override
  void dispose() {
    widget.motion.removeListener(_onMotion);
    _ctrl.dispose();
    super.dispose();
  }

  void _onMotion() => _applyMotion(widget.motion.value);

  void _applyMotion(({double offsetX, bool snap}) next, {bool force = false}) {
    if (!mounted) return;

    final effects = AppLifecycleGate.effectsEnabled;
    final shouldSnap = next.snap || !effects;
    if (shouldSnap || (next.offsetX - _displayX).abs() < 0.5) {
      _ctrl.stop();
      setState(() => _displayX = next.offsetX);
      return;
    }

    if (!force && _ctrl.isAnimating) {
      // 快速连切 Tab 时上一段位移未结束，直接对齐避免颜文字来回闪。
      _ctrl.stop();
      setState(() => _displayX = next.offsetX);
      return;
    }

    if ((_displayX - next.offsetX).abs() < 0.5) {
      return;
    }

    _anim = Tween<double>(
      begin: _displayX,
      end: next.offsetX,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _displayX = next.offsetX;
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final x = _ctrl.isAnimating ? _anim.value : _displayX;
          return Transform.translate(offset: Offset(x, 0), child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// 顶栏快捷输入：挂到根 [Overlay]，键盘顶起时不随 MaterialApp builder 重建，避免 IME 退字复活。
class AgentQuickChatInputOverlay extends StatefulWidget {
  const AgentQuickChatInputOverlay({super.key});

  @override
  State<AgentQuickChatInputOverlay> createState() =>
      _AgentQuickChatInputOverlayState();
}

class _AgentQuickChatInputOverlayState
    extends State<AgentQuickChatInputOverlay> {
  AgentCompanionController? _controller;
  OverlayEntry? _entry;
  bool _visible = false;
  int _session = 0;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AgentCompanionScope.maybeOf(context);
    if (identical(_controller, next)) return;
    _controller?.removeListener(_onControllerChanged);
    _controller = next;
    _controller?.addListener(_onControllerChanged);
    _syncFromController(force: true);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onControllerChanged() => _syncFromController();

  void _syncFromController({bool force = false}) {
    final c = _controller;
    if (c == null) {
      _removeOverlay();
      return;
    }

    final nextVisible = c.quickChatOpen;
    final nextSession = c.quickChatSession;
    final nextSending = c.quickChatSending;

    if (!force &&
        _visible == nextVisible &&
        _session == nextSession &&
        _sending == nextSending) {
      return;
    }

    final sessionChanged = _session != nextSession;
    _visible = nextVisible;
    _session = nextSession;
    _sending = nextSending;

    if (!_visible) {
      _removeOverlay();
      return;
    }

    if (_entry == null || sessionChanged) {
      _removeOverlay();
      _insertOverlay();
      return;
    }

    _entry!.markNeedsBuild();
  }

  void _insertOverlay() {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // navigator overlay 暂不可用（如路由切换/启动瞬间）：下一帧重试，
      // 避免“点了颜文字却没弹出输入框”。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) _insertOverlay();
      });
      return;
    }

    final controller = _controller!;
    final session = _session;

    _entry = OverlayEntry(
      maintainState: true,
      builder: (context) =>
          _QuickChatOverlayLayer(controller: controller, session: session),
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _QuickChatOverlayLayer extends StatelessWidget {
  final AgentCompanionController controller;
  final int session;

  const _QuickChatOverlayLayer({
    required this.controller,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 4;
    final mq = MediaQuery.of(context);
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: MediaQuery(
        data: mq.copyWith(viewInsets: EdgeInsets.zero),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _QuickChatInputBubble(
              key: ValueKey(session),
              controller: controller,
              sending: controller.quickChatSending,
            ),
          ),
        ),
      ),
    );
  }
}

/// 对话页全屏 overlay 会盖住全局颜文字层，因此在顶栏内联渲染一份。
class InlineBarCompanion extends StatelessWidget {
  final String? titleText;
  final TextStyle titleStyle;
  final double leadingWidth;
  final double actionsWidth;

  const InlineBarCompanion({
    super.key,
    this.titleText,
    required this.titleStyle,
    required this.leadingWidth,
    required this.actionsWidth,
  });

  @override
  Widget build(BuildContext context) {
    final controller = AgentCompanionScope.maybeOf(context);
    if (controller == null || !controller.agentChatOpen) {
      return const SizedBox.shrink();
    }

    final barWidth = MediaQuery.sizeOf(context).width;
    final offsetX = CompanionBarLayout.companionOffsetX(
      barWidth: barWidth,
      titleText: titleText,
      titleStyle: titleStyle,
      leadingWidth: leadingWidth,
      actionsWidth: actionsWidth,
    );

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LifecycleTickerGate(
          child: Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(offsetX, 0),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: kToolbarHeight,
                    child: Center(
                      child: RepaintBoundary(
                        child: LifecycleTickerGate(
                          child: AgentKaomoji(
                            mood: controller.displayMood,
                            size: 20,
                            shaking:
                                controller.displayShaking &&
                                !controller.companionWiggling,
                            wiggling: controller.companionWiggling,
                            color:
                                controller.companionForegroundColor ??
                                context.appColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 由当前可见顶栏上报布局，用于驱动全局颜文字定位动画。
class CompanionBarLayoutReporter extends StatefulWidget {
  final String? layoutKey;
  final String? titleText;
  final TextStyle titleStyle;
  final double leadingWidth;
  final double actionsWidth;
  final Color? companionColor;

  const CompanionBarLayoutReporter({
    super.key,
    this.layoutKey,
    this.titleText,
    required this.titleStyle,
    required this.leadingWidth,
    required this.actionsWidth,
    this.companionColor,
  });

  @override
  State<CompanionBarLayoutReporter> createState() =>
      _CompanionBarLayoutReporterState();
}

class _CompanionBarLayoutReporterState
    extends State<CompanionBarLayoutReporter> {
  late final DebouncedCallback _debouncedReport = DebouncedCallback(
    callback: _reportNow,
    delay: const Duration(milliseconds: 180),
  );
  AgentCompanionController? _companion;
  bool _lastAgentChatOpen = false;

  @override
  void initState() {
    super.initState();
    appRouteLifecycleObserver.addListener(_scheduleReport);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleReport();
    });
  }

  @override
  void dispose() {
    _companion?.removeListener(_onCompanionLayoutGate);
    appRouteLifecycleObserver.removeListener(_scheduleReport);
    _debouncedReport.dispose();
    super.dispose();
  }

  void _onCompanionLayoutGate() {
    final open = _companion?.agentChatOpen ?? false;
    if (_lastAgentChatOpen && !open) {
      _debouncedReport.cancel();
      _reportNow();
    }
    _lastAgentChatOpen = open;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AgentCompanionScope.maybeOf(context);
    if (_companion != next) {
      _companion?.removeListener(_onCompanionLayoutGate);
      _companion = next;
      _lastAgentChatOpen = next?.agentChatOpen ?? false;
      _companion?.addListener(_onCompanionLayoutGate);
      _scheduleReport();
    }
  }

  @override
  void didUpdateWidget(covariant CompanionBarLayoutReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layoutKey != oldWidget.layoutKey ||
        widget.titleText != oldWidget.titleText ||
        widget.leadingWidth != oldWidget.leadingWidth ||
        widget.actionsWidth != oldWidget.actionsWidth ||
        widget.companionColor != oldWidget.companionColor) {
      _scheduleReport();
    }
  }

  bool _shouldReport() {
    final controller = AgentCompanionScope.maybeOf(context);
    // 碎碎念输入中暂停布局上报，键盘顶起时 viewInsets 变化会频繁触发 rebuild。
    if (controller?.quickChatOpen == true) return false;

    // 后台思考时 Offstage 对话页不能抢可见页的颜文字定位。
    if (widget.layoutKey == 'agent-chat' && controller?.agentChatOpen != true) {
      return false;
    }

    final route = ModalRoute.of(context);
    final isCurrentRoute = route?.isCurrent == true;

    // 对话 overlay 不在 Navigator 路由树内，ModalRoute 为空；仍须上报顶栏布局。
    if (controller?.agentChatOpen == true && widget.layoutKey == 'agent-chat') {
      return route?.isCurrent ?? true;
    }

    if (!isCurrentRoute) return false;

    // 对话页上 push 的子页（如助手设置）由当前顶栏上报空白区。
    if (controller?.agentChatOpen == true && widget.layoutKey != 'agent-chat') {
      return true;
    }

    if (widget.layoutKey != null) {
      final scope = CompanionLayoutScope.maybeOf(context);
      if (scope != null) {
        if (scope.activeLayoutKey == widget.layoutKey) return true;
        // push 出的全屏页不在 Tab active key 内，仍是当前路由即可上报。
        return isCurrentRoute;
      }
      return true;
    }
    return true;
  }

  void _scheduleReport() {
    if (!_shouldReport()) return;
    _debouncedReport();
  }

  void _reportNow() {
    if (!mounted || !_shouldReport()) return;
    final controller = AgentCompanionScope.maybeOf(context);
    if (controller == null || controller.quickChatOpen) return;
    final width = MediaQuery.sizeOf(context).width;
    controller.reportBarLayout(
      layoutKey: widget.layoutKey ?? 'route:${context.widget.runtimeType}',
      titleText: widget.titleText,
      titleStyle: widget.titleStyle,
      barWidth: width,
      leadingWidth: widget.leadingWidth,
      actionsWidth: widget.actionsWidth,
      companionColor: widget.companionColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _DockedCompanion extends StatelessWidget {
  final AgentCompanionController controller;
  final AppColorScheme colors;

  const _DockedCompanion({required this.controller, required this.colors});

  static ({Color background, Color text, Color border}) _speechBubbleStyle(
    AppColorScheme colors,
    bool isDark,
  ) {
    if (isDark) {
      return (
        background: colors.primaryLight,
        text: colors.textPrimary,
        border: colors.border,
      );
    }
    return (
      background: colors.surfaceMuted,
      text: colors.textPrimary,
      border: colors.borderLight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleStyle = _speechBubbleStyle(colors, isDark);

    Widget? speech;
    if (!controller.agentChatOpen && !controller.quickChatOpen) {
      if (controller.toastMessage != null && controller.toastType != null) {
        speech = _AnimatedCompanionBubble(
          key: const ValueKey('companion-toast'),
          text: controller.toastMessage!,
          dismissing: controller.toastDismissing,
          backgroundColor: AppToastStyle.backgroundColor(
            controller.toastType!,
            colors,
            isDark,
          ),
          textColor: AppToastStyle.textColor(isDark, colors),
          borderRadius: BorderRadius.circular(14),
          maxWidth: 260,
        );
      } else if (controller.quickReply != null) {
        speech = _AnimatedCompanionBubble(
          key: const ValueKey('companion-quick-reply'),
          text: controller.quickReply!,
          dismissing: controller.quickReplyDismissing,
          backgroundColor: bubbleStyle.background,
          textColor: bubbleStyle.text,
          borderRadius: AppDecorations.borderRadiusPill,
          maxWidth: 280,
          maxLines: 4,
          border: Border.all(color: bubbleStyle.border, width: 0.5),
        );
      }
    }

    return Material(
      color: Colors.transparent,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: controller.agentChatOpen
                      ? null
                      : controller.toggleQuickChat,
                  borderRadius: BorderRadius.circular(20),
                  // 命中区撑满整个顶栏高度，并左右留足宽度，避免小颜文字难点到。
                  child: SizedBox(
                    height: kToolbarHeight,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 0,
                          ),
                          child: RepaintBoundary(
                            child: LifecycleTickerGate(
                              child: AgentKaomoji(
                                mood: controller.displayMood,
                                size: 20,
                                shaking:
                                    controller.displayShaking &&
                                    !controller.companionWiggling,
                                wiggling: controller.companionWiggling,
                                color:
                                    controller.companionForegroundColor ??
                                    colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (speech != null) ...[
              const SizedBox(height: 2),
              IgnorePointer(child: speech),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickChatInputBubble extends StatefulWidget {
  final AgentCompanionController controller;
  final bool sending;

  const _QuickChatInputBubble({
    super.key,
    required this.controller,
    required this.sending,
  });

  @override
  State<_QuickChatInputBubble> createState() => _QuickChatInputBubbleState();
}

class _QuickChatInputBubbleState extends State<_QuickChatInputBubble> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  static const _actionSize = 34.0;
  static const _panelRadius = 22.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || widget.sending) return;
    _inputCtrl.clear();
    await widget.controller.sendQuickMessage(text);
  }

  void _dismiss() {
    if (widget.sending) return;
    widget.controller.toggleQuickChat();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = context.glassConfig;
    final sending = widget.sending;
    final maxWidth = math.min(MediaQuery.sizeOf(context).width - 40, 300.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: AppDecorations.glassShadow(colors),
          color: colors.card.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(_panelRadius),
          border: Border.all(
            color: colors.glassBorder,
            width: config.borderWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _QuickChatIconButton(
                icon: Icons.close_rounded,
                colors: colors,
                size: _actionSize,
                onTap: sending ? null : _dismiss,
                tooltip: '关闭',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _QuickChatEditor(
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  enabled: !sending,
                  textColor: colors.textPrimary,
                  hintColor: colors.textMuted,
                  onSend: _send,
                ),
              ),
              const SizedBox(width: 4),
              _QuickChatSendButton(
                controller: _inputCtrl,
                sending: sending,
                colors: colors,
                size: _actionSize,
                onSend: _send,
                onStop: widget.controller.cancelQuickMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入框独立挂载，避免与发送按钮共用 rebuild 路径。
class _QuickChatEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final Color textColor;
  final Color hintColor;
  final VoidCallback onSend;

  const _QuickChatEditor({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.textColor,
    required this.hintColor,
    required this.onSend,
  });

  @override
  State<_QuickChatEditor> createState() => _QuickChatEditorState();
}

class _QuickChatEditorState extends State<_QuickChatEditor> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      minLines: 1,
      maxLines: 4,
      textAlignVertical: TextAlignVertical.center,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => widget.onSend(),
      style: AppFonts.body(
        color: widget.textColor,
      ).copyWith(fontSize: 14, height: 1.35),
      decoration: InputDecoration(
        hintText: '问点什么…',
        hintStyle: AppFonts.body(
          color: widget.hintColor,
        ).copyWith(fontSize: 14, height: 1.35),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
    );
  }
}

class _QuickChatSendButton extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final AppColorScheme colors;
  final double size;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _QuickChatSendButton({
    required this.controller,
    required this.sending,
    required this.colors,
    required this.size,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canSend = controller.text.trim().isNotEmpty && !sending;
        if (sending) {
          return _QuickChatIconButton(
            icon: Icons.stop_rounded,
            colors: colors,
            size: size,
            filled: true,
            enabled: true,
            onTap: onStop,
            tooltip: '停止',
          );
        }
        return _QuickChatIconButton(
          icon: Icons.arrow_upward_rounded,
          colors: colors,
          size: size,
          filled: true,
          enabled: canSend,
          onTap: canSend ? onSend : null,
          tooltip: '发送',
        );
      },
    );
  }
}

class _QuickChatIconButton extends StatelessWidget {
  final IconData icon;
  final AppColorScheme colors;
  final double size;
  final VoidCallback? onTap;
  final bool filled;
  final bool loading = false;
  final bool enabled;
  final String? tooltip;

  const _QuickChatIconButton({
    required this.icon,
    required this.colors,
    required this.size,
    this.onTap,
    this.filled = false,
    this.enabled = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = enabled && onTap != null;

    late final Color bg;
    late final Color fg;
    Border? border;

    if (filled) {
      if (loading || active) {
        bg = colors.primary;
        fg = isDark ? colors.scaffold : Colors.white;
      } else {
        bg = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD4D7DC);
        fg = colors.textMuted;
      }
    } else {
      bg = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFECEEF1);
      fg = colors.textSecondary;
      border = Border.all(
        color: isDark ? colors.border : colors.borderLight,
        width: 1,
      );
    }

    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Icon(icon, size: 18, color: fg),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _AnimatedCompanionBubble extends StatefulWidget {
  final String text;
  final bool dismissing;
  final Color backgroundColor;
  final Color textColor;
  final BorderRadius borderRadius;
  final double maxWidth;
  final int maxLines;
  final BoxBorder? border;

  const _AnimatedCompanionBubble({
    super.key,
    required this.text,
    required this.dismissing,
    required this.backgroundColor,
    required this.textColor,
    required this.borderRadius,
    required this.maxWidth,
    this.maxLines = 4,
    this.border,
  });

  @override
  State<_AnimatedCompanionBubble> createState() =>
      _AnimatedCompanionBubbleState();
}

class _AnimatedCompanionBubbleState extends State<_AnimatedCompanionBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _slide = Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCompanionBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dismissing && !oldWidget.dismissing) {
      _controller.reverse();
    } else if (!widget.dismissing && widget.text != oldWidget.text) {
      _controller.forward(from: 0.85);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(_scale),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: widget.borderRadius,
                border: widget.border,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Text(
                    widget.text,
                    key: ValueKey(widget.text),
                    style: AppFonts.body(color: widget.textColor).copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    maxLines: widget.maxLines,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
