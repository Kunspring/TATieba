import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Runtime glass tuning for standard glass UI.
///
/// 朴素毛玻璃：仅 BackdropFilter 模糊 + 半透明染色，不做额外色彩/颗粒/
/// 高光处理，以控制 GPU 开销。
class AppGlassConfig {
  const AppGlassConfig({
    required this.backdropBlurSigma,
    required this.backdropBlurSigmaStrong,
    required this.dockBlurSigma,
    required this.backdropBlurPanels,
    required this.backdropBlurDock,
    required this.backdropBlurAppBar,
    required this.fillAlpha,
    required this.fillAlphaStrong,
    required this.borderWidth,
  });

  final double backdropBlurSigma;
  final double backdropBlurSigmaStrong;
  final double dockBlurSigma;

  final bool backdropBlurPanels;
  final bool backdropBlurDock;
  final bool backdropBlurAppBar;
  final double fillAlpha;
  final double fillAlphaStrong;
  final double borderWidth;

  // 毛玻璃策略（2026-07-08 已彻底关闭模糊）：
  // - 三个模糊开关全部置 false → _GlassFrosting 中 sigma==0 → blurOn=false →
  //   不创建任何 BackdropFilter，所有玻璃面退化为半透明色块，零 GPU 模糊开销。
  // - 用户实测「仅固定栏模糊」在真机仍明显卡顿，故整体降级为色块。
  // - 若后续想恢复：按「固定栏优先」只把 backdropBlurAppBar / backdropBlurDock
  //   置 true（面板 backdropBlurPanels 保持 false，因其覆盖滚动内容会每帧重算）。
  static const current = AppGlassConfig(
    backdropBlurSigma: 10,
    backdropBlurSigmaStrong: 12,
    dockBlurSigma: 10,
    backdropBlurPanels: false,
    backdropBlurDock: false,
    backdropBlurAppBar: false,
    fillAlpha: 1,
    fillAlphaStrong: 1,
    borderWidth: 0.75,
  );

  Color glassFill(AppColorScheme colors, {bool strong = false}) {
    final base = strong ? colors.glassFillStrong : colors.glassFill;
    final alphaScale = strong ? fillAlphaStrong : fillAlpha;
    if (alphaScale >= 0.99) return base;
    return base.withValues(alpha: base.a * alphaScale);
  }
}

extension AppGlassConfigContext on BuildContext {
  AppGlassConfig get glassConfig => AppGlassConfig.current;
}
