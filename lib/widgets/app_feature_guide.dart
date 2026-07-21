import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_guide_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_fonts.dart';
import '../theme/app_glass.dart';
import '../theme/glass_app_bar_layout.dart';
import '../widgets/agent_kaomoji.dart';
import '../utils/agent_kaomoji_mood.dart';
import '../widgets/agent_ripple_overlay.dart';

/// 场景化浮窗引导（箭头指向目标 + 示意动画）。
class AppFeatureGuide {
  AppFeatureGuide._();

  /// 主界面：音量键 → 颜文字，按顺序展示。
  static Future<void> showMainGuidesIfNeeded(BuildContext context) async {
    if (!context.mounted) return;
    if (!await AppGuideService.hasSeenVolumeGuide()) {
      if (!context.mounted) return;
      await _showOverlay(
        context,
        builder: (_) => const _VolumeKeyGuideOverlay(),
      );
      await AppGuideService.markVolumeGuideSeen();
    }
    if (!context.mounted) return;
    if (!await AppGuideService.hasSeenKaomojiGuide()) {
      if (!context.mounted) return;
      await _showOverlay(context, builder: (_) => const _KaomojiGuideOverlay());
      await AppGuideService.markKaomojiGuideSeen();
    }
    if (!context.mounted) return;
    if (!await AppGuideService.hasSeenShakeGuide()) {
      if (!context.mounted) return;
      await _showOverlay(context, builder: (_) => const _ShakeGuideOverlay());
      await AppGuideService.markShakeGuideSeen();
    }
  }

  /// 阅读页：左右滑切换帖子（仅多帖上下文）。
  static Future<void> showPostSwipeGuideIfNeeded(
    BuildContext context, {
    required bool enabled,
  }) async {
    if (!enabled || !context.mounted) return;
    if (await AppGuideService.hasSeenPostSwipeGuide()) return;
    if (!context.mounted) return;
    await _showOverlay(context, builder: (_) => const _PostSwipeGuideOverlay());
    await AppGuideService.markPostSwipeGuideSeen();
  }

  static Future<void> _showOverlay(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭引导',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: builder(context),
        );
      },
    );
  }
}

class _GuideBubble extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback? onDismiss;

  const _GuideBubble({
    required this.title,
    required this.description,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppFonts.title(color: colors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            description,
            style: AppFonts.bodySmall(color: colors.textSecondary),
          ),
          if (onDismiss != null) ...[
            const SizedBox(height: 14),
            _GuideDismissButton(onDismiss: onDismiss!),
          ],
        ],
      ),
    );
  }
}

class _GuideDismissButton extends StatelessWidget {
  final VoidCallback onDismiss;

  const _GuideDismissButton({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(
        onPressed: onDismiss,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('知道了'),
      ),
    );
  }
}

/// 音量减键引导：箭头指向屏幕右侧音量键位置。
class _VolumeKeyGuideOverlay extends StatelessWidget {
  const _VolumeKeyGuideOverlay();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = context.appColors;
    final target = AgentRippleOverlay.volumeKeyOrigin(size);
    final targetY = target.dy;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: targetY - 34,
            child: _VolumeKeyTargetBadge(colors: colors),
          ),
          Positioned(
            left: 20,
            right: 72,
            top: math.max(96.0, targetY - 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _GuideBubble(
                  title: '音量减键打开 AI 对话',
                  description: '按下手机侧边的音量 −，随时展开助手对话；再按一次可关闭。',
                  onDismiss: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: CustomPaint(
                    size: const Size(120, 36),
                    painter: _CurvedArrowPainter(
                      color: colors.primary,
                      pointsRight: true,
                    ),
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

class _VolumeKeyTargetBadge extends StatelessWidget {
  final AppColorScheme colors;

  const _VolumeKeyTargetBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 68,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        border: Border.all(color: colors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.remove_rounded, color: colors.primary, size: 22),
          const SizedBox(height: 14),
          Icon(Icons.add_rounded, color: colors.textMuted, size: 18),
        ],
      ),
    );
  }
}

/// 颜文字引导：高亮圈指向顶栏颜文字（不重复绘制表情）。
class _KaomojiGuideOverlay extends StatelessWidget {
  const _KaomojiGuideOverlay();

  double _kaomojiCenterX(BuildContext context) {
    final barWidth = MediaQuery.sizeOf(context).width;
    final layout = GlassAppBarLayout.maybeOf(context);
    if (layout == null) return barWidth / 2;
    return CompanionBarLayout.blankSpaceCenterX(
      barWidth: barWidth,
      titleText: layout.titleText,
      titleStyle: layout.titleStyle,
      leadingWidth: layout.leadingWidth,
      actionsWidth: layout.actionsWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final top = MediaQuery.paddingOf(context).top;
    final kaomojiY = top + kToolbarHeight * 0.5;
    final centerX = _kaomojiCenterX(context);
    const highlightSize = 48.0;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            left: centerX - highlightSize / 2,
            top: kaomojiY - highlightSize / 2,
            child: _KaomojiTargetHighlight(
              size: highlightSize,
              color: colors.primary,
            ),
          ),
          Positioned(
            top: kaomojiY + highlightSize / 2 + 6,
            left: 24,
            right: 24,
            child: Column(
              children: [
                CustomPaint(
                  size: const Size(48, 28),
                  painter: _CurvedArrowPainter(
                    color: colors.primary,
                    pointsRight: false,
                    pointsUp: true,
                  ),
                ),
                const SizedBox(height: 4),
                _GuideBubble(
                  title: '点击颜文字快捷对话',
                  description:
                      '点击顶部导航栏的颜文字，或摇一摇手机，'
                      '展开输入框快速提问，不必先打开全屏对话。',
                  onDismiss: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏颜文字高亮圈：只圈住已有颜文字，避免叠两层表情。
class _KaomojiTargetHighlight extends StatefulWidget {
  final double size;
  final Color color;

  const _KaomojiTargetHighlight({required this.size, required this.color});

  @override
  State<_KaomojiTargetHighlight> createState() =>
      _KaomojiTargetHighlightState();
}

class _KaomojiTargetHighlightState extends State<_KaomojiTargetHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = 0.22 + _pulse.value * 0.18;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(
                  alpha: 0.85 + _pulse.value * 0.1,
                ),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: glow),
                  blurRadius: 14 + _pulse.value * 6,
                  spreadRadius: 1 + _pulse.value * 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 摇一摇引导：示意手机晃动 + 颜文字左右摆。
class _ShakeGuideOverlay extends StatefulWidget {
  const _ShakeGuideOverlay();

  @override
  State<_ShakeGuideOverlay> createState() => _ShakeGuideOverlayState();
}

class _ShakeGuideOverlayState extends State<_ShakeGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _tilt;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _tilt = Tween<double>(
      begin: -0.14,
      end: 0.14,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                height: 210,
                child: AnimatedBuilder(
                  animation: _tilt,
                  builder: (context, _) {
                    return Transform.rotate(
                      angle: _tilt.value,
                      alignment: Alignment.center,
                      child: _ShakeGuidePhoneDemo(colors: colors),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _GuideBubble(
                title: '摇一摇打开 AI 快捷输入',
                description:
                    '在主界面摇动手机，颜文字会先左右晃动，'
                    '随后自动展开快捷输入框并弹出键盘，可直接提问。',
                onDismiss: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShakeGuidePhoneDemo extends StatelessWidget {
  final AppColorScheme colors;

  const _ShakeGuidePhoneDemo({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 196,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.borderLight, width: 1.2),
        boxShadow: AppDecorations.softShadow(colors, blur: 12),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 5,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 18),
          const AgentKaomoji(
            mood: AgentKaomojiMood.happy,
            size: 24,
            wiggling: true,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: AppDecorations.borderRadiusMd,
              border: Border.all(color: colors.borderLight),
            ),
            child: Text(
              '想问什么…',
              style: AppFonts.caption(color: colors.textMuted),
            ),
          ),
          const Spacer(),
          Icon(Icons.vibration_rounded, color: colors.primary, size: 22),
        ],
      ),
    );
  }
}

/// 阅读页左右滑引导。
class _PostSwipeGuideOverlay extends StatefulWidget {
  const _PostSwipeGuideOverlay();

  @override
  State<_PostSwipeGuideOverlay> createState() => _PostSwipeGuideOverlayState();
}

class _PostSwipeGuideOverlayState extends State<_PostSwipeGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _slide = Tween<double>(
      begin: -28,
      end: 28,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                height: 150,
                child: AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          left: 12,
                          child: Icon(
                            Icons.chevron_left_rounded,
                            color: colors.primary.withValues(alpha: 0.7),
                            size: 30,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: colors.primary.withValues(alpha: 0.7),
                            size: 30,
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(_slide.value, 0),
                          child: _DemoPostCard(colors: colors),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _GuideBubble(
                title: '左右滑动切换帖子',
                description: '在阅读页横向滑动，即可切换到上一篇或下一篇帖子。',
                onDismiss: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoPostCard extends StatelessWidget {
  final AppColorScheme colors;

  const _DemoPostCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppDecorations.borderRadiusLg,
        border: Border.all(color: colors.borderLight),
        boxShadow: AppDecorations.softShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 8,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.35),
              borderRadius: AppDecorations.borderRadiusSm,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 8,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: AppDecorations.borderRadiusSm,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 140,
            height: 8,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: AppDecorations.borderRadiusSm,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvedArrowPainter extends CustomPainter {
  final Color color;
  final bool pointsRight;
  final bool pointsUp;

  const _CurvedArrowPainter({
    required this.color,
    this.pointsRight = true,
    this.pointsUp = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    late Path path;
    if (pointsUp) {
      path = Path()
        ..moveTo(size.width * 0.5, size.height)
        ..quadraticBezierTo(
          size.width * 0.5,
          size.height * 0.35,
          size.width * 0.5,
          4,
        );
      canvas.drawPath(path, paint);
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.5, 4)
          ..lineTo(size.width * 0.5 - 7, 14)
          ..moveTo(size.width * 0.5, 4)
          ..lineTo(size.width * 0.5 + 7, 14),
        paint,
      );
      return;
    }

    path = Path()
      ..moveTo(4, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.2,
        size.width - 6,
        size.height * 0.45,
      );
    canvas.drawPath(path, paint);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 6, size.height * 0.45)
        ..lineTo(size.width - 18, size.height * 0.45 - 8)
        ..moveTo(size.width - 6, size.height * 0.45)
        ..lineTo(size.width - 18, size.height * 0.45 + 8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvedArrowPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.pointsRight != pointsRight ||
        oldDelegate.pointsUp != pointsUp;
  }
}
