import 'dart:convert';

import 'package:enough_ascii_art/enough_ascii_art.dart' as figlet;
import 'package:flutter/services.dart';

import 'agent_art_engine.dart';
import 'agent_art_shapes.dart';

/// AI 绘画工具：FIGlet 大字、像素画布、字符网格（基于 enough_ascii_art + 自研像素引擎）。
abstract final class AgentArtTools {
  AgentArtTools._();

  static const maxCanvas = 64;
  static const figletFonts = ['standard', 'small', 'block'];

  static List<Map<String, dynamic>> get definitions => [
    _tool(
      'draw_figlet',
      '用 FIGlet 大字横幅「画」文字艺术。用户要标题字、banner、炫酷大字时用。',
      {
        'text': _str('要渲染的文字，建议 1~20 字符'),
        'font': _str('字体：standard | small | block，默认 standard'),
      },
      ['text'],
    ),
    _tool(
      'draw_pixel_art',
      '在像素画布上画图。**推荐用「字符网格」画法（更简单、更易出好图）：'
          '直接传 rows（每行等宽字符串）+ palette（字符→颜色），例如 '
          'rows=["..@@..",".####.","######"], palette={"#":"#ff4d6d",".":"transparent"}。'
          '也支持高级写法 operations（数组，每项含 op 与 color：'
          'fill_rect(x,y,w,h)/draw_line(x1,y1,x2,y2)/draw_circle(x,y,radius)/set_pixels）。'
          '画布最大 64×64。常见图形（爱心/星星/猫…）优先用 draw_shape。',
      {
        'width': _int('画布宽 1~64（网格画法可省略，由 rows 自动决定）'),
        'height': _int('画布高 1~64（网格画法可省略）'),
        'background': _str('可选背景色，如 #1a1a2e 或 transparent'),
        'rows': {
          'type': 'array',
          'description':
              '字符网格画法（推荐）：每行等宽字符串，字符在 palette 中映射到颜色，"." 表示透明。例 ["..@@..",".####.","######"]',
          'items': {'type': 'string'},
        },
        'palette': {
          'type': 'object',
          'description': '字符到颜色，如 {"#":"#FF0000",".":"transparent"}',
        },
        'operations': {
          'type': 'array',
          'description': '高级画法：绘制步骤数组。每项含 op、color 及坐标',
          'items': {'type': 'object'},
        },
      },
      [],
    ),
    _tool(
      'draw_ascii_grid',
      '用字符网格画像素图（pixlrt 风格）。每行等宽字符串，palette 映射字符→颜色。'
          '例：palette {"#":"#ff0000",".":透明}，rows ["..##..",".####."]',
      {
        'rows': {
          'type': 'array',
          'description': '字符行，每行等宽',
          'items': {'type': 'string'},
        },
        'palette': {
          'type': 'object',
          'description': '字符到颜色，如 {"#":"#FF0000",".":"transparent"}',
        },
      },
      ['rows', 'palette'],
    ),
    _tool(
      'style_unicode_text',
      '把文字变成 Unicode 花式字体（双 struck、圈字等），不算像素画但可当文字艺术。',
      {
        'text': _str('要转换的文字'),
        'style': _str(
          'doublestruck | circled | monospace | fullwidth | sansBold，默认 doublestruck',
        ),
      },
      ['text'],
    ),
    _tool(
      'draw_shape',
      '画一个预设的可爱图形（按名字召唤，必定出好图）：'
          'heart(爱心) / star(星星) / smiley(笑脸) / cat(猫) / flower(花) / skull(骷髅)。'
          '用户说「画个爱心 / 星星 / 猫…」时用，比手写坐标省事且稳定。可选 color 改主色。',
      {
        'name': _str('图形名：heart | star | smiley | cat | flower | skull'),
        'color': _str('可选，覆盖主色，如 #00ff88 或 green'),
      },
      ['name'],
    ),
  ];

  static Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      return switch (name) {
        'draw_figlet' => await _drawFiglet(args),
        'draw_pixel_art' => _drawPixelArt(args),
        'draw_ascii_grid' => _drawAsciiGrid(args),
        'style_unicode_text' => _styleUnicode(args),
        'draw_shape' => AgentArtShapes.draw(
          args['name']?.toString(),
          color: args['color']?.toString(),
        ),
        _ => {'error': '未知绘画工具: $name'},
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _drawFiglet(
    Map<String, dynamic> args,
  ) async {
    final text = args['text']?.toString().trim() ?? '';
    if (text.isEmpty) return {'error': '请提供 text'};
    if (text.length > 40) return {'error': 'text 最多 40 字符'};
    final fontName =
        (args['font']?.toString().trim().toLowerCase() ?? 'standard')
            .replaceAll('.flf', '');
    if (!figletFonts.contains(fontName)) {
      return {'error': 'font 须为 ${figletFonts.join(' | ')} 之一'};
    }

    final fontText = await rootBundle.loadString('assets/figlet/$fontName.flf');
    final font = figlet.Font.text(fontText);
    final art = figlet.renderFiglet(text, font);

    return {
      'action': 'figlet',
      'text': text,
      'font': fontName,
      'art': art,
      'kind': 'ascii',
    };
  }

  static Map<String, dynamic> _drawPixelArt(Map<String, dynamic> args) {
    final width = _intArg(args['width'], defaultValue: 16, max: maxCanvas);
    final height = _intArg(args['height'], defaultValue: 16, max: maxCanvas);
    if (width < 1 || height < 1) {
      return {'error': 'width/height 须在 1~$maxCanvas'};
    }

    final ops = _parseOperations(args);
    if (ops == null || ops.isEmpty) {
      // 网格画法（推荐）：rows / palette 任意其一出现即走字符网格路径
      if (args['rows'] != null || args['palette'] != null) {
        return _drawAsciiGrid(args);
      }
      return {
        'error':
            '没拿到可识别的画法。推荐：① 网格画法传 rows（每行等宽字符串）+ '
            'palette（字符→颜色），如 rows=["..@@..",".####.","######"], '
            'palette={"#":"#ff4d6d",".":"transparent"}；'
            '② 常见图形直接用 draw_shape（爱心/星星/猫…）。'
            '高级玩法才是 operations 数组。',
      };
    }
    if (ops.length > 64) {
      return {'error': 'operations 最多 64 步'};
    }

    final canvas = PixelCanvas(width, height);
    final bg = PixelCanvas.parseColor(args['background']?.toString());
    if (bg != null) {
      canvas.fillRect(0, 0, width, height, bg);
    }

    var applied = 0;
    for (var i = 0; i < ops.length; i++) {
      final err = _applyOp(canvas, op: ops[i], index: i + 1);
      if (err != null) return {'error': err};
      applied++;
    }
    if (applied == 0) {
      return {'error': 'operations 中没有可识别的绘制步骤'};
    }

    final pixelJson = canvas.toJson();
    return {
      'action': 'pixel_art',
      'kind': 'pixel',
      ...pixelJson,
      'ascii_preview': canvas.toAsciiPreview(),
    };
  }

  static Map<String, dynamic> _drawAsciiGrid(Map<String, dynamic> args) {
    final rows = _parseRows(args['rows']);
    if (rows == null || rows.isEmpty) {
      return {'error': 'rows 不能为空（字符串数组，或换行分隔的单字符串）'};
    }
    if (rows.length > maxCanvas) {
      return {'error': 'rows 最多 $maxCanvas 行'};
    }

    final paletteRaw = args['palette'];
    if (paletteRaw is! Map || paletteRaw.isEmpty) {
      return {'error': 'palette 不能为空'};
    }
    final palette = <String, Color>{};
    for (final entry in paletteRaw.entries) {
      final key = entry.key.toString();
      if (key.isEmpty) continue;
      final color = PixelCanvas.parseColor(entry.value?.toString());
      if (color != null) palette[key] = color;
    }
    if (palette.isEmpty) {
      return {
        'error':
            'palette 至少需要一个有效颜色（如 {"#":"#FF0000",".":"transparent"}）。'
            '若只是想画常见图形，直接用 draw_shape（爱心/星星/猫…）更稳。',
      };
    }

    try {
      final canvas = PixelCanvas.fromGrid(rows: rows, palette: palette);
      final pixelJson = canvas.toJson();
      return {
        'action': 'pixel_art',
        'kind': 'grid',
        ...pixelJson,
        'ascii_preview': canvas.toAsciiPreview(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Map<String, dynamic> _styleUnicode(Map<String, dynamic> args) {
    final text = args['text']?.toString() ?? '';
    if (text.trim().isEmpty) return {'error': '请提供 text'};
    if (text.length > 80) return {'error': 'text 最多 80 字符'};

    final styleName =
        args['style']?.toString().trim().toLowerCase() ?? 'doublestruck';
    final font = switch (styleName) {
      'circled' => figlet.UnicodeFont.circled,
      'monospace' => figlet.UnicodeFont.monospace,
      'fullwidth' => figlet.UnicodeFont.fullwidth,
      'sansbold' || 'sans_bold' => figlet.UnicodeFont.sansBold,
      'script' => figlet.UnicodeFont.script,
      _ => figlet.UnicodeFont.doublestruck,
    };

    final styled = figlet.renderUnicode(text, font);
    return {
      'action': 'unicode_text',
      'text': text,
      'style': styleName,
      'art': styled,
      'kind': 'ascii',
    };
  }

  static String? _applyOp(
    PixelCanvas canvas, {
    required Map<String, dynamic> op,
    required int index,
  }) {
    final name = _normalizeOpName(
      op['op'] ?? op['operation'] ?? op['type'] ?? op['action'] ?? op['name'],
    );
    if (name.isEmpty) {
      return '第 $index 步缺少 op（如 fill_rect / draw_line）';
    }

    final color = PixelCanvas.parseColor(
      op['color'] ??
          op['stroke'] ??
          op['bg'] ??
          (op['fill'] is String ? op['fill'] : null),
    );
    if (color == null && name != 'set_pixels' && name != 'set_pixel') {
      return '第 $index 步「$name」缺少有效 color（如 #FF0000 或 red）';
    }

    switch (name) {
      case 'fill_rect':
        canvas.fillRect(
          _intArg(op['x']),
          _intArg(op['y']),
          _intArg(op['w'] ?? op['width'], defaultValue: 1).clamp(1, maxCanvas),
          _intArg(op['h'] ?? op['height'], defaultValue: 1).clamp(1, maxCanvas),
          color!,
        );
      case 'draw_line':
        canvas.drawLine(
          _intArg(op['x1'] ?? _pointCoord(op['from'], 0) ?? op['x0']),
          _intArg(op['y1'] ?? _pointCoord(op['from'], 1) ?? op['y0']),
          _intArg(op['x2'] ?? _pointCoord(op['to'], 0) ?? op['x1']),
          _intArg(op['y2'] ?? _pointCoord(op['to'], 1) ?? op['y1']),
          color!,
        );
      case 'draw_circle':
        canvas.drawCircle(
          _intArg(op['x'] ?? op['cx']),
          _intArg(op['y'] ?? op['cy']),
          _intArg(op['radius'] ?? op['r'], defaultValue: 1).clamp(0, maxCanvas),
          color!,
          fill:
              op['filled'] != false &&
              op['stroke_only'] != true &&
              op['outline'] != true &&
              (op['fill'] is bool ? op['fill'] as bool : true),
        );
      case 'set_pixel':
        canvas.setPixel(_intArg(op['x']), _intArg(op['y']), color!);
      case 'set_pixels':
        final points = op['points'] ?? op['pixels'] ?? op['coords'];
        if (points is! List) {
          return '第 $index 步 set_pixels 需要 points 数组';
        }
        var painted = 0;
        for (final p in points) {
          if (p is! Map) continue;
          final map = Map<String, dynamic>.from(p);
          final c = PixelCanvas.parseColor(
            map['color'] ?? map['fill'] ?? map['c'] ?? color,
          );
          if (c == null) continue;
          canvas.setPixel(_intArg(map['x']), _intArg(map['y']), c);
          painted++;
        }
        if (painted == 0) {
          return '第 $index 步 set_pixels 没有有效坐标点';
        }
      default:
        return '第 $index 步未知 op「$name」，可用 fill_rect/draw_line/draw_circle/set_pixel/set_pixels';
    }
    return null;
  }

  /// 解析 AI 常见的 operations 变体（字符串、别名键、单步对象等）。
  static List<Map<String, dynamic>>? _parseOperations(
    Map<String, dynamic> args,
  ) {
    final raw =
        args['operations'] ?? args['ops'] ?? args['steps'] ?? args['commands'];
    if (raw == null) return null;

    dynamic decoded = raw;
    if (decoded is String) {
      final text = decoded.trim();
      if (text.isEmpty) return null;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return null;
      }
    }

    if (decoded is Map) {
      decoded = [decoded];
    }
    if (decoded is! List || decoded.isEmpty) return null;

    final ops = <Map<String, dynamic>>[];
    for (final item in decoded) {
      final map = _coerceOpMap(item);
      if (map != null) ops.add(map);
    }
    return ops.isEmpty ? null : ops;
  }

  static Map<String, dynamic>? _coerceOpMap(dynamic item) {
    if (item is! Map) return null;
    var map = Map<String, dynamic>.from(item);

    // {"fill_rect": {"x":0,...}} 嵌套写法
    if (!_hasOpKey(map)) {
      for (final key in const [
        'fill_rect',
        'draw_line',
        'draw_circle',
        'set_pixel',
        'set_pixels',
        'fill',
        'rect',
        'line',
        'circle',
      ]) {
        final nested = map[key];
        if (nested is Map) {
          map = {...Map<String, dynamic>.from(nested), 'op': key};
          break;
        }
      }
    }

    map['op'] = _normalizeOpName(
      map['op'] ??
          map['operation'] ??
          map['type'] ??
          map['action'] ??
          map['name'],
    );

    // x,y,x2,y2 → w,h
    if (map['op'] == 'fill_rect') {
      if (!map.containsKey('w') && map.containsKey('x2')) {
        map['w'] = _intArg(map['x2']) - _intArg(map['x']) + 1;
      }
      if (!map.containsKey('h') && map.containsKey('y2')) {
        map['h'] = _intArg(map['y2']) - _intArg(map['y']) + 1;
      }
      map.putIfAbsent('w', () => map['width']);
      map.putIfAbsent('h', () => map['height']);
    }

    return map['op'].toString().isEmpty ? null : map;
  }

  static bool _hasOpKey(Map<String, dynamic> map) {
    return map.containsKey('op') ||
        map.containsKey('operation') ||
        map.containsKey('type') ||
        map.containsKey('action') ||
        map.containsKey('name');
  }

  static String _normalizeOpName(dynamic raw) {
    final n = raw?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
    return switch (n) {
      'fill' ||
      'rect' ||
      'rectangle' ||
      'fill_rectangle' ||
      'box' => 'fill_rect',
      'line' || 'line_to' || 'stroke' => 'draw_line',
      'circle' || 'ellipse' || 'dot' => 'draw_circle',
      'pixel' || 'point' || 'set_point' => 'set_pixel',
      'pixels' || 'points' || 'coords' => 'set_pixels',
      _ => n,
    };
  }

  static List<String>? _parseRows(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final lines = raw.split('\n').map((l) => l.trimRight()).toList();
      return lines.where((l) => l.isNotEmpty).toList();
    }
    if (raw is List) {
      return raw.map((e) => e.toString()).where((l) => l.isNotEmpty).toList();
    }
    return null;
  }

  static int? _pointCoord(dynamic point, int index) {
    if (point is List && point.length > index) {
      return _intArg(point[index]);
    }
    if (point is Map) {
      if (index == 0) {
        return _intArg(point['x'] ?? point[0]);
      }
      return _intArg(point['y'] ?? point[1]);
    }
    return null;
  }

  static int _intArg(dynamic raw, {int defaultValue = 0, int max = 999}) {
    if (raw is num) return raw.round().clamp(-maxCanvas, max);
    final v = int.tryParse(raw?.toString() ?? '');
    if (v == null) return defaultValue;
    return v.clamp(-maxCanvas, max);
  }

  static Map<String, dynamic> _tool(
    String name,
    String description, [
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
  ]) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  static Map<String, dynamic> _str(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, dynamic> _int(String description) => {
    'type': 'integer',
    'description': description,
  };

  static String describeCall(String name, Map<String, dynamic> args) {
    return switch (name) {
      'draw_figlet' => 'FIGlet「${args['text'] ?? ''}」',
      'draw_pixel_art' =>
        '像素画 ${args['width'] ?? '?'}×${args['height'] ?? '?'}',
      'draw_ascii_grid' => '字符网格像素画',
      'style_unicode_text' => '花式字「${args['text'] ?? ''}」',
      'draw_shape' => '图形「${args['name'] ?? ''}」',
      _ => name,
    };
  }
}
