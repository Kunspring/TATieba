import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tieba_post.dart';
import '../models/bar_forum_context.dart';
import 'sign_in_progress_service.dart';
import 'tieba_client.dart';
import 'tieba_message_service.dart';

/// 本地已缓存的账号摘要，用于首屏免闪烁展示。
class TiebaAccountLocalSnapshot {
  final String? displayName;
  final String? accountName;
  final String? avatarUrl;

  const TiebaAccountLocalSnapshot({
    this.displayName,
    this.accountName,
    this.avatarUrl,
  });
}

class TiebaAccountService {
  static const String _bdussKey = 'tieba_bduss';
  static const String _stokenKey = 'tieba_stoken';
  static const String _userNameKey = 'tieba_username';
  static const String _tiebaNameKey = 'tieba_name';
  static const String _portraitKey = 'tieba_portrait';
  static const String _followedBarsKey = 'tieba_followed_bars';
  static const String _tbsKey = 'tieba_tbs';

  static bool? _cachedBound;
  static String? _cachedBduss;
  static String? _cachedStoken;
  static String? _cachedUserName;
  static String? _cachedTiebaName;
  static String? _cachedPortrait;
  static bool _cacheLoaded = false;

  /// 启动时预热本地凭证，避免个人页先闪「未登录」。
  static Future<void> warmFromDisk() async {
    if (_cacheLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _readCacheFromPrefs(prefs);
    _cacheLoaded = true;
  }

  static void _readCacheFromPrefs(SharedPreferences prefs) {
    _cachedBduss = prefs.getString(_bdussKey);
    _cachedStoken = prefs.getString(_stokenKey);
    _cachedUserName = prefs.getString(_userNameKey);
    _cachedTiebaName = prefs.getString(_tiebaNameKey);
    _cachedPortrait = prefs.getString(_portraitKey);
    _cachedBound = _cachedBduss != null && _cachedBduss!.isNotEmpty;
  }

  static Future<void> _ensureCache() async {
    if (_cacheLoaded) return;
    await warmFromDisk();
  }

  static String? portraitToUrl(String? portrait) {
    if (portrait == null || portrait.isEmpty) return null;
    return portrait.startsWith('http')
        ? portrait
        : 'https://himg.bdimg.com/sys/portrait/item/$portrait';
  }

  static TiebaAccountLocalSnapshot? get localSnapshot {
    if (_cachedBound != true) return null;
    final accountName = _cachedUserName;
    final nick = _cachedTiebaName;
    final displayName = nick != null && nick.isNotEmpty ? nick : accountName;
    return TiebaAccountLocalSnapshot(
      displayName: displayName,
      accountName: accountName,
      avatarUrl: portraitToUrl(_cachedPortrait),
    );
  }

  static Future<String?> getBduss() async {
    await _ensureCache();
    return _cachedBduss;
  }

  static Future<String?> getStoken() async {
    await _ensureCache();
    return _cachedStoken;
  }

  static bool _tbsFetchedThisSession = false;

  static Future<String> getTbs() async {
    if (!_tbsFetchedThisSession) {
      final refreshed = await refreshTbs();
      if (refreshed.isNotEmpty) return refreshed;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tbsKey) ?? '';
  }

  static Future<String> refreshTbs() async {
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return '';
    final tbs = await TiebaClient.fetchTbsToken(bduss);
    if (tbs.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tbsKey, tbs);
      _tbsFetchedThisSession = true;
    }
    return tbs;
  }

  static Future<String?> getTiebaUserName() async {
    await _ensureCache();
    return _cachedUserName;
  }

  static Future<String?> getTiebaName() async {
    await _ensureCache();
    return _cachedTiebaName;
  }

  static Future<String?> getPortrait() async {
    await _ensureCache();
    return _cachedPortrait;
  }

  static Future<bool> isBound() async {
    await _ensureCache();
    return _cachedBound == true;
  }

  static Future<void> bind({
    required String bduss,
    String? stoken,
    String? userName,
    String? tiebaName,
    String? portrait,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bdussKey, bduss);
    if (stoken != null) await prefs.setString(_stokenKey, stoken);
    if (userName != null) await prefs.setString(_userNameKey, userName);
    if (tiebaName != null) await prefs.setString(_tiebaNameKey, tiebaName);
    if (portrait != null) await prefs.setString(_portraitKey, portrait);
    await prefs.remove(_tbsKey);
    _tbsFetchedThisSession = false;
    _cachedBduss = bduss;
    _cachedStoken = stoken;
    _cachedUserName = userName;
    _cachedTiebaName = tiebaName;
    _cachedPortrait = portrait;
    _cachedBound = bduss.isNotEmpty;
    _cacheLoaded = true;
  }

  static Future<void> unbind() async {
    // 先断开 WS 连接，避免残留已认证的连接
    try {
      await TiebaMessageService.disposeConnection();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bdussKey);
    await prefs.remove(_stokenKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_tiebaNameKey);
    await prefs.remove(_portraitKey);
    await prefs.remove(_followedBarsKey);
    await prefs.remove(_tbsKey);
    _tbsFetchedThisSession = false;
    _cachedBduss = null;
    _cachedStoken = null;
    _cachedUserName = null;
    _cachedTiebaName = null;
    _cachedPortrait = null;
    _cachedBound = false;
    _cacheLoaded = true;
  }

  static Future<List<FollowedBar>> fetchFollowedBars() async {
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return [];
    try {
      final portrait = await getPortrait();
      if (portrait != null && portrait.isNotEmpty) {
        final names = await TiebaClient.fetchFollowedBarNames(bduss, portrait);
        if (names.isNotEmpty) {
          final avatarFutures = names.map(
            (n) => TiebaClient.fetchBarAvatarByFrs(n, bduss),
          );
          final avatars = await Future.wait(avatarFutures);
          final bars = <FollowedBar>[];
          for (int i = 0; i < names.length; i++) {
            bars.add(
              FollowedBar(name: names[i], id: '', avatar: avatars[i] ?? ''),
            );
          }
          await _saveFollowedBars(bars);
          return bars;
        }
      }
    } catch (_) {}
    return _getCachedFollowedBars();
  }

  static Future<void> _saveFollowedBars(List<FollowedBar> bars) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _followedBarsKey,
      jsonEncode(
        bars
            .map((b) => {'name': b.name, 'id': b.id, 'avatar': b.avatar})
            .toList(),
      ),
    );
  }

  static Future<List<FollowedBar>> _getCachedFollowedBars() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_followedBarsKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map(
            (e) => FollowedBar(
              name: e['name'] ?? '',
              id: e['id'] ?? '',
              avatar: e['avatar'] ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<TiebaPost>> fetchBarThreads(String barName) async {
    return TiebaClient.fetchBarThreadsForm(barName);
  }

  static Future<bool> followBar(String barName) async {
    final name = barName.trim();
    if (name.isEmpty) return false;
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return false;
    var tbs = await getTbs();
    if (tbs.isEmpty) return false;
    var ok = await TiebaClient.followBar(name, bduss, tbs);
    if (!ok) {
      tbs = await refreshTbs();
      if (tbs.isNotEmpty) {
        ok = await TiebaClient.followBar(name, bduss, tbs);
      }
    }
    if (ok) await fetchFollowedBars();
    return ok;
  }

  static Future<bool> unfollowBar(String barName) async {
    final name = barName.trim();
    if (name.isEmpty) return false;
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return false;
    var tbs = await getTbs();
    if (tbs.isEmpty) return false;
    var ok = await TiebaClient.unfollowBar(name, bduss, tbs);
    if (!ok) {
      tbs = await refreshTbs();
      if (tbs.isNotEmpty) {
        ok = await TiebaClient.unfollowBar(name, bduss, tbs);
      }
    }
    if (ok) await fetchFollowedBars();
    return ok;
  }

  static Future<bool> isFollowedBar(String barName) async {
    final name = barName.trim();
    if (name.isEmpty) return false;
    final bars = await fetchFollowedBars();
    return bars.any((b) => b.name == name);
  }

  static Future<bool> followUser(String portrait) async {
    final normalized = portrait.trim();
    if (normalized.isEmpty) return false;
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return false;
    var tbs = await getTbs();
    if (tbs.isEmpty) return false;
    var ok = await TiebaClient.followUser(
      portrait: normalized,
      bduss: bduss,
      tbs: tbs,
    );
    if (!ok) {
      tbs = await refreshTbs();
      if (tbs.isNotEmpty) {
        ok = await TiebaClient.followUser(
          portrait: normalized,
          bduss: bduss,
          tbs: tbs,
        );
      }
    }
    return ok;
  }

  static Future<bool> unfollowUser(String portrait) async {
    final normalized = portrait.trim();
    if (normalized.isEmpty) return false;
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return false;
    var tbs = await getTbs();
    if (tbs.isEmpty) return false;
    var ok = await TiebaClient.unfollowUser(
      portrait: normalized,
      bduss: bduss,
      tbs: tbs,
    );
    if (!ok) {
      tbs = await refreshTbs();
      if (tbs.isNotEmpty) {
        ok = await TiebaClient.unfollowUser(
          portrait: normalized,
          bduss: bduss,
          tbs: tbs,
        );
      }
    }
    return ok;
  }

  static Future<bool?> fetchUserIsFollowedByMe({
    required String portrait,
    String? userId,
  }) async {
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) return null;
    final stoken = await getStoken();
    return TiebaClient.fetchUserIsFollowedByMe(
      portrait: portrait,
      userId: userId,
      bduss: bduss,
      stoken: stoken,
    );
  }

  static Future<BarForumContext?> fetchBarForumContext(String barName) async {
    final name = barName.trim();
    if (name.isEmpty) return null;
    final bduss = await getBduss();
    final portrait = await getPortrait();
    final tbs = await getTbs();
    return TiebaClient.fetchBarForumContext(
      name,
      bduss: bduss,
      portrait: portrait,
      tbs: tbs,
    );
  }

  static Future<SignInResult> signInBar(String barName) async {
    final bduss = await getBduss();
    if (bduss == null || bduss.isEmpty) {
      return SignInResult(success: false, message: '未绑定贴吧账号');
    }
    try {
      final tbs = await getTbs();
      final ok = await TiebaClient.signInBar(
        barName,
        bduss,
        tbs,
      ).timeout(const Duration(seconds: 8));
      return ok
          ? SignInResult(success: true, message: '签到成功')
          : SignInResult(success: false, message: '签到失败');
    } catch (_) {
      return SignInResult(success: false, message: '网络错误');
    }
  }

  static Future<List<SignInResult>> signInAllBars({
    SignInProgressCallback? onProgress,
  }) async {
    final bars = await fetchFollowedBars();
    if (bars.isEmpty) return [];
    final queue = bars.where((b) => b.name.isNotEmpty).toList();
    final results = <SignInResult>[];
    var successCount = 0;

    for (var i = 0; i < queue.length; i++) {
      final bar = queue[i];
      await onProgress?.call(
        SignInProgressEvent(
          index: i,
          total: queue.length,
          barName: bar.name,
          signing: true,
          successCount: successCount,
        ),
      );

      SignInResult result;
      try {
        final r = await signInBar(bar.name).timeout(
          const Duration(seconds: 8),
          onTimeout: () => SignInResult(success: false, message: '超时'),
        );
        result = SignInResult(
          success: r.success,
          message: '${bar.name}: ${r.message}',
        );
      } catch (_) {
        result = SignInResult(success: false, message: '${bar.name}: 网络错误');
      }

      if (result.success) successCount++;
      results.add(result);

      await onProgress?.call(
        SignInProgressEvent(
          index: i,
          total: queue.length,
          barName: bar.name,
          signing: false,
          success: result.success,
          message: result.message,
          successCount: successCount,
        ),
      );
    }
    return results;
  }
}

class FollowedBar {
  final String name;
  final String id;
  final String avatar;
  FollowedBar({required this.name, required this.id, this.avatar = ''});
}

class SignInResult {
  final bool success;
  final String message;
  SignInResult({required this.success, required this.message});
}
