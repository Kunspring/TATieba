import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SplashOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDone;

  const SplashOverlay({super.key, required this.child, this.onDone});

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward().then((_) {
      widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final p = _progress.value;

        if (p >= 1.0) return widget.child;

        final size = MediaQuery.sizeOf(context);
        final center = Offset(size.width / 2, size.height / 2);
        final maxR = _maxRadius(size, center);
        final revealR = maxR * _revealCurve(p);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _splashColor(isDark)),
            ClipPath(
              clipper: _CircleRevealClipper(center: center, radius: revealR),
              clipBehavior: Clip.antiAlias,
              child: widget.child,
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _SplashRipplePainter(
                  center: center,
                  maxRadius: maxR,
                  progress: p,
                  ringColor: _rippleColor(isDark, colors),
                ),
                size: size,
              ),
            ),
          ],
        );
      },
    );
  }
}

Color _splashColor(bool isDark) {
  return isDark ? AppColors.darkScaffold : AppColors.scaffold;
}

Color _rippleColor(bool isDark, AppColorScheme colors) {
  return (isDark ? colors.primary : colors.primary).withValues(alpha: 0.18);
}

/// 先慢后快：中心小圆阶段快速弹出，边缘收束时平滑融合。
double _revealCurve(double t) {
  return Curves.easeInCubic.transform(t);
}

double _maxRadius(Size size, Offset center) {
  final corners = [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ];
  var maxDist = 0.0;
  for (final corner in corners) {
    maxDist = math.max(maxDist, (corner - center).distance);
  }
  return maxDist + 24;
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

class _SplashRipplePainter extends CustomPainter {
  final Offset center;
  final double maxRadius;
  final double progress;
  final Color ringColor;

  const _SplashRipplePainter({
    required this.center,
    required this.maxRadius,
    required this.progress,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 4 圈波纹从中心向外扩散，每圈间隔约 0.12 进度
    for (var i = 0; i < 4; i++) {
      final ringStart = i * 0.12;
      final ringProgress = ((progress - ringStart) / 0.76).clamp(0.0, 1.0);
      if (ringProgress <= 0 || ringProgress >= 1) continue;

      final r = ringProgress * maxRadius;
      final opacity = (1.0 - ringProgress) * 0.6;
      paint.color = ringColor.withValues(alpha: opacity);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashRipplePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.maxRadius != maxRadius ||
        oldDelegate.center != center;
  }
}
