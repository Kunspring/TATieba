/// 判断用户请求是否应先调用 Agent 工具（查帖 / 控 App 等）。
abstract final class AgentToolIntent {
  AgentToolIntent._();

  static bool likelyRequiresTools(String message) {
    final t = _normalize(message);
    if (t.isEmpty) return false;

    if (_negativeToolCue.hasMatch(t)) return false;

    if (_pureChatOnly(t)) return false;

    if (_actionVerb.hasMatch(t)) return true;

    if (_dataNoun.hasMatch(t) && _questionCue.hasMatch(t)) return true;

    if (_barName.hasMatch(t) && _barAction.hasMatch(t)) return true;

    return false;
  }

  static bool likelyRequiresOpenPost(String message) {
    final t = _normalize(message);
    if (t.isEmpty) return false;
    if (!RegExp(r'(打开|看看|进去|跳转|带我|点开|浏览|查看|瞧|读)').hasMatch(t)) {
      return false;
    }
    return _dataNoun.hasMatch(t) ||
        RegExp(r'\btid\b|\d{8,}', caseSensitive: false).hasMatch(t);
  }

  /// 未调用工具却像「已经查完/做完」的回复。
  static bool looksLikePrematureCompletion(
    String content, {
    required bool toolsWereUsed,
  }) {
    if (toolsWereUsed) return false;
    final t = content.trim();
    if (t.isEmpty) return false;

    if (_donePhrase.any(t.contains)) return true;

    if (RegExp(r'^\s*\d+[.、)\]]\s*\S', multiLine: true).allMatches(t).length >=
        2) {
      return true;
    }

    if (RegExp(r'^\s*[-*•]\s+\S', multiLine: true).allMatches(t).length >= 3) {
      return true;
    }

    return false;
  }

  static String get retryNudge =>
      '[系统] 你刚才没有调用任何工具就回复了。此请求必须先调用合适的 tool 获取真实数据或执行 App 操作，禁止编造内容。请立即调用 tool，拿到结果后再用简短口语回复用户。';

  static String _normalize(String text) {
    var t = text.trim();
    if (t.isEmpty) return t;
    t = t.replaceAll(RegExp(r'[#*`>\[\](){}|]'), ' ');
    t = t.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => t);
    if (t.length > 200) t = t.substring(0, 200);
    return t;
  }

  static bool _pureChatOnly(String t) {
    if (RegExp(r'^(你好|嗨|在吗|谢谢|晚安|早上好|哈哈|嗯|哦|啊|唉)').hasMatch(t) &&
        t.length < 24) {
      return true;
    }
    if (RegExp(r'^(我去|卧槽|我靠|呵呵|你是|你个|神经病|有病)').hasMatch(t) && t.length < 32) {
      return true;
    }
    if (RegExp(r'我.*让你.*了吗|谁让你|没让你|别在这').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'(你是猪|你是狗|傻[了逼吗]|笨蛋|滚蛋)').hasMatch(t) &&
        !_explicitDrawRequest.hasMatch(t) &&
        !_dataNoun.hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^(你觉得|你怎么看|聊聊|随便|无聊|好烦|好累|开心|难过)').hasMatch(t) &&
        !_actionVerb.hasMatch(t) &&
        !_dataNoun.hasMatch(t)) {
      return true;
    }
    return false;
  }

  /// 用户明确要画，才算绘画请求（口嗨/斗嘴里的「猪」不算）。
  static final _explicitDrawRequest = RegExp(
    r'画(个|一|下|点|出|张|只|条)?|帮我画|绘制|做(个|一).{0,4}图|'
    r'像素画|ascii|figlet|banner|logo|涂鸦',
    caseSensitive: false,
  );

  static final _negativeToolCue = RegExp(
    r'没让你|让我画了吗|谁让你|不要画|别画|没让你画|我让你.*了吗|'
    r'我踏马让你|我他妈让你|又干嘛去了|你怎么又',
  );

  static final _actionVerb = RegExp(
    r'(打开|看看|带我去|切到|跳转|前往|进入|返回|设置|登录|签到|'
    r'搜索|搜一|搜下|查一|查下|查找|查询|列出|有哪些|还有什么|'
    r'找(个|一|下|到)?|帮我找|帮我看|帮我查|帮我开|帮我搜|刷新|reload|browse|'
    r'总结|摘要|解读|读一|读下|阅读|分析|评价|怎么看|'
    r'画(个|一|下|点|出|张|只|条)|帮我画|绘制|ascii|像素|figlet|banner|logo|涂鸦)',
  );

  static final _dataNoun = RegExp(
    r'(帖子|贴吧|吧友|收藏|关注|回复|私信|消息|热帖|吧务|签到|推荐|视频|'
    r'评论区|热评|槽点|tid|pid)',
  );

  static final _questionCue = RegExp(r'[?？]|吗|么|呢|哪些|什么|怎么|多少|有没有|没');

  static final _barName = RegExp(r'[\u4e00-\u9fffA-Za-z0-9]{2,12}吧');

  static final _barAction = RegExp(r'看|查|搜|开|进|帖|热|签');

  static const _donePhrase = [
    '已经打开',
    '已打开',
    '帮你打开',
    '找到了',
    '查到了',
    '搜到了',
    '以下是',
    '共有',
    '一共',
    '这些帖子',
    '这些吧',
    '签到成功',
    '为你搜索',
    '搜索结果',
    '我帮你',
    '帮你查',
  ];
}
