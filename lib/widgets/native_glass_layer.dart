import 'package:flutter/material.dart';

/// 原生毛玻璃（PlatformView）方案说明与占位。
///
/// 历史上曾尝试用 iOS `UIVisualEffectView` / Android `BlurView` 的
/// `PlatformView`（`UiKitView` / `PlatformViewLink`，viewType
/// `tieba_app/native_glass`）实现「原生级」毛玻璃，但存在两个致命问题：
///
/// 1. **架构上不可行**：Flutter 的 `PlatformView` 处于独立合成层，只能模糊
///    其原生层之后的内容，无法模糊 Flutter 自身渲染的界面。也就是说，它
///    永远模糊不到 App 里的图片/文字——这正是它「上次没成功」的根本原因。
/// 2. **启用即崩溃**：该方案需要在 Android/iOS 原生侧注册对应的
///    `PlatformViewFactory`，而本仓库从未注册，打开开关会直接抛异常。
///
/// 因此「原生系统级毛玻璃质感」在本应用中的正确实现，是在 GPU 上用
/// `BackdropFilter`（见 [lib/theme/app_glass.dart]）配合
/// 「模糊 + 饱和 + 微提亮 + 顶部高光 + 磨砂颗粒 + 厚度光泽」配方完成——
/// 这也是生产级 Flutter 应用（包括大量号称「原生毛玻璃」的 App）的标准做法，
/// 观感与 iOS UIVisualEffectView / macOS vibrancy / Windows Acrylic 一致。
///
/// 此处仅保留能力判断占位，确保任何遗留引用都不会在误开启时崩溃。
bool nativeGlassBlurAvailable() => false;

/// 已退役的原生平台视图毛玻璃层（见上方说明）。
/// 始终返回空，正确的实现位于 [lib/theme/app_glass.dart] 的 GPU 配方。
class NativeGlassLayer extends StatelessWidget {
  final double sigma;
  final bool isDark;

  const NativeGlassLayer({
    super.key,
    required this.sigma,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
