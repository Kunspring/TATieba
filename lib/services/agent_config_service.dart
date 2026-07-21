import 'package:shared_preferences/shared_preferences.dart';

/// DeepSeek 官方 OpenAI 兼容接口默认值。
/// 文档：https://api-docs.deepseek.com
class DeepSeekDefaults {
  static const baseUrl = 'https://api.deepseek.com';
  static const model = 'deepseek-v4-flash';
  static const models = ['deepseek-v4-flash', 'deepseek-v4-pro'];
}

class AgentConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final String serperApiKey;

  const AgentConfig({
    this.baseUrl = DeepSeekDefaults.baseUrl,
    this.apiKey = '',
    this.model = DeepSeekDefaults.model,
    this.serperApiKey = '',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  bool get hasSerperKey => serperApiKey.trim().isNotEmpty;

  /// V4 Flash / Pro 均支持工具调用。
  bool get supportsToolCalling => true;

  /// Thinking / reasoner 模型通常只接受 tool_choice: auto | none。
  bool get supportsForcedToolChoice {
    final m = model.trim().toLowerCase();
    if (m.contains('deepseek-v4') ||
        m.contains('deepseek-reasoner') ||
        m.contains('deepseek-r1') ||
        m.contains('reasoner') ||
        m.contains('-r1')) {
      return false;
    }
    return true;
  }

  String get completionsUrl {
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.endsWith('/chat/completions')) return url;
    if (url.endsWith('/v1')) return '$url/chat/completions';
    // DeepSeek 官方根地址使用 /chat/completions（非 /v1）
    if (url.contains('deepseek.com')) return '$url/chat/completions';
    return '$url/v1/chat/completions';
  }
}

class AgentConfigService {
  static const _baseUrlKey = 'agent_api_base';
  static const _apiKeyKey = 'agent_api_key';
  static const _modelKey = 'agent_model';
  static const _historyKey = 'agent_chat_history';
  static const _serperKeyKey = 'agent_serper_api_key';

  static Future<AgentConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBase = prefs.getString(_baseUrlKey)?.trim() ?? '';
    final savedModel = prefs.getString(_modelKey);
    return AgentConfig(
      baseUrl: savedBase.isNotEmpty ? savedBase : DeepSeekDefaults.baseUrl,
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      model: _normalizeModel(savedModel),
      serperApiKey: prefs.getString(_serperKeyKey) ?? '',
    );
  }

  static String _normalizeModel(String? saved) {
    final model = saved?.trim() ?? '';
    if (model.isEmpty) return DeepSeekDefaults.model;
    return switch (model) {
      'deepseek-chat' => 'deepseek-v4-flash',
      'deepseek-reasoner' => 'deepseek-v4-pro',
      _ => model,
    };
  }

  static Future<void> save(AgentConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, config.baseUrl.trim());
    await prefs.setString(_apiKeyKey, config.apiKey.trim());
    await prefs.setString(_modelKey, config.model.trim());
    await prefs.setString(_serperKeyKey, config.serperApiKey.trim());
  }

  static Future<String?> loadHistoryJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_historyKey);
  }

  static Future<void> saveHistoryJson(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, json);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
