import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/tieba_cuid.dart';

/// 持久化设备标识与设备指纹，供写操作附带 `cuid` 及真实设备参数。
///
/// 首次运行时随机选择一款真实设备型号并持久化，后续稳定使用同一指纹，
/// 避免所有安装共享相同设备信息被聚类检测。
class DeviceIdService {
  DeviceIdService._();

  static const _androidIdKey = 'tieba_android_id';
  static const _cuidKey = 'tieba_cuid_galaxy2_v2';
  static const _wsCuidKey = 'tieba_ws_cuid';
  static const _modelKey = 'tieba_device_model';
  static const _manufacturerKey = 'tieba_device_manufacturer';
  static const _androidVersKey = 'tieba_device_android_version';
  static const _deviceUuidKey = 'tieba_device_uuid';

  // ---- profiles: popular Android devices in China market ----
  static const _profiles = <({String model, String manufacturer, String version})>[
    (model: 'SM-S928B', manufacturer: 'samsung', version: '14'),
    (model: 'SM-F946B', manufacturer: 'samsung', version: '14'),
    (model: 'SM-S901B', manufacturer: 'samsung', version: '13'),
    (model: 'SM-G991B', manufacturer: 'samsung', version: '12'),
    (model: '23127PN0CG', manufacturer: 'Xiaomi', version: '14'),
    (model: '2311DRK48C', manufacturer: 'Xiaomi', version: '14'),
    (model: '2210132C', manufacturer: 'Xiaomi', version: '13'),
    (model: 'PJA110', manufacturer: 'HONOR', version: '13'),
    (model: 'PHW110', manufacturer: 'HUAWEI', version: '13'),
    (model: 'V2324A', manufacturer: 'vivo', version: '14'),
    (model: 'V2301A', manufacturer: 'vivo', version: '14'),
    (model: 'RMX3700', manufacturer: 'realme', version: '14'),
    (model: 'RMX3560', manufacturer: 'realme', version: '13'),
  ];

  // ---- cached values ----
  static String? _cuidCached;
  static String? _wsCuidCached;
  static String? _modelCached;
  static String? _manufacturerCached;
  static String? _androidVersionCached;
  static String? _deviceUuidCached;

  // ---- sync accessors ----

  static String getCuidGalaxy2Cached() => _cuidCached ?? '';

  /// WebSocket IM 连接使用的 cuid（`baidutiebaapp<uuid>` 格式），
  /// 首先生成后持久化，不会每次连接重新生成。
  static String getWsCuid() => _wsCuidCached ?? '';

  static String getModel() => _modelCached ?? 'SM-G991B';

  static String getManufacturer() => _manufacturerCached ?? 'samsung';

  static String getAndroidVersion() => _androidVersionCached ?? '12';

  /// 设备 UUID（field 37），首次运行时随机生成并持久化。
  static String getDeviceUuid() => _deviceUuidCached ?? '1008621x';

  // ---- warmup ----

  static Future<void> warmup() async {
    _cuidCached = await getCuidGalaxy2();
    _wsCuidCached = await _loadOrCreateWsCuid();
    await _ensureProfile();
  }

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

  static Future<void> _ensureProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_modelKey);
    if (existing != null) {
      _modelCached = existing;
      _manufacturerCached = prefs.getString(_manufacturerKey) ?? 'samsung';
      _androidVersionCached = prefs.getString(_androidVersKey) ?? '12';
      _deviceUuidCached = prefs.getString(_deviceUuidKey) ?? _randomDeviceUuid();
      return;
    }
    // First launch: pick a random profile and persist
    final rng = Random.secure();
    final profile = _profiles[rng.nextInt(_profiles.length)];
    _modelCached = profile.model;
    _manufacturerCached = profile.manufacturer;
    _androidVersionCached = profile.version;
    _deviceUuidCached = _randomDeviceUuid();
    await prefs.setString(_modelKey, _modelCached!);
    await prefs.setString(_manufacturerKey, _manufacturerCached!);
    await prefs.setString(_androidVersKey, _androidVersionCached!);
    await prefs.setString(_deviceUuidKey, _deviceUuidCached!);
  }

  static String _randomDeviceUuid() {
    final rng = Random.secure();
    final chars = '0123456789abcdef';
    final buf = StringBuffer();
    for (var i = 0; i < 15; i++) {
      buf.write(chars[rng.nextInt(chars.length)]);
    }
    return '$buf';
  }

  static Future<String> _loadOrCreateWsCuid() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_wsCuidKey);
    if (cached != null && cached.isNotEmpty) return cached;
    final cuid = 'baidutiebaapp${_uuidV4()}';
    await prefs.setString(_wsCuidKey, cuid);
    return cuid;
  }

  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => i.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}'
        '${hex(bytes[14])}${hex(bytes[15])}';
  }

  static String _randomAndroidId() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
