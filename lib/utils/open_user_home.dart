import 'package:flutter/material.dart';

import '../screens/user/user_home_page.dart';
import '../services/app_ui_context.dart';
import '../services/tieba_client.dart';

/// 打开用户主页（Lite 同款入口）。
Future<void> openUserHome(
  BuildContext context, {
  String? portrait,
  String? userName,
  String? authorAvatar,
  String? barName,
  bool isSelf = false,
}) {
  if (isSelf) {
    return Navigator.of(context).push(
      uiPageRoute(
        name: AppUiRouteNames.userHome,
        arguments: {
          if (userName != null && userName.trim().isNotEmpty)
            'user_name': userName.trim(),
          'is_self': true,
        },
        builder: (_) => UserHomePage(
          portrait: portrait,
          userName: userName,
          barName: barName,
          isSelf: true,
        ),
      ),
    );
  }
  final resolvedPortrait =
      portrait ?? TiebaClient.portraitFromAvatarUrl(authorAvatar);
  final resolvedUserName = userName?.trim();
  if ((resolvedPortrait == null || resolvedPortrait.isEmpty) &&
      (resolvedUserName == null || resolvedUserName.isEmpty)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开该用户主页')));
    return Future.value();
  }
  return Navigator.of(context).push(
    uiPageRoute(
      name: AppUiRouteNames.userHome,
      arguments: {
        if (resolvedUserName != null && resolvedUserName.isNotEmpty)
          'user_name': resolvedUserName,
      },
      builder: (_) => UserHomePage(
        portrait: resolvedPortrait,
        userName: resolvedUserName,
        barName: barName,
        isSelf: false,
      ),
    ),
  );
}
