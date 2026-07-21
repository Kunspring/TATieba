import 'dart:convert';

import 'app_shell_controller.dart';
import 'app_ui_context.dart';

/// AI 可直接驱动 App 界面与导航的工具（不访问贴吧 API）。
abstract final class AgentAppTools {
  AgentAppTools._();

  static const _names = {
    'navigate_tab',
    'open_bar',
    'clear_bar_filter',
    'open_post',
    'open_favorites',
    'open_settings',
    'open_login',
    'open_agent_config',
    'open_agent_chat',
    'close_agent_chat',
    'navigate_back',
    'set_theme',
    'get_ui_context',
  };

  static bool isAppTool(String name) => _names.contains(name);

  static List<Map<String, dynamic>> get definitions => [
    _tool(
      'navigate_tab',
      '切换底部 Tab：首页(home)、进吧(forum)、消息(messages)、个人(profile)',
      {'tab': _str('目标 Tab：home | forum | messages | profile')},
      ['tab'],
    ),
    _tool(
      'open_bar',
      '打开某个贴吧的首页帖子流（等同于用户从进吧页选中该吧）',
      {'bar_name': _str('贴吧名称，例如 孙笑川')},
      ['bar_name'],
    ),
    _tool('clear_bar_filter', '清除首页吧筛选，回到推荐流'),
    _tool(
      'open_post',
      '在 App 内打开帖子详情页呈现给用户（用户说「打开/看看这个帖」时使用）',
      {
        'tid': _str('帖子 tid'),
        'title': _str('可选，帖子标题'),
        'bar_name': _str('可选，所在吧名'),
        'author': _str('可选，作者'),
        'reply_count': _int('可选，回复数'),
      },
      ['tid'],
    ),
    _tool('open_favorites', '打开收藏页'),
    _tool('open_settings', '打开设置页'),
    _tool('open_login', '打开扫码登录页'),
    _tool('open_agent_config', '打开助手设置页（API 配置）'),
    _tool('open_agent_chat', '展开全屏助手对话'),
    _tool('close_agent_chat', '关闭助手对话层'),
    _tool('navigate_back', '返回上一页（等同系统返回）'),
    _tool(
      'set_theme',
      '切换外观：light 白天 / dark 夜间 / system 跟随系统',
      {'mode': _str('light | dark | system')},
      ['mode'],
    ),
    _tool(
      'get_ui_context',
      '读取用户当前 App 界面上下文（所在 Tab、打开的页面、正在阅读的帖子等）。'
          '不截图、不走视觉，用于理解「这个帖」「当前页」「我在看什么」等指代。',
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

  static String describeCall(String name, Map<String, dynamic> args) {
    return switch (name) {
      'navigate_tab' => '切换到 ${_tabLabel(args['tab']?.toString())}',
      'open_bar' => '打开「${args['bar_name'] ?? '贴吧'}」',
      'clear_bar_filter' => '回到首页推荐',
      'open_post' => '打开帖子 ${args['tid'] ?? ''}',
      'open_favorites' => '打开收藏',
      'open_settings' => '打开设置',
      'open_login' => '打开登录',
      'open_agent_config' => '打开助手设置',
      'open_agent_chat' => '展开助手对话',
      'close_agent_chat' => '关闭助手对话',
      'navigate_back' => '返回上一页',
      'set_theme' => '切换为 ${args['mode'] ?? '主题'}',
      'get_ui_context' => '查看当前界面',
      _ => name,
    };
  }

  static String _tabLabel(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'home' || '首页' || '0' => '首页',
      'forum' || '进吧' || '1' => '进吧',
      'messages' || 'message' || '消息' || '2' => '消息',
      'profile' || '个人' || '3' => '个人',
      _ => raw ?? 'Tab',
    };
  }

  static AppShellTab? _parseTab(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'home' || '首页' || '0' => AppShellTab.home,
      'forum' || '进吧' || '1' => AppShellTab.forum,
      'messages' || 'message' || '消息' || '2' => AppShellTab.messages,
      'profile' || '个人' || '3' => AppShellTab.profile,
      _ => null,
    };
  }

  static int? _intArg(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static Future<String> execute(String name, Map<String, dynamic> args) async {
    final shell = AppShellController.instance;
    try {
      switch (name) {
        case 'navigate_tab':
          final tab = _parseTab(args['tab']?.toString());
          if (tab == null) {
            return _err('无效的 tab，请用 home / forum / messages / profile');
          }
          shell.selectTab(
            tab,
            toast: '已切换到${_tabLabel(args['tab']?.toString())}',
          );
          return _ok(
            name,
            message: '已切换到 ${_tabLabel(args['tab']?.toString())}',
          );

        case 'open_bar':
          final bar = args['bar_name']?.toString().trim() ?? '';
          if (bar.isEmpty) return _err('请提供 bar_name');
          shell.openBar(bar);
          return _ok(name, message: '已打开「$bar」吧', extra: {'bar_name': bar});

        case 'clear_bar_filter':
          shell.clearBarFilter();
          return _ok(name, message: '已回到首页推荐');

        case 'open_post':
          final tid = args['tid']?.toString().trim() ?? '';
          if (tid.isEmpty) return _err('请提供 tid');
          shell.openPost(
            tid: tid,
            title: args['title']?.toString(),
            barName: args['bar_name']?.toString(),
            author: args['author']?.toString(),
            replyCount: _intArg(args['reply_count']),
          );
          return _ok(
            name,
            message: '已打开帖子',
            extra: {
              'tid': tid,
              if (args['title'] != null) 'title': args['title'],
              if (args['bar_name'] != null) 'bar_name': args['bar_name'],
            },
          );

        case 'open_favorites':
          shell.openRoute(AppShellRoute.favorites, toast: '已打开收藏');
          return _ok(name, message: '已打开收藏');

        case 'open_settings':
          shell.openRoute(AppShellRoute.settings, toast: '已打开设置');
          return _ok(name, message: '已打开设置');

        case 'open_login':
          shell.openRoute(AppShellRoute.login, toast: '已打开登录');
          return _ok(name, message: '已打开扫码登录');

        case 'open_agent_config':
          shell.openRoute(AppShellRoute.agentConfig, toast: '已打开助手设置');
          return _ok(name, message: '已打开助手设置');

        case 'open_agent_chat':
          shell.openAgentChat(toast: '已展开助手对话');
          return _ok(name, message: '已展开助手对话');

        case 'close_agent_chat':
          shell.closeAgentChat(toast: '已关闭助手对话');
          return _ok(name, message: '已关闭助手对话');

        case 'navigate_back':
          final popped = shell.maybePop();
          return _ok(
            name,
            message: popped ? '已返回上一页' : '当前已在顶层，无法返回',
            extra: {'popped': popped},
          );

        case 'set_theme':
          final mode = args['mode']?.toString().trim() ?? '';
          if (mode.isEmpty) return _err('请提供 mode：light / dark / system');
          await shell.setThemeMode(mode);
          return _ok(name, message: '已切换外观为 $mode', extra: {'mode': mode});

        case 'get_ui_context':
          return AppUiContextService.instance.toToolResult();

        default:
          return _err('未知 App 工具: $name');
      }
    } catch (e) {
      return _err(e.toString());
    }
  }

  static String _ok(
    String action, {
    required String message,
    Map<String, dynamic>? extra,
  }) {
    return jsonEncode({
      'ok': true,
      'action': action,
      'message': message,
      ...?extra,
    });
  }

  static String _err(String message) => jsonEncode({'error': message});
}
