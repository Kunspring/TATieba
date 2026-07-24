import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/agent_kaomoji_mood.dart';
import 'agent_kaomoji.dart';

class SplashOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDone;

  /// 子页面数据就绪后置为 true，开屏会在最短展示时间过后立即展开。
  static final ready = ValueNotifier(false);

  const SplashOverlay({super.key, required this.child, this.onDone});

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealCtrl;
  late final Animation<double> _kaomojiOpacity;
  late final Animation<double> _revealProgress;

  bool _ready = false;
  bool _minTimeElapsed = false;
  bool _revealing = false;

  static const _revealMs = 650;
  static const double _fadeFraction = 200 / _revealMs;
  static const _minDisplayMs = 800;

  @override
  void initState() {
    super.initState();

    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _revealMs),
    );
    _kaomojiOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _revealCtrl,
        curve: const Interval(0, _fadeFraction, curve: Curves.easeOut),
      ),
    );
    _revealProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _revealCtrl,
        curve:
            const Interval(_fadeFraction, 1.0, curve: Curves.easeInCubic),
      ),
    );
    _revealCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone?.call();
      }
    });

    if (SplashOverlay.ready.value) {
      _ready = true;
    } else {
      SplashOverlay.ready.addListener(_onReady);
    }

    Future.delayed(const Duration(milliseconds: _minDisplayMs), () {
      if (!mounted) return;
      _minTimeElapsed = true;
      _tryStartReveal();
    });
  }

  void _onReady() {
    if (!SplashOverlay.ready.value) return;
    SplashOverlay.ready.removeListener(_onReady);
    _ready = true;
    _tryStartReveal();
  }

  void _tryStartReveal() {
    if (_revealing || !_ready || !_minTimeElapsed) return;
    _revealing = true;
    _revealCtrl.forward();
  }

  @override
  void dispose() {
    SplashOverlay.ready.removeListener(_onReady);
    _revealCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedBuilder(
      animation: _revealCtrl,
      builder: (context, _) {
        if (_revealCtrl.isCompleted) return widget.child;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final size = MediaQuery.sizeOf(context);
        final center = Offset(size.width / 2, size.height / 2);
        final maxR = _maxRadius(size, center);

        final revealP = _revealing ? _revealProgress.value : 0.0;
        final kaomojiAlpha = _revealing ? _kaomojiOpacity.value : 1.0;
        final shaking =
            !_revealing || _revealCtrl.value < _fadeFraction;

        final revealR = maxR * Curves.easeInCubic.transform(revealP);

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
                color:
                    isDark ? const Color(0xFF1a1a1a) : Colors.white),
            ClipPath(
              clipper:
                  _CircleRevealClipper(center: center, radius: revealR),
              clipBehavior: Clip.antiAlias,
              child: widget.child,
            ),
            if (_revealing && revealP > 0)
              IgnorePointer(
                child: CustomPaint(
                  painter: _SplashRipplePainter(
                    center: center,
                    maxRadius: maxR,
                    progress: revealP,
                    ringColor: _rippleColor(isDark, colors),
                  ),
                  size: size,
                ),
              ),
            if (kaomojiAlpha > 0)
              IgnorePointer(
                child: Opacity(
                  opacity: kaomojiAlpha,
                  child: Center(
                    child: AgentKaomoji(
                      mood: AgentKaomojiMood.welcome,
                      size: 36,
                      shaking: shaking,
                      color:
                          Color(isDark ? 0xFFE0E0E0 : 0xFF333333),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Color _rippleColor(bool isDark, AppColorScheme colors) {
  return (isDark ? colors.primary : colors.primary)
      .withValues(alpha: 0.18);
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
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
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

    for (var i = 0; i < 4; i++) {
      final ringStart = i * 0.12;
      final ringProgress =
          ((progress - ringStart) / 0.76).clamp(0.0, 1.0);
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
