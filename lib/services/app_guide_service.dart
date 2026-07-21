import 'package:shared_preferences/shared_preferences.dart';

/// 首次使用功能引导（分场景浮窗）。
class AppGuideService {
  AppGuideService._();

  static const _legacyKey = 'feature_guide_seen_v1';
  static const _volumeKey = 'guide_volume_v1';
  static const _kaomojiKey = 'guide_kaomoji_v1';
  static const _shakeKey = 'guide_shake_v1';
  static const _swipeKey = 'guide_post_swipe_v1';
  static const _pullFavoriteKey = 'guide_post_pull_favorite_v1';

  static Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_legacyKey) != true) return;
    await prefs.setBool(_volumeKey, true);
    await prefs.setBool(_kaomojiKey, true);
    await prefs.setBool(_swipeKey, true);
  }

  static Future<bool> hasSeenVolumeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    return prefs.getBool(_volumeKey) ?? false;
  }

  static Future<bool> hasSeenKaomojiGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    return prefs.getBool(_kaomojiKey) ?? false;
  }

  static Future<bool> hasSeenShakeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    return prefs.getBool(_shakeKey) ?? false;
  }

  static Future<bool> hasSeenPostSwipeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    return prefs.getBool(_swipeKey) ?? false;
  }

  static Future<bool> hasSeenPostPullFavoriteGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded(prefs);
    return prefs.getBool(_pullFavoriteKey) ?? false;
  }

  static Future<void> markVolumeGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_volumeKey, true);
  }

  static Future<void> markKaomojiGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kaomojiKey, true);
  }

  static Future<void> markShakeGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shakeKey, true);
  }

  static Future<void> markPostSwipeGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_swipeKey, true);
  }

  static Future<void> markPostPullFavoriteGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pullFavoriteKey, true);
  }
}
