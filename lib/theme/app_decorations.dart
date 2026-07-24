import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppDecorations {
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  static BorderRadius get borderRadiusSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderRadiusMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderRadiusLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderRadiusXl => BorderRadius.circular(radiusXl);
  static BorderRadius get borderRadiusPill => BorderRadius.circular(radiusPill);

  static List<BoxShadow> softShadow(AppColorScheme colors, {double blur = 8}) {
    return [
      BoxShadow(
        color: colors.shadow,
        blurRadius: blur,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> glassShadow(AppColorScheme colors) {
    return [
      BoxShadow(
        color: colors.shadow,
        blurRadius: 8,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static BoxDecoration card(
    AppColorScheme colors, {
    BorderRadius? borderRadius,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? colors.card,
      borderRadius: borderRadius ?? borderRadiusLg,
      border: Border.all(color: colors.borderLight, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: colors.shadow,
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  /// AI 工具结果卡片：白天加强边框与阴影，夜间保持原有半透明底。
  static BoxDecoration agentResultCard(
    AppColorScheme colors, {
    required Brightness brightness,
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? borderRadiusLg;
    if (brightness == Brightness.light) {
      return BoxDecoration(
        color: colors.card,
        borderRadius: radius,
        border: Border.all(color: colors.border, width: 0.75),
        boxShadow: softShadow(colors, blur: 10),
      );
    }
    return BoxDecoration(
      color: colors.surfaceMuted.withValues(alpha: 0.35),
      borderRadius: radius,
      border: Border.all(color: colors.border, width: 0.6),
      boxShadow: [
        BoxShadow(
          color: colors.shadow.withValues(alpha: 0.35),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  /// AI 结果卡片内的嵌套块（评论预览、像素画框等）。
  static BoxDecoration agentResultInset(
    AppColorScheme colors, {
    required Brightness brightness,
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? borderRadiusMd;
    if (brightness == Brightness.light) {
      return BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: radius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.7),
          width: 0.5,
        ),
      );
    }
    return BoxDecoration(
      color: colors.surfaceMuted,
      borderRadius: radius,
      border: Border.all(color: colors.borderLight, width: 0.5),
    );
  }

  static BoxDecoration glassCard(
    AppColorScheme colors, {
    BorderRadius? borderRadius,
    Color? tint,
  }) {
    return BoxDecoration(
      color: tint ?? colors.glassFill,
      borderRadius: borderRadius ?? borderRadiusLg,
      border: Border.all(color: colors.border, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: colors.shadow,
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  static BoxDecoration bottomNav() {
    return const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x1A000000), width: 0.5)),
    );
  }
}
