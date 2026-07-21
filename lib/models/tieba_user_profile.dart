import '../utils/forum_level_style.dart';
import '../utils/json_parse.dart';

/// 贴吧用户主页资料（对齐 Lite 个人信息页字段）。
class TiebaUserProfile {
  final String? userId;
  final String portrait;
  final String userName;
  final String displayName;
  final String? intro;
  final int postCount;
  final int fanCount;
  final int followCount;
  final double? forumAgeYears;
  final bool isVip;
  final int? growthLevel;
  final int? forumLevel;
  final String? forumLevelName;
  final String? forumLevelBarName;
  final bool? isFollowedByMe;

  const TiebaUserProfile({
    this.userId,
    required this.portrait,
    required this.userName,
    required this.displayName,
    this.intro,
    this.postCount = 0,
    this.fanCount = 0,
    this.followCount = 0,
    this.forumAgeYears,
    this.isVip = false,
    this.growthLevel,
    this.forumLevel,
    this.forumLevelName,
    this.forumLevelBarName,
    this.isFollowedByMe,
  });

  String get avatarUrl {
    if (portrait.isEmpty) return '';
    if (portrait.startsWith('http')) return portrait;
    return 'https://himg.bdimg.com/sys/portrait/item/$portrait';
  }

  String? get forumAgeLabel {
    final age = forumAgeYears;
    if (age == null || age <= 0) return null;
    if (age >= 1) return '吧龄 ${age.toStringAsFixed(1)} 年';
    final days = (age * 365).round();
    if (days <= 0) return null;
    return '吧龄 $days 天';
  }

  String? get growthLevelLabel {
    final level = growthLevel;
    if (level == null || level <= 0) return null;
    return 'Lv.$level';
  }

  String? get forumLevelLabel {
    final label = ForumLevelStyle.displayLabel(
      level: forumLevel,
      levelName: forumLevelName,
    );
    return label.isEmpty ? null : label;
  }

  TiebaUserProfile copyWith({
    int? growthLevel,
    int? forumLevel,
    String? forumLevelName,
    String? forumLevelBarName,
    bool? isFollowedByMe,
  }) {
    return TiebaUserProfile(
      userId: userId,
      portrait: portrait,
      userName: userName,
      displayName: displayName,
      intro: intro,
      postCount: postCount,
      fanCount: fanCount,
      followCount: followCount,
      forumAgeYears: forumAgeYears,
      isVip: isVip,
      growthLevel: growthLevel ?? this.growthLevel,
      forumLevel: forumLevel ?? this.forumLevel,
      forumLevelName: forumLevelName ?? this.forumLevelName,
      forumLevelBarName: forumLevelBarName ?? this.forumLevelBarName,
      isFollowedByMe: isFollowedByMe ?? this.isFollowedByMe,
    );
  }

  factory TiebaUserProfile.fromApi(Map<String, dynamic> json) {
    final portrait = parseOptionalString(json['portrait']) ?? '';
    final userName = parseOptionalString(json['user_name']) ?? '';
    final nick =
        parseOptionalString(json['nick_name']) ??
        parseOptionalString(json['nick_name_new']) ??
        parseOptionalString(json['name_show']) ??
        parseOptionalString(json['displayName']);
    final displayName = (nick != null && nick.isNotEmpty) ? nick : userName;

    double? forumAge;
    final rawAge = json['forum_age'] ?? json['age'];
    if (rawAge is num) {
      forumAge = rawAge.toDouble();
    } else {
      forumAge = double.tryParse(rawAge?.toString() ?? '');
    }

    return TiebaUserProfile(
      userId: json['user_id']?.toString(),
      portrait: portrait,
      userName: userName,
      displayName: displayName.isNotEmpty ? displayName : '用户',
      intro:
          parseOptionalString(json['intro']) ??
          parseOptionalString(json['sign']),
      postCount: parseOptionalInt(json['post_num']) ?? 0,
      fanCount: parseOptionalInt(json['fans_num'] ?? json['fan_num']) ?? 0,
      followCount: parseOptionalInt(json['follow_num']) ?? 0,
      forumAgeYears: forumAge,
      isVip: json['is_vip'] == true || json['is_vip'] == 1,
      growthLevel: parseOptionalInt(json['growth_level'] ?? json['glevel']),
      forumLevel: parseOptionalInt(json['forum_level'] ?? json['level']),
      forumLevelName: parseOptionalString(
        json['forum_level_name'] ?? json['level_name'],
      ),
      forumLevelBarName: parseOptionalString(
        json['forum_level_bar'] ?? json['bar_name'],
      ),
    );
  }
}
