import 'package:shared_preferences/shared_preferences.dart';

class XunfeiConfig {
  final String appId;
  final String apiKey;
  final String apiSecret;

  const XunfeiConfig({this.appId = '', this.apiKey = '', this.apiSecret = ''});

  bool get isConfigured =>
      appId.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      apiSecret.trim().isNotEmpty;
}

class XunfeiConfigService {
  static const _appIdKey = 'agent_xunfei_app_id';
  static const _apiKeyKey = 'agent_xunfei_api_key';
  static const _apiSecretKey = 'agent_xunfei_api_secret';

  static Future<XunfeiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return XunfeiConfig(
      appId: prefs.getString(_appIdKey) ?? '',
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      apiSecret: prefs.getString(_apiSecretKey) ?? '',
    );
  }

  static Future<void> save(XunfeiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appIdKey, config.appId.trim());
    await prefs.setString(_apiKeyKey, config.apiKey.trim());
    await prefs.setString(_apiSecretKey, config.apiSecret.trim());
  }
}
