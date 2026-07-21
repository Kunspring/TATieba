import 'agent_tools.dart';
import 'agent_meta_tools.dart';

/// 工具选择打分与最优工具推断（纯函数，零网络依赖，可离线量化评测）。
///
/// 设计取舍：不调用 LLM，用「工具描述关键词重叠 + 意图触发词」做确定性打分。
/// - 优点：零成本、可复现、可度量，适合做路由辅助信号与回归测试。
/// - 缺点：无法理解极模糊的语义（如「搜贴吧」vs「搜帖子」）。
/// 在 Agent 中它仅作为辅助信号；真正的工具选型仍由 LLM 函数调用完成。
abstract final class AgentToolValidator {
  AgentToolValidator._();

  /// 每个 leaf 工具的意图触发词（命中即显著加分）。人工归纳，覆盖常见说法。
  static const Map<String, List<String>> _triggers = {
    'search_threads': ['搜', '搜索', '查帖', '找帖', '关键词', '搜一下', '查一下'],
    'discover_posts': ['找', '想要', '推荐', '氛围', '类型', '什么样的帖', '来点', '有没有', '哪种'],
    'read_post': [
      '读',
      '解读',
      '评价',
      '总结',
      '靠不靠谱',
      '评论区',
      '这帖说啥',
      '站队',
      '槽点',
      '分析',
    ],
    'get_post_detail': ['帖子详情', '详情', '点开看'],
    'get_bar_posts': ['翻', '吧的帖', '吧里'],
    'get_forum_info': ['吧详情', '吧介绍', '吧信息', '贴吧详情'],
    'search_forums': ['搜吧', '找吧', '搜贴吧', '找贴吧', '哪些吧', '什么吧'],
    'find_video_posts': ['视频', 'vid', '带视频'],
    'sign_bar': ['签到'],
    'follow_bar': ['关注', '加上关注'],
    'unfollow_bar': ['取消关注', '取关'],
    'list_followed_bars': ['关注的吧', '我关注的'],
    'list_favorites': ['收藏', '我收藏的'],
    'get_my_profile': ['我的资料', '我是谁', '我的信息'],
    'get_user_posts': ['他的帖子', '用户发帖', '某人发的'],
    'list_at_me': ['@我', '提到我', '艾特'],
    'list_reply_me': ['回复我', '回我的'],
    'web_search': ['天气', '新闻', '百科', '价格', '实时', '查一下网', '百度'],
    'draw_figlet': ['figlet', '大字', '横幅'],
    'draw_pixel_art': ['像素画', '像素图'],
    'draw_ascii_grid': ['ascii', '字符画'],
    'style_unicode_text': ['花式字', '艺术字', 'unicode'],
    'draw_shape': ['爱心', '星星', '笑脸', '猫', '花', '骷髅', '图形', '画个'],
  };

  /// 对全部 leaf 工具打分（分数越高越匹配）。[message] 为自然语言请求。
  static Map<String, double> scoreToolSelection(String message) {
    final msg = _normalize(message);
    final msgTokens = _tokenize(msg);
    final scores = <String, double>{};

    for (final def in AgentTools.definitions) {
      final fn = def['function'];
      if (fn is! Map) continue;
      final name = fn['name']?.toString() ?? '';
      if (name.isEmpty || AgentMetaTools.isMetaTool(name)) continue;

      var score = 0.0;

      // 1) 意图触发词命中
      final triggers = _triggers[name] ?? const [];
      for (final t in triggers) {
        if (msg.contains(t)) score += 2.0;
      }

      // 2) 工具名子串命中
      if (msg.contains(name)) score += 3.0;

      // 3) 描述关键词重叠（bigram 级）
      final desc = (fn['description']?.toString() ?? '').toLowerCase();
      final descTokens = _tokenize(desc);
      for (final tk in descTokens) {
        if (msgTokens.contains(tk)) score += 1.0;
      }

      if (score > 0) scores[name] = score;
    }
    return scores;
  }

  /// 返回得分最高的工具；若最高分低于 [minScore] 则返回 null（交给 LLM/纯聊判定）。
  static String? topTool(String message, {double minScore = 1.0}) {
    final scores = scoreToolSelection(message);
    String? best;
    var bestScore = 0.0;
    scores.forEach((name, s) {
      if (s > bestScore) {
        bestScore = s;
        best = name;
      }
    });
    if (best == null || bestScore < minScore) return null;
    return best;
  }

  static String _normalize(String text) => text.trim().toLowerCase();

  static Set<String> _tokenize(String text) {
    final tokens = <String>{};
    for (final m in RegExp(r'[a-z0-9]{2,}').allMatches(text)) {
      tokens.add(m.group(0)!);
    }
    final chinese = text.replaceAll(RegExp(r'[^一-龥]'), '');
    for (var i = 0; i + 2 <= chinese.length; i++) {
      tokens.add(chinese.substring(i, i + 2));
    }
    if (chinese.length == 1) tokens.add(chinese);
    return tokens;
  }
}
