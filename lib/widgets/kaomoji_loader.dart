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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
            painter: _KaomojiPainter(progress: _ctrl.value, color: color),
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

  static const _eyeTopY = 34.0;
  static const _eyeMidY = 46.0;
  static const _eyeBotY = 58.0;
  static const _eyeOuterX = 18.0;
  static const _eyeInnerX = 38.0;
  static const _mouthY = 68.0;
  static const _mouthHalf = 14.0;
  static const _dotBaseY = 82.0;
  static const _dotMaxRise = 9.0;
  static const _dotRadius = 3.5;
  static const _dotSpacing = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale, scale);

    final t = progress;

    // --- face breathing scale ---
    final breathe = 1.0 + math.sin(t * 2 * math.pi) * 0.015;
    canvas.save();
    canvas.translate(50, 50);
    canvas.scale(breathe);
    canvas.translate(-50, -50);

    // --- eye squint: quick blink twice per cycle ---
    final squintRaw = math.sin(t * 2 * math.pi * 2);
    final squint = math.pow(squintRaw.clamp(0.0, 1.0), 3).toDouble();
    // Left eye '>'
    final lInnerX = _eyeInnerX - squint * 6;
    final leftEye = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final leftPath = Path()
      ..moveTo(_eyeOuterX, _eyeTopY)
      ..lineTo(lInnerX, _eyeMidY)
      ..lineTo(_eyeOuterX, _eyeBotY);
    canvas.drawPath(leftPath, leftEye);

    // Right eye '<'
    final rInnerX = 100 - _eyeInnerX + squint * 6;
    final rightEye = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rightPath = Path()
      ..moveTo(100 - _eyeOuterX, _eyeTopY)
      ..lineTo(rInnerX, _eyeMidY)
      ..lineTo(100 - _eyeOuterX, _eyeBotY);
    canvas.drawPath(rightPath, rightEye);

    // --- mouth: subtle wobble ---
    final mouthWobble = math.sin(t * 2 * math.pi + 1.2) * 1.2;
    final mouthPaint = Paint()
      ..color = color.withValues(alpha: 0.5 + squint * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(50 - _mouthHalf, _mouthY + mouthWobble),
      Offset(50 + _mouthHalf, _mouthY + mouthWobble),
      mouthPaint,
    );

    canvas.restore(); // breathe scale

    // --- bouncing dots ---
    final centerX = 50.0;
    for (var i = 0; i < 3; i++) {
      final phase = i * 0.22;
      final dotCycle = (t + phase) % 1.0;
      // parabolic bounce: 0 → peak at 0.5 → back to 0
      final rise = math.sin(dotCycle * math.pi);
      final dotY = _dotBaseY - rise * _dotMaxRise;
      // dot expands slightly at peak
      final dotScale = 0.7 + rise * 0.3;
      final dotAlpha = 0.35 + rise * 0.65;

      final dotPaint = Paint()
        ..color = color.withValues(alpha: dotAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(centerX + (i - 1) * _dotSpacing, dotY),
        _dotRadius * dotScale,
        dotPaint,
      );
    }

    canvas.restore(); // full scale
  }

  @override
  bool shouldRepaint(_KaomojiPainter old) =>
      old.progress != progress || old.color != color;
}
