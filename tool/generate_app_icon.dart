import 'dart:io';

import 'package:image/image.dart' as img;

/// 生成 assets/app_icon.png：浅灰底，>_< 中心落在左上黄金分割点，
/// 包围盒宽度占画布较小黄金分割边长（φ⁻²）。
void main() {
  const canvasSize = 1024;

  const designMinX = 14.0;
  const designMaxX = 86.0;
  const designMinY = 26.0;
  const designMaxY = 64.0;
  const designWidth = designMaxX - designMinX;
  const designHeight = designMaxY - designMinY;
  const designCenterX = (designMinX + designMaxX) / 2;
  const designCenterY = (designMinY + designMaxY) / 2;

  // φ⁻² ≈ 0.382：较小黄金分割区域边长
  const goldenSection = 0.3819660112501051;
  final goldenSize = canvasSize * goldenSection;

  // 颜文字包围盒宽 = 较小黄金分割边长，高按比例缩放
  final scale = goldenSize / designWidth;
  final stroke = (5.8 * scale).clamp(12.0, 28.0).round();

  // 中心落在左上黄金分割交点
  final ox = goldenSize - designCenterX * scale;
  final oy = goldenSize - designCenterY * scale;

  final bg = img.ColorRgb8(242, 243, 245);
  final strokeColor = img.ColorRgb8(0, 0, 0);

  final image = img.Image(width: canvasSize, height: canvasSize);
  img.fill(image, color: bg);

  void segment(double x1, double y1, double x2, double y2) {
    _drawStroke(
      image,
      ox: ox,
      oy: oy,
      scale: scale,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      thickness: stroke,
      color: strokeColor,
    );
  }

  // KaomojiLoader 路径（100×100 设计坐标）
  segment(14, 26, 34, 40);
  segment(34, 40, 14, 54);
  segment(86, 26, 66, 40);
  segment(66, 40, 86, 54);
  segment(38, 64, 62, 64);

  final out = File('assets/app_icon.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print
  print(
    'Wrote ${out.path} ($canvasSize×$canvasSize, '
    'kaomoji ${(designWidth * scale).round()}×${(designHeight * scale).round()} '
    'at golden-ratio point, goldenSize=${goldenSize.round()})',
  );
}

void _drawStroke(
  img.Image image, {
  required double ox,
  required double oy,
  required double scale,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required int thickness,
  required img.Color color,
}) {
  final sx1 = (ox + x1 * scale).round();
  final sy1 = (oy + y1 * scale).round();
  final sx2 = (ox + x2 * scale).round();
  final sy2 = (oy + y2 * scale).round();

  img.drawLine(
    image,
    x1: sx1,
    y1: sy1,
    x2: sx2,
    y2: sy2,
    color: color,
    thickness: thickness,
  );
}
