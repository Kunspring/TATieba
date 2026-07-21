import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

class BaiduQrLoginService {
  static const headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://passport.baidu.com/',
  };

  static String _generateGid() {
    final hex = '0123456789abcdef';
    final rng = Random();
    return List.generate(32, (_) => hex[rng.nextInt(16)]).join();
  }

  static Map<String, dynamic> _parseResponseBody(String body) {
    final trimmed = body.trim();
    final jsonpMatch = RegExp(
      r'^\w+\((.*)\)\s*$',
      dotAll: true,
    ).firstMatch(trimmed);
    final jsonStr = jsonpMatch?.group(1) ?? trimmed;
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw Exception('二维码数据格式异常');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String _normalizeImgUrl(String raw, String sign) {
    var url = raw.replaceAll(r'\/', '/').trim();
    if (url.isEmpty) {
      url = 'passport.baidu.com/v2/api/qrcode?sign=$sign&lp=pc&qrloginfrom=pc';
    }
    if (!url.startsWith('http')) {
      url = 'https://$url';
    }
    return url;
  }

  static Future<QrLoginResult> getQrCode() async {
    final gid = _generateGid();
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final resp = await http
        .get(
          Uri.parse(
            'https://passport.baidu.com/v2/api/getqrcode'
            '?lp=pc&qrloginfrom=pc&gid=$gid&apiver=v3&tpl=tb&tt=$ts&_=$ts',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('获取二维码失败: HTTP ${resp.statusCode}');
    }
    final data = _parseResponseBody(resp.body);
    final errno = data['errno'];
    if (errno != null && errno != 0 && errno != '0') {
      throw Exception('获取二维码失败: errno=$errno');
    }
    final sign = data['sign']?.toString() ?? '';
    if (sign.isEmpty) throw Exception('二维码数据异常: sign为空');
    final imgUrl = _normalizeImgUrl(data['imgurl']?.toString() ?? '', sign);
    return QrLoginResult(sign: sign, imgUrl: imgUrl);
  }

  static Future<List<int>> fetchQrImageBytes(String imgUrl) async {
    final resp = await http
        .get(Uri.parse(imgUrl), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
      throw Exception('二维码图片加载失败: HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  static Future<LoginPollResult> pollQrStatus(String sign) async {
    try {
      final gid = _generateGid();
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final callback = 'bd__cbs__${gid.substring(0, 8)}';
      final resp = await http
          .get(
            Uri.parse(
              'https://passport.baidu.com/channel/unicast'
              '?channel_id=$sign&channel_from=&apiver=v3'
              '&callback=$callback&gid=$gid&tpl=tb&lp=pc&tt=$ts',
            ),
            headers: headers,
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return LoginPollResult(status: PollStatus.error);
      }
      final text = resp.body;
      final errnoMatch = RegExp(r'"errno":([\-0-9]+)').firstMatch(text);
      if (errnoMatch == null) return LoginPollResult(status: PollStatus.error);
      final errno = int.parse(errnoMatch.group(1)!);
      if (errno == 1) {
        return LoginPollResult(status: PollStatus.waiting);
      }
      if (errno != 0) {
        return LoginPollResult(status: PollStatus.error);
      }
      final channelMatch = RegExp(r'"channel_v":"(.*)"}\)').firstMatch(text);
      if (channelMatch == null)
        return LoginPollResult(status: PollStatus.error);
      final raw = channelMatch
          .group(1)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
      final channelV = jsonDecode(raw);
      if (channelV['status'] == true) {
        return LoginPollResult(status: PollStatus.waiting);
      }
      final bduss = channelV['v'] ?? '';
      if (bduss.isEmpty) return LoginPollResult(status: PollStatus.error);
      return LoginPollResult(status: PollStatus.scanned, bdussToken: bduss);
    } catch (_) {
      return LoginPollResult(status: PollStatus.error);
    }
  }

  static Future<BaiduUserInfo> getBaiduUserInfo(String bdussToken) async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final resp = await http
        .get(
          Uri.parse(
            'https://passport.baidu.com/v3/login/main/qrbdusslogin'
            '?bduss=$bdussToken&loginVersion=v4&qrcode=1&tpl=tb&apiver=v3&tt=$ts',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final text = resp.body;

    String jsonStr = text;
    final jsonpMatch = RegExp(r'\((\{.*\})\)', dotAll: true).firstMatch(text);
    if (jsonpMatch != null) {
      jsonStr = jsonpMatch.group(1)!;
    }

    jsonStr = jsonStr
        .replaceAll(RegExp(r"'([^']+)'"), r'"$1"')
        .replaceAll(r'&amp;', '&')
        .replaceAll(r'&quot;', '"')
        .replaceAll(r'&lt;', '<')
        .replaceAll(r'&gt;', '>')
        .replaceAll(r'\"', '"');

    jsonStr = jsonStr.replaceAllMapped(
      RegExp(r'"(\w+)":\s*"\[([^\]]*)\]"'),
      (m) => '"${m[1]}": "${m[2]?.replaceAll('"', '\\"')}"',
    );

    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr);
    } catch (_) {
      final bdussMatch = RegExp(r'"bduss"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      final stokenMatch = RegExp(
        r'"stoken"\s*:\s*"([^"]+)"',
      ).firstMatch(jsonStr);
      final usernameMatch = RegExp(
        r'"userName"\s*:\s*"([^"]+)"',
      ).firstMatch(jsonStr);
      final displayNameMatch = RegExp(
        r'"displayName"\s*:\s*"([^"]+)"',
      ).firstMatch(jsonStr);
      final portraitMatch =
          RegExp(r'"portraitSign"\s*:\s*"([^"]+)"').firstMatch(jsonStr) ??
          RegExp(r'"portrait"\s*:\s*"([^"]+)"').firstMatch(jsonStr);

      if (bdussMatch != null) {
        return BaiduUserInfo(
          bduss: bdussMatch.group(1) ?? '',
          stoken: stokenMatch?.group(1) ?? '',
          ptoken: '',
          username: usernameMatch?.group(1) ?? '',
          displayName:
              displayNameMatch?.group(1) ?? usernameMatch?.group(1) ?? '',
          userId: '',
          portrait: portraitMatch?.group(1) ?? '',
        );
      }
      throw Exception('响应解析失败');
    }

    final code = data['code']?.toString() ?? data['errInfo']?.toString() ?? '';

    if (code != '110000' && code != '0') {
      throw Exception('登录失败: code=$code');
    }

    final rootData = data['\$1'] ?? data['data'] ?? {};
    final sessionData = rootData['session'] ?? rootData;
    final userData = rootData['user'] ?? {};

    final bduss = sessionData['bduss']?.toString() ?? bdussToken;
    final stoken = sessionData['stoken']?.toString() ?? '';
    final ptoken = sessionData['ptoken']?.toString() ?? '';
    final username = userData['username']?.toString() ?? '';
    final displayName =
        userData['displayName']?.toString() ??
        userData['displayname']?.toString() ??
        '';
    final userId = userData['userId']?.toString() ?? '';
    final portrait =
        userData['portraitSign']?.toString() ??
        userData['portrait']?.toString() ??
        '';

    if (bduss.isEmpty) {
      throw Exception('BDUSS为空');
    }

    return BaiduUserInfo(
      bduss: bduss,
      stoken: stoken,
      ptoken: ptoken,
      username: username,
      displayName: displayName.isNotEmpty ? displayName : username,
      userId: userId,
      portrait: portrait,
    );
  }
}

enum PollStatus { waiting, scanned, error }

class QrLoginResult {
  final String sign;
  final String imgUrl;
  QrLoginResult({required this.sign, required this.imgUrl});
}

class LoginPollResult {
  final PollStatus status;
  final String? bdussToken;
  LoginPollResult({required this.status, this.bdussToken});
}

class BaiduUserInfo {
  final String bduss;
  final String stoken;
  final String ptoken;
  final String username;
  final String displayName;
  final String userId;
  final String portrait;
  BaiduUserInfo({
    required this.bduss,
    required this.stoken,
    required this.ptoken,
    required this.username,
    required this.displayName,
    required this.userId,
    this.portrait = '',
  });
}
