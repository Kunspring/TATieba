import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 从音量键侧（屏幕右缘）展开的圆形波纹，揭示 [child]。
class AgentRippleOverlay extends StatelessWidget {
  /// 展开：匀速收尾，避免 easeOutCirc 开头过快。
  static const Curve expandCurve = Curves.easeOutCubic;

  /// 收起：先慢后快，与展开对称。
  static const Curve collapseCurve = Curves.easeInCirc;

  final double progress;
  final Widget child;

  const AgentRippleOverlay({
    super.key,
    required this.progress,
    required this.child,
  });

  static Offset volumeKeyOrigin(Size size) {
    return Offset(size.width + 6, size.height * 0.42);
  }

  static double maxRadius(Size size, Offset origin) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    var maxDist = 0.0;
    for (final corner in corners) {
      maxDist = math.max(maxDist, (corner - origin).distance);
    }
    return maxDist + 48;
  }

  @override
  Widget build(BuildContext context) {
    // progress==0 时仍挂载 child，确保对话页注册回调并在首帧完成 bootstrap。
    if (progress <= 0) {
      return Offstage(offstage: true, child: SizedBox.expand(child: child));
    }

    final size = MediaQuery.sizeOf(context);
    final origin = volumeKeyOrigin(size);
    final radius = maxRadius(size, origin) * progress;
    final colors = context.appColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipPath(
          clipper: _CircleRevealClipper(center: origin, radius: radius),
          clipBehavior: Clip.antiAlias,
          child: ColoredBox(color: colors.scaffold, child: child),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _RippleRingPainter(
              center: origin,
              radius: radius,
              progress: progress,
              ringColor: colors.primary.withValues(alpha: 0.22),
            ),
            size: size,
          ),
        ),
      ],
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  const _CircleRevealClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) {
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return oldClipper.radius != radius || oldClipper.center != center;
  }
}

class _RippleRingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double progress;
  final Color ringColor;

  const _RippleRingPainter({
    required this.center,
    required this.radius,
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (var i = 0; i < 3; i++) {
      final wave = (progress * 1.15 - i * 0.08).clamp(0.0, 1.0);
      if (wave <= 0) continue;
      final r = radius * (1 - i * 0.06);
      paint.color = ringColor.withValues(alpha: (1 - wave) * 0.55);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RippleRingPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.progress != progress ||
        oldDelegate.center != center;
  }
}
