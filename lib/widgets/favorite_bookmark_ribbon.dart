import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 收藏书签配色：与吧内等级黄牌一致的描边半透明样式。
abstract final class FavoriteBookmarkColors {
  FavoriteBookmarkColors._();

  /// 黄牌 accent，同 [ForumLevelStyle] Lv.10–12。
  static const accent = Color(0xFFFFA014);
  static const fillAlpha = 0.18;
  static const strokeAlpha = 0.55;
  static const strokeWidth = 0.6;
}

/// 阅读页下拉/钉住书签的尺寸与边距。
abstract final class FavoriteBookmarkLayout {
  FavoriteBookmarkLayout._();

  static const edgeInset = 16.0;
  static const pinWidth = 24.0;
  static const pinHeight = 40.0;
}

/// 阅读器书签：顶平悬挂，底边两角下垂，中间 V 形缺口朝内。
class FavoriteBookmarkGlyph extends StatelessWidget {
  final double width;
  final double height;

  const FavoriteBookmarkGlyph({
    super.key,
    this.width = FavoriteBookmarkLayout.pinWidth,
    this.height = FavoriteBookmarkLayout.pinHeight,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: const _FavoriteBookmarkPainter(),
    );
  }
}

class _FavoriteBookmarkPainter extends CustomPainter {
  const _FavoriteBookmarkPainter();

  Path _ribbonPath(double w, double h) {
    final notch = math.min(w * 0.34, h * 0.26);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.5, h - notch)
      ..lineTo(0, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final path = _ribbonPath(w, h);

    canvas.drawPath(
      path,
      Paint()
        ..color = FavoriteBookmarkColors.accent.withValues(
          alpha: FavoriteBookmarkColors.fillAlpha,
        ),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = FavoriteBookmarkColors.accent.withValues(
          alpha: FavoriteBookmarkColors.strokeAlpha,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = FavoriteBookmarkColors.strokeWidth
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(covariant _FavoriteBookmarkPainter oldDelegate) => false;
}

/// 下拉过程中的书签指示（无背景条、无文字）。
class PullFavoriteBookmarkIndicator extends StatelessWidget {
  final double progress;

  const PullFavoriteBookmarkIndicator({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.02) return const SizedBox.shrink();

    final eased = Curves.easeOutCubic.transform(p);
    final height = FavoriteBookmarkLayout.pinHeight * (0.12 + eased * 0.88);
    const width = FavoriteBookmarkLayout.pinWidth;

    return SizedBox(
      width: width,
      height: height,
      child: Opacity(
        opacity: eased,
        child: FavoriteBookmarkGlyph(width: width, height: height),
      ),
    );
  }
}

/// 收藏成功后钉在内容区右上角的黄色书签（与下拉指示同一位置）。
class PinnedFavoriteBookmark extends StatefulWidget {
  final bool visible;
  final int entranceTrigger;
  final bool instant;

  const PinnedFavoriteBookmark({
    super.key,
    required this.visible,
    this.entranceTrigger = 0,
    this.instant = false,
  });

  @override
  State<PinnedFavoriteBookmark> createState() => _PinnedFavoriteBookmarkState();
}

class _PinnedFavoriteBookmarkState extends State<PinnedFavoriteBookmark>
    with SingleTickerProviderStateMixin {
  static const _slideMs = 280;

  late final AnimationController _ctrl;
  late Animation<double> _slide;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _slideMs),
    );
    _slide = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _shown = widget.visible;
    if (_shown) _ctrl.value = 1;
  }

  void _show({required bool animate}) {
    _shown = true;
    if (animate) {
      _ctrl.forward(from: 0);
    } else {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant PinnedFavoriteBookmark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _show(animate: !widget.instant);
    } else if (!widget.visible && oldWidget.visible) {
      _ctrl.reverse().whenComplete(() {
        if (mounted) setState(() => _shown = false);
      });
    } else if (widget.visible &&
        widget.entranceTrigger != oldWidget.entranceTrigger) {
      _show(animate: !widget.instant);
    } else if (widget.visible && widget.instant && !oldWidget.instant) {
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown && !widget.visible) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) {
          final t = _slide.value;
          return Transform.translate(
            offset: Offset(0, -FavoriteBookmarkLayout.pinHeight * (1 - t)),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          );
        },
        child: const FavoriteBookmarkGlyph(),
      ),
    );
  }
}
