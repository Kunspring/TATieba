import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class KaomojiLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const KaomojiLoader({super.key, this.size = 48, this.color});

  @override
  State<KaomojiLoader> createState() => _KaomojiLoaderState();
}

class _KaomojiLoaderState extends State<KaomojiLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
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
          final t = _ctrl.value;
          final scale = 0.985 + 0.045 * math.sin(t * math.pi * 2);
          return Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              isComplex: true,
              willChange: true,
              painter: _KaomojiPainter(progress: t, color: color),
            ),
          );
        },
      ),
    );
  }
}

class _KaomojiPainter extends CustomPainter {
  _KaomojiPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static final Path _leftEyePath = Path()
    ..moveTo(14, 26)
    ..lineTo(34, 40)
    ..lineTo(14, 54);

  static final Path _rightEyePath = Path()
    ..moveTo(86, 26)
    ..lineTo(66, 40)
    ..lineTo(86, 54);

  static final Path _mouthPath = Path()
    ..moveTo(38, 64)
    ..lineTo(62, 64);

  static ui.PathMetric? _leftMetric;
  static ui.PathMetric? _rightMetric;
  static double? _leftLen;
  static double? _rightLen;

  static void _ensureMetrics() {
    if (_leftMetric != null) return;
    _leftMetric = _leftEyePath.computeMetrics().first;
    _rightMetric = _rightEyePath.computeMetrics().first;
    _leftLen = _leftMetric!.length;
    _rightLen = _rightMetric!.length;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureMetrics();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final guidePaint = Paint.from(paint)..color = color.withValues(alpha: 0.1);

    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale, scale);

    final mouthPaint = Paint.from(paint)
      ..color = color.withValues(
        alpha: 0.35 + 0.15 * (math.sin(progress * math.pi * 2) * 0.5 + 0.5),
      )
      ..strokeWidth = 3.5;
    canvas.drawPath(_mouthPath, mouthPaint);

    _drawSwept(
      canvas,
      _leftEyePath,
      _leftMetric!,
      _leftLen!,
      progress,
      paint,
      guidePaint,
    );
    _drawSwept(
      canvas,
      _rightEyePath,
      _rightMetric!,
      _rightLen!,
      progress,
      paint,
      guidePaint,
    );

    canvas.restore();
  }

  void _drawSwept(
    Canvas canvas,
    Path guidePath,
    ui.PathMetric metric,
    double len,
    double t,
    Paint paint,
    Paint guide,
  ) {
    canvas.drawPath(guidePath, guide);

    final window = len * 0.38;
    // 单程 len + window：t=0 与 t=1 高亮均在路径外，循环首尾一致，避免开放路径回绕跳变。
    final travel = len + window;
    final phase = t * travel;
    final segStart = phase - window;
    final segEnd = phase;

    final drawStart = segStart.clamp(0.0, len);
    final drawEnd = segEnd.clamp(0.0, len);
    if (drawEnd <= drawStart) return;

    canvas.drawPath(metric.extractPath(drawStart, drawEnd), paint);
  }

  @override
  bool shouldRepaint(_KaomojiPainter old) =>
      old.progress != progress || old.color != color;
}
