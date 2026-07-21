import '../models/agent_result_block.dart';
import 'agent_app_tools.dart';
import 'agent_meta_tools.dart';

abstract final class AgentResultBuilder {
  AgentResultBuilder._();

  /// 收集工具结果卡片；元工具会展开嵌套 leaf 步骤。
  static void absorbResults(
    String toolName,
    Map<String, dynamic> json,
    List<AgentResultBlock> sink,
  ) {
    if (AgentMetaTools.isMetaTool(toolName)) {
      if (json['error'] != null && !shouldSuppressErrorCard(toolName, json)) {
        final block = fromTool(toolName, json);
        if (block != null && !_isDuplicateErrorBlock(sink, block)) {
          sink.add(block);
        }
        return;
      }
      for (final nested in AgentMetaTools.nestedStepResults(toolName, json)) {
        absorbResults(nested.key, nested.value, sink);
      }
      final metaBlock = fromTool(toolName, json);
      if (metaBlock != null) sink.add(metaBlock);
      return;
    }

    if (json['error'] != null && shouldSuppressErrorCard(toolName, json)) {
      return;
    }

    final block = fromTool(toolName, json);
    if (block != null) {
      if (block.type == AgentResultType.error &&
          _isDuplicateErrorBlock(sink, block)) {
        return;
      }
      sink.add(block);
    }
  }

  static bool shouldSuppressErrorCard(
    String toolName,
    Map<String, dynamic> json,
  ) {
    if (toolName == 'find_video_posts' &&
        json['error'] == null &&
        json['hint'] != null) {
      return true;
    }
    // 艺术工具错误不再静默吞掉——改为展示引导性错误，让 AI 自我纠错。
    return false;
  }

  static bool _isDuplicateErrorBlock(
    List<AgentResultBlock> sink,
    AgentResultBlock block,
  ) {
    if (block.type != AgentResultType.error) return false;
    final text = block.items.map((i) => i.content?.trim() ?? '').join('\n');
    for (final existing in sink) {
      if (existing.type != AgentResultType.error) continue;
      final existingText = existing.items
          .map((i) => i.content?.trim() ?? '')
          .join('\n');
      if (existingText == text) return true;
      if (text.isNotEmpty &&
          existingText.isNotEmpty &&
          (existingText.contains(text) || text.contains(existingText))) {
        return true;
      }
    }
    return false;
  }

  /// 同轮多条错误卡片合并为一张。
  static List<AgentResultBlock> mergeErrorBlocks(
    List<AgentResultBlock> blocks,
  ) {
    final out = <AgentResultBlock>[];
    final errorTexts = <String>[];

    void flushErrors() {
      if (errorTexts.isEmpty) return;
      final unique = errorTexts.toSet().toList();
      out.add(
        AgentResultBlock(
          type: AgentResultType.error,
          label: '出错了',
          items: [AgentResultItem(content: unique.join('\n'))],
        ),
      );
      errorTexts.clear();
    }

    for (final block in blocks) {
      if (block.type != AgentResultType.error) {
        flushErrors();
        out.add(block);
        continue;
      }
      for (final item in block.items) {
        final t = item.content?.trim();
        if (t != null && t.isNotEmpty) errorTexts.add(t);
      }
    }
    flushErrors();
    return out;
  }

  static AgentResultBlock? fromTool(
    String toolName,
    Map<String, dynamic> json,
  ) {
    if (json['error'] != null) {
      if (shouldSuppressErrorCard(toolName, json)) return null;

      return AgentResultBlock(
        type: AgentResultType.error,

        label: '出错了',

        items: [AgentResultItem(content: json['error']?.toString())],
      );
    }

    return switch (toolName) {
      'list_followed_bars' => _bars(json),

      'get_bar_posts' ||
      'search_threads' ||
      'discover_posts' ||
      'get_recommend_feed' ||
      'get_user_posts' => _barPosts(json),

      'find_video_posts' =>
        json['posts'] is List ? _barPosts(json) : _postDetail(json),

      'search_forums' => _forums(json),

      'get_forum_info' => _forumInfo(json),

      'get_post_detail' => _postDetail(json),

      'read_post' => _postReadSummary(json),

      'get_post_replies' || 'get_sub_replies' => _replies(json, toolName),

      'list_favorites' => _favorites(json),

      'list_at_me' || 'list_reply_me' => _notifyItems(json, toolName),

      'get_my_profile' => _profile(json),

      'sign_bar' => _signResult(json),

      'follow_bar' || 'unfollow_bar' => _followResult(json),

      'web_search' => _webSearch(json),

      'list_skills' => _skillsList(json),

      'list_tool_recipes' => _toolRecipes(json),

      'draw_figlet' ||
      'draw_pixel_art' ||
      'draw_ascii_grid' ||
      'style_unicode_text' ||
      'draw_shape' => _artResult(json, toolName),

      'save_skill' || 'delete_skill' => _metaAction(json),

      _ when AgentAppTools.isAppTool(toolName) => _appAction(json),

      _ => null,
    };
  }

  static AgentResultBlock? _bars(Map<String, dynamic> json) {
    final raw = json['bars'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((b) {
      final map = Map<String, dynamic>.from(b);

      return AgentResultItem(
        barName: map['name']?.toString(),

        avatar: map['avatar']?.toString(),
      );
    }).toList();

    if (items.isEmpty) {
      return const AgentResultBlock(
        type: AgentResultType.bars,

        label: '关注的吧',

        items: [],
      );
    }

    final count = json['count'] ?? items.length;

    return AgentResultBlock(
      type: AgentResultType.bars,

      label: '关注了 $count 个吧',

      items: items,
    );
  }

  static AgentResultBlock? _forums(Map<String, dynamic> json) {
    final raw = json['forums'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((f) {
      final map = Map<String, dynamic>.from(f);

      final name = map['name']?.toString() ?? '';

      final members = map['member_count'];

      return AgentResultItem(
        barName: name,

        content: members != null ? '成员 $members' : null,
      );
    }).toList();

    final query = json['query']?.toString() ?? '';

    return AgentResultBlock(
      type: AgentResultType.bars,

      label: query.isNotEmpty ? '搜索吧 · $query' : '搜索吧',

      items: items,
    );
  }

  static AgentResultBlock? _forumInfo(Map<String, dynamic> json) {
    final forum = json['forum'];

    if (forum is! Map) return null;

    final map = Map<String, dynamic>.from(forum);

    final name = map['name']?.toString() ?? '吧详情';

    final members = map['member_count'];

    final posts = map['post_count'];

    final slogan = map['slogan']?.toString();

    final bits = <String>[
      if (members != null) '成员 $members',

      if (posts != null) '帖子 $posts',

      if (slogan != null && slogan.isNotEmpty) slogan,
    ];

    return AgentResultBlock(
      type: AgentResultType.bars,

      label: name,

      items: [
        AgentResultItem(
          barName: name,

          avatar: map['avatar']?.toString(),

          content: bits.join(' · '),
        ),
      ],
    );
  }

  static AgentResultBlock? _barPosts(Map<String, dynamic> json) {
    final raw = json['posts'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((p) {
      final map = Map<String, dynamic>.from(p);

      return AgentResultItem(
        tid: map['tid']?.toString(),

        title: map['title']?.toString(),

        barName: map['bar_name']?.toString() ?? json['bar_name']?.toString(),

        author: map['author']?.toString(),

        replyCount: _int(map['reply_count']),

        hasVideo: map['has_video'] == true || map['has_video'] == 1,

        content: map['match_reason']?.toString(),
      );
    }).toList();

    if (items.isEmpty) return null;

    final label = _postsLabel(json);

    return AgentResultBlock(
      type: AgentResultType.posts,

      label: label,

      items: items,
    );
  }

  static String _postsLabel(Map<String, dynamic> json) {
    if (json['intent'] != null) {
      final intent = json['intent']?.toString() ?? '';
      final bar = json['bar_name']?.toString();
      final scanned = json['candidates_scanned'];
      final suffix = scanned != null ? ' · 筛了 $scanned 条' : '';
      if (bar != null && bar.isNotEmpty) {
        return '$bar · 需求「$intent」$suffix';
      }
      return '需求「$intent」$suffix';
    }

    if (json['query'] != null) {
      final bar = json['bar_name']?.toString();

      final q = json['query'];

      return bar != null && bar.isNotEmpty ? '$bar · 搜「$q」' : '搜「$q」';
    }

    if (json.containsKey('has_more')) return '推荐流 · 第${json['page'] ?? 1} 页';

    if (json['video_only'] == true) {
      final bar = json['bar_name']?.toString();
      final scanned = json['pages_scanned'];
      final pageLabel = scanned != null
          ? '翻了 $scanned 页'
          : '第${json['page'] ?? 1} 页';
      if (bar != null && bar.isNotEmpty) {
        return '$bar · 视频帖 · $pageLabel';
      }
      return '视频帖 · $pageLabel';
    }

    if (json['portrait'] != null) return '用户帖子 · 第${json['page'] ?? 1} 页';

    final bar = json['bar_name']?.toString() ?? '吧内';

    return '$bar · 帖子流 · 第${json['page'] ?? 1} 页';
  }

  static AgentResultBlock? _postDetail(Map<String, dynamic> json) {
    final comments =
        (json['top_comments'] as List?)?.whereType<Map>().map((c) {
          final map = Map<String, dynamic>.from(c);

          return AgentResultItem(
            floor: _int(map['floor']),

            author: map['author']?.toString(),

            content: map['content']?.toString(),
          );
        }).toList() ??
        const <AgentResultItem>[];

    return AgentResultBlock(
      type: AgentResultType.postDetail,

      label: json['has_video'] == true
          ? '${json['bar_name']?.toString().trim().isNotEmpty == true ? json['bar_name'] : '视频帖'} · 详情'
          : json['bar_name']?.toString() ?? '帖子详情',

      items: [
        AgentResultItem(
          tid: json['tid']?.toString(),

          title: json['title']?.toString(),

          barName: json['bar_name']?.toString(),

          author: json['author']?.toString(),

          replyCount: _int(json['reply_count']),

          hasVideo: json['has_video'] == true || json['has_video'] == 1,

          content: json['content']?.toString(),

          comments: comments,
        ),
      ],
    );
  }

  static AgentResultBlock? _postReadSummary(Map<String, dynamic> json) {
    final focus = json['focus']?.toString().trim();
    final label = focus != null && focus.isNotEmpty
        ? '已阅读 · $focus'
        : '已阅读 · ${json['title']?.toString() ?? '帖子'}';

    return AgentResultBlock(
      type: AgentResultType.postDetail,
      label: label,
      items: [
        AgentResultItem(
          tid: json['tid']?.toString(),
          title: json['title']?.toString(),
          barName: json['bar_name']?.toString(),
          author: json['author']?.toString(),
          replyCount: _int(json['reply_count']),
          hasVideo: json['has_video'] == true || json['has_video'] == 1,
          content:
              json['reading_summary']?.toString() ??
              json['body_excerpt']?.toString(),
        ),
      ],
    );
  }

  static AgentResultBlock? _replies(Map<String, dynamic> json, String tool) {
    final raw = tool == 'get_sub_replies'
        ? json['sub_replies']
        : json['replies'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((c) {
      final map = Map<String, dynamic>.from(c);

      return AgentResultItem(
        floor: _int(map['floor']),

        author: map['author']?.toString(),

        content: map['content']?.toString(),

        replyCount: _int(map['likes']),
      );
    }).toList();

    final tid = json['tid']?.toString() ?? '';

    return AgentResultBlock(
      type: AgentResultType.postDetail,

      label: tool == 'get_sub_replies' ? '楼中楼 · $tid' : '回复 · $tid',

      items: items,
    );
  }

  static AgentResultBlock? _favorites(Map<String, dynamic> json) {
    final raw = json['posts'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((p) {
      final map = Map<String, dynamic>.from(p);

      return AgentResultItem(
        tid: map['tid']?.toString(),

        title: map['title']?.toString(),

        barName: map['bar_name']?.toString(),
      );
    }).toList();

    final count = json['count'] ?? items.length;

    return AgentResultBlock(
      type: AgentResultType.favorites,

      label: '收藏 $count 条',

      items: items,
    );
  }

  static AgentResultBlock? _notifyItems(
    Map<String, dynamic> json,
    String tool,
  ) {
    final raw = json['items'];

    if (raw is! List) return null;

    final items = raw.whereType<Map>().map((n) {
      final map = Map<String, dynamic>.from(n);

      return AgentResultItem(
        tid: map['tid']?.toString(),

        barName: map['bar_name']?.toString(),

        author: map['author']?.toString(),

        content: map['content']?.toString(),
      );
    }).toList();

    return AgentResultBlock(
      type: AgentResultType.posts,

      label: tool == 'list_at_me' ? '@ 我的' : '回复我的',

      items: items,
    );
  }

  static AgentResultBlock? _profile(Map<String, dynamic> json) {
    final profile = json['profile'];

    if (profile is! Map) return null;

    final map = Map<String, dynamic>.from(profile);

    final name =
        map['nick_name']?.toString() ?? map['user_name']?.toString() ?? '我的资料';

    final bits = <String>[
      if (map['user_name'] != null) '@${map['user_name']}',

      if (map['post_num'] != null) '发帖 ${map['post_num']}',

      if (map['fans_num'] != null) '粉丝 ${map['fans_num']}',

      if (map['intro'] != null && map['intro'].toString().isNotEmpty)
        map['intro'].toString(),
    ];

    return AgentResultBlock(
      type: AgentResultType.postDetail,

      label: '用户资料',

      items: [
        AgentResultItem(
          title: name,

          author: map['user_name']?.toString(),

          content: bits.join(' · '),
        ),
      ],
    );
  }

  static AgentResultBlock? _webSearch(Map<String, dynamic> json) {
    // AI 自判：搜索结果仅自用、用户不需要看原始链接时，不渲染卡片
    if (json['show_card'] == false) return null;
    final raw = json['results'];
    if (raw is! List) return null;
    var items = raw.whereType<Map>().map((r) {
      final map = Map<String, dynamic>.from(r);
      final url = map['url']?.toString() ?? '';
      return AgentResultItem(
        title: map['title']?.toString(),
        url: url,
        barName: _host(url),
        content: map['snippet']?.toString(),
      );
    }).toList();
    // 精选：只展示最相关的 top 条（服务侧已截断，这里兜底）
    final top = json['top'];
    if (top is int && top > 0 && top < items.length) {
      items = items.take(top).toList();
    }
    final query = json['query']?.toString() ?? '';
    return AgentResultBlock(
      type: AgentResultType.webSearch,
      label: query.isNotEmpty ? '联网 · $query' : '联网搜索',
      items: items,
    );
  }

  static String? _host(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    return host.replaceFirst(RegExp(r'^www\.'), '');
  }

  static AgentResultBlock? _skillsList(Map<String, dynamic> json) {
    final raw = json['skills'];
    if (raw is! List || raw.isEmpty) {
      return AgentResultBlock(
        type: AgentResultType.postDetail,
        label: '技能库',
        items: [AgentResultItem(content: '暂无保存的技能')],
      );
    }
    final items = raw.whereType<Map>().map((s) {
      final map = Map<String, dynamic>.from(s);
      final name = map['name']?.toString() ?? '未命名';
      final desc = map['description']?.toString() ?? '';
      final steps = map['step_count'];
      final bits = <String>[
        if (desc.isNotEmpty) desc,
        if (steps != null) '$steps 步',
      ];
      return AgentResultItem(barName: name, content: bits.join(' · '));
    }).toList();
    return AgentResultBlock(
      type: AgentResultType.bars,
      label: '已保存技能 (${items.length})',
      items: items,
    );
  }

  static AgentResultBlock? _toolRecipes(Map<String, dynamic> json) {
    final raw = json['recipes'];
    if (raw is! List || raw.isEmpty) {
      return AgentResultBlock(
        type: AgentResultType.postDetail,
        label: '工具配方',
        items: [AgentResultItem(content: '暂无内置配方')],
      );
    }
    final items = raw.whereType<Map>().map((r) {
      final map = Map<String, dynamic>.from(r);
      final title = map['title']?.toString() ?? map['id']?.toString() ?? '';
      final desc = map['description']?.toString() ?? '';
      final steps = map['steps'];
      final stepCount = steps is List ? steps.length : 0;
      final bits = <String>[
        if (desc.isNotEmpty) desc,
        if (stepCount > 0) '$stepCount 步',
      ];
      return AgentResultItem(barName: title, content: bits.join(' · '));
    }).toList();
    return AgentResultBlock(
      type: AgentResultType.bars,
      label: '工具搭配配方 (${items.length})',
      items: items,
    );
  }

  static AgentResultBlock? _artResult(
    Map<String, dynamic> json,
    String toolName,
  ) {
    final kind = json['kind']?.toString() ?? 'ascii';
    final label = switch (toolName) {
      'draw_figlet' => 'FIGlet',
      'draw_pixel_art' => '像素画',
      'draw_ascii_grid' => '字符网格画',
      'style_unicode_text' => '花式字',
      _ => '小画',
    };

    if (json['error'] != null) {
      return AgentResultBlock(
        type: AgentResultType.error,
        label: label,
        items: [AgentResultItem(content: json['error'].toString())],
      );
    }

    if ((kind == 'pixel' || kind == 'grid' || kind == 'shape') &&
        json['pixels'] is List) {
      final pixels = (json['pixels'] as List).map((e) => e.toString()).toList();
      final width = json['width'] is int
          ? json['width'] as int
          : int.tryParse(json['width']?.toString() ?? '') ?? 0;
      final height = json['height'] is int
          ? json['height'] as int
          : int.tryParse(json['height']?.toString() ?? '') ?? 0;
      return AgentResultBlock(
        type: AgentResultType.art,
        label: label,
        items: [
          AgentResultItem(
            title: json['text']?.toString(),
            content: json['ascii_preview']?.toString(),
            artWidth: width,
            artHeight: height,
            artPixels: pixels,
          ),
        ],
      );
    }

    final art = json['art']?.toString() ?? '';
    if (art.isEmpty) return null;
    return AgentResultBlock(
      type: AgentResultType.art,
      label: label,
      items: [AgentResultItem(title: json['text']?.toString(), content: art)],
    );
  }

  static AgentResultBlock? _metaAction(Map<String, dynamic> json) {
    final msg =
        json['message']?.toString() ?? json['error']?.toString() ?? '已执行';
    if (json['error'] != null) {
      return AgentResultBlock(
        type: AgentResultType.error,
        label: '技能操作',
        items: [AgentResultItem(content: msg)],
      );
    }
    return AgentResultBlock(
      type: AgentResultType.postDetail,
      label: '技能',
      items: [AgentResultItem(content: msg)],
    );
  }

  static AgentResultBlock? _appAction(Map<String, dynamic> json) {
    if (json['ok'] != true) {
      return AgentResultBlock(
        type: AgentResultType.error,
        label: '操作失败',
        items: [
          AgentResultItem(
            content: json['error']?.toString() ?? json['message']?.toString(),
          ),
        ],
      );
    }
    final msg = json['message']?.toString() ?? '已执行';
    final tid = json['tid']?.toString();
    return AgentResultBlock(
      type: AgentResultType.postDetail,
      label: 'App 操作',
      items: [
        AgentResultItem(
          tid: tid,
          title: json['title']?.toString(),
          barName: json['bar_name']?.toString(),
          content: msg,
        ),
      ],
    );
  }

  static AgentResultBlock? _signResult(Map<String, dynamic> json) {
    final bar = json['bar_name']?.toString() ?? '';

    final msg =
        json['message']?.toString() ??
        (json['signed'] == true ? '签到成功' : '签到失败');

    return AgentResultBlock(
      type: AgentResultType.postDetail,

      label: bar.isNotEmpty ? '$bar 签到' : '签到',

      items: [AgentResultItem(content: msg, barName: bar)],
    );
  }

  static AgentResultBlock? _followResult(Map<String, dynamic> json) {
    final bar = json['bar_name']?.toString() ?? '';
    final action = json['action']?.toString();
    final ok = json['followed'] == true;
    final msg = json['message']?.toString() ?? (ok ? '操作成功' : '操作失败');
    final label = switch (action) {
      'unfollow' => bar.isNotEmpty ? '取消关注 · $bar' : '取消关注',
      _ => bar.isNotEmpty ? '关注 · $bar' : '关注吧',
    };
    return AgentResultBlock(
      type: AgentResultType.postDetail,
      label: label,
      items: [AgentResultItem(content: msg, barName: bar)],
    );
  }

  static int? _int(dynamic value) {
    if (value is int) return value;

    return int.tryParse(value?.toString() ?? '');
  }
}
