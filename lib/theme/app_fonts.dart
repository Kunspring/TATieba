import 'package:flutter/material.dart';

abstract final class AppFonts {
  AppFonts._();

  static const double letterSpacingChinese = 0.3;
  static const double letterSpacingEnglish = -0.2;
  static const double lineHeightTight = 1.3;
  static const double lineHeightNormal = 1.5;
  static const double lineHeightRelaxed = 1.55;

  static TextStyle _withDefaults({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double height = 1.5,
    double letterSpacing = 0.0,
    Color? color,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static TextStyle display({Color? color}) => _withDefaults(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: lineHeightTight,
    letterSpacing: letterSpacingEnglish,
    color: color,
  );

  static TextStyle headline({Color? color}) => _withDefaults(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: lineHeightTight,
    letterSpacing: letterSpacingEnglish,
    color: color,
  );

  static TextStyle title({Color? color}) => _withDefaults(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: lineHeightNormal,
    letterSpacing: letterSpacingChinese,
    color: color,
  );

  static TextStyle body({Color? color}) => _withDefaults(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: lineHeightRelaxed,
    letterSpacing: letterSpacingChinese,
    color: color,
  );

  static TextStyle bodySmall({Color? color}) => _withDefaults(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: lineHeightNormal,
    letterSpacing: letterSpacingChinese,
    color: color,
  );

  static TextStyle caption({Color? color}) => _withDefaults(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: lineHeightNormal,
    letterSpacing: letterSpacingChinese,
    color: color,
  );

  static TextStyle label({Color? color}) => _withDefaults(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
    color: color,
  );

  static TextStyle button({Color? color}) => _withDefaults(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0.3,
    color: color,
  );

  static TextStyle numeric({Color? color}) => _withDefaults(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -0.3,
    color: color,
  );

  static TextStyle count({Color? color}) => _withDefaults(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -0.2,
    color: color,
  );
}
