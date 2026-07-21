import 'dart:convert';

import '../models/tieba_post.dart';
import '../utils/agent_post_reader.dart';
import 'agent_app_tools.dart';
import 'agent_config_service.dart';
import 'agent_meta_tools.dart';
import 'agent_persona.dart';
import 'agent_post_discovery.dart';
import 'agent_art_tools.dart';
import 'tieba_account_service.dart';
import 'tieba_client.dart';
import 'tieba_favorite_service.dart';
import 'sign_in_reminder_service.dart';
import 'web_search_service.dart';

abstract final class AgentTools {
  static String get systemPrompt => AgentPersona.systemPrompt;

  static List<Map<String, dynamic>> get definitions => [
    ...dataToolDefinitions,
    ...AgentAppTools.definitions,
    ...AgentArtTools.definitions,
    ...AgentMetaTools.apiDefinitions,
  ];

  static List<Map<String, dynamic>> get dataToolDefinitions =>
      _dataToolDefinitions;

  static List<Map<String, dynamic>> get _dataToolDefinitions => [
    _tool('list_followed_bars', '获取当前账号关注的贴吧列表'),
    _tool(
      'get_bar_posts',
      '按时间顺序翻某个吧的帖子流（最新帖列表）。'
          '仅当用户明确要「看看/翻翻某某吧、某某吧有啥新帖」时用。'
          '找特定主题/类型/氛围的帖必须用 discover_posts 或 search_threads，禁止用本工具代替找帖。'
          'bar_name 必须来自用户原话，不要从界面状态或 home_bar_filter 猜测。',
      {
        'bar_name': _str('贴吧名称（用户明确点名的吧），例如 孙笑川'),
        'page': _int('页码，从 1 开始'),
        'limit': _int('返回条数 1~15，按当前需求自行决定'),
      },
      ['bar_name'],
    ),
    _tool(
      'get_post_detail',
      '获取帖子详情摘要（用于展示卡片，正文与评论较短）',
      {'tid': _str('帖子 tid')},
      ['tid'],
    ),
    _tool(
      'read_post',
      '深入阅读帖子正文与评论，供你理解内容后再回答。'
          '用户要摘要/解读/评价/站队/找槽点/问「这帖说啥/靠不靠谱/评论区咋样」时用；'
          '有 tid 时优先本工具，不要用 search_threads 代替阅读。'
          '不知道 tid 时先用 search_threads、get_ui_context 或 list_favorites 拿到 tid 再读。',
      {
        'tid': _str('帖子 tid'),
        'focus': _str('可选，用户问题或你要关注的阅读角度'),
        'comment_pages': _int('拉取评论页数 1~3，默认 2；看舆论/热评时建议 2'),
      },
      ['tid'],
    ),
    _tool(
      'get_post_replies',
      '获取帖子回复楼层（分页）',
      {'tid': _str('帖子 tid'), 'page': _int('页码，从 1 开始')},
      ['tid'],
    ),
    _tool(
      'get_sub_replies',
      '获取楼中楼回复',
      {'tid': _str('帖子 tid'), 'pid': _str('楼层 pid'), 'page': _int('页码，从 1 开始')},
      ['tid', 'pid'],
    ),
    _tool('list_favorites', '获取当前账号收藏的帖子', {
      'limit': _int('返回条数 1~15，按当前需求自行决定'),
    }),
    _tool(
      'search_threads',
      '按关键词搜索帖子列表（只返回标题/摘要，不能理解正文）',
      {
        'query': _str('搜索关键词'),
        'bar_name': _str('可选，限定在某个吧内搜索'),
        'page': _int('页码，从 1 开始'),
        'limit': _int('返回条数 1~15，按当前需求自行决定'),
      },
      ['query'],
    ),
    _tool(
      'discover_posts',
      '按用户需求智能找帖。用户描述「想要什么样的帖」而不是给关键词时用此工具；'
          '会理解需求、扩展多种搜索词、扫推荐流/吧内帖，并按契合度排序。'
          '关键词搜不到或需求很抽象时优先用它，别死守一条 search_threads。',
      {
        'intent': _str('用户想找什么样的帖，用自然语言描述需求/氛围/主题，不要只写一两个关键词'),
        'bar_name': _str('可选，仅当用户明确限定在某个吧内找时才传；不要从界面上下文推断'),
        'page': _int('页码，从 1 开始'),
        'limit': _int('返回条数 1~10，默认 5'),
      },
      ['intent'],
    ),
    _tool(
      'search_forums',
      '按关键词搜索贴吧',
      {'query': _str('搜索关键词'), 'page': _int('页码，从 1 开始')},
      ['query'],
    ),
    _tool(
      'get_forum_info',
      '获取贴吧详情（成员数、简介等）',
      {'bar_name': _str('贴吧名称')},
      ['bar_name'],
    ),
    _tool('get_recommend_feed', '获取首页个性化推荐流', {
      'page': _int('页码，从 1 开始'),
      'limit': _int('返回条数 1~15，按当前需求自行决定'),
    }),
    _tool(
      'find_video_posts',
      '查找带视频的帖子。用户要找/推荐/来个视频帖时用此工具；'
          '要几条就传 limit（如「俩」=2），**只调一次**，工具会自动翻页凑够，'
          '禁止 run_plan/repeat_call 连翻多页或自己连调 page=1/2。'
          'limit=1 时返回该帖详情卡片（可点开阅读），不要只报 tid。',
      {
        'bar_name': _str('可选，限定在某个吧内找；不传则在首页推荐流找'),
        'page': _int('可选起始页码，从 1 开始；一般不用传'),
        'limit': _int('返回条数 1~5，找「一个」时用 1'),
      },
    ),
    _tool('get_my_profile', '获取当前登录用户的资料'),
    _tool(
      'get_user_posts',
      '获取某用户发布的主题帖',
      {
        'portrait': _str('用户 portrait（可从资料接口获取）'),
        'page': _int('页码，从 1 开始'),
        'limit': _int('返回条数 1~15，按当前需求自行决定'),
      },
      ['portrait'],
    ),
    _tool('list_at_me', '获取 @ 我的消息', {'page': _int('页码，从 1 开始')}),
    _tool('list_reply_me', '获取回复我的消息', {'page': _int('页码，从 1 开始')}),
    _tool('sign_bar', '给某个贴吧签到', {'bar_name': _str('贴吧名称')}, ['bar_name']),
    _tool('follow_bar', '关注某个贴吧', {'bar_name': _str('贴吧名称')}, ['bar_name']),
    _tool('unfollow_bar', '取消关注某个贴吧', {'bar_name': _str('贴吧名称')}, ['bar_name']),
    _tool(
      'web_search',
      '搜索互联网获取实时信息（新闻、百科、价格、天气、通用知识等，非贴吧内帖子）。'
          '搜索结果可能只是你自己用来确认事实/补全知识，也可能要展示给用户看——用 show_card 控制是否出卡片。',
      {
        'query': _str('搜索关键词，尽量具体'),
        'show_card': _bool(
          '是否把搜索结果渲染成卡片展示给用户。'
          '默认 true。仅当你自己为了确认事实/补全知识而搜、用户并不需要看原始链接时，设 false（答案写进你的回复即可）。',
        ),
        'top': _int('最多展示几条结果（1~6），默认 6；只挑最相关的几条展示、省空间时用。'),
      },
      ['query'],
    ),
  ];

  static Map<String, dynamic> _tool(
    String name,
    String description, [
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
  ]) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  static Map<String, dynamic> _str(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, dynamic> _int(String description) => {
    'type': 'integer',
    'description': description,
  };

  static Map<String, dynamic> _bool(String description) => {
    'type': 'boolean',
    'description': description,
  };

  static String describeCall(String name, Map<String, dynamic> args) {
    final page = _pageArg(args);
    final pageSuffix = page > 1 ? '（第 $page 页）' : '';
    final limit = args['limit'];
    final limitSuffix = limit != null ? '，$limit条' : '';
    return switch (name) {
      'list_followed_bars' => '查看关注的贴吧',
      'get_bar_posts' =>
        '翻阅「${args['bar_name'] ?? '贴吧'}」帖子$pageSuffix$limitSuffix',
      'get_post_detail' => '打开帖子 ${args['tid'] ?? ''}',
      'read_post' =>
        '阅读帖子 ${args['tid'] ?? ''}${args['focus'] != null ? ' · ${args['focus']}' : ''}',
      'get_post_replies' => '读取帖子回复 ${args['tid'] ?? ''}$pageSuffix',
      'get_sub_replies' => '读取楼中楼 ${args['pid'] ?? ''}$pageSuffix',
      'list_favorites' => '查看收藏帖子$limitSuffix',
      'search_threads' => '搜索帖子「${args['query'] ?? ''}」$pageSuffix$limitSuffix',
      'discover_posts' =>
        '按需求找帖「${args['intent'] ?? ''}」${args['bar_name'] != null ? ' · ${args['bar_name']}' : ''}$pageSuffix$limitSuffix',
      'search_forums' => '搜索贴吧「${args['query'] ?? ''}」$pageSuffix',
      'get_forum_info' => '查看吧「${args['bar_name'] ?? ''}」详情',
      'get_recommend_feed' => '拉取推荐流$pageSuffix$limitSuffix',
      'find_video_posts' =>
        '找带视频的帖${args['bar_name'] != null ? ' · ${args['bar_name']}' : ''}$pageSuffix$limitSuffix',
      'get_my_profile' => '读取我的资料',
      'get_user_posts' => '查看用户发帖$pageSuffix$limitSuffix',
      'list_at_me' => '查看 @ 我的消息$pageSuffix',
      'list_reply_me' => '查看回复我的消息$pageSuffix',
      'sign_bar' => '签到「${args['bar_name'] ?? '贴吧'}」',
      'follow_bar' => '关注「${args['bar_name'] ?? '贴吧'}」',
      'unfollow_bar' => '取消关注「${args['bar_name'] ?? '贴吧'}」',
      'web_search' => '联网搜「${args['query'] ?? ''}」',
      'draw_figlet' ||
      'draw_pixel_art' ||
      'draw_ascii_grid' ||
      'style_unicode_text' ||
      'draw_shape' => AgentArtTools.describeCall(name, args),
      _ when AgentMetaTools.isMetaTool(name) => AgentMetaTools.describeCall(
        name,
        args,
      ),
      _ when AgentAppTools.isAppTool(name) => AgentAppTools.describeCall(
        name,
        args,
      ),
      _ => name,
    };
  }

  /// 校验某工具的必填参数是否齐备（不执行工具，仅看 schema）。
  /// 返回缺失/非法参数说明列表；空列表表示通过。
  static List<String> validateArgs(String toolName, Map<String, dynamic> args) {
    final errors = <String>[];
    Map<String, dynamic>? schema;
    for (final def in definitions) {
      final fn = def['function'];
      if (fn is Map && fn['name'] == toolName) {
        schema = fn as Map<String, dynamic>;
        break;
      }
    }
    if (schema == null) return errors; // 无 schema（如元工具）不校验
    final params = schema['parameters'];
    if (params is! Map) return errors;
    final required = params['required'];
    if (required is! List) return errors;
    for (final r in required) {
      final key = r.toString();
      final raw = args[key];
      final present =
          raw != null && (raw is! String || raw.toString().trim().isNotEmpty);
      if (!present) errors.add('缺少必填参数「$key」');
    }
    return errors;
  }

  /// 执行 leaf 工具（数据 + App 控制），供元工具编排调用。
  static Future<String> invokeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    if (AgentMetaTools.isMetaTool(name)) {
      return jsonEncode({'error': '元工具不能作为 run_plan/batch_call 的子步骤: $name'});
    }
    if (AgentAppTools.isAppTool(name)) {
      return AgentAppTools.execute(name, args);
    }
    final paramErrors = validateArgs(name, args);
    if (paramErrors.isNotEmpty) {
      return jsonEncode({'error': '参数校验失败：${paramErrors.join('；')}'});
    }
    try {
      switch (name) {
        case 'list_followed_bars':
          return jsonEncode(await _listFollowedBars());
        case 'get_bar_posts':
          return jsonEncode(await _getBarPosts(args));
        case 'get_post_detail':
          return jsonEncode(await _getPostDetail(args));
        case 'read_post':
          return jsonEncode(await _readPost(args));
        case 'get_post_replies':
          return jsonEncode(await _getPostReplies(args));
        case 'get_sub_replies':
          return jsonEncode(await _getSubReplies(args));
        case 'list_favorites':
          return jsonEncode(await _listFavorites(args));
        case 'search_threads':
          return jsonEncode(await _searchThreads(args));
        case 'discover_posts':
          return jsonEncode(await _discoverPosts(args));
        case 'search_forums':
          return jsonEncode(await _searchForums(args));
        case 'get_forum_info':
          return jsonEncode(await _getForumInfo(args));
        case 'get_recommend_feed':
          return jsonEncode(await _getRecommendFeed(args));
        case 'find_video_posts':
          return jsonEncode(await _findVideoPosts(args));
        case 'get_my_profile':
          return jsonEncode(await _getMyProfile());
        case 'get_user_posts':
          return jsonEncode(await _getUserPosts(args));
        case 'list_at_me':
          return jsonEncode(await _listAtMe(args));
        case 'list_reply_me':
          return jsonEncode(await _listReplyMe(args));
        case 'sign_bar':
          return jsonEncode(await _signBar(args));
        case 'follow_bar':
          return jsonEncode(await _followBar(args));
        case 'unfollow_bar':
          return jsonEncode(await _unfollowBar(args));
        case 'web_search':
          return jsonEncode(await _webSearch(args));
        case 'draw_figlet':
        case 'draw_pixel_art':
        case 'draw_ascii_grid':
        case 'style_unicode_text':
        case 'draw_shape':
          return jsonEncode(await AgentArtTools.execute(name, args));
        default:
          return jsonEncode({'error': '未知工具: $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  static Future<String> execute(String name, Map<String, dynamic> args) async {
    if (AgentMetaTools.isMetaTool(name)) {
      return AgentMetaTools.execute(name, args);
    }
    return invokeTool(name, args);
  }

  static Future<String?> _bduss() => TiebaAccountService.getBduss();
  static Future<String?> _stoken() => TiebaAccountService.getStoken();

  static Future<Map<String, dynamic>?> _loginError() async {
    if (await TiebaAccountService.isBound()) return null;
    return {'error': '未登录贴吧，请先在个人页扫码登录'};
  }

  static int _pageArg(Map<String, dynamic> args) {
    return args['page'] is int
        ? args['page'] as int
        : int.tryParse(args['page']?.toString() ?? '') ?? 1;
  }

  static int _limitArg(
    Map<String, dynamic> args, {
    int defaultLimit = 3,
    int max = 15,
  }) {
    final raw = args['limit'];
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed < 1) return defaultLimit;
    return parsed.clamp(1, max);
  }

  static List<Map<String, dynamic>> _mapPosts(
    Iterable<TiebaPost> posts, {
    required int limit,
  }) {
    return posts
        .take(limit)
        .map(
          (p) => {
            'tid': p.id,
            'title': p.title,
            'author': p.author,
            'reply_count': p.replyCount,
            'bar_name': p.barName,
            'has_video': _postHasVideo(p),
            if (p.cover?.isNotEmpty == true) 'cover': p.cover,
          },
        )
        .toList();
  }

  static Future<Map<String, dynamic>> _listFollowedBars() async {
    final err = await _loginError();
    if (err != null) return err;
    final bars = await TiebaAccountService.fetchFollowedBars();
    return {
      'bars': bars.map((b) => {'name': b.name, 'avatar': b.avatar}).toList(),
      'count': bars.length,
    };
  }

  static Future<Map<String, dynamic>> _getBarPosts(
    Map<String, dynamic> args,
  ) async {
    final barName = args['bar_name']?.toString() ?? '';
    if (barName.isEmpty) return {'error': '缺少 bar_name'};
    final page = _pageArg(args);
    final limit = _limitArg(args);
    final bduss = await _bduss();
    var posts = await TiebaClient.fetchBarThreads(
      barName,
      page: page,
      bduss: bduss,
    );
    if (posts.isEmpty) {
      posts = await TiebaClient.fetchBarThreadsForm(
        barName,
        page: page,
        bduss: bduss,
      );
    }
    return {
      'bar_name': barName,
      'page': page,
      'limit': limit,
      'posts': _mapPosts(posts, limit: limit),
    };
  }

  static Future<Map<String, dynamic>> _getPostDetail(
    Map<String, dynamic> args,
  ) async {
    final tid = args['tid']?.toString() ?? '';
    if (tid.isEmpty) return {'error': '缺少 tid'};
    final bduss = await _bduss();
    final stoken = await _stoken();
    final detail = await TiebaClient.fetchPostDetail(
      tid,
      bduss: bduss,
      stoken: stoken,
    );
    if (detail == null) return {'error': '帖子不存在或加载失败'};
    return _postDetailJson(detail);
  }

  static Future<Map<String, dynamic>> _readPost(
    Map<String, dynamic> args,
  ) async {
    final tid = args['tid']?.toString().trim() ?? '';
    if (tid.isEmpty) return {'error': '缺少 tid'};
    final focus = args['focus']?.toString().trim();
    final commentPages = _limitArg(args, defaultLimit: 2, max: 3);

    final bduss = await _bduss();
    final stoken = await _stoken();
    final first = await TiebaClient.fetchPostDetail(
      tid,
      bduss: bduss,
      stoken: stoken,
    );
    if (first == null) return {'error': '帖子不存在或加载失败'};

    var comments = List<TiebaComment>.from(first.comments);
    var pagesFetched = 1;
    var hasMore = first.hasMore;

    for (var page = 2; page <= commentPages && hasMore; page++) {
      final more = await TiebaClient.fetchPostDetail(
        tid,
        page: page,
        bduss: bduss,
        stoken: stoken,
      );
      if (more == null || more.comments.isEmpty) break;
      comments = mergeAgentReadComments(comments, more.comments);
      pagesFetched = page;
      hasMore = more.hasMore;
    }

    return AgentPostReader.buildReadPayload(
      detail: first,
      comments: comments,
      focus: focus?.isNotEmpty == true ? focus : null,
      commentPagesFetched: pagesFetched,
      hasMoreComments: hasMore,
    );
  }

  static Future<Map<String, dynamic>> _getPostReplies(
    Map<String, dynamic> args,
  ) async {
    final tid = args['tid']?.toString() ?? '';
    if (tid.isEmpty) return {'error': '缺少 tid'};
    final page = _pageArg(args);
    final bduss = await _bduss();
    final stoken = await _stoken();
    final detail = await TiebaClient.fetchPostDetail(
      tid,
      page: page,
      bduss: bduss,
      stoken: stoken,
    );
    if (detail == null) return {'error': '帖子不存在或加载失败'};
    return {
      'tid': tid,
      'page': page,
      'has_more': detail.hasMore,
      'replies': detail.comments
          .take(20)
          .map(
            (c) => {
              'pid': c.id,
              'floor': c.floor,
              'author': c.author,
              'content': c.content.length > 160
                  ? '${c.content.substring(0, 160)}…'
                  : c.content,
              'likes': c.likes,
            },
          )
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _getSubReplies(
    Map<String, dynamic> args,
  ) async {
    final tid = args['tid']?.toString() ?? '';
    final pid = args['pid']?.toString() ?? '';
    if (tid.isEmpty || pid.isEmpty) return {'error': '缺少 tid 或 pid'};
    final page = _pageArg(args);
    final bduss = await _bduss();
    final stoken = await _stoken();
    final subs = await TiebaClient.fetchMoreSubComments(
      tid,
      pid,
      page: page,
      bduss: bduss,
      stoken: stoken,
    );
    return {
      'tid': tid,
      'pid': pid,
      'page': page,
      'sub_replies': subs
          .take(20)
          .map(
            (c) => {
              'author': c.author,
              'content': c.content.length > 120
                  ? '${c.content.substring(0, 120)}…'
                  : c.content,
              'likes': c.likes,
            },
          )
          .toList(),
    };
  }

  static Map<String, dynamic> _postDetailJson(TiebaPostDetail detail) {
    final post = detail.post;
    final hasVideo = post.video != null && post.video!.src.isNotEmpty;
    return {
      'tid': post.id,
      'title': post.title,
      'author': post.author,
      'bar_name': post.barName,
      'has_video': hasVideo,
      'content': post.content.length > 500
          ? '${post.content.substring(0, 500)}…'
          : post.content,
      'reply_count': detail.totalComments,
      'top_comments': detail.comments
          .take(5)
          .map(
            (c) => {
              'floor': c.floor,
              'author': c.author,
              'content': c.content.length > 120
                  ? '${c.content.substring(0, 120)}…'
                  : c.content,
            },
          )
          .toList(),
    };
  }

  static Future<List<TiebaPost>> _loadPostsForScan({
    String? barName,
    required int page,
  }) async {
    final bduss = await _bduss();
    if (barName != null && barName.trim().isNotEmpty) {
      var posts = await TiebaClient.fetchBarThreads(
        barName.trim(),
        page: page,
        bduss: bduss,
      );
      if (posts.isEmpty) {
        posts = await TiebaClient.fetchBarThreadsForm(
          barName.trim(),
          page: page,
          bduss: bduss,
        );
      }
      return posts;
    }
    final loadType = page == 1 ? 1 : 2;
    final feed = await TiebaClient.fetchPersonalized(
      loadType: loadType,
      page: page == 1 ? 1 : page - 1,
      bduss: bduss,
    );
    return feed.posts;
  }

  static bool _postHasVideo(TiebaPost post) {
    final video = post.video;
    if (video == null) return false;
    if (video.src.isNotEmpty) return true;
    return video.width > 0 || (video.coverSrc?.isNotEmpty ?? false);
  }

  static Future<Map<String, dynamic>> _findVideoPosts(
    Map<String, dynamic> args,
  ) async {
    final barName = args['bar_name']?.toString().trim();
    if (barName != null && barName.isEmpty) {
      return {'error': 'bar_name 不能为空字符串'};
    }
    final startPage = _pageArg(args);
    final limit = _limitArg(args, defaultLimit: 1, max: 5);
    const maxPagesToScan = 8;

    final found = <TiebaPost>[];
    var page = startPage;
    var pagesScanned = 0;

    while (found.length < limit && pagesScanned < maxPagesToScan) {
      final posts = await _loadPostsForScan(barName: barName, page: page);
      pagesScanned++;
      if (posts.isEmpty) break;
      for (final post in posts) {
        if (!_postHasVideo(post)) continue;
        if (found.any((p) => p.id == post.id)) continue;
        found.add(post);
        if (found.length >= limit) break;
      }
      page++;
    }

    if (found.isEmpty) {
      return {
        'video_only': true,
        'posts': <Map<String, dynamic>>[],
        'pages_scanned': pagesScanned,
        'page': startPage,
        'bar_name': ?barName,
        'hint': barName != null && barName.isNotEmpty
            ? '「$barName」翻了 $pagesScanned 页没找到带视频的帖子，可以换吧或指定关键词试试'
            : '推荐流翻了 $pagesScanned 页没找到带视频的帖子，可以指定某个吧名再试',
      };
    }

    if (limit == 1) {
      final bduss = await _bduss();
      final stoken = await _stoken();
      final detail = await TiebaClient.fetchPostDetail(
        found.first.id,
        bduss: bduss,
        stoken: stoken,
      );
      if (detail != null) {
        return _postDetailJson(detail);
      }
    }

    return {
      'bar_name': ?barName,
      'page': startPage,
      'pages_scanned': pagesScanned,
      'limit': limit,
      'video_only': true,
      'posts': _mapPosts(found, limit: limit),
    };
  }

  static Future<Map<String, dynamic>> _listFavorites(
    Map<String, dynamic> args,
  ) async {
    final limit = _limitArg(args);
    final favs = await TiebaFavoriteService.loadFavoritePosts();
    return {
      'count': favs.length,
      'limit': limit,
      'posts': favs
          .take(limit)
          .map((p) => {'tid': p.id, 'title': p.title, 'bar_name': p.barName})
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _discoverPosts(
    Map<String, dynamic> args,
  ) async {
    final intent = args['intent']?.toString().trim() ?? '';
    if (intent.isEmpty) return {'error': '缺少 intent'};
    final barRaw = args['bar_name']?.toString().trim();
    final barName = barRaw != null && barRaw.isNotEmpty ? barRaw : null;
    final page = _pageArg(args);
    final limit = _limitArg(args, defaultLimit: 5, max: 10);
    final bduss = await _bduss();
    return AgentPostDiscovery.discover(
      intent: intent,
      barName: barName,
      limit: limit,
      page: page,
      bduss: bduss,
    );
  }

  static Future<Map<String, dynamic>> _searchThreads(
    Map<String, dynamic> args,
  ) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return {'error': '缺少 query'};
    final barName = args['bar_name']?.toString();
    final page = _pageArg(args);
    final limit = _limitArg(args);
    final bduss = await _bduss();
    final posts = await TiebaClient.searchThreads(
      query: query,
      barName: barName,
      page: page,
      bduss: bduss,
    );
    return {
      'query': query,
      if (barName != null && barName.isNotEmpty) 'bar_name': barName,
      'page': page,
      'limit': limit,
      'posts': _mapPosts(posts, limit: limit),
    };
  }

  static Future<Map<String, dynamic>> _searchForums(
    Map<String, dynamic> args,
  ) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return {'error': '缺少 query'};
    final page = _pageArg(args);
    final bduss = await _bduss();
    final forums = await TiebaClient.searchForums(
      query: query,
      page: page,
      bduss: bduss,
    );
    return {'query': query, 'page': page, 'forums': forums.take(15).toList()};
  }

  static Future<Map<String, dynamic>> _getForumInfo(
    Map<String, dynamic> args,
  ) async {
    final barName = args['bar_name']?.toString() ?? '';
    if (barName.isEmpty) return {'error': '缺少 bar_name'};
    final bduss = await _bduss();
    final info = await TiebaClient.fetchForumDetail(barName, bduss: bduss);
    if (info == null) return {'error': '吧不存在或加载失败'};
    return {'forum': info};
  }

  static Future<Map<String, dynamic>> _getRecommendFeed(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final page = _pageArg(args);
    final limit = _limitArg(args);
    final bduss = await _bduss();
    final loadType = page == 1 ? 1 : 2;
    final feed = await TiebaClient.fetchPersonalized(
      loadType: loadType,
      page: page == 1 ? 1 : page - 1,
      bduss: bduss,
    );
    return {
      'page': page,
      'limit': limit,
      'has_more': feed.hasMore,
      'posts': _mapPosts(feed.posts, limit: limit),
    };
  }

  static Future<Map<String, dynamic>> _getMyProfile() async {
    final err = await _loginError();
    if (err != null) return err;
    final bduss = await _bduss();
    if (bduss == null || bduss.isEmpty) return {'error': '未登录'};
    final profile = await TiebaClient.fetchSelfProfile(bduss: bduss);
    if (profile == null) {
      return {
        'profile': {
          'user_name': await TiebaAccountService.getTiebaUserName(),
          'nick_name': await TiebaAccountService.getTiebaName(),
          'portrait': await TiebaAccountService.getPortrait(),
        },
      };
    }
    return {'profile': profile};
  }

  static Future<Map<String, dynamic>> _getUserPosts(
    Map<String, dynamic> args,
  ) async {
    final portrait = args['portrait']?.toString() ?? '';
    if (portrait.isEmpty) return {'error': '缺少 portrait'};
    final page = _pageArg(args);
    final limit = _limitArg(args);
    final bduss = await _bduss();
    final posts = await TiebaClient.fetchUserPosts(
      portrait: portrait,
      page: page,
      bduss: bduss,
    );
    return {
      'portrait': portrait,
      'page': page,
      'limit': limit,
      'posts': _mapPosts(posts, limit: limit),
    };
  }

  static Future<Map<String, dynamic>> _listAtMe(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final bduss = await _bduss();
    if (bduss == null) return {'error': '未登录'};
    final page = _pageArg(args);
    final items = await TiebaClient.getAts(pn: page, bduss: bduss);
    return {
      'page': page,
      'items': items
          .take(15)
          .map(
            (a) => {
              'tid': a.tid.toString(),
              'bar_name': a.fname,
              'author': a.replyer.nickName ?? a.replyer.userName,
              'content': a.text.length > 120
                  ? '${a.text.substring(0, 120)}…'
                  : a.text,
            },
          )
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _listReplyMe(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final bduss = await _bduss();
    if (bduss == null) return {'error': '未登录'};
    final page = _pageArg(args);
    final items = await TiebaClient.getReplys(pn: page, bduss: bduss);
    return {
      'page': page,
      'items': items
          .take(15)
          .map(
            (r) => {
              'tid': r.tid.toString(),
              'bar_name': r.fname,
              'author': r.replyer.nickName ?? r.replyer.userName,
              'content': r.text.length > 120
                  ? '${r.text.substring(0, 120)}…'
                  : r.text,
            },
          )
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _signBar(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final barName = args['bar_name']?.toString() ?? '';
    if (barName.isEmpty) return {'error': '缺少 bar_name'};
    final bduss = await _bduss();
    if (bduss == null) return {'error': '未登录'};
    final tbs = await TiebaAccountService.getTbs();
    if (tbs.isEmpty) return {'error': '获取 tbs 失败，请重新登录'};
    final ok = await TiebaClient.signInBar(barName, bduss, tbs);
    if (ok) {
      await SignInReminderService.instance.markSignedInToday();
      return {'bar_name': barName, 'signed': true, 'message': '签到成功'};
    }
    return {
      'bar_name': barName,
      'signed': false,
      'error': '签到失败或今日已签',
      'message': '签到失败或今日已签',
    };
  }

  static Future<Map<String, dynamic>> _followBar(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final barName = args['bar_name']?.toString().trim() ?? '';
    if (barName.isEmpty) return {'error': '缺少 bar_name'};
    final ok = await TiebaAccountService.followBar(barName);
    if (ok) {
      return {
        'bar_name': barName,
        'followed': true,
        'action': 'follow',
        'message': '已关注 $barName',
      };
    }
    return {
      'bar_name': barName,
      'followed': false,
      'action': 'follow',
      'error': '关注失败，请稍后重试',
      'message': '关注失败，请稍后重试',
    };
  }

  static Future<Map<String, dynamic>> _unfollowBar(
    Map<String, dynamic> args,
  ) async {
    final err = await _loginError();
    if (err != null) return err;
    final barName = args['bar_name']?.toString().trim() ?? '';
    if (barName.isEmpty) return {'error': '缺少 bar_name'};
    final ok = await TiebaAccountService.unfollowBar(barName);
    if (ok) {
      return {
        'bar_name': barName,
        'unfollowed': true,
        'action': 'unfollow',
        'message': '已取消关注 $barName',
      };
    }
    return {
      'bar_name': barName,
      'unfollowed': false,
      'action': 'unfollow',
      'error': '取消关注失败，请稍后重试',
      'message': '取消关注失败，请稍后重试',
    };
  }

  static Future<Map<String, dynamic>> _webSearch(
    Map<String, dynamic> args,
  ) async {
    final query = args['query']?.toString() ?? '';
    if (query.trim().isEmpty) return {'error': '缺少 query'};
    final config = await AgentConfigService.load();
    final showCard = args['show_card'];
    final topRaw = args['top'];
    final top = topRaw is int ? topRaw : int.tryParse(topRaw?.toString() ?? '');
    final topClamped = top?.clamp(1, 6);
    final result = await WebSearchService.search(
      query: query,
      serperApiKey: config.serperApiKey,
      maxResults: topClamped,
    );
    if (result['error'] != null) return result;
    return {
      ...result,
      'show_card': showCard is bool ? showCard : true,
      'top': ?topClamped,
    };
  }
}
