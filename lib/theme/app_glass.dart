import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_fonts.dart';
import 'app_decorations.dart';
import 'app_glass_config.dart';
import '../utils/app_lifecycle_gate.dart';
import '../widgets/agent_companion/agent_companion_layer.dart';
import 'glass_app_bar_layout.dart';

/// 实色面板：不再使用 BackdropFilter，零 GPU 模糊开销。
class _SolidPanel extends StatelessWidget {
  final Color fill;
  final Border border;
  final BorderRadiusGeometry? radius;
  final EdgeInsetsGeometry? padding;
  final Widget child;
  final List<BoxShadow>? boxShadow;

  const _SolidPanel({
    required this.fill,
    required this.border,
    required this.radius,
    this.padding,
    required this.child,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: border,
        color: fill,
        boxShadow: boxShadow,
      ),
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );
  }
}

Widget glassSurface({
  required AppColorScheme colors,
  required Widget child,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
  bool strong = false,
  Border? border,
  EdgeInsetsGeometry? padding,
  Color? fillOverride,
  List<BoxShadow>? boxShadow,
}) {
  final config = AppGlassConfig.current;
  final fill = fillOverride ?? config.glassFill(colors, strong: strong);

  return _SolidPanel(
    fill: fill,
    border:
        border ??
        Border.all(color: colors.glassBorder, width: config.borderWidth),
    radius: borderRadius,
    padding: padding,
    boxShadow: boxShadow,
    child: child,
  );
}

Widget appBarSurface(AppColorScheme colors, {Color? fillColor}) {
  final config = AppGlassConfig.current;
  final fill = fillColor ?? config.glassFill(colors, strong: true);

  return _SolidPanel(
    fill: fill,
    border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
    radius: BorderRadius.zero,
    boxShadow: [
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.25),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ],
    child: const SizedBox.expand(),
  );
}

double glassTopInset(BuildContext context, {PreferredSizeWidget? appBar}) {
  return MediaQuery.paddingOf(context).top +
      (appBar?.preferredSize.height ?? kToolbarHeight);
}

abstract final class AppSystemUi {
  AppSystemUi._();

  static SystemUiOverlayStyle overlayFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // 系统栏透明会露出 Android 窗口默认纯黑底，启动瞬间像「背景变黑」。
    final scaffold = isDark ? AppColors.darkScaffold : AppColors.scaffold;
    final base = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return base.copyWith(
      statusBarColor: scaffold,
      systemNavigationBarColor: scaffold,
      systemNavigationBarDividerColor: scaffold,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static void apply(Brightness brightness) {
    SystemChrome.setSystemUIOverlayStyle(overlayFor(brightness));
  }
}

class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.appColors.scaffold, child: child);
  }
}

class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBody;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBody = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: extendBody,
        extendBodyBehindAppBar: appBar != null,
        appBar: appBar,
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<String> tabs;

  const GlassTabBar({super.key, required this.controller, required this.tabs});

  static const _tabHeight = 36.0;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _GlassTabShell(
        colors: colors,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final animIndex =
                controller.animation?.value ?? controller.index.toDouble();
            final effects = AppLifecycleGate.effectsEnabled;
            // 标签高亮跟随“已选定”的离散目标索引，与导航栏 / 进吧页
            // [GlassSegmentTabs] 行为一致：点击瞬间新标签即高亮，避免在滑动
            // 中点（≈0.5）出现两个标签同时变灰的闪烁。
            final selectedIndex = controller.index.toDouble();

            return _GlassSlidingTabTrack(
              count: tabs.length,
              // 指示器位置始终跟随 TabController 的连续动画值（animIndex）：
              // 点击时由 animateTo 的 280ms 缓动驱动平滑滑动；手动滑动
              // TabBarView 时跟随手指。这正是 Flutter 原生 TabBar 指示器的
              // 实现方式，与进吧页 / 导航栏 [GlassSegmentTabs] 的滑动观感一致。
              position: animIndex,
              animate: false,
              duration: effects
                  ? const Duration(milliseconds: 280)
                  : Duration.zero,
              height: _tabHeight,
              indicator: _glassTabIndicator(colors),
              labels: tabs,
              selectedIndexForStyle: selectedIndex,
              labelStyle: (selected) => AppFonts.button(
                color: selected ? colors.textPrimary : colors.textMuted,
              ),
              onTap: (index) {
                if (controller.index != index) {
                  // 与 [GlassSegmentTabs] 保持一致的缓动曲线。
                  controller.animateTo(index, curve: Curves.easeOutCubic);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class GlassSegmentOption<T> {
  final T value;
  final String label;

  const GlassSegmentOption({required this.value, required this.label});
}

/// 与用户主页 [GlassTabBar] 同款的胶囊分段选择（无需 TabController）。
class GlassSegmentTabs<T> extends StatelessWidget {
  final List<GlassSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry? margin;

  const GlassSegmentTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.margin = EdgeInsets.zero,
  });

  static const _tabHeight = 36.0;
  static const _animDuration = Duration(milliseconds: 280);

  int get _selectedIndex {
    final idx = options.indexWhere((o) => o.value == selected);
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = AppLifecycleGate.effectsEnabled;

    return Container(
      margin: margin,
      child: _GlassTabShell(
        colors: colors,
        child: _GlassSlidingTabTrack(
          count: options.length,
          position: _selectedIndex.toDouble(),
          animate: effects,
          duration: effects ? _animDuration : Duration.zero,
          height: _tabHeight,
          indicator: _glassTabIndicator(colors),
          labels: options.map((o) => o.label).toList(),
          selectedIndexForStyle: _selectedIndex.toDouble(),
          labelStyle: (selected) => AppFonts.button(
            color: selected ? colors.textPrimary : colors.textMuted,
          ),
          onTap: (index) {
            final value = options[index].value;
            if (value != selected) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _GlassSlidingTabTrack extends StatelessWidget {
  final int count;
  final double position;
  final bool animate;
  final Duration duration;
  final double height;
  final BoxDecoration indicator;
  final List<String> labels;
  final double selectedIndexForStyle;
  final TextStyle Function(bool selected) labelStyle;
  final ValueChanged<int> onTap;

  const _GlassSlidingTabTrack({
    required this.count,
    required this.position,
    required this.animate,
    this.duration = const Duration(milliseconds: 280),
    required this.height,
    required this.indicator,
    required this.labels,
    required this.selectedIndexForStyle,
    required this.labelStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / count;
        final indicatorLeft = position.clamp(0, count - 1) * slotWidth;

        Widget indicatorChild = IgnorePointer(
          child: DecoratedBox(decoration: indicator),
        );

        if (animate) {
          indicatorChild = AnimatedPositioned(
            duration: duration,
            curve: Curves.easeOutCubic,
            left: indicatorLeft,
            width: slotWidth,
            top: 0,
            height: height,
            child: indicatorChild,
          );
        } else {
          indicatorChild = Positioned(
            left: indicatorLeft,
            width: slotWidth,
            top: 0,
            height: height,
            child: indicatorChild,
          );
        }

        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              indicatorChild,
              Row(
                children: List.generate(count, (i) {
                  final selected = (selectedIndexForStyle - i).abs() < 0.5;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onTap(i),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        height: height,
                        child: Center(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle(selected),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

BoxDecoration _glassTabIndicator(AppColorScheme colors) {
  return BoxDecoration(
    color: colors.surfaceMuted,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: colors.borderLight, width: 0.5),
    boxShadow: [
      BoxShadow(
        color: colors.shadow,
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ],
  );
}

class _GlassTabShell extends StatelessWidget {
  final AppColorScheme colors;
  final Widget child;

  const _GlassTabShell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderLight, width: 0.5),
      ),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? titleText;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;
  final double? leadingWidth;
  final Color? fillColor;
  final bool showCompanion;
  final String? companionLayoutKey;
  final Color? companionColor;
  final bool useInlineCompanion;
  final bool centerTitle;

  const GlassAppBar({
    super.key,
    this.title,
    this.titleText,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
    this.leadingWidth,
    this.fillColor,
    this.showCompanion = true,
    this.companionLayoutKey,
    this.companionColor,
    this.useInlineCompanion = true,
    this.centerTitle = false,
  });

  static SystemUiOverlayStyle overlayStyleFor(BuildContext context) {
    return AppSystemUi.overlayFor(Theme.of(context).brightness);
  }

  static String? _readTitleText(Widget? title) {
    if (title is Text) {
      return title.data ?? title.textSpan?.toPlainText();
    }
    return null;
  }

  static double _estimateActionsWidth(List<Widget>? actions) {
    if (actions == null || actions.isEmpty) return 0;
    var total = 0.0;
    for (final action in actions) {
      total += _estimateWidgetWidth(action);
    }
    return total;
  }

  static double _estimateWidgetWidth(Widget widget) {
    if (widget is SizedBox) {
      if (widget.width != null) return widget.width!;
      if (widget.child != null) return _estimateWidgetWidth(widget.child!);
      return 0;
    }
    if (widget is Padding) {
      var padH = 0.0;
      final padding = widget.padding;
      if (padding is EdgeInsets) {
        padH = padding.horizontal;
      } else if (padding is EdgeInsetsDirectional) {
        padH = padding.start + padding.end;
      }
      return padH +
          _estimateWidgetWidth(widget.child ?? const SizedBox.shrink());
    }
    if (widget is Row) {
      var width = 0.0;
      for (final child in widget.children) {
        width += _estimateWidgetWidth(child);
      }
      return width;
    }
    if (widget is Text) {
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: widget.style),
        maxLines: widget.maxLines ?? 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }
    if (widget is IconButton) return 48;
    if (widget is TextButton) {
      return _estimateWidgetWidth(widget.child ?? const SizedBox.shrink()) + 24;
    }
    if (widget is FilledButton) {
      return _estimateWidgetWidth(widget.child ?? const SizedBox.shrink()) + 32;
    }
    if (widget is OutlinedButton) {
      return _estimateWidgetWidth(widget.child ?? const SizedBox.shrink()) + 32;
    }
    if (widget is GestureDetector) {
      return _estimateWidgetWidth(widget.child ?? const SizedBox.shrink());
    }
    if (widget is CircularProgressIndicator) {
      return 18;
    }
    if (widget is Icon) return 24;
    return 48;
  }

  static Widget? _prepareTitle(
    Widget? title,
    bool reserveCompanionSpace, {
    double? maxWidth,
  }) {
    if (title == null) return null;
    Widget child = title;
    if (title is Text) {
      child = Text(
        title.data ?? title.textSpan?.toPlainText() ?? '',
        style: title.style,
        strutStyle: title.strutStyle,
        textAlign: TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (reserveCompanionSpace && maxWidth != null && maxWidth > 0) {
      child = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overlay = overlayStyleFor(context);
    final resolvedTitleText = titleText ?? _readTitleText(title);
    final resolvedLeadingWidth = leadingWidth ?? kToolbarHeight;
    final resolvedActionsWidth = _estimateActionsWidth(actions);
    final resolvedTitle = title is Text ? title as Text : null;
    final titleStyle =
        resolvedTitle?.style ?? AppFonts.title(color: colors.textPrimary);
    final titleMaxWidth = showCompanion
        ? CompanionBarLayout.titleMaxWidthForBar(
            barWidth: MediaQuery.sizeOf(context).width,
            leadingWidth: resolvedLeadingWidth,
            actionsWidth: resolvedActionsWidth,
          )
        : null;

    return GlassAppBarLayout(
      titleText: showCompanion ? resolvedTitleText : null,
      titleStyle: titleStyle,
      leadingWidth: resolvedLeadingWidth,
      actionsWidth: resolvedActionsWidth,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: AppBar(
          clipBehavior: Clip.none,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: overlay,
          automaticallyImplyLeading: automaticallyImplyLeading,
          centerTitle: centerTitle,
          toolbarHeight: toolbarHeight,
          leadingWidth: leadingWidth,
          leading: leading,
          title: _prepareTitle(title, showCompanion, maxWidth: titleMaxWidth),
          actions: actions,
          flexibleSpace: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              appBarSurface(colors, fillColor: fillColor),
              if (showCompanion) ...[
                CompanionBarLayoutReporter(
                  layoutKey: companionLayoutKey,
                  titleText: resolvedTitleText,
                  titleStyle: titleStyle,
                  leadingWidth: resolvedLeadingWidth,
                  actionsWidth: resolvedActionsWidth,
                  companionColor: companionColor,
                ),
                if (companionLayoutKey == 'agent-chat' && useInlineCompanion)
                  InlineBarCompanion(
                    titleText: resolvedTitleText,
                    titleStyle: titleStyle,
                    leadingWidth: resolvedLeadingWidth,
                    actionsWidth: resolvedActionsWidth,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    final height = toolbarHeight ?? kToolbarHeight;
    return Size.fromHeight(height);
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? tint;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = borderRadius ?? AppDecorations.borderRadiusLg;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: radius,
        border: Border.all(color: colors.borderLight, width: 0.5),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: tint != null
            ? ColoredBox(color: tint!.withValues(alpha: 0.08), child: child)
            : child,
      ),
    );

    if (onTap != null || onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppDecorations.softShadow(colors, blur: 8),
        ),
        child: content,
      ),
    );
  }
}

class GlassBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavItem> items;
  final bool snapSelection;

  const GlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
    this.snapSelection = false,
  });

  static const selectionAnimDuration = Duration(milliseconds: 280);
  static const _navTrackHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final effects = AppLifecycleGate.effectsEnabled;
    final animDuration = effects && !snapSelection
        ? selectionAnimDuration
        : Duration.zero;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
                if (isLight) ...[
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ] else ...[
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ],
              ],
        ),
        child: RepaintBoundary(
          child: glassSurface(
            colors: colors,
            borderRadius: BorderRadius.circular(28),
            strong: true,
            border: Border.all(
              color: colors.borderLight,
              width: 1,
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: SizedBox(
              height: _navTrackHeight,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = items.length;
                  final slotWidth = constraints.maxWidth / count;
                  const inset = 2.0;
                  final indicatorLeft = selectedIndex * slotWidth + inset;
                  final indicatorWidth = slotWidth - inset * 2;

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      AnimatedPositioned(
                        duration: animDuration,
                        curve: Curves.easeOutCubic,
                        left: indicatorLeft,
                        width: indicatorWidth,
                        top: 0,
                        height: _navTrackHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: isLight
                                  ? colors.card
                                  : colors.surfaceMuted,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isLight
                                    ? colors.borderLight
                                    : colors.glassBorder,
                                width: 0.5,
                              ),
                              boxShadow: isLight
                                  ? [
                                      BoxShadow(
                                        color: colors.shadow,
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(count, (i) {
                          return Expanded(
                            child: _GlassNavCell(
                              item: items[i],
                              selected: i == selectedIndex,
                              isLight: isLight,
                              colors: colors,
                              animDuration: animDuration,
                              trackHeight: _navTrackHeight,
                              onTap: () => onDestinationSelected(i),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavCell extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final bool isLight;
  final AppColorScheme colors;
  final Duration animDuration;
  final double trackHeight;
  final VoidCallback onTap;

  const _GlassNavCell({
    required this.item,
    required this.selected,
    required this.isLight,
    required this.colors,
    required this.animDuration,
    required this.trackHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: trackHeight,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 22,
                    color: selected ? colors.navSelected : colors.navUnselected,
                  ),
                  ClipRect(
                    child: AnimatedAlign(
                      duration: animDuration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      widthFactor: selected ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.navSelected,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.badgeCount > 0)
                Positioned(
                  right: selected ? -2 : -4,
                  top: -2,
                  child: _NavBadge(count: item.badgeCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  final int count;

  const _NavBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class GlassNavItem {
  final IconData icon;
  final String label;
  final int badgeCount;

  const GlassNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool strong;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.strong = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = borderRadius ?? AppDecorations.borderRadiusXl;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? colors.card : colors.surfaceMuted,
        borderRadius: radius,
        border: Border.all(color: colors.borderLight, width: 0.5),
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}
