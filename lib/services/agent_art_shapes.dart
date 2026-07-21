import 'dart:ui';

import 'agent_art_engine.dart';

/// 预设图形库：用户说「画个爱心 / 星星 / 猫…」时按名召唤，确定性出好图。
/// 每个图形是一组等宽字符行 + 调色板（`.` = 透明）。
/// 走与像素画同一套渲染（PixelCanvas.fromGrid → 结果卡片），永不翻车。
abstract final class AgentArtShapes {
  AgentArtShapes._();

  static const Map<String, _Shape> _shapes = {
    'heart': _Shape(
      '红心',
      {'@': '#ff4d6d', '.': 'transparent'},
      [
        '.@@.....@@.',
        '.@@.....@@.',
        '@@@@...@@@@',
        '@@@@@.@@@@@',
        '@@@@@@@@@@@',
        '@@@@@@@@@@@',
        '.@@@@@@@@@.',
        '..@@@@@@@..',
        '...@@@@@...',
        '....@@@....',
      ],
    ),
    'star': _Shape(
      '星星',
      {'@': '#ffd43b', '.': 'transparent'},
      [
        '.....@.....',
        '....@@@....',
        '.@@@@@@@@@.',
        '.@@@@@@@@@.',
        '..@@@@@@@..',
        '...@@@@@...',
        '..@.@.@.@..',
        '.@.......@.',
      ],
    ),
    'smiley': _Shape(
      '笑脸',
      {'@': '#ffd43b', '.': 'transparent'},
      [
        '...@@@@@...',
        '..@@@@@@@..',
        '.@@@@@@@@@.',
        '.@@.@...@@.',
        '.@@@@@@@@@.',
        '.@@@@@@@@@.',
        '..@@@.@@@..',
        '..@@@@@@@..',
        '...@@@@@...',
      ],
    ),
    'cat': _Shape(
      '猫',
      {'@': '#9aa0a6', '.': 'transparent'},
      [
        '.@.......@.',
        '.@@.....@@.',
        '.@@@@@@@@@.',
        '.@@.@.@.@@.',
        '.@@@@@@@@@.',
        '.@@@.@.@@@.',
        '.@@@@@@@@@.',
        '..@@@@@@@..',
        '...@@@@@...',
      ],
    ),
    'flower': _Shape(
      '花',
      {'@': '#ff8fab', '.': 'transparent'},
      [
        '..@.@.@.@..',
        '.@@@@@@@@@.',
        '@@@@@@@@@@@',
        '.@@@@@@@@@.',
        '..@@@@@@@..',
        '.....@.....',
        '.....@.....',
        '....@@@....',
      ],
    ),
    'skull': _Shape(
      '骷髅',
      {'@': '#e9ecef', '.': 'transparent'},
      [
        '..@@@@@@@..',
        '.@@@@@@@@@.',
        '.@@.@.@.@@.',
        '.@@@@@@@@@.',
        '.@@@@@@@@@.',
        '..@@@@@@@..',
        '..@.@.@.@..',
        '...@@@@@...',
      ],
    ),
  };

  static List<String> get names => _shapes.keys.toList();

  /// 按名画一个预设图形。
  /// [name] 为图形名（不区分大小写）；[color] 可选，覆盖主填充色。
  /// 返回与像素画同构的 JSON（kind: 'shape'），便于结果卡片复用渲染。
  static Map<String, dynamic> draw(
    String? name, {
    String? color,
    String? background,
  }) {
    final key = (name ?? '').toString().trim().toLowerCase();
    final shape = _shapes[key];
    if (shape == null) {
      return {'error': '没有「$name」这个图形，可选：${names.join(' / ')}'};
    }

    final palette = <String, Color>{};
    for (final entry in shape.palette.entries) {
      final c = PixelCanvas.parseColor(entry.value);
      if (c != null) palette[entry.key] = c;
    }

    // 可选主色覆盖：把第一个非透明调色板键重映射到新颜色
    if (color != null) {
      final override = PixelCanvas.parseColor(color);
      if (override != null) {
        final firstKey = shape.palette.keys.firstWhere(
          (k) => shape.palette[k] != 'transparent',
          orElse: () => '',
        );
        if (firstKey.isNotEmpty) palette[firstKey] = override;
      }
    }

    try {
      final canvas = PixelCanvas.fromGrid(rows: shape.rows, palette: palette);
      if (background != null) {
        final bg = PixelCanvas.parseColor(background);
        if (bg != null) {
          for (var y = 0; y < canvas.height; y++) {
            for (var x = 0; x < canvas.width; x++) {
              if (canvas.getPixel(x, y) == null) canvas.setPixel(x, y, bg);
            }
          }
        }
      }
      final pixelJson = canvas.toJson();
      return {
        'action': 'pixel_art',
        'kind': 'shape',
        'shape': key,
        'width': canvas.width,
        'height': canvas.height,
        ...pixelJson,
        'ascii_preview': canvas.toAsciiPreview(),
      };
    } catch (e) {
      return {'error': '图形「$key」渲染失败：${e.toString()}'};
    }
  }
}

class _Shape {
  final String label;
  final Map<String, String> palette;
  final List<String> rows;
  const _Shape(this.label, this.palette, this.rows);
}
