import 'dart:math' as math;

import 'package:flutter/material.dart';

class KaomojiLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const KaomojiLoader({super.key, this.size = 48, this.color});

  @override
  State<KaomojiLoader> createState() => _KaomojiLoaderState();
}

class _KaomojiLoaderState extends State<KaomojiLoader>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _ctrl;
  final _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            isComplex: true,
            willChange: true,
            painter: _LissajousPainter(
              elapsed: DateTime.now().difference(_startedAt),
              color: color,
            ),
          );
        },
      ),
    );
  }
}

class _LissajousPainter extends CustomPainter {
  _LissajousPainter({required this.elapsed, required this.color});

  final Duration elapsed;
  final Color color;

  static const _durationMs = 6000.0;
  static const _pulseDurationMs = 5400.0;
  static const _particleCount = 28;
  static const _trailSpan = 0.38;
  static const _amp = 24.0;
  static const _ampBoost = 6.0;
  static const _ax = 3.0;
  static const _by = 4.0;
  static const _phase = 1.57;
  static const _yScale = 0.92;
  static const _strokeWidth = 3.2;

  double get _detailScale {
    final ms = elapsed.inMilliseconds.toDouble();
    final pulseProgress = (ms % _pulseDurationMs) / _pulseDurationMs;
    final pulseAngle = pulseProgress * math.pi * 2;
    return 0.52 + ((math.sin(pulseAngle + 0.55) + 1) / 2) * 0.48;
  }

  double get _progress {
    final ms = elapsed.inMilliseconds.toDouble();
    return (ms % _durationMs) / _durationMs;
  }

  static double _normalize(double x) => ((x % 1.0) + 1.0) % 1.0;

  Offset _point(double progress) {
    final ds = _detailScale;
    final t = progress * math.pi * 2;
    final amp = _amp + ds * _ampBoost;
    return Offset(
      50 + math.sin(_ax * t + _phase) * amp,
      50 + math.sin(_by * t) * (amp * _yScale),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale, scale);

    // --- faint background Lissajous path ---
    final path = Path();
    const steps = 200;
    for (var i = 0; i <= steps; i++) {
      final pt = _point(i / steps);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // --- trailing particles ---
    final progress = _progress;
    for (var i = 0; i < _particleCount; i++) {
      final tailOffset = i / (_particleCount - 1);
      final p = _normalize(progress - tailOffset * _trailSpan);
      final pt = _point(p);
      final fade = math.pow(1 - tailOffset, 0.56);
      canvas.drawCircle(
        Offset(pt.dx, pt.dy),
        0.9 + fade * 2.7,
        Paint()
          ..color = color.withValues(alpha: 0.04 + fade * 0.96)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LissajousPainter old) =>
      old.elapsed != elapsed || old.color != color;
}
