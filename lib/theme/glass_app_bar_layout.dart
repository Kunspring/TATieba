import 'package:flutter/material.dart';

/// 供顶栏上报布局信息。
class GlassAppBarLayout extends InheritedWidget {
  final String? titleText;
  final TextStyle titleStyle;
  final double leadingWidth;
  final double actionsWidth;

  const GlassAppBarLayout({
    super.key,
    required this.titleText,
    required this.titleStyle,
    required this.leadingWidth,
    required this.actionsWidth,
    required super.child,
  });

  static GlassAppBarLayout? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GlassAppBarLayout>();
  }

  @override
  bool updateShouldNotify(covariant GlassAppBarLayout oldWidget) {
    return titleText != oldWidget.titleText ||
        titleStyle != oldWidget.titleStyle ||
        leadingWidth != oldWidget.leadingWidth ||
        actionsWidth != oldWidget.actionsWidth;
  }
}

abstract final class CompanionBarLayout {
  CompanionBarLayout._();

  static const _minBlankWidth = 44.0;
  static const _companionReserveWidth = 96.0;
  static const _maxTitleWidthCap = 200.0;
  static const _minTitleWidth = 72.0;

  static double _measureTitleWidth({
    required String titleText,
    required TextStyle titleStyle,
    required double maxWidth,
  }) {
    if (titleText.isEmpty || maxWidth <= 0) return 0;
    final painter = TextPainter(
      text: TextSpan(text: titleText, style: titleStyle),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.width;
  }

  /// 顶栏可用区域 [leading, actions) 内，标题右侧空白区的中心 X。
  static double blankSpaceCenterX({
    required double barWidth,
    required String? titleText,
    required TextStyle titleStyle,
    required double leadingWidth,
    required double actionsWidth,
  }) {
    if (barWidth <= 0) return 0;

    final areaLeft = leadingWidth;
    final areaRight = barWidth - actionsWidth;
    if (areaRight <= areaLeft) return barWidth / 2;

    final titleMaxWidth = titleMaxWidthForBar(
      barWidth: barWidth,
      leadingWidth: leadingWidth,
      actionsWidth: actionsWidth,
    );

    var blankLeft = areaLeft;
    final trimmedTitle = titleText?.trim() ?? '';
    if (trimmedTitle.isNotEmpty && titleMaxWidth > 0) {
      blankLeft =
          areaLeft +
          _measureTitleWidth(
            titleText: trimmedTitle,
            titleStyle: titleStyle,
            maxWidth: titleMaxWidth,
          );
    }

    if (areaRight - blankLeft < _minBlankWidth) {
      return (areaLeft + areaRight) / 2;
    }

    return (blankLeft + areaRight) / 2;
  }

  /// 相对屏幕中心的偏移，供全局颜文字层平滑移动。
  static double companionOffsetX({
    required double barWidth,
    required String? titleText,
    required TextStyle titleStyle,
    required double leadingWidth,
    required double actionsWidth,
  }) {
    if (barWidth <= 0) return 0;
    final centerX = blankSpaceCenterX(
      barWidth: barWidth,
      titleText: titleText,
      titleStyle: titleStyle,
      leadingWidth: leadingWidth,
      actionsWidth: actionsWidth,
    );
    return centerX - barWidth / 2;
  }

  /// 标题极限宽度：为颜文字保留空白，且不超过 [_maxTitleWidthCap]。
  static double titleMaxWidthForBar({
    required double barWidth,
    required double leadingWidth,
    required double actionsWidth,
  }) {
    if (barWidth <= 0) return 0;
    final available = (barWidth - leadingWidth - actionsWidth).clamp(
      0.0,
      barWidth,
    );
    if (available <= 0) return 0;

    final reserved = available - _companionReserveWidth;
    if (reserved <= 0) {
      return available.clamp(0.0, _maxTitleWidthCap);
    }

    return reserved
        .clamp(_minTitleWidth, _maxTitleWidthCap)
        .clamp(0.0, available);
  }
}
