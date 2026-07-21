import 'package:flutter/material.dart';

/// 聊天里展示 AI 画的像素图（放大显示每个像素）。
class AgentPixelArtView extends StatelessWidget {
  final int width;
  final int height;
  final List<String> pixels;
  final double pixelSize;

  const AgentPixelArtView({
    super.key,
    required this.width,
    required this.height,
    required this.pixels,
    this.pixelSize = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (width <= 0 || height <= 0 || pixels.isEmpty) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      size: Size(width * pixelSize, height * pixelSize),
      painter: _PixelPainter(
        width: width,
        height: height,
        pixels: pixels,
        pixelSize: pixelSize,
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  final int width;
  final int height;
  final List<String> pixels;
  final double pixelSize;

  _PixelPainter({
    required this.width,
    required this.height,
    required this.pixels,
    required this.pixelSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (idx >= pixels.length) continue;
        final color = _parseHex(pixels[idx]);
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * pixelSize, y * pixelSize, pixelSize, pixelSize),
          paint,
        );
      }
    }
  }

  Color? _parseHex(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == '.') return null;
    var hex = t.startsWith('#') ? t.substring(1) : t;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  @override
  bool shouldRepaint(covariant _PixelPainter oldDelegate) {
    return oldDelegate.pixels != pixels ||
        oldDelegate.width != width ||
        oldDelegate.height != height;
  }
}
