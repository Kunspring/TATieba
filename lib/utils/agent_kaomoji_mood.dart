import 'agent_kaomoji_library.dart';

enum AgentKaomojiMood {
  welcome,
  neutral,
  thinking,
  working,
  curious,
  focused,
  happy,
  sorry,
  surrender,
  error,
  surprised,
  dazed,
}

extension AgentKaomojiMoodX on AgentKaomojiMood {
  String get face => switch (this) {
    AgentKaomojiMood.welcome => AgentKaomojiLibrary.wave,
    AgentKaomojiMood.neutral => AgentKaomojiLibrary.cat,
    AgentKaomojiMood.thinking => AgentKaomojiLibrary.gentle,
    AgentKaomojiMood.working => AgentKaomojiLibrary.determined,
    AgentKaomojiMood.curious => AgentKaomojiLibrary.wink,
    AgentKaomojiMood.focused => AgentKaomojiLibrary.determined,
    AgentKaomojiMood.happy => AgentKaomojiLibrary.smug,
    AgentKaomojiMood.sorry => AgentKaomojiLibrary.cry,
    AgentKaomojiMood.surrender => AgentKaomojiLibrary.bow,
    AgentKaomojiMood.error => AgentKaomojiLibrary.angry,
    AgentKaomojiMood.surprised => AgentKaomojiLibrary.shocked,
    AgentKaomojiMood.dazed => AgentKaomojiLibrary.drool,
  };

  /// 给 AI 看的简短状态名。
  String get label => switch (this) {
    AgentKaomojiMood.welcome => '打招呼',
    AgentKaomojiMood.neutral => '平常',
    AgentKaomojiMood.thinking => '琢磨',
    AgentKaomojiMood.working => '干活',
    AgentKaomojiMood.curious => '好奇',
    AgentKaomojiMood.focused => '专注',
    AgentKaomojiMood.happy => '开心',
    AgentKaomojiMood.sorry => '抱歉',
    AgentKaomojiMood.surrender => '认输',
    AgentKaomojiMood.error => '出错',
    AgentKaomojiMood.surprised => '惊讶',
    AgentKaomojiMood.dazed => '发呆',
  };

  String describe({bool shaking = false}) {
    final shake = shaking ? '，正在抖动（思考/处理中）' : '';
    return '$face（$label$shake）';
  }
}

abstract final class AgentKaomojiMoodResolver {
  AgentKaomojiMoodResolver._();

  static AgentKaomojiMood forChatState({
    required bool working,
    required bool toolMode,
    required bool isWelcome,
    String? lastUserText,
    String? lastAssistantText,
    bool lastAssistantIsError = false,
    List<String> thinkingSteps = const [],
    int thinkingCycleTick = 0,
  }) {
    if (working) {
      return forThinkingProgress(
        thinkingSteps,
        toolMode: toolMode,
        cycleTick: thinkingCycleTick,
      );
    }
    if (isWelcome) return AgentKaomojiMood.welcome;
    if (lastAssistantIsError) return AgentKaomojiMood.error;

    final assistantMood = lastAssistantText == null || lastAssistantText.isEmpty
        ? null
        : scoreAssistantText(lastAssistantText);
    final userMood = lastUserText == null || lastUserText.isEmpty
        ? null
        : scoreUserText(lastUserText, toolMode: toolMode);

    if (assistantMood != null && assistantMood != AgentKaomojiMood.neutral) {
      return assistantMood;
    }
    if (userMood != null && userMood != AgentKaomojiMood.neutral) {
      return userMood;
    }
    return assistantMood ?? userMood ?? AgentKaomojiMood.neutral;
  }

  static AgentKaomojiMood forThinkingProgress(
    List<String> steps, {
    bool toolMode = true,
    int cycleTick = 0,
  }) {
    if (steps.isNotEmpty) {
      final latest = steps.last;
      if (latest.contains('调用')) return AgentKaomojiMood.working;
      if (latest.contains('深度推理')) return AgentKaomojiMood.focused;
      if (latest.contains('分析')) return AgentKaomojiMood.thinking;
    }

    if (toolMode && steps.isEmpty) return AgentKaomojiMood.thinking;

    const cycle = [
      AgentKaomojiMood.thinking,
      AgentKaomojiMood.curious,
      AgentKaomojiMood.focused,
    ];
    return cycle[cycleTick % cycle.length];
  }

  static AgentKaomojiMood forAssistantMessage({
    required String content,
    required bool isError,
  }) {
    if (isError) return AgentKaomojiMood.error;
    return scoreAssistantText(content);
  }

  static AgentKaomojiMood forUserText(String text, {bool toolMode = true}) {
    return scoreUserText(text, toolMode: toolMode);
  }

  static AgentKaomojiMood forAssistantText(String text) {
    return scoreAssistantText(text);
  }

  static AgentKaomojiMood scoreUserText(String text, {bool toolMode = true}) {
    final t = _normalize(text);
    if (t.isEmpty) return AgentKaomojiMood.neutral;

    final scores = _baseScores(t);
    _scoreGreeting(t, scores, weight: 4);
    _scoreQuestion(t, scores, weight: 3);
    _scoreShocking(t, scores, weight: 4);
    if (toolMode) _scoreTiebaIntent(t, scores, weight: 3);
    _scoreComplaint(t, scores, weight: 3);

    return _pick(scores, fallback: AgentKaomojiMood.neutral);
  }

  static AgentKaomojiMood scoreAssistantText(String text) {
    final scores = _baseScores('');

    // 颜文字/表情必须在 _normalize 之前识别（normalize 会剥掉括号）。
    _scoreEmbeddedKaomojis(text, scores, weight: 7);
    _scoreUnicodeEmojis(text, scores, weight: 5);

    final t = _normalize(text);
    if (t.isEmpty) {
      return _pick(scores, fallback: AgentKaomojiMood.neutral);
    }

    _scoreApology(t, scores, weight: 5);
    _scoreSorryTone(t, scores, weight: 4);
    _scoreEmpathy(t, scores, weight: 4);
    _scoreShocking(t, scores, weight: 3);
    _scoreHappyTone(t, scores, weight: 3);
    _scoreTiebaIntent(t, scores, weight: 2);
    _scoreQuestion(t, scores, weight: 1);

    return _pick(scores, fallback: AgentKaomojiMood.neutral);
  }

  static Map<AgentKaomojiMood, int> _baseScores(String t) {
    return {
      AgentKaomojiMood.welcome: 0,
      AgentKaomojiMood.neutral: 1,
      AgentKaomojiMood.thinking: 0,
      AgentKaomojiMood.working: 0,
      AgentKaomojiMood.curious: 0,
      AgentKaomojiMood.focused: 0,
      AgentKaomojiMood.happy: 0,
      AgentKaomojiMood.sorry: 0,
      AgentKaomojiMood.surrender: 0,
      AgentKaomojiMood.error: 0,
      AgentKaomojiMood.surprised: 0,
      AgentKaomojiMood.dazed: 0,
    };
  }

  static AgentKaomojiMood _pick(
    Map<AgentKaomojiMood, int> scores, {
    required AgentKaomojiMood fallback,
  }) {
    AgentKaomojiMood best = fallback;
    var bestScore = scores[fallback] ?? 0;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        best = entry.key;
        bestScore = entry.value;
      }
    }
    return bestScore <= 1 ? fallback : best;
  }

  static String _normalize(String text) {
    var t = text.trim();
    if (t.isEmpty) return t;

    t = t.replaceAll(RegExp(r'[#*`>\[\](){}|]'), ' ');
    t = t
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => t);
    t = t.trim();
    if (t.length > 160) t = t.substring(0, 160);
    return t;
  }

  static void _scoreGreeting(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    final lower = t.toLowerCase();
    const keys = [
      '你好',
      '您好',
      '嗨',
      'hello',
      'hi',
      '早上好',
      '中午好',
      '晚上好',
      '在吗',
      '谢谢',
      '感谢',
      '多谢',
    ];
    if (keys.any((k) => lower.contains(k))) {
      scores[AgentKaomojiMood.welcome] =
          (scores[AgentKaomojiMood.welcome] ?? 0) + weight;
    }
  }

  static void _scoreQuestion(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    var score = 0;
    if (RegExp(r'[?？]\s*$').hasMatch(t)) score += weight;
    if (RegExp(r'^(为什么|为何|怎么|如何|啥|哪|谁|多少|是不是|能不能|可不可以)').hasMatch(t)) {
      score += weight;
    }
    if (RegExp(r'(吗|么|呢)\s*[?？]?\s*$').hasMatch(t) &&
        !t.contains('什么') &&
        !t.contains('这么') &&
        !t.contains('那么')) {
      score += weight - 1;
    }
    if (score > 0) {
      scores[AgentKaomojiMood.curious] =
          (scores[AgentKaomojiMood.curious] ?? 0) + score;
    }
  }

  static void _scoreShocking(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = [
      '竟然',
      '居然',
      '没想到',
      '震惊',
      '天哪',
      '卧槽',
      'wtf',
      '离谱',
      '惊了',
      '真的假的',
    ];
    if (keys.any(t.contains) || t.contains('!!') || t.contains('！！')) {
      scores[AgentKaomojiMood.surprised] =
          (scores[AgentKaomojiMood.surprised] ?? 0) + weight;
    }
  }

  static void _scoreTiebaIntent(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = [
      '贴吧',
      '哪个吧',
      '进吧',
      '吧名',
      '吧友',
      '吧内',
      '热帖',
      '发帖',
      '帖子',
      '回帖',
      '回复',
      '楼层',
      '楼中楼',
      '签到',
      '收藏',
      '关注',
      'tid',
      'pid',
      'browse',
    ];
    final barPattern = RegExp(r'[\u4e00-\u9fff]{2,8}吧(?!友|内|名)');
    if (keys.any(t.contains) || barPattern.hasMatch(t)) {
      scores[AgentKaomojiMood.focused] =
          (scores[AgentKaomojiMood.focused] ?? 0) + weight;
    }
  }

  static void _scoreComplaint(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = ['烦', '气死', '无语', '累了', '不行', '好难', '崩溃', '救命'];
    if (keys.any(t.contains)) {
      scores[AgentKaomojiMood.sorry] =
          (scores[AgentKaomojiMood.sorry] ?? 0) + weight;
    }
  }

  static void _scoreApology(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = ['抱歉', '对不起', '不好意思', '失礼', '委屈你了'];
    if (keys.any(t.contains)) {
      scores[AgentKaomojiMood.surrender] =
          (scores[AgentKaomojiMood.surrender] ?? 0) + weight;
    }
  }

  static void _scoreSorryTone(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = [
      '出错',
      '失败',
      '无法',
      '不能',
      '未配置',
      '请先',
      '没有权限',
      '未登录',
      '找不到',
      '没找到',
      '不支持',
    ];
    if (keys.any(t.contains)) {
      scores[AgentKaomojiMood.sorry] =
          (scores[AgentKaomojiMood.sorry] ?? 0) + weight;
    }
  }

  static void _scoreHappyTone(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const strong = ['太好了', '搞定', '成功了', '完成了', '没问题', '可以了', '祝'];
    const mild = ['好的', '找到', '成功', '可以', '希望', '推荐', '如下'];

    var score = 0;
    if (strong.any(t.contains)) score += weight + 1;
    if (mild.any(t.contains)) score += weight - 1;

    if (score > 0) {
      scores[AgentKaomojiMood.happy] =
          (scores[AgentKaomojiMood.happy] ?? 0) + score;
    }
  }

  /// 识别 AI 回复里自带的颜文字（含库内标准形与常见变体）。
  static void _scoreEmbeddedKaomojis(
    String raw,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    if (raw.isEmpty) return;

    const libraryMoods = <String, AgentKaomojiMood>{
      AgentKaomojiLibrary.cry: AgentKaomojiMood.sorry,
      AgentKaomojiLibrary.bow: AgentKaomojiMood.surrender,
      AgentKaomojiLibrary.smug: AgentKaomojiMood.happy,
      AgentKaomojiLibrary.shocked: AgentKaomojiMood.surprised,
      AgentKaomojiLibrary.drool: AgentKaomojiMood.dazed,
      AgentKaomojiLibrary.angry: AgentKaomojiMood.error,
      AgentKaomojiLibrary.wink: AgentKaomojiMood.curious,
      AgentKaomojiLibrary.gentle: AgentKaomojiMood.thinking,
      AgentKaomojiLibrary.determined: AgentKaomojiMood.working,
      AgentKaomojiLibrary.wave: AgentKaomojiMood.welcome,
    };

    AgentKaomojiMood? matched;
    var matchedAt = -1;

    void consider(String token, AgentKaomojiMood mood) {
      final idx = raw.lastIndexOf(token);
      if (idx < 0 || idx < matchedAt) return;
      matchedAt = idx;
      matched = mood;
    }

    for (final entry in libraryMoods.entries) {
      consider(entry.key, entry.value);
    }

    const extraPatterns = <String, AgentKaomojiMood>{
      '(T_T)': AgentKaomojiMood.sorry,
      '(╥_╥)': AgentKaomojiMood.sorry,
      '(;ω;)': AgentKaomojiMood.sorry,
      '(；ω；)': AgentKaomojiMood.sorry,
      'QAQ': AgentKaomojiMood.sorry,
      'TAT': AgentKaomojiMood.sorry,
      'T.T': AgentKaomojiMood.sorry,
      '(≧▽≦)': AgentKaomojiMood.happy,
      '(⌒▽⌒)': AgentKaomojiMood.happy,
      '(￣ω￣)': AgentKaomojiMood.happy,
      '(・∀・)': AgentKaomojiMood.happy,
      '(°o°)': AgentKaomojiMood.surprised,
      '(⊙_⊙)': AgentKaomojiMood.surprised,
      '(・_・)?': AgentKaomojiMood.curious,
    };
    for (final entry in extraPatterns.entries) {
      consider(entry.key, entry.value);
    }

    // 哭脸变体：(´；ω；`) / (´;ω;`) 等
    final cryVariantPattern = RegExp(
      r'\([\u00b4\u2019`"]?[;\uFF1B]?\u03c9[;\uFF1B]?[\u00b4\u2019`"]?\)',
    );
    for (final match in cryVariantPattern.allMatches(raw)) {
      consider(match.group(0)!, AgentKaomojiMood.sorry);
    }

    if (matched != null) {
      scores[matched!] = (scores[matched!] ?? 0) + weight;
    }
  }

  static void _scoreUnicodeEmojis(
    String raw,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    if (raw.isEmpty) return;

    const sorry = ['😭', '🥲', '😢', '😿', '💔'];
    const happy = ['😊', '😄', '😁', '🥳', '🎉', '👍', '❤', '♥'];
    const surprised = ['😱', '😲', '😳', '🤯'];
    const thinking = ['🤔', '💭'];

    AgentKaomojiMood? matched;
    var matchedAt = -1;

    void consider(String emoji, AgentKaomojiMood mood) {
      final idx = raw.lastIndexOf(emoji);
      if (idx < 0 || idx < matchedAt) return;
      matchedAt = idx;
      matched = mood;
    }

    for (final e in sorry) {
      consider(e, AgentKaomojiMood.sorry);
    }
    for (final e in happy) {
      consider(e, AgentKaomojiMood.happy);
    }
    for (final e in surprised) {
      consider(e, AgentKaomojiMood.surprised);
    }
    for (final e in thinking) {
      consider(e, AgentKaomojiMood.thinking);
    }

    if (matched != null) {
      scores[matched!] = (scores[matched!] ?? 0) + weight;
    }
  }

  static void _scoreEmpathy(
    String t,
    Map<AgentKaomojiMood, int> scores, {
    required int weight,
  }) {
    const keys = [
      '抱抱',
      '心疼',
      '别难过',
      '别哭',
      '不哭',
      '难受',
      '委屈',
      '理解你',
      '懂你',
      '陪着你',
      '我懂',
    ];
    if (keys.any(t.contains)) {
      scores[AgentKaomojiMood.sorry] =
          (scores[AgentKaomojiMood.sorry] ?? 0) + weight;
    }
  }
}
