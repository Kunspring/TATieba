import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const primary = Color(0xFF000000);
  static const primaryDark = Color(0xFF000000);
  static const primaryLight = Color(0xFFF0F0F0);
  static const primaryHover = Color(0xFFE0E0E0);
  static const scaffold = Color(0xFFF2F3F5);
  static const appBar = Color(0xFFE0E3E8);
  static const card = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFE8EAED);
  static const border = Color(0xFFDDDDDD);
  static const borderLight = Color(0xFFEEEEEE);
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0xFF666666);
  static const textMuted = Color(0xFF999999);
  static const divider = Color(0xFFE0E0E0);
  static const shadow = Color.fromRGBO(0, 0, 0, 0.06);
  static const navSelected = Color(0xFF000000);
  static const navUnselected = Color(0xFF8A919A);
  static const white = Colors.white;
  static const accent = Color(0xFF000000);
  static const searchBg = Color(0xFFF5F5F5);
  static const accentSubtle = Color(0xFFF0F0F0);
  static const focusYellow = Color(0xFF000000);
  static const error = Color(0xFFD32F2F);
  static const success = Color(0xFF388E3C);

  static const glassFill = Color(0x99FFFFFF);
  static const glassFillStrong = Color(0xBFFFFFFF);
  static const glassBorder = Color(0x38000000);
  static const glassHighlight = Color(0x80FFFFFF);

  static const darkPrimary = Color(0xFFFFFFFF);
  static const darkPrimaryDark = Color(0xFFE0E0E0);
  static const darkPrimaryLight = Color(0xFF333333);
  static const darkPrimaryHover = Color(0xFF444444);
  static const darkScaffold = Color(0xFF141414);
  static const darkAppBar = Color(0xFF0A0A0A);
  static const darkCard = Color(0xFF1E1E1E);
  static const darkSurfaceMuted = Color(0xFF252525);
  static const darkBorder = Color(0xFF555555);
  static const darkBorderLight = Color(0xFF444444);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFBBBBBB);
  static const darkTextMuted = Color(0xFF888888);
  static const darkDivider = Color(0xFF1F1F1F);
  static const darkShadow = Color.fromRGBO(0, 0, 0, 0.4);
  static const darkNavUnselected = Color(0xFF888888);
  static const darkAccent = Color(0xFFFFFFFF);
  static const darkSearchBg = Color(0xFF0A0A0A);
  static const darkGlassFill = Color(0x66141414);
  static const darkGlassFillStrong = Color(0x99141414);
  static const darkGlassBorder = Color(0x45FFFFFF);
  static const darkGlassHighlight = Color(0x18FFFFFF);
}

@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.scaffold,
    required this.appBar,
    required this.card,
    required this.surfaceMuted,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.shadow,
    required this.navSelected,
    required this.navUnselected,
    required this.accent,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.glassHighlight,
  });

  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color scaffold;
  final Color appBar;
  final Color card;
  final Color surfaceMuted;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color shadow;
  final Color navSelected;
  final Color navUnselected;
  final Color accent;
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color glassHighlight;

  static const light = AppColorScheme(
    borderLight: AppColors.borderLight,
    primary: AppColors.primary,
    primaryDark: AppColors.primaryDark,
    primaryLight: AppColors.primaryLight,
    scaffold: AppColors.scaffold,
    appBar: AppColors.appBar,
    card: AppColors.card,
    surfaceMuted: AppColors.surfaceMuted,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    divider: AppColors.divider,
    shadow: AppColors.shadow,
    navSelected: AppColors.navSelected,
    navUnselected: AppColors.navUnselected,
    accent: AppColors.accent,
    glassFill: AppColors.glassFill,
    glassFillStrong: AppColors.glassFillStrong,
    glassBorder: AppColors.glassBorder,
    glassHighlight: AppColors.glassHighlight,
  );

  static const dark = AppColorScheme(
    borderLight: AppColors.darkBorderLight,
    primary: AppColors.darkPrimary,
    primaryDark: AppColors.darkPrimaryDark,
    primaryLight: AppColors.darkPrimaryLight,
    scaffold: AppColors.darkScaffold,
    appBar: AppColors.darkAppBar,
    card: AppColors.darkCard,
    surfaceMuted: AppColors.darkSurfaceMuted,
    border: AppColors.darkBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textMuted: AppColors.darkTextMuted,
    divider: AppColors.darkDivider,
    shadow: AppColors.darkShadow,
    navSelected: AppColors.darkPrimary,
    navUnselected: AppColors.darkNavUnselected,
    accent: AppColors.darkAccent,
    glassFill: AppColors.darkGlassFill,
    glassFillStrong: AppColors.darkGlassFillStrong,
    glassBorder: AppColors.darkGlassBorder,
    glassHighlight: AppColors.darkGlassHighlight,
  );

  @override
  AppColorScheme copyWith({
    Color? borderLight,
    Color? primary,
    Color? primaryDark,
    Color? primaryLight,
    Color? scaffold,
    Color? appBar,
    Color? card,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? shadow,
    Color? navSelected,
    Color? navUnselected,
    Color? accent,
    Color? glassFill,
    Color? glassFillStrong,
    Color? glassBorder,
    Color? glassHighlight,
  }) {
    return AppColorScheme(
      borderLight: borderLight ?? this.borderLight,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryLight: primaryLight ?? this.primaryLight,
      scaffold: scaffold ?? this.scaffold,
      appBar: appBar ?? this.appBar,
      card: card ?? this.card,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      shadow: shadow ?? this.shadow,
      navSelected: navSelected ?? this.navSelected,
      navUnselected: navUnselected ?? this.navUnselected,
      accent: accent ?? this.accent,
      glassFill: glassFill ?? this.glassFill,
      glassFillStrong: glassFillStrong ?? this.glassFillStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      appBar: Color.lerp(appBar, other.appBar, t)!,
      card: Color.lerp(card, other.card, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      navSelected: Color.lerp(navSelected, other.navSelected, t)!,
      navUnselected: Color.lerp(navUnselected, other.navUnselected, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassFillStrong: Color.lerp(glassFillStrong, other.glassFillStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColorScheme get appColors =>
      Theme.of(this).extension<AppColorScheme>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppColorScheme.dark
          : AppColorScheme.light);
}
