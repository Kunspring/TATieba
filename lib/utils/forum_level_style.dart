import 'package:flutter/material.dart';

/// 贴吧吧内等级配色（绿 / 蓝 / 橙 / 红，与官方客户端分段一致）。
class ForumLevelStyle {
  final Color backgroundColor;
  final Color textColor;
  final String tierLabel;

  const ForumLevelStyle({
    required this.backgroundColor,
    required this.textColor,
    required this.tierLabel,
  });

  static ForumLevelStyle forLevel(int level) {
    if (level <= 0) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFFE8E8E8),
        textColor: Color(0xFF666666),
        tierLabel: '',
      );
    }
    if (level <= 3) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFF59B954),
        textColor: Colors.white,
        tierLabel: '绿牌',
      );
    }
    if (level <= 6) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFF5BAFF1),
        textColor: Colors.white,
        tierLabel: '蓝牌',
      );
    }
    if (level <= 9) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFF2B89E6),
        textColor: Colors.white,
        tierLabel: '蓝牌',
      );
    }
    if (level <= 12) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFFFFA014),
        textColor: Colors.white,
        tierLabel: '黄牌',
      );
    }
    if (level <= 15) {
      return const ForumLevelStyle(
        backgroundColor: Color(0xFFFF6824),
        textColor: Colors.white,
        tierLabel: '黄牌',
      );
    }
    return const ForumLevelStyle(
      backgroundColor: Color(0xFFE02020),
      textColor: Colors.white,
      tierLabel: '红牌',
    );
  }

  static String displayLabel({int? level, String? levelName}) {
    final named = levelName?.trim();
    final hasLevel = level != null && level > 0;
    final levelText = hasLevel ? 'Lv.$level' : '';

    if (named != null && named.isNotEmpty) {
      if (!hasLevel) return named;
      if (_labelAlreadyContainsLevel(named, level)) return named;
      return '$named $levelText';
    }
    if (hasLevel) return levelText;
    return '';
  }

  static bool _labelAlreadyContainsLevel(String named, int level) {
    final lv = level.toString();
    return named.contains('Lv.$lv') ||
        named.contains('lv.$lv') ||
        named.contains('LV.$lv') ||
        named == lv ||
        named.endsWith('$lv级') ||
        named.endsWith('等级$lv');
  }

  static bool hasLevel({int? level, String? levelName}) {
    if (level != null && level > 0) return true;
    return levelName?.trim().isNotEmpty == true;
  }
}
