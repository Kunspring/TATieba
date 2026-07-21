import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/agent_memory_entry.dart';
import '../models/agent_message.dart';
import '../utils/agent_kaomoji_mood.dart';
import 'agent_config_service.dart';
import 'agent_memory_service.dart';
import 'agent_tool_intent.dart';
import 'app_ui_context.dart';

/// 用户当前诉求（认知评估 · 意图）。
enum EmotionIntent {
  vent,
  seekComfort,
  seekInfo,
  casualChat,
  ventAndSolve,
  celebrate,
  unclear,
}

/// 回复策略（认知层输出）。
enum ReplyStrategy {
  empathizeFirst,
  chatNaturally,
  gatherInfo,
  useTools,
  redirectGently,
}

extension EmotionIntentLabel on EmotionIntent {
  String get label => switch (this) {
    EmotionIntent.vent => '发泄吐槽',
    EmotionIntent.seekComfort => '需要安慰',
    EmotionIntent.seekInfo => '想要信息',
    EmotionIntent.casualChat => '随便聊聊',
    EmotionIntent.ventAndSolve => '吐槽并求办法',
    EmotionIntent.celebrate => '分享开心',
    EmotionIntent.unclear => '尚不明确',
  };
}

extension ReplyStrategyLabel on ReplyStrategy {
  String get label => switch (this) {
    ReplyStrategy.empathizeFirst => '先共情接话',
    ReplyStrategy.chatNaturally => '自然陪聊',
    ReplyStrategy.gatherInfo => '先问清楚',
    ReplyStrategy.useTools => '查数据/操作 App',
    ReplyStrategy.redirectGently => '轻引导换话题',
  };
}

/// 统一情感状态：驱动颜文字、system prompt 与 tool 门控。
class AgentEmotionState {
  final double valence;
  final double arousal;
  final EmotionIntent intent;
  final ReplyStrategy strategy;
  final AgentKaomojiMood companionMood;
  final String primaryLabel;
  final double confidence;
  final bool usedLlmAppraisal;

  const AgentEmotionState({
    required this.valence,
    required this.arousal,
    required this.intent,
    required this.strategy,
    required this.companionMood,
    required this.primaryLabel,
    required this.confidence,
    this.usedLlmAppraisal = false,
  });

  String buildPromptBlock({bool companionShaking = false}) {
    final moodDesc = companionMood.describe(shaking: companionShaking);
    final valenceDesc = valence > 0.25
        ? '偏正面'
        : valence < -0.25
        ? '偏负面'
        : '中性';
    final arousalDesc = arousal > 0.55
        ? '较激动'
        : arousal < 0.35
        ? '较平静'
        : '中等';

    final strategyHint = switch (strategy) {
      ReplyStrategy.empathizeFirst => '先接话共情，一句即可；不要主动查帖/跳转/给教程',
      ReplyStrategy.gatherInfo => '先问一句弄清用户到底要什么，别急着调工具',
      ReplyStrategy.useTools => '用户明确要查/要看/要操作，可先调 tool',
      ReplyStrategy.redirectGently => '用户可能陷在情绪里，陪两句再轻轻换角度',
      ReplyStrategy.chatNaturally => '像朋友随口回，不必上价值',
    };

    return '''
## 情感认知（内部参考，勿向用户复述本段）
- 用户情绪：$valenceDesc、$arousalDesc（$primaryLabel）
- 诉求：${intent.label}
- 你的策略：${strategy.label}——$strategyHint
- 顶栏颜文字已是 $moodDesc；正文默认不带颜文字，要带时最多 1 个且与状态相符
''';
  }
}

/// 多源信号融合 + 可选 LLM 认知评估。
class AgentEmotionFusion {
  AgentEmotionFusion._();

  static final AgentEmotionFusion instance = AgentEmotionFusion._();

  static const _emaAlpha = 0.35;
  static const _appraisalConfidenceThreshold = 0.45;

  double _emaValence = 0;
  double _emaArousal = 0.32;
  AgentEmotionState? _lastTurnState;

  AgentEmotionState? get lastTurnState => _lastTurnState;

  /// 顶栏颜文字 / 空闲态展示用（同步、无 LLM）。
  AgentEmotionState fuseForDisplay({
    required List<AgentMessage> messages,
    required bool toolMode,
    required bool isWelcome,
    required bool lastAssistantIsError,
    String? lastUserText,
    String? lastAssistantText,
  }) {
    return _fuseRules(
      userMessage: lastUserText ?? '',
      history: messages,
      toolMode: toolMode,
      isWelcome: isWelcome,
      lastAssistantIsError: lastAssistantIsError,
      lastAssistantText: lastAssistantText,
      browseSummary: null,
      applyEma: true,
    );
  }

  /// 每轮对话：规则融合，低置信度时可选 LLM 认知评估。
  Future<AgentEmotionState> fuseForTurn({
    required String userMessage,
    required List<AgentMessage> history,
    required bool toolMode,
    AgentConfig? config,
    String? browseSummary,
  }) async {
    final rules = _fuseRules(
      userMessage: userMessage,
      history: history,
      toolMode: toolMode,
      isWelcome: false,
      lastAssistantIsError: false,
      browseSummary: browseSummary,
      applyEma: true,
    );

    final ambiguous = _isAmbiguous(userMessage, rules);
    if (ambiguous &&
        rules.confidence < _appraisalConfidenceThreshold &&
        config != null &&
        config.isConfigured) {
      final appraised = await _llmAppraise(
        userMessage: userMessage,
        history: history,
        config: config,
      );
      if (appraised != null) {
        final merged = _mergeAppraisal(rules, appraised);
        _lastTurnState = merged;
        return merged;
      }
    }

    _lastTurnState = rules;
    return rules;
  }

  AgentEmotionState _fuseRules({
    required String userMessage,
    required List<AgentMessage> history,
    required bool toolMode,
    required bool isWelcome,
    required bool lastAssistantIsError,
    String? lastAssistantText,
    String? browseSummary,
    required bool applyEma,
  }) {
    if (isWelcome) {
      return _finalize(
        valence: 0.35,
        arousal: 0.4,
        intent: EmotionIntent.casualChat,
        strategy: ReplyStrategy.chatNaturally,
        companionMood: AgentKaomojiMood.welcome,
        primaryLabel: '打招呼',
        confidence: 0.85,
        applyEma: applyEma,
      );
    }

    if (lastAssistantIsError) {
      return _finalize(
        valence: -0.35,
        arousal: 0.45,
        intent: EmotionIntent.unclear,
        strategy: ReplyStrategy.chatNaturally,
        companionMood: AgentKaomojiMood.error,
        primaryLabel: '出错',
        confidence: 0.9,
        applyEma: applyEma,
      );
    }

    final text = userMessage.trim();
    final userMood = text.isEmpty
        ? AgentKaomojiMood.neutral
        : AgentKaomojiMoodResolver.forUserText(text, toolMode: toolMode);

    final assistantMood =
        (lastAssistantText == null || lastAssistantText.isEmpty)
        ? null
        : AgentKaomojiMoodResolver.forAssistantText(lastAssistantText);

    var valence = _valenceFromMood(userMood);
    var arousal = _arousalFromMood(userMood);
    var confidence = 0.62;

    if (assistantMood != null && assistantMood != AgentKaomojiMood.neutral) {
      valence = _blend(valence, _valenceFromMood(assistantMood), 0.35);
      arousal = _blend(arousal, _arousalFromMood(assistantMood), 0.25);
    }

    final intent = _detectIntent(text, toolMode: toolMode);
    confidence = _adjustConfidence(text, intent, confidence);

    final uiBoost = _uiContextBoost();
    valence += uiBoost.valence;
    arousal += uiBoost.arousal;
    if (uiBoost.valence != 0 || uiBoost.arousal != 0) {
      confidence = (confidence + 0.08).clamp(0, 1);
    }

    final browseBoost = _browseBoost(browseSummary);
    valence += browseBoost.valence;
    arousal += browseBoost.arousal;

    final emotionalMemories = _emotionalMemoryHints();
    final strategy = _pickStrategy(
      intent: intent,
      userMessage: text,
      toolMode: toolMode,
      emotionalMemories: emotionalMemories,
    );

    if (emotionalMemories.isNotEmpty &&
        (intent == EmotionIntent.vent || intent == EmotionIntent.seekComfort)) {
      confidence = (confidence + 0.1).clamp(0, 1);
    }

    valence = valence.clamp(-1.0, 1.0);
    arousal = arousal.clamp(0.0, 1.0);

    final primaryLabel = _primaryLabel(valence, arousal, intent);
    final companionMood = _companionMoodFromSignals(
      valence: valence,
      arousal: arousal,
      userMood: userMood,
      assistantMood: assistantMood,
      intent: intent,
      strategy: strategy,
    );

    return _finalize(
      valence: valence,
      arousal: arousal,
      intent: intent,
      strategy: strategy,
      companionMood: companionMood,
      primaryLabel: primaryLabel,
      confidence: confidence,
      applyEma: applyEma,
    );
  }

  AgentEmotionState _finalize({
    required double valence,
    required double arousal,
    required EmotionIntent intent,
    required ReplyStrategy strategy,
    required AgentKaomojiMood companionMood,
    required String primaryLabel,
    required double confidence,
    required bool applyEma,
    bool usedLlmAppraisal = false,
  }) {
    if (applyEma) {
      _emaValence = _blend(_emaValence, valence, _emaAlpha);
      _emaArousal = _blend(_emaArousal, arousal, _emaAlpha);
    }

    return AgentEmotionState(
      valence: applyEma ? _emaValence : valence,
      arousal: applyEma ? _emaArousal : arousal,
      intent: intent,
      strategy: strategy,
      companionMood: companionMood,
      primaryLabel: primaryLabel,
      confidence: confidence,
      usedLlmAppraisal: usedLlmAppraisal,
    );
  }

  static double _blend(double a, double b, double weight) =>
      a * (1 - weight) + b * weight;

  static double _valenceFromMood(AgentKaomojiMood mood) => switch (mood) {
    AgentKaomojiMood.happy || AgentKaomojiMood.welcome => 0.55,
    AgentKaomojiMood.curious || AgentKaomojiMood.thinking => 0.05,
    AgentKaomojiMood.sorry ||
    AgentKaomojiMood.surrender ||
    AgentKaomojiMood.error => -0.55,
    AgentKaomojiMood.surprised => -0.1,
    AgentKaomojiMood.dazed => -0.15,
    AgentKaomojiMood.working || AgentKaomojiMood.focused => 0,
    AgentKaomojiMood.neutral => 0,
  };

  static double _arousalFromMood(AgentKaomojiMood mood) => switch (mood) {
    AgentKaomojiMood.surprised ||
    AgentKaomojiMood.happy ||
    AgentKaomojiMood.error => 0.75,
    AgentKaomojiMood.sorry || AgentKaomojiMood.surrender => 0.55,
    AgentKaomojiMood.working || AgentKaomojiMood.focused => 0.5,
    AgentKaomojiMood.curious || AgentKaomojiMood.thinking => 0.45,
    AgentKaomojiMood.welcome => 0.4,
    AgentKaomojiMood.dazed || AgentKaomojiMood.neutral => 0.28,
  };

  static EmotionIntent _detectIntent(String text, {required bool toolMode}) {
    final t = text.trim();
    if (t.isEmpty) return EmotionIntent.unclear;

    if (_celebratePattern.hasMatch(t)) return EmotionIntent.celebrate;

    final vent = _ventPattern.hasMatch(t);
    final comfort = _comfortPattern.hasMatch(t);
    final wantsSolve = _solvePattern.hasMatch(t);
    final wantsTools = toolMode && AgentToolIntent.likelyRequiresTools(t);

    if (vent && wantsSolve) return EmotionIntent.ventAndSolve;
    if (comfort) return EmotionIntent.seekComfort;
    if (vent) return EmotionIntent.vent;
    if (wantsTools) return EmotionIntent.seekInfo;

    if (RegExp(
      r'^(你好|嗨|在吗|哈喽|无聊|随便|聊聊)[\?？!！。~\s]*$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return EmotionIntent.casualChat;
    }

    if (RegExp(r'[?？]|怎么|如何|为什么|多少|有没有').hasMatch(t) && t.length < 80) {
      return EmotionIntent.seekInfo;
    }

    if (t.length <= 8) return EmotionIntent.casualChat;
    return EmotionIntent.unclear;
  }

  static final _ventPattern = RegExp(
    r'(好烦|烦死|气死|无语|离谱|服了|崩溃|破防|吐|骂|垃圾|什么鬼|'
    r'绷不住|下头|恶心|烦人|烦透了|不想动|累死了|烦)',
  );

  static final _comfortPattern = RegExp(
    r'(难过|伤心|丧|孤独|害怕|焦虑|抑郁|委屈|想哭|好难|撑不住|'
    r'没人|emo|Emo|EMO)',
  );

  static final _solvePattern = RegExp(r'(怎么办|咋办|怎么弄|如何解决|有没有办法|帮我想|给个建议)');

  static final _celebratePattern = RegExp(
    r'(太开心|好开心|中了|过了|上岸|爽|耶|哈哈{2,}|太好了|'
    r'恭喜|庆祝|欧了|血赚)',
  );

  static double _adjustConfidence(
    String text,
    EmotionIntent intent,
    double base,
  ) {
    if (intent != EmotionIntent.unclear) return (base + 0.15).clamp(0, 1);
    if (text.length <= 6) return (base - 0.2).clamp(0, 1);
    if (_ironyPattern.hasMatch(text)) return (base - 0.25).clamp(0, 1);
    return base;
  }

  static final _ironyPattern = RegExp(r'(还行吧|一般吧|呵呵|挺好的|不错哦|可以可以|就那样)');

  static ({double valence, double arousal}) _uiContextBoost() {
    final summary = AppUiContextService.instance.buildSummary();
    var valence = 0.0;
    var arousal = 0.0;

    if (summary.contains('帖子') || summary.contains('帖详情')) {
      arousal += 0.08;
    }
    if (summary.contains('争议') ||
        summary.contains('骂') ||
        summary.contains('吵架')) {
      valence -= 0.12;
      arousal += 0.12;
    }
    return (valence: valence, arousal: arousal);
  }

  static ({double valence, double arousal}) _browseBoost(
    String? browseSummary,
  ) {
    if (browseSummary == null || browseSummary.trim().isEmpty) {
      return (valence: 0.0, arousal: 0.0);
    }
    var valence = 0.0;
    var arousal = 0.0;
    if (RegExp(r'(骂|吵|崩|离谱|破防|争议|翻车)').hasMatch(browseSummary)) {
      valence -= 0.1;
      arousal += 0.1;
    }
    return (valence: valence, arousal: arousal);
  }

  static List<String> _emotionalMemoryHints() {
    return AgentMemoryService.instance.entries
        .where((e) => e.category == AgentMemoryCategory.emotional)
        .map((e) => e.content)
        .take(4)
        .toList();
  }

  static ReplyStrategy _pickStrategy({
    required EmotionIntent intent,
    required String userMessage,
    required bool toolMode,
    required List<String> emotionalMemories,
  }) {
    final explicitTools =
        toolMode && AgentToolIntent.likelyRequiresTools(userMessage);

    if (explicitTools) return ReplyStrategy.useTools;

    switch (intent) {
      case EmotionIntent.vent:
      case EmotionIntent.seekComfort:
        final hatesPreaching = emotionalMemories.any(
          (m) => m.contains('说教') || m.contains('道理') || m.contains('上课'),
        );
        if (hatesPreaching || intent == EmotionIntent.seekComfort) {
          return ReplyStrategy.empathizeFirst;
        }
        return ReplyStrategy.empathizeFirst;
      case EmotionIntent.ventAndSolve:
        return ReplyStrategy.gatherInfo;
      case EmotionIntent.seekInfo:
        return ReplyStrategy.useTools;
      case EmotionIntent.celebrate:
        return ReplyStrategy.chatNaturally;
      case EmotionIntent.casualChat:
        return ReplyStrategy.chatNaturally;
      case EmotionIntent.unclear:
        return ReplyStrategy.chatNaturally;
    }
  }

  static String _primaryLabel(
    double valence,
    double arousal,
    EmotionIntent intent,
  ) {
    if (intent == EmotionIntent.celebrate) return '开心';
    if (intent == EmotionIntent.seekComfort) return '需要陪伴';
    if (intent == EmotionIntent.vent || intent == EmotionIntent.ventAndSolve) {
      return '吐槽';
    }
    if (valence < -0.35 && arousal > 0.5) return '激动不满';
    if (valence < -0.25) return '偏低落';
    if (valence > 0.35) return '愉快';
    if (arousal > 0.6) return '较兴奋';
    return '平常';
  }

  static AgentKaomojiMood _companionMoodFromSignals({
    required double valence,
    required double arousal,
    required AgentKaomojiMood userMood,
    required AgentKaomojiMood? assistantMood,
    required EmotionIntent intent,
    required ReplyStrategy strategy,
  }) {
    if (strategy == ReplyStrategy.useTools &&
        (userMood == AgentKaomojiMood.focused ||
            userMood == AgentKaomojiMood.working)) {
      return AgentKaomojiMood.working;
    }

    if (assistantMood != null &&
        assistantMood != AgentKaomojiMood.neutral &&
        assistantMood != AgentKaomojiMood.curious) {
      return assistantMood;
    }

    if (userMood != AgentKaomojiMood.neutral &&
        userMood != AgentKaomojiMood.curious) {
      return userMood;
    }

    if (intent == EmotionIntent.celebrate) return AgentKaomojiMood.happy;
    if (intent == EmotionIntent.seekComfort ||
        (valence < -0.3 && intent == EmotionIntent.vent)) {
      return AgentKaomojiMood.sorry;
    }
    if (valence < -0.45 && arousal > 0.55) return AgentKaomojiMood.sorry;
    if (arousal > 0.65 && valence > -0.1) return AgentKaomojiMood.surprised;

    return userMood;
  }

  bool _isAmbiguous(String text, AgentEmotionState rules) {
    if (rules.confidence >= _appraisalConfidenceThreshold) return false;
    if (_ironyPattern.hasMatch(text)) return true;
    if (_ventPattern.hasMatch(text) && _celebratePattern.hasMatch(text)) {
      return true;
    }
    if (text.length <= 10 && rules.intent == EmotionIntent.unclear) return true;
    return false;
  }

  Future<AgentEmotionState?> _llmAppraise({
    required String userMessage,
    required List<AgentMessage> history,
    required AgentConfig config,
  }) async {
    try {
      final recent = history
          .where(
            (m) =>
                m.role == AgentMessageRole.user ||
                m.role == AgentMessageRole.assistant,
          )
          .toList()
          .reversed
          .take(4)
          .toList()
          .reversed
          .map(
            (m) =>
                '${m.role == AgentMessageRole.user ? '用户' : '助手'}: ${_clip(m.content, 80)}',
          )
          .join('\n');

      final resp = await http
          .post(
            Uri.parse(config.completionsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode({
              'model': config.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '你是情感认知评估模块。根据用户最新话和最近对话，输出一行 JSON，字段：'
                      'valence(-1~1), arousal(0~1), primary(中文2~4字), '
                      'intent(vent|seekComfort|seekInfo|casualChat|ventAndSolve|celebrate|unclear), '
                      'strategy(empathizeFirst|chatNaturally|gatherInfo|useTools|redirectGently), '
                      'companion_mood(welcome|neutral|thinking|working|curious|focused|happy|sorry|surrender|error|surprised|dazed)。'
                      '只输出 JSON，不要解释。',
                },
                {
                  'role': 'user',
                  'content': [
                    if (recent.isNotEmpty) '最近对话:\n$recent',
                    '最新用户: ${_clip(userMessage, 160)}',
                  ].join('\n\n'),
                },
              ],
              'temperature': 0.15,
              'max_tokens': 120,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return null;
      final message = choice['message'];
      if (message is! Map) return null;
      var raw = message['content']?.toString().trim() ?? '';
      if (raw.isEmpty) return null;

      final jsonStart = raw.indexOf('{');
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        raw = raw.substring(jsonStart, jsonEnd + 1);
      }

      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final valence =
          (parsed['valence'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? 0.0;
      final arousal =
          (parsed['arousal'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.3;
      final intent = _parseIntent(parsed['intent']?.toString());
      final strategy = _parseStrategy(parsed['strategy']?.toString());
      final mood = _parseMood(parsed['companion_mood']?.toString());
      final primary = parsed['primary']?.toString().trim().isNotEmpty == true
          ? parsed['primary'].toString().trim()
          : _primaryLabel(valence, arousal, intent);

      return AgentEmotionState(
        valence: valence,
        arousal: arousal,
        intent: intent,
        strategy: strategy,
        companionMood: mood,
        primaryLabel: primary,
        confidence: 0.78,
        usedLlmAppraisal: true,
      );
    } catch (_) {
      return null;
    }
  }

  AgentEmotionState _mergeAppraisal(
    AgentEmotionState rules,
    AgentEmotionState appraised,
  ) {
    final valence = _blend(rules.valence, appraised.valence, 0.55);
    final arousal = _blend(rules.arousal, appraised.arousal, 0.55);
    _emaValence = _blend(_emaValence, valence, _emaAlpha);
    _emaArousal = _blend(_emaArousal, arousal, _emaAlpha);

    return AgentEmotionState(
      valence: _emaValence,
      arousal: _emaArousal,
      intent: appraised.intent == EmotionIntent.unclear
          ? rules.intent
          : appraised.intent,
      strategy: appraised.strategy,
      companionMood: appraised.companionMood,
      primaryLabel: appraised.primaryLabel,
      confidence: 0.78,
      usedLlmAppraisal: true,
    );
  }

  static EmotionIntent _parseIntent(String? raw) {
    return switch (raw?.trim()) {
      'vent' => EmotionIntent.vent,
      'seekComfort' => EmotionIntent.seekComfort,
      'seekInfo' => EmotionIntent.seekInfo,
      'casualChat' => EmotionIntent.casualChat,
      'ventAndSolve' => EmotionIntent.ventAndSolve,
      'celebrate' => EmotionIntent.celebrate,
      _ => EmotionIntent.unclear,
    };
  }

  static ReplyStrategy _parseStrategy(String? raw) {
    return switch (raw?.trim()) {
      'empathizeFirst' => ReplyStrategy.empathizeFirst,
      'chatNaturally' => ReplyStrategy.chatNaturally,
      'gatherInfo' => ReplyStrategy.gatherInfo,
      'useTools' => ReplyStrategy.useTools,
      'redirectGently' => ReplyStrategy.redirectGently,
      _ => ReplyStrategy.chatNaturally,
    };
  }

  static AgentKaomojiMood _parseMood(String? raw) {
    return switch (raw?.trim()) {
      'welcome' => AgentKaomojiMood.welcome,
      'thinking' => AgentKaomojiMood.thinking,
      'working' => AgentKaomojiMood.working,
      'curious' => AgentKaomojiMood.curious,
      'focused' => AgentKaomojiMood.focused,
      'happy' => AgentKaomojiMood.happy,
      'sorry' => AgentKaomojiMood.sorry,
      'surrender' => AgentKaomojiMood.surrender,
      'error' => AgentKaomojiMood.error,
      'surprised' => AgentKaomojiMood.surprised,
      'dazed' => AgentKaomojiMood.dazed,
      _ => AgentKaomojiMood.neutral,
    };
  }

  static String _clip(String raw, int max) {
    final text = raw.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }

  /// 根据融合策略决定是否允许工具（共情优先时抑制误触）。
  static bool shouldAllowTools({
    required ReplyStrategy strategy,
    required String userMessage,
    required bool toolModeEnabled,
  }) {
    if (!toolModeEnabled) return false;
    if (strategy == ReplyStrategy.useTools) return true;
    if (strategy == ReplyStrategy.empathizeFirst &&
        !AgentToolIntent.likelyRequiresTools(userMessage)) {
      return false;
    }
    return AgentToolIntent.likelyRequiresTools(userMessage);
  }
}
