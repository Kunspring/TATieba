import 'package:flutter_test/flutter_test.dart';
import 'package:tieba_app/services/agent_art_tools.dart';

void main() {
  test('draw_pixel_art accepts op aliases', () async {
    final r = await AgentArtTools.execute('draw_pixel_art', {
      'width': 8,
      'height': 8,
      'operations': [
        {
          'type': 'fill_rect',
          'x': 0,
          'y': 0,
          'width': 8,
          'height': 8,
          'color': '#112233',
        },
        {'operation': 'circle', 'x': 4, 'y': 4, 'radius': 2, 'color': 'red'},
      ],
    });
    expect(r['error'], isNull);
    expect(r['width'], 8);
  });

  test('draw_pixel_art parses string operations', () async {
    final r = await AgentArtTools.execute('draw_pixel_art', {
      'width': 4,
      'height': 4,
      'ops':
          '[{"op":"fill_rect","x":0,"y":0,"w":4,"h":4,"color":"rgb(255,0,0)"}]',
    });
    expect(r['error'], isNull);
  });

  test('draw_pixel_art parses nested op maps', () async {
    final r = await AgentArtTools.execute('draw_pixel_art', {
      'width': 4,
      'height': 4,
      'operations': [
        {
          'fill_rect': {'x': 0, 'y': 0, 'w': 4, 'h': 4, 'color': '#00FF00'},
        },
      ],
    });
    expect(r['error'], isNull);
  });

  test('draw_ascii_grid accepts multiline string rows', () async {
    final r = await AgentArtTools.execute('draw_ascii_grid', {
      'rows': '..##..\n.####.',
      'palette': {'#': '#FF0000', '.': 'transparent'},
    });
    expect(r['error'], isNull);
    expect(r['width'], greaterThan(0));
  });

  test('draw_shape renders every preset without error', () async {
    for (final name in const [
      'heart',
      'star',
      'smiley',
      'cat',
      'flower',
      'skull',
    ]) {
      final r = await AgentArtTools.execute('draw_shape', {'name': name});
      expect(r['error'], isNull, reason: 'shape $name should render');
      expect(r['kind'], 'shape');
      expect(r['pixels'], isA<List>());
      expect(r['width'], greaterThan(0));
      expect(r['height'], greaterThan(0));
    }
  });

  test('draw_shape unknown name returns instructive error', () async {
    final r = await AgentArtTools.execute('draw_shape', {'name': 'dragon'});
    expect(r['error'], isNotNull);
    expect(r['error'].toString(), contains('可选'));
  });

  test('draw_shape honors color override', () async {
    final r = await AgentArtTools.execute('draw_shape', {
      'name': 'heart',
      'color': 'green',
    });
    expect(r['error'], isNull);
    expect(r['pixels'], isA<List>());
  });
}
