import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 全局 UI 面板配置。
///
/// 2026-07-21 后已改为实色方案：所有玻璃面、AppBar、底栏、陪伴层、聊天页
/// 边框统一实色化，不再透出底层内容，零 BackdropFilter 开销。
class AppGlassConfig {
  const AppGlassConfig({
    required this.borderWidth,
  });

  final double borderWidth;

  /// 当前全局配置。
  static const current = AppGlassConfig(
    borderWidth: 0.75,
  );

  Color glassFill(AppColorScheme colors, {bool strong = false}) {
    return strong ? colors.glassFillStrong : colors.glassFill;
  }
}

extension AppGlassConfigContext on BuildContext {
  AppGlassConfig get glassConfig => AppGlassConfig.current;
}
