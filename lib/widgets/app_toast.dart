import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'agent_companion/agent_companion_controller.dart';

export 'agent_companion/agent_companion_controller.dart' show AppToastType;

void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
}) {
  final companion = AgentCompanionScope.maybeOf(context);
  if (companion != null) {
    companion.showToast(message, type);
    return;
  }

  _showSnackBarFallback(context, message, type: type);
}

void _showSnackBarFallback(
  BuildContext context,
  String message, {
  required AppToastType type,
}) {
  final colors = context.appColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: AppToastStyle.textColor(isDark, colors),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: AppToastStyle.backgroundColor(type, colors, isDark),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(seconds: 3),
    ),
  );
}

abstract final class AppToastStyle {
  AppToastStyle._();

  static Color baseColor(AppToastType type, AppColorScheme colors) {
    return switch (type) {
      AppToastType.success => AppColors.success,
      AppToastType.error => AppColors.error,
      AppToastType.info => colors.primary,
      AppToastType.warning => Colors.orange,
    };
  }

  static Color backgroundColor(
    AppToastType type,
    AppColorScheme colors,
    bool isDark,
  ) {
    return baseColor(type, colors).withValues(alpha: isDark ? 0.85 : 0.9);
  }

  static Color textColor(bool isDark, AppColorScheme colors) {
    return isDark ? colors.textPrimary : Colors.white;
  }
}
