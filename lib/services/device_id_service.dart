import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/tieba_cuid.dart';

/// 持久化设备标识，供点赞等写操作附带 `cuid`。
class DeviceIdService {
  DeviceIdService._();

  static const _androidIdKey = 'tieba_android_id';
  static const _cuidKey = 'tieba_cuid_galaxy2_v2';

  static Future<String> getCuidGalaxy2() async {
    final prefs = await SharedPreferences.getInstance();
    var androidId = prefs.getString(_androidIdKey);
    androidId ??= _randomAndroidId();

    final expected = TiebaCuid.cuidGalaxy2(androidId);
    final cached = prefs.getString(_cuidKey);
    if (cached == expected) return expected;

    await prefs.setString(_androidIdKey, androidId);
    await prefs.setString(_cuidKey, expected);
    return expected;
  }

  static String _randomAndroidId() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
