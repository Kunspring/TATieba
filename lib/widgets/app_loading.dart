import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../utils/app_lifecycle_gate.dart';
import 'kaomoji_loader.dart';

class AppLoading extends StatelessWidget {
  final double size;
  final String? message;

  const AppLoading({super.key, this.size = 40, this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KaomojiLoader(size: size, color: colors.textPrimary),
        if (message != null) ...[
          const SizedBox(height: 14),
          Text(
            message!,
            style: AppFonts.body(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// 保持 [KaomojiLoader] 实例不被销毁，避免加载动画循环重置。
class PersistentAppLoading extends StatefulWidget {
  final double size;
  final String? message;

  const PersistentAppLoading({super.key, this.size = 44, this.message});

  @override
  State<PersistentAppLoading> createState() => _PersistentAppLoadingState();
}

class _PersistentAppLoadingState extends State<PersistentAppLoading>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppLoading(size: widget.size, message: widget.message);
  }
}

class AppLoadingPage extends StatelessWidget {
  final String? message;
  final bool fill;

  const AppLoadingPage({super.key, this.message, this.fill = true});

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: PersistentAppLoading(size: 44, message: message ?? '加载中…'),
    );
    if (!fill) return content;
    return ColoredBox(
      color: Colors.transparent,
      child: SizedBox.expand(child: content),
    );
  }
}

/// 加载与内容交叉淡入淡出；底层 loader 常驻，动画不中断。
class LoadingFadeView extends StatefulWidget {
  final bool loading;
  final Widget child;
  final Widget? loadingWidget;
  final String? message;
  final Duration duration;

  final bool blockInteraction;

  const LoadingFadeView({
    super.key,
    required this.loading,
    required this.child,
    this.loadingWidget,
    this.message,
    this.duration = const Duration(milliseconds: 260),
    this.blockInteraction = true,
  });

  @override
  State<LoadingFadeView> createState() => _LoadingFadeViewState();
}

class _LoadingFadeViewState extends State<LoadingFadeView> {
  bool _contentMounted = false;

  @override
  void initState() {
    super.initState();
    _contentMounted = !widget.loading;
  }

  @override
  void didUpdateWidget(covariant LoadingFadeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.loading) {
      _contentMounted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loader = RepaintBoundary(
      child:
          widget.loadingWidget ??
          PersistentAppLoading(
            key: const ValueKey('loading-fade-default'),
            size: 44,
            message: widget.message ?? '加载中…',
          ),
    );

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (_contentMounted)
          IgnorePointer(
            ignoring: widget.loading && widget.blockInteraction,
            child: AnimatedOpacity(
              opacity: widget.loading ? 0 : 1,
              duration: widget.duration,
              curve: Curves.easeOutCubic,
              child: widget.child,
            ),
          ),
        IgnorePointer(
          ignoring: !widget.loading,
          child: AnimatedOpacity(
            opacity: widget.loading ? 1 : 0,
            duration: widget.duration,
            curve: Curves.easeInCubic,
            child: Center(child: loader),
          ),
        ),
      ],
    );
  }
}

/// 列表底部加载指示器：保持动画实例不销毁，避免分页时动画重置。
class LoadMoreFooter extends StatelessWidget {
  final bool loading;
  final bool active;
  final double size;

  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.active,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: AnimatedOpacity(
          opacity: loading ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !loading,
            child: KaomojiLoader(
              key: const ValueKey('load-more-kaomoji'),
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}

/// 内容首次挂载时的淡入 + 轻微上滑，避免整段回复突然出现。
class ContentReveal extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback? onComplete;

  const ContentReveal({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.onComplete,
  });

  @override
  State<ContentReveal> createState() => _ContentRevealState();
}

class _ContentRevealState extends State<ContentReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _fade;
  Animation<Offset>? _slide;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppLifecycleGate.effectsEnabled) {
      _controller?.value = 1.0;
    } else if (_controller == null) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    if (_controller != null) return;
    final effects = AppLifecycleGate.effectsEnabled;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic),
        );
    if (effects) {
      _controller!.forward().whenComplete(() => widget.onComplete?.call());
    } else {
      _controller!.value = 1.0;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = _fade;
    final slide = _slide;
    if (fade == null || slide == null) return widget.child;
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: widget.child),
    );
  }
}
