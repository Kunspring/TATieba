/// 内置工具搭配配方（教 AI 如何组合 leaf 工具）。
abstract final class AgentToolRecipes {
  AgentToolRecipes._();

  static const catalogPrompt = r'''
常见搭配配方（仅多步时参考 run_plan）：
1. discover_read：discover_posts → read_post（$prev.posts.0.tid）
2. discover_open：discover_posts → open_post（$prev.posts.0.tid）
3. search_read：search_threads → read_post（$prev.posts.0.tid）
4. search_open：search_threads → open_post（$prev.posts.0.tid）
5. ui_read：get_ui_context → read_post（$prev.tid）
6. ui_open：get_ui_context → open_post（$prev.tid）
7. find_video_open：find_video_posts(limit=1) → open_post（$prev.tid）

单步任务（只找帖、只搜索、只读帖）请直接调对应 leaf 工具，不要 run_plan。
步骤间传值：$prev.posts.0.tid、$prev.tid 等。''';

  static List<Map<String, dynamic>> listForApi() {
    return _recipes
        .map(
          (r) => {
            'id': r.id,
            'title': r.title,
            'description': r.description,
            'steps': r.exampleSteps,
          },
        )
        .toList();
  }

  /// 规则兜底：从用户话推断常用搭配（无 LLM 时 compose_plan / 路由器用）。
  static List<Map<String, dynamic>>? suggestSteps(
    String text, {
    bool openPost = false,
    String? barName,
  }) {
    final t = text.trim();
    if (t.isEmpty) return null;

    final uiContext = RegExp(r'这个|当前|屏幕|正在看|我在看').hasMatch(t);
    final video = RegExp(r'视频').hasMatch(t);
    final discover =
        !RegExp(r'搜|搜索|关键词').hasMatch(t) &&
        RegExp(r'找|有没有|推荐|那种|想要|来点|整点|类似的').hasMatch(t);
    final search = RegExp(r'搜|搜索').hasMatch(t);
    final read = RegExp(r'总结|解读|说啥|靠谱|评论区|槽点|评价|读|看看内容').hasMatch(t);
    final open = openPost || RegExp(r'打开|带我去|点开|跳转').hasMatch(t);

    Map<String, dynamic> barArg() =>
        barName != null && barName.isNotEmpty ? {'bar_name': barName} : {};

    if (uiContext) {
      if (open) {
        return _cloneSteps('ui_open', intent: t);
      }
      return _cloneSteps('ui_read', intent: t);
    }

    if (video) {
      if (open) return _cloneSteps('find_video_open');
      return [
        {
          'tool': 'find_video_posts',
          'args': {'limit': 1},
          'label': '找视频帖',
        },
      ];
    }

    if (discover) {
      if (open) {
        return _cloneSteps('discover_open', intent: t, extraArgs: barArg());
      }
      if (read) {
        return _cloneSteps('discover_read', intent: t, extraArgs: barArg());
      }
      return [
        {
          'tool': 'discover_posts',
          'args': {'intent': t, 'limit': 3, ...barArg()},
          'label': '按需求找帖',
        },
      ];
    }

    if (search) {
      if (open) return _cloneSteps('search_open', intent: t);
      if (read) return _cloneSteps('search_read', intent: t);
      return [
        {
          'tool': 'search_threads',
          'args': {'query': t, 'limit': 5},
          'label': '搜索',
        },
      ];
    }

    if (open && read) {
      return _cloneSteps('discover_read', intent: t);
    }

    return null;
  }

  static List<Map<String, dynamic>> _cloneSteps(
    String id, {
    String? intent,
    Map<String, dynamic> extraArgs = const {},
  }) {
    final recipe = _recipes.firstWhere((r) => r.id == id);
    return recipe.exampleSteps.map((step) {
      final copy = Map<String, dynamic>.from(step);
      if (copy['args'] is Map) {
        final args = Map<String, dynamic>.from(copy['args'] as Map);
        args.removeWhere((k, v) => v is String && v.startsWith('（'));
        if (intent != null) {
          if (args.containsKey('intent')) args['intent'] = intent;
          if (args.containsKey('query')) args['query'] = intent;
          if (args.containsKey('focus')) args['focus'] = intent;
        }
        args.addAll(extraArgs);
        copy['args'] = args;
      }
      return copy;
    }).toList();
  }

  static const _recipes = [
    _Recipe(
      id: 'discover_read',
      title: '按需求找帖并阅读',
      description: '需求模糊时先 discover_posts，再 read_post 读懂内容',
      exampleSteps: [
        {
          'tool': 'discover_posts',
          'args': {'intent': '（用户描述的需求）', 'limit': 3},
          'label': '按需求找帖',
        },
        {
          'tool': 'read_post',
          'args': {'tid': r'$prev.posts.0.tid', 'focus': '（用户关注点）'},
          'label': '阅读首条',
        },
      ],
    ),
    _Recipe(
      id: 'discover_open',
      title: '按需求找帖并打开',
      description: '找到合适的帖后直接 open_post 给用户看',
      exampleSteps: [
        {
          'tool': 'discover_posts',
          'args': {'intent': '（用户描述）', 'limit': 1},
          'label': '找帖',
        },
        {
          'tool': 'open_post',
          'args': {
            'tid': r'$prev.posts.0.tid',
            'title': r'$prev.posts.0.title',
            'bar_name': r'$prev.posts.0.bar_name',
          },
          'label': '打开',
        },
      ],
    ),
    _Recipe(
      id: 'search_open',
      title: '关键词搜索并打开',
      exampleSteps: [
        {
          'tool': 'search_threads',
          'args': {'query': '（关键词）', 'limit': 5},
          'label': '搜索',
        },
        {
          'tool': 'open_post',
          'args': {
            'tid': r'$prev.posts.0.tid',
            'title': r'$prev.posts.0.title',
            'bar_name': r'$prev.posts.0.bar_name',
          },
          'label': '打开',
        },
      ],
    ),
    _Recipe(
      id: 'ui_open',
      title: '打开当前屏幕上的帖',
      exampleSteps: [
        {'tool': 'get_ui_context', 'label': '读界面'},
        {
          'tool': 'open_post',
          'args': {
            'tid': r'$prev.tid',
            'title': r'$prev.title',
            'bar_name': r'$prev.bar_name',
          },
          'label': '打开当前帖',
        },
      ],
    ),
    _Recipe(
      id: 'search_read',
      title: '关键词搜索并阅读',
      exampleSteps: [
        {
          'tool': 'search_threads',
          'args': {'query': '（关键词）', 'limit': 5},
          'label': '搜索',
        },
        {
          'tool': 'read_post',
          'args': {'tid': r'$prev.posts.0.tid'},
          'label': '阅读',
        },
      ],
    ),
    _Recipe(
      id: 'ui_read',
      title: '读当前屏幕上的帖',
      description: '用户说「这个帖」时用',
      exampleSteps: [
        {'tool': 'get_ui_context', 'label': '读界面'},
        {
          'tool': 'read_post',
          'args': {'tid': r'$prev.tid'},
          'label': '阅读当前帖',
        },
      ],
    ),
    _Recipe(
      id: 'find_video_open',
      title: '找视频帖并打开',
      exampleSteps: [
        {
          'tool': 'find_video_posts',
          'args': {'limit': 1},
          'label': '找视频帖',
        },
        {
          'tool': 'open_post',
          'args': {'tid': r'$prev.tid', 'title': r'$prev.title'},
          'label': '打开',
        },
      ],
    ),
  ];
}

class _Recipe {
  final String id;
  final String title;
  final String description;
  final List<Map<String, dynamic>> exampleSteps;

  const _Recipe({
    required this.id,
    required this.title,
    this.description = '',
    required this.exampleSteps,
  });
}
