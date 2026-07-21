import 'package:flutter/material.dart';

abstract final class AppIcons {
  static const settingsAsset = 'assets/settings_icon.png';

  static IconData get add => Icons.add_rounded;
  static IconData get arrowBack => Icons.arrow_back;
  static IconData get autoRenew => Icons.autorenew;
  static IconData get bookmark => Icons.bookmark;
  static IconData get bookmarkBorder => Icons.bookmark_border;
  static IconData get bookmarkOutline => Icons.bookmark_outline;
  static IconData get close => Icons.close;
  static IconData get deleteOutline => Icons.delete_outline;
  static IconData get emojiEmotions => Icons.emoji_emotions_outlined;
  static IconData get errorOutline => Icons.error_outline;
  static IconData get forum => Icons.forum_outlined;
  static IconData get moreVert => Icons.more_vert;
  static IconData get reply => Icons.reply;
  static IconData get search => Icons.search;
  static IconData get settings => Icons.settings_outlined;
  static IconData get thumbUp => Icons.thumb_up;
  static IconData get thumbUpOutline => Icons.thumb_up_outlined;
  static IconData get favorite => Icons.favorite;
  static IconData get favoriteBorder => Icons.favorite_border;
  static IconData get person => Icons.person;
}

/// 自定义设置齿轮图标（assets/settings_icon.png）。
class AppSettingsIcon extends StatelessWidget {
  const AppSettingsIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          AppIcons.settingsAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
