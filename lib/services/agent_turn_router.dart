import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/agent_message.dart';
import 'agent_config_service.dart';
import 'agent_tool_intent.dart';
import 'agent_tool_recipes.dart';

/// 每轮对话前的意图理解 + 工具路径规划（LLM 为主，规则兜底）。
class AgentTurnPlan {
  final bool needsTools;
  final bool forceTools;
  final bool openPostAfter;
  final bool pureChat;
  final String? userGoal;
  final String? planText;
  final List<String> suggestedTools;
  final List<Map<String, dynamic>> suggestedPlanSteps;
  final bool useComposePlan;
  final AgentTurnPlanSource source;

  const AgentTurnPlan({
    this.needsTools = false,
    this.forceTools = false,
    this.openPostAfter = false,
    this.pureChat = true,
    this.userGoal,
    this.planText,
    this.suggestedTools = const [],
    this.suggestedPlanSteps = const [],
    this.useComposePlan = false,
    this.source = AgentTurnPlanSource.heuristic,
  });

  bool get useRunPlan =>
      suggestedPlanSteps.length >= 2 || suggestedTools.length >= 2;

  factory AgentTurnPlan.chatOnly() => const AgentTurnPlan(pureChat: true);

  bool get hasGuidance =>
      (planText?.trim().isNotEmpty ?? false) ||
      suggestedTools.isNotEmpty ||
      suggestedPlanSteps.isNotEmpty ||
      useComposePlan ||
      (userGoal?.trim().isNotEmpty ?? false);

  String? buildPromptBlock() {
    if (pureChat && !needsTools) return null;
    if (!hasGuidance && !needsTools) return null;

    final parts = <String>[
      '## 本轮理解（App 预分析，帮你选对工具）',
      '下面是根据用户话和最近上下文推断的，**供你执行时参考**；',
      '若与用户最新一句冲突，以用户最新一句为准。',
    ];
    if (userGoal?.trim().isNotEmpty == true) {
      parts.add('- 用户目标：${userGoal!.trim()}');
    }
    if (planText?.trim().isNotEmpty == true) {
      parts.add('- 建议怎么做：${planText!.trim()}');
    }
    if (suggestedTools.isNotEmpty) {
      parts.add('- 优先工具：${suggestedTools.join(' → ')}');
    }
    if (useRunPlan && suggestedPlanSteps.isNotEmpty) {
      parts.add(
        '- **多步时**可用 run_plan（步骤见配方 list_tool_recipes）；单步请直接调 leaf 工具。',
      );
    } else if (suggestedTools.length == 1) {
      parts.add('- **直接调用** `${suggestedTools.first}`，不要包 run_plan。');
    } else if (suggestedTools.length > 1) {
      parts.add('- 建议顺序：${suggestedTools.join(' → ')}（每步单独调，或 run_plan 串起来）。');
    }
    if (needsTools) {
      parts.add('- **此轮需要真实数据或 App 操作**：必须先调用 tool，禁止编造。');
    }
    if (openPostAfter) {
      parts.add('- 用户可能要**打开帖子看**：查到 tid 后用 open_post。');
    }
    return parts.join('\n');
  }

  String buildRetryNudge() {
    final toolHint = suggestedTools.isEmpty
        ? '合适的 leaf 工具（如 discover_posts、search_threads、read_post）'
        : (useRunPlan && suggestedPlanSteps.length >= 2
              ? 'run_plan 或直接 ${suggestedTools.first}'
              : suggestedTools.first);
    var msg = '[系统] 你刚才没有调用工具就回复了。此轮必须先调用 $toolHint 获取真实数据或完成 App 操作，禁止编造。';
    if (planText?.trim().isNotEmpty == true) {
      msg += '建议路径：${planText!.trim()}。';
    }
    msg += '请立即调用 tool，拿到结果后再用简短口语回复。';
    return msg;
  }
}

enum AgentTurnPlanSource { llm, heuristic }

abstract final class AgentTurnRouter {
  AgentTurnRouter._();

  static const _toolGuide = '''
工具选择（按用户真实意图，不要死记关键词）：
- 描述想要什么样的帖/氛围/类型、搜不到合适结果 → discover_posts
- 用户给了明确搜索词、只要列清单 → search_threads
- 用户明确要翻/看看某个吧的最新帖流 → get_bar_posts（必须用户点名的吧名）
- 找帖/推荐/有没有某类帖 → discover_posts 或 search_threads，禁止 get_bar_posts
- 不要从界面 home_bar_filter 等状态猜吧名去 get_bar_posts 拉第一页
- 要读懂/评价/总结某帖内容 → read_post（需 tid；可先 discover/search/ui_context）
- 「这个帖/当前页/我在看的」→ get_ui_context 再 read_post
- 找视频帖 → find_video_posts（一次调用、传 limit，工具自动翻页；禁止 run_plan 多步翻页）
- 打开/看看/带我去 → open_post（有 tid 时直接调）
- 画个图/ASCII/像素/logo/banner → draw_pixel_art 等（**用户明确说要画**；斗嘴/口嗨禁止调绘画工具）；常见图形（爱心/星星/猫…）优先 draw_shape
- 不确定工具名 → get_tool_catalog（禁止编造工具名）
- 真正多步（找→读/打开）→ run_plan 或 list_tool_recipes 看配方
- 步骤间传值：run_plan 里用 \$prev.posts.0.tid 等引用上一步结果
- 查吧/收藏/消息/签到等 → 对应 list/get/sign 工具
- 纯闲聊/斗嘴/骂人/情绪/观点 → 不用 tool''';

  static Future<AgentTurnPlan> route({
    required String userMessage,
    required List<AgentMessage> history,
    required AgentConfig config,
  }) async {
    final text = userMessage.trim();
    if (text.isEmpty) return AgentTurnPlan.chatOnly();

    if (_isObviousPureChat(text)) {
      return AgentTurnPlan.chatOnly();
    }

    if (!config.isConfigured) {
      return _heuristicPlan(text);
    }

    try {
      final llmPlan = await _routeWithLlm(
        userMessage: text,
        history: history,
        config: config,
      );
      if (llmPlan != null) return llmPlan;
    } catch (_) {}

    return _heuristicPlan(text);
  }

  static bool _isObviousPureChat(String text) {
    if (AgentToolIntent.likelyRequiresTools(text)) return false;
    final t = text.trim();
    if (t.length <= 4) return true;
    if (RegExp(r'我.*让你.*了吗|谁让你|没让你|又干嘛去了').hasMatch(t)) {
      return true;
    }
    return RegExp(
      r'^(你好|嗨|在吗|哈喽|谢谢|晚安|早|嗯|哦|啊|哈+$|我去|卧槽|你是)',
      caseSensitive: false,
    ).hasMatch(t);
  }

  static AgentTurnPlan _heuristicPlan(String text) {
    final needs = AgentToolIntent.likelyRequiresTools(text);
    final open = AgentToolIntent.likelyRequiresOpenPost(text);
    if (!needs && !open) {
      return AgentTurnPlan.chatOnly();
    }

    final tools = <String>[];
    var plan = '';

    if (RegExp(r'这个|当前|屏幕|正在看|我在看').hasMatch(text)) {
      tools.add('get_ui_context');
      plan = '先读当前界面上下文';
    }
    if (RegExp(r'视频').hasMatch(text)) {
      tools.add('find_video_posts');
      plan = plan.isEmpty ? '找带视频的帖' : '$plan，或找视频帖';
    } else if (needs &&
        !RegExp(r'搜|搜索|关键词').hasMatch(text) &&
        RegExp(r'找|有没有|推荐|那种|想要|来点|整点|类似的').hasMatch(text)) {
      tools.add('discover_posts');
      plan = plan.isEmpty ? '按需求智能找帖' : plan;
    } else if (RegExp(r'搜|搜索').hasMatch(text)) {
      tools.add('search_threads');
    }
    if (RegExp(r'总结|解读|说啥|靠谱|评论区|槽点|评价|读').hasMatch(text)) {
      if (!tools.contains('read_post')) tools.add('read_post');
    }
    if (RegExp(
      r'画(个|一|下|点|出|张|只|条)|帮我画|绘制|像素画|ascii|logo|banner|figlet|涂鸦',
    ).hasMatch(text)) {
      tools.add('draw_pixel_art');
      tools.add('draw_shape');
      plan = plan.isEmpty ? '画像素/ASCII 图' : plan;
    }
    if (open) {
      tools.add('open_post');
    }

    final planSteps = AgentToolRecipes.suggestSteps(text, openPost: open);

    return AgentTurnPlan(
      needsTools: true,
      forceTools: needs,
      openPostAfter: open,
      pureChat: false,
      userGoal: _clip(text, 48),
      planText: plan.isEmpty ? '按意图选工具获取真实数据' : plan,
      suggestedTools: tools.isEmpty ? const ['get_tool_catalog'] : tools,
      suggestedPlanSteps: planSteps ?? const [],
      useComposePlan: false,
      source: AgentTurnPlanSource.heuristic,
    );
  }

  static Future<AgentTurnPlan?> _routeWithLlm({
    required String userMessage,
    required List<AgentMessage> history,
    required AgentConfig config,
  }) async {
    final context = _formatHistory(history);

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
                    '你是 App 内的「回合路由器」：读懂用户这句话真正要什么，判断要不要调工具、调哪些。'
                    '语言千变万化，抓意图不要抓字面。'
                    '$_toolGuide\n\n'
                    '只输出 JSON，不要其它文字：'
                    '{"pure_chat":bool,"needs_tools":bool,"force_tools":bool,'
                    '"open_post":bool,"use_compose_plan":bool,'
                    '"user_goal":"8~30字","plan":"15~50字执行建议",'
                    '"tools":["tool_name",...],'
                    '"plan_steps":[{"tool":"...","args":{...},"label":"..."}]}\n'
                    'pure_chat=true 时 needs_tools 必须为 false，tools 与 plan_steps 为空。'
                    '多步任务时 plan_steps 填完整链路，下一步可用 \$prev.xxx 引用上一步。',
              },
              {
                'role': 'user',
                'content':
                    '最近对话：\n$context\n\n'
                    '用户本轮：$userMessage',
              },
            ],
            'temperature': 0.2,
            'max_tokens': 200,
          }),
        )
        .timeout(const Duration(seconds: 14));

    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body) as Map;
    final choice = (body['choices'] as List?)?.first;
    if (choice is! Map) return null;
    final message = choice['message'];
    if (message is! Map) return null;
    final raw = message['content']?.toString().trim() ?? '';
    final jsonText = _extractJsonObject(raw);
    if (jsonText == null) return null;

    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    final pureChat = map['pure_chat'] == true;
    if (pureChat) return AgentTurnPlan.chatOnly();

    final needsTools = map['needs_tools'] == true;
    final tools =
        (map['tools'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .take(4)
            .toList() ??
        const <String>[];

    final planSteps =
        (map['plan_steps'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => m['tool']?.toString().trim().isNotEmpty == true)
            .take(6)
            .toList() ??
        const <Map<String, dynamic>>[];

    final useCompose = false;

    return AgentTurnPlan(
      needsTools: needsTools,
      forceTools: map['force_tools'] == true && needsTools,
      openPostAfter: map['open_post'] == true,
      pureChat: false,
      userGoal: _clip(map['user_goal']?.toString() ?? '', 40),
      planText: _clip(map['plan']?.toString() ?? '', 80),
      suggestedTools: tools,
      suggestedPlanSteps: planSteps,
      useComposePlan: useCompose,
      source: AgentTurnPlanSource.llm,
    );
  }

  static String _formatHistory(List<AgentMessage> history) {
    final recent = history
        .where(
          (m) =>
              m.role == AgentMessageRole.user ||
              m.role == AgentMessageRole.assistant,
        )
        .toList();
    final tail = recent.length > 4 ? recent.sublist(recent.length - 4) : recent;
    if (tail.isEmpty) return '（无）';
    return tail
        .map((m) {
          final role = m.role == AgentMessageRole.user ? '用户' : '助手';
          final text = _clip(m.content.replaceAll('\n', ' '), 100);
          return '$role：$text';
        })
        .join('\n');
  }

  static String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }

  static String _clip(String raw, int max) {
    final t = raw.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }
}
