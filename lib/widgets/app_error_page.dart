import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';

/// 全局崩溃兜底页：替代 Flutter 默认红屏（`ErrorWidget.builder` 调用）。
///
/// 重要约束：本 widget 在 build/layout/paint 出错时被框架插入渲染树，
/// 此时 [Theme] / [MediaQuery] / [Navigator] 可能不可用。因此**不得**依赖
/// 这些（不使用 [SafeArea]、[Scaffold]、依赖 [Theme] 的按钮等），否则会触发
/// 二次崩溃，反而比红屏更糟。颜色全部自包含，仅通过 platformBrightness
/// 自适应明暗。
class AppErrorPage extends StatelessWidget {
  const AppErrorPage({super.key, this.details, this.onRetry});

  final FlutterErrorDetails? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        ui.Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF7F7F7);
    final fg = isDark ? const Color(0xFFEAEAEA) : const Color(0xFF222222);
    final sub = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666);
    final accent = isDark ? const Color(0xFF6E8BFF) : const Color(0xFF3B6FE0);

    final exception = details?.exceptionAsString() ?? '';
    final stack = details?.stack?.toString() ?? '';

    return ColoredBox(
      color: bg,
      child: Center(
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 54, color: sub),
              const SizedBox(height: 20),
              Text(
                '出了点小问题',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '应用遇到了一个意外错误。你可以尝试返回首页，或重启应用。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: sub),
              ),
              const SizedBox(height: 24),
              _ErrorActionButton(
                label: '返回首页',
                color: accent,
                onTap: () {
                  try {
                    onRetry?.call();
                  } catch (_) {
                    // 导航栈不可用时尽力而为，忽略。
                  }
                },
              ),
              if (kDebugMode && exception.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sub.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Text(
                      '$exception\n\n$stack',
                      style: TextStyle(
                        fontSize: 11,
                        color: sub,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 自绘按钮，避免依赖 [Theme]（错误上下文下 [Theme] 可能不可用）。
class _ErrorActionButton extends StatelessWidget {
  const _ErrorActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
