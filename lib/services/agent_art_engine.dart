import 'dart:math' as math;
import 'dart:ui';

/// 像素画布引擎（思路参考开源 pixel-mcp / pixlrt：用代码画像素）。
class PixelCanvas {
  final int width;
  final int height;
  late final List<Color?> _pixels;

  PixelCanvas(this.width, this.height)
    : assert(width > 0 && height > 0),
      assert(width <= 64 && height <= 64) {
    _pixels = List<Color?>.filled(width * height, null);
  }

  int _index(int x, int y) => y * width + x;

  void setPixel(int x, int y, Color color) {
    if (!_inBounds(x, y)) return;
    _pixels[_index(x, y)] = color;
  }

  Color? getPixel(int x, int y) {
    if (!_inBounds(x, y)) return null;
    return _pixels[_index(x, y)];
  }

  void fillRect(int x, int y, int w, int h, Color color) {
    for (var dy = 0; dy < h; dy++) {
      for (var dx = 0; dx < w; dx++) {
        setPixel(x + dx, y + dy, color);
      }
    }
  }

  void drawLine(int x1, int y1, int x2, int y2, Color color) {
    var x = x1;
    var y = y1;
    final dx = (x2 - x1).abs();
    final dy = (y2 - y1).abs();
    final sx = x1 < x2 ? 1 : -1;
    final sy = y1 < y2 ? 1 : -1;
    var err = dx - dy;

    while (true) {
      setPixel(x, y, color);
      if (x == x2 && y == y2) break;
      final e2 = err * 2;
      if (e2 > -dy) {
        err -= dy;
        x += sx;
      }
      if (e2 < dx) {
        err += dx;
        y += sy;
      }
    }
  }

  void drawCircle(int cx, int cy, int radius, Color color, {bool fill = true}) {
    if (radius < 0) return;
    if (fill) {
      for (var y = -radius; y <= radius; y++) {
        for (var x = -radius; x <= radius; x++) {
          if (x * x + y * y <= radius * radius) {
            setPixel(cx + x, cy + y, color);
          }
        }
      }
      return;
    }
    for (var angle = 0.0; angle < 360; angle += 0.5) {
      final rad = angle * math.pi / 180;
      setPixel(
        cx + (radius * math.cos(rad)).round(),
        cy + (radius * math.sin(rad)).round(),
        color,
      );
    }
  }

  /// 从字符网格导入（pixlrt 风格），每字符映射 palette 里的颜色。
  factory PixelCanvas.fromGrid({
    required List<String> rows,
    required Map<String, Color> palette,
  }) {
    if (rows.isEmpty) {
      throw ArgumentError('rows 不能为空');
    }
    final height = rows.length;
    final width = rows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    if (width == 0 || width > 64 || height > 64) {
      throw ArgumentError('画布尺寸须在 1~64');
    }
    final canvas = PixelCanvas(width, height);
    for (var y = 0; y < height; y++) {
      final row = rows[y];
      for (var x = 0; x < width; x++) {
        final ch = x < row.length ? row[x] : ' ';
        final color = palette[ch];
        if (color != null) canvas.setPixel(x, y, color);
      }
    }
    return canvas;
  }

  Map<String, dynamic> toJson() {
    final pixels = <String>[];
    for (final p in _pixels) {
      if (p == null) {
        pixels.add('.');
      } else {
        pixels.add(_colorToHex(p));
      }
    }
    return {'width': width, 'height': height, 'pixels': pixels};
  }

  /// 用灰度字符生成简易 ASCII 预览。
  String toAsciiPreview({String empty = ' '}) {
    const shades = ' .:-=+*#%@';
    final buf = StringBuffer();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = getPixel(x, y);
        if (c == null) {
          buf.write(empty);
          continue;
        }
        final lum = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255;
        final idx = (lum / 255 * (shades.length - 1)).round().clamp(
          0,
          shades.length - 1,
        );
        buf.write(shades[idx]);
      }
      if (y < height - 1) buf.writeln();
    }
    return buf.toString();
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  static Color? parseColor(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      return Color(0xFF000000 | (raw & 0xFFFFFF));
    }
    if (raw is List && raw.length >= 3) {
      final r = _channel(raw[0]);
      final g = _channel(raw[1]);
      final b = _channel(raw[2]);
      if (r == null || g == null || b == null) return null;
      final a = raw.length >= 4 ? (_channel(raw[3]) ?? 255) : 255;
      return Color.fromARGB(a, r, g, b);
    }
    if (raw is Map) {
      final r = _channel(raw['r'] ?? raw['red']);
      final g = _channel(raw['g'] ?? raw['green']);
      final b = _channel(raw['b'] ?? raw['blue']);
      if (r != null && g != null && b != null) {
        final a = _channel(raw['a'] ?? raw['alpha']) ?? 255;
        return Color.fromARGB(a, r, g, b);
      }
    }

    final t = raw.toString().trim();
    if (t.isEmpty || t == '.' || t == 'transparent' || t == 'null') {
      return null;
    }

    final rgbMatch = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([\d.]+))?\s*\)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (rgbMatch != null) {
      final r = int.parse(rgbMatch.group(1)!);
      final g = int.parse(rgbMatch.group(2)!);
      final b = int.parse(rgbMatch.group(3)!);
      final alphaRaw = rgbMatch.group(4);
      final a = alphaRaw == null
          ? 255
          : (double.parse(alphaRaw) <= 1
                ? (double.parse(alphaRaw) * 255).round()
                : double.parse(alphaRaw).round());
      return Color.fromARGB(
        a.clamp(0, 255),
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      );
    }

    const named = {
      'black': Color(0xFF000000),
      'white': Color(0xFFFFFFFF),
      'red': Color(0xFFFF0000),
      'green': Color(0xFF00FF00),
      'blue': Color(0xFF0000FF),
      'yellow': Color(0xFFFFFF00),
      'cyan': Color(0xFF00FFFF),
      'magenta': Color(0xFFFF00FF),
      'orange': Color(0xFFFF8800),
      'pink': Color(0xFFFF69B4),
      'purple': Color(0xFFAA00FF),
      'gray': Color(0xFF888888),
      'grey': Color(0xFF888888),
    };
    final lower = t.toLowerCase();
    if (named.containsKey(lower)) return named[lower];

    var hex = t;
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        return Color(0xFF000000 | value);
      }
    }
    if (hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        return Color(value | 0xFF000000);
      }
    }
    return null;
  }

  static int? _channel(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.round().clamp(0, 255);
    return int.tryParse(raw.toString())?.clamp(0, 255);
  }
}
