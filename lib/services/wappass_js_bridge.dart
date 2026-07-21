import 'tieba_auth_service.dart';

/// 百度 wappass 登录页通过 `prompt/alert/confirm` 与原生容器通信。
///
/// Android 登录成功时会 `prompt("{action:{name:'authorized_response',params:[xml]}}")`；
/// iOS 则走 `sapi://loginSucceed/...` 导航。两者都需由客户端消费，否则页面会一直「请等待」。
class WappassJsBridge {
  WappassJsBridge._();

  static bool isLoginHost(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.contains('wappass.baidu.com') ||
        host.contains('passport.baidu.com');
  }

  static bool looksLikeBridge(String message) {
    final text = message.trim();
    if (text.isEmpty) return false;
    if (TiebaAuthService.isLoginSucceedCallback(text) ||
        text.toLowerCase().contains('loginsucceed')) {
      return true;
    }
    return text.startsWith('{') && text.contains('action');
  }

  static String? parseActionName(String message) {
    final match = RegExp(
      r'''name\s*:\s*["']([^"']+)["']''',
    ).firstMatch(message);
    return match?.group(1);
  }

  static List<String> parseStringParams(String message) {
    final match = RegExp(
      r'''params\s*:\s*\[(.*)\]''',
      dotAll: true,
    ).firstMatch(message);
    if (match == null) return const [];
    return RegExp(r'''["']((?:\\.|[^"'])*)["']''')
        .allMatches(match.group(1)!)
        .map((m) => m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\"', '"'))
        .toList();
  }

  static String? extractSapiUrl(String message) {
    final match = RegExp(
      r'sapi://\S+',
      caseSensitive: false,
    ).firstMatch(message);
    final raw = match?.group(0);
    if (raw == null) return null;
    var url = raw;
    while (url.endsWith('"') || url.endsWith("'") || url.endsWith('}')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// 返回 `true` 表示已消费该 JS 对话框，调用方应静默返回默认值。
  static bool handle(
    String message, {
    void Function(String title)? onSetTitle,
    void Function(String payload)? onLoginPayload,
    void Function(String url)? onNavigate,
  }) {
    final text = message.trim();
    if (text.isEmpty) return false;

    final sapiUrl = extractSapiUrl(text);
    if (sapiUrl != null) {
      onNavigate?.call(sapiUrl);
      return true;
    }

    if (TiebaAuthService.isLoginSucceedCallback(text) ||
        TiebaAuthService.isLoginFailedCallback(text)) {
      onNavigate?.call(text);
      return true;
    }

    if (!looksLikeBridge(text)) return false;

    final action = parseActionName(text);
    final params = parseStringParams(text);

    switch (action) {
      case 'action_set_title':
        if (params.isNotEmpty) {
          onSetTitle?.call(params.first);
        }
        return true;
      case 'authorized_response':
      case 'action_authorized_response':
        // 完整 prompt 字符串里含 XML/JSON，比只取 params 更可靠。
        onLoginPayload?.call(text);
        return true;
      case 'action_load_external_webview':
      case 'action_load_url':
      case 'action_open_url':
        if (params.isNotEmpty) {
          onNavigate?.call(params.first);
        }
        return true;
      default:
        if (TiebaAuthService.parseCredentialsFromPayload(text) != null) {
          onLoginPayload?.call(text);
          return true;
        }
        return true;
    }
  }
}
