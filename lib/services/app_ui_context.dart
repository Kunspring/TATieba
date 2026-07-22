import 'dart:convert';

import 'package:flutter/material.dart';

/// 语义化界面路由名（写入 [RouteSettings.name]，供 AI 读取当前界面）。
abstract final class AppUiRouteNames {
  AppUiRouteNames._();

  static const postDetail = '/ui/post-detail';
  static const homeFeed = '/ui/home-feed';
  static const userHome = '/ui/user-home';
  static const subComments = '/ui/sub-comments';
  static const privateChat = '/ui/private-chat';
  static const favorites = '/ui/favorites';
  static const settings = '/ui/settings';
  static const loginHub = '/ui/login-hub';
  static const agentConfig = '/ui/agent-config';
  static const webLogin = '/ui/web-login';
  static const qrLogin = '/ui/qr-login';
  static const imageViewer = '/ui/image-viewer';
  static const videoPlayer = '/ui/video-player';
  static const agentChatOverlay = '/agent-chat-overlay';
}

Route<T> uiPageRoute<T>({
  required String name,
  Map<String, dynamic>? arguments,
  required WidgetBuilder builder,
}) {
  return MaterialPageRoute<T>(
    settings: RouteSettings(name: name, arguments: arguments),
    builder: builder,
  );
}

/// 记录用户当前 Tab、导航栈与页面补充信息，供 AI 理解「当前在看什么」。
class AppUiContextService {
  AppUiContextService._();

  static final AppUiContextService instance = AppUiContextService._();

  int _tabIndex = 0;
  String? _selectedBar;
  bool _agentChatOpen = false;
  bool _quickChatOpen = false;

  final List<_RouteFrame> _routeStack = [];
  Map<String, dynamic>? _foregroundExtras;

  void updateShell({
    int? tabIndex,
    String? selectedBar,
    bool? agentChatOpen,
    bool? quickChatOpen,
    bool clearSelectedBar = false,
  }) {
    if (tabIndex != null) _tabIndex = tabIndex;
    if (clearSelectedBar) {
      _selectedBar = null;
    } else if (selectedBar != null) {
      _selectedBar = selectedBar.trim().isEmpty ? null : selectedBar.trim();
    }
    if (agentChatOpen != null) _agentChatOpen = agentChatOpen;
    if (quickChatOpen != null) _quickChatOpen = quickChatOpen;
  }

  void onRoutePushed(Route<dynamic> route) {
    _routeStack.add(_RouteFrame.from(route));
  }

  void onRouteRemoved(Route<dynamic> route) {
    _routeStack.removeWhere((frame) => frame.route == route);
    if (_routeStack.isEmpty) {
      _foregroundExtras = null;
    }
  }

  void setForegroundExtras(Map<String, dynamic>? extras) {
    _foregroundExtras = extras == null || extras.isEmpty
        ? null
        : Map<String, dynamic>.from(extras);
  }

  Map<String, dynamic> snapshot() {
    final routes = _routeStack.map((f) => f.toJson()).toList();
    final foreground = _foregroundRouteJson();
    final out = <String, dynamic>{
      'tab': _tabKey,
      'tab_label': _tabLabel,
      if (_selectedBar != null && _selectedBar!.isNotEmpty)
        'home_bar_filter': _selectedBar,
      'agent_chat_overlay': _agentChatOpen,
      'quick_chat_input': _quickChatOpen,
      'route_stack': routes,
      'foreground': ?foreground,
      'summary': buildSummary(),
    };
    if (foreground != null) {
      _promoteForegroundFields(out, foreground);
    }
    return out;
  }

  /// 把 foreground / detail 里的 tid 等提到顶层，便于 \$prev.tid 引用。
  static void _promoteForegroundFields(
    Map<String, dynamic> out,
    Map<String, dynamic> foreground,
  ) {
    void put(String key, dynamic value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      out.putIfAbsent(key, () => value);
    }

    for (final key in ['tid', 'title', 'bar_name', 'author', 'reply_count']) {
      put(key, foreground[key]);
    }
    final detail = foreground['detail'];
    if (detail is Map) {
      for (final key in ['tid', 'title', 'bar_name', 'author', 'reply_count']) {
        put(key, detail[key]);
      }
    }
  }

  String buildSummary() {
    if (_agentChatOpen) {
      return '用户正在全屏 AI 助手对话界面';
    }

    if (_routeStack.isNotEmpty) {
      final top = _routeStack.last;
      final desc = _describeRoute(top, useExtras: true);
      if (_routeStack.length > 1) {
        return '$desc（下层：${_describeShell()}）';
      }
      return desc;
    }

    final shell = _describeShell();
    if (_quickChatOpen) {
      return '$shell；顶部颜文字快捷输入框已展开';
    }
    return shell;
  }

  String toToolResult() => jsonEncode(snapshot());

  /// 注入系统提示：提醒模型勿把界面上的吧名误用于 get_bar_posts。
  String? buildAgentHint() {
    final parts = <String>['## 当前界面（参考，勿机械套用）'];
    parts.add('- ${_describeShell()}');
    if (_routeStack.isNotEmpty) {
      parts.add('- 前台：${_describeRoute(_routeStack.last, useExtras: true)}');
    }
    if (_selectedBar != null && _selectedBar!.isNotEmpty) {
      parts.add(
        '- 首页当前筛了「$_selectedBar」吧；用户**没明确说**这吧/某某吧时，'
        '找帖用 discover_posts/search_threads，**禁止** get_bar_posts 拉该吧第一页。',
      );
    } else {
      parts.add(
        '- 用户找帖/推荐/有没有某类帖 → discover_posts 或 search_threads；'
        'get_bar_posts 仅当用户明确要翻某个吧的帖子流。',
      );
    }
    return parts.join('\n');
  }

  Map<String, dynamic>? _foregroundRouteJson() {
    if (_routeStack.isEmpty) return null;
    final top = _routeStack.last.toJson();
    if (_foregroundExtras != null && _foregroundExtras!.isNotEmpty) {
      top['detail'] = Map<String, dynamic>.from(_foregroundExtras!);
    }
    top['description'] = _describeRoute(_routeStack.last, useExtras: true);
    return top;
  }

  String get _tabKey => switch (_tabIndex) {
    0 => 'home',
    1 => 'forum',
    2 => 'messages',
    3 => 'profile',
    _ => 'home',
  };

  String get _tabLabel => switch (_tabIndex) {
    0 => '首页',
    1 => '进吧',
    2 => '消息',
    3 => '个人',
    _ => '首页',
  };

  String _describeShell() {
    if (_tabIndex == 0 && _selectedBar != null && _selectedBar!.isNotEmpty) {
      return '用户在首页浏览「$_selectedBar」吧的帖子流';
    }
    return switch (_tabIndex) {
      0 => '用户在首页浏览推荐帖子流',
      1 => '用户在进吧页浏览关注/最近访问的吧',
      2 => '用户在消息页查看私信与通知',
      3 => '用户在个人页',
      _ => '用户在 App 主界面',
    };
  }

  String _describeRoute(_RouteFrame frame, {bool useExtras = false}) {
    final args = frame.params;
    final extras = useExtras ? _foregroundExtras : null;
    return switch (frame.name) {
      AppUiRouteNames.postDetail ||
      '/ui/post-detail' => _postDetailDesc(args, extras),
      AppUiRouteNames.homeFeed || '/ui/home-feed' => _describeShell(),
      AppUiRouteNames.userHome || '/ui/user-home' => _userHomeDesc(args),
      AppUiRouteNames.subComments ||
      '/ui/sub-comments' => _subCommentsDesc(args),
      AppUiRouteNames.privateChat ||
      '/ui/private-chat' => _privateChatDesc(args),
      AppUiRouteNames.favorites || '/ui/favorites' => '用户在收藏页',
      AppUiRouteNames.settings || '/ui/settings' => '用户在设置页',
      AppUiRouteNames.loginHub || '/ui/login-hub' => '用户在登录页',
      AppUiRouteNames.agentConfig || '/ui/agent-config' => '用户在助手 API 设置页',
      AppUiRouteNames.webLogin || '/ui/web-login' => '用户在 Web 登录页',
      AppUiRouteNames.qrLogin || '/ui/qr-login' => '用户在扫码登录页',
      AppUiRouteNames.imageViewer || '/ui/image-viewer' => '用户在查看图片',
      AppUiRouteNames.videoPlayer || '/ui/video-player' => '用户在播放视频',
      AppUiRouteNames.agentChatOverlay ||
      '/agent-chat-overlay' => '用户在全屏 AI 助手对话界面',
      _ => frame.label.isNotEmpty ? '用户在${frame.label}' : '用户在子页面',
    };
  }

  String _postDetailDesc(
    Map<String, dynamic>? args,
    Map<String, dynamic>? extras,
  ) {
    final tid = extras?['tid'] ?? args?['tid'];
    final title = extras?['title'] ?? args?['title'];
    final bar = extras?['bar_name'] ?? args?['bar_name'];
    final author = extras?['author'];
    final parts = <String>['用户在阅读帖子'];
    if (title != null && '$title'.trim().isNotEmpty) {
      parts.add('「$title」');
    }
    if (bar != null && '$bar'.trim().isNotEmpty) {
      parts.add('（$bar吧）');
    }
    if (tid != null && '$tid'.trim().isNotEmpty) {
      parts.add('[tid=$tid]');
    }
    if (author != null && '$author'.trim().isNotEmpty) {
      parts.add('作者：$author');
    }
    return parts.join('');
  }

  String _userHomeDesc(Map<String, dynamic>? args) {
    final name = args?['user_name'] ?? args?['display_name'];
    if (name != null && '$name'.trim().isNotEmpty) {
      return '用户在查看用户「$name」的主页';
    }
    return '用户在查看用户主页';
  }

  String _subCommentsDesc(Map<String, dynamic>? args) {
    final tid = args?['tid'];
    final pid = args?['pid'];
    return '用户在查看楼中楼回复${tid != null ? '（帖 $tid / 楼 $pid）' : ''}';
  }

  String _privateChatDesc(Map<String, dynamic>? args) {
    final name = args?['peer_name'];
    if (name != null && '$name'.trim().isNotEmpty) {
      return '用户在与「$name」的私信对话页';
    }
    return '用户在私信对话页';
  }
}

class _RouteFrame {
  final Route<dynamic> route;
  final String name;
  final String label;
  final Map<String, dynamic>? params;

  _RouteFrame({
    required this.route,
    required this.name,
    required this.label,
    this.params,
  });

  factory _RouteFrame.from(Route<dynamic> route) {
    final settings = route.settings;
    final name = settings.name ?? route.runtimeType.toString();
    Map<String, dynamic>? params;
    final raw = settings.arguments;
    if (raw is Map) {
      params = raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return _RouteFrame(
      route: route,
      name: name,
      label: _labelForName(name),
      params: params,
    );
  }

  static String _labelForName(String name) {
    return switch (name) {
      AppUiRouteNames.postDetail => '帖子详情',
      AppUiRouteNames.userHome => '用户主页',
      AppUiRouteNames.subComments => '楼中楼',
      AppUiRouteNames.privateChat => '私信对话',
      AppUiRouteNames.favorites => '收藏',
      AppUiRouteNames.settings => '设置',
      AppUiRouteNames.loginHub => '登录',
      AppUiRouteNames.agentConfig => '助手设置',
      AppUiRouteNames.webLogin => 'Web 登录',
      AppUiRouteNames.qrLogin => '扫码登录',
      AppUiRouteNames.imageViewer => '图片查看',
      AppUiRouteNames.videoPlayer => '视频播放',
      AppUiRouteNames.agentChatOverlay => 'AI 对话',
      _ => '',
    };
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (label.isNotEmpty) 'label': label,
    if (params != null && params!.isNotEmpty) ...params!,
  };
}
