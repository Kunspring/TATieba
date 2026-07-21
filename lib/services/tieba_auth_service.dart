import 'dart:convert';

import 'app_shell_controller.dart';
import 'sign_in_reminder_service.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_favorite_service.dart';

/// 统一完成贴吧登录：校验凭证、拉用户信息、持久化并通知全局刷新。
class TiebaAuthService {
  TiebaAuthService._();

  /// 贴吧 Lite 同款：登录成功后跳转到贴吧「我的」页，在 onPageFinished 读 Cookie 完成登录。
  static const mobileLoginUrl =
      'https://wappass.baidu.com/passport'
      '?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';

  /// 登录成功后的贴吧跳转页（与 [mobileLoginUrl] 中 u= 参数一致）。
  static const loginRedirectPrefixes = [
    'https://tieba.baidu.com/index/tbwise/',
    'https://tiebac.baidu.com/index/tbwise/',
  ];

  static bool isLoginRedirectUrl(String url) {
    final lower = url.trim().toLowerCase();
    return loginRedirectPrefixes.any((prefix) => lower.startsWith(prefix));
  }

  static const _loginSucceedPrefix = 'sapi://loginsucceed';
  static const _loginFailedPrefix = 'sapi://loginfailed';

  static bool isLoginSucceedCallback(String url) =>
      url.toLowerCase().startsWith(_loginSucceedPrefix);

  static bool isLoginFailedCallback(String url) =>
      url.toLowerCase().startsWith(_loginFailedPrefix);

  /// 从 bridge 回调 / sapi URL / XML 片段中解析 BDUSS。
  static ({String bduss, String? stoken, String? uid})?
  parseCredentialsFromPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    if (isLoginSucceedCallback(text) ||
        text.toLowerCase().contains('loginsucceed')) {
      final fromUrl = parseLoginSucceedUrl(text);
      if (fromUrl != null) return fromUrl;
    }

    String? tag(String name) {
      final match = RegExp(
        '<$name>(.*?)</$name>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(text);
      final value = match?.group(1);
      if (value == null || value.isEmpty) return null;
      return _decodeCredential(value);
    }

    var bduss = tag('bduss');
    var stoken = tag('stoken');
    final uid = tag('uid');
    if (bduss != null && bduss.isNotEmpty) {
      return (bduss: bduss, stoken: stoken, uid: uid);
    }

    final jsonStart = text.indexOf('{');
    if (jsonStart >= 0) {
      final tail = text.substring(jsonStart);
      final end = tail.lastIndexOf('}');
      if (end > 0) {
        try {
          final decoded = jsonDecode(tail.substring(0, end + 1));
          if (decoded is Map) {
            final nested = decoded['result'] ?? decoded['data'] ?? decoded;
            if (nested is Map) {
              bduss =
                  nested['bduss']?.toString() ?? nested['BDUSS']?.toString();
              stoken =
                  nested['stoken']?.toString() ?? nested['STOKEN']?.toString();
            } else if (nested is String) {
              return parseCredentialsFromPayload(nested);
            }
            if (bduss != null && bduss.isNotEmpty) {
              return (
                bduss: _decodeCredential(bduss),
                stoken: stoken != null && stoken.isNotEmpty
                    ? _decodeCredential(stoken)
                    : null,
                uid: decoded['uid']?.toString(),
              );
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// 解析 `sapi://loginSucceed` 回调（贴吧 Lite / 官方客户端同款）。
  static ({String bduss, String? stoken, String? uid})? parseLoginSucceedUrl(
    String url,
  ) {
    if (!isLoginSucceedCallback(url) &&
        !url.toLowerCase().contains('loginsucceed')) {
      return null;
    }

    String? tag(String name) {
      final match = RegExp(
        '<$name>(.*?)</$name>',
        caseSensitive: false,
      ).firstMatch(url);
      final value = match?.group(1);
      if (value == null || value.isEmpty) return null;
      return value;
    }

    var bduss = tag('bduss');
    var stoken = tag('stoken');
    final uid = tag('uid');

    if (bduss != null && bduss.isNotEmpty) {
      return (
        bduss: _decodeCredential(bduss),
        stoken: stoken != null && stoken.isNotEmpty
            ? _decodeCredential(stoken)
            : null,
        uid: uid,
      );
    }

    final jsonStart = url.indexOf('{');
    if (jsonStart >= 0) {
      final tail = url.substring(jsonStart);
      final end = tail.lastIndexOf('}');
      if (end > 0) {
        try {
          final decoded = jsonDecode(tail.substring(0, end + 1));
          if (decoded is Map) {
            final nested = decoded['result'] ?? decoded['data'] ?? decoded;
            if (nested is Map) {
              bduss =
                  nested['bduss']?.toString() ?? nested['BDUSS']?.toString();
              stoken =
                  nested['stoken']?.toString() ?? nested['STOKEN']?.toString();
            } else if (nested is String) {
              return parseCredentialsFromPayload(nested);
            } else {
              bduss =
                  decoded['bduss']?.toString() ?? decoded['BDUSS']?.toString();
              stoken =
                  decoded['stoken']?.toString() ??
                  decoded['STOKEN']?.toString();
            }
            final parsedUid =
                decoded['uid']?.toString() ?? decoded['UID']?.toString();
            if (bduss != null && bduss.isNotEmpty) {
              return (
                bduss: _decodeCredential(bduss),
                stoken: stoken != null && stoken.isNotEmpty
                    ? _decodeCredential(stoken)
                    : null,
                uid: parsedUid,
              );
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

  static String _decodeCredential(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static const cookieOrigins = [
    'https://wappass.baidu.com',
    'https://tieba.baidu.com',
    'https://tiebac.baidu.com',
    'https://www.baidu.com',
    'https://passport.baidu.com',
  ];

  static String? cookieValue(
    Iterable<({String name, String value})> cookies,
    String name,
  ) {
    final target = name.toLowerCase();
    for (final cookie in cookies) {
      if (cookie.name.toLowerCase() == target && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return null;
  }

  static ({String bduss, String? stoken})? extractCredentials(
    Iterable<({String name, String value})> cookies, {
    bool requireStoken = false,
  }) {
    final bduss = cookieValue(cookies, 'BDUSS');
    if (bduss == null || bduss.isEmpty) return null;
    final stoken = cookieValue(cookies, 'STOKEN');
    if (requireStoken && (stoken == null || stoken.isEmpty)) return null;
    return (bduss: bduss, stoken: stoken);
  }

  static Future<void> completeLogin({
    required String bduss,
    String? stoken,
  }) async {
    final valid = await TiebaClient.isSessionValid(bduss, stoken: stoken);
    if (!valid) {
      throw TiebaAuthException('登录凭证无效或已过期');
    }

    final profile = await TiebaClient.fetchSelfProfile(bduss: bduss);
    final nick = profile?['nick_name']?.toString().trim();
    final userName = profile?['user_name']?.toString().trim();
    final displayName = (nick != null && nick.isNotEmpty)
        ? nick
        : (userName != null && userName.isNotEmpty ? userName : '用户');

    await TiebaAccountService.bind(
      bduss: bduss,
      stoken: stoken,
      userName: userName,
      tiebaName: displayName,
      portrait: profile?['portrait']?.toString(),
    );
    await TiebaAccountService.refreshTbs();
    await SignInReminderService.instance.onLoginChanged();
    TiebaFavoriteService.invalidateCache();
    AppShellController.instance.onLoginChanged?.call();
  }
}

class TiebaAuthException implements Exception {
  final String message;
  TiebaAuthException(this.message);

  @override
  String toString() => message;
}
