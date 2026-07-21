import 'dart:convert';

import 'agent_app_tools.dart';
import 'agent_art_tools.dart';
import 'agent_plan_validator.dart';
import 'agent_skill_store.dart';
import 'agent_tool_recipes.dart';
import 'agent_tools.dart';

/// 元工具：编排、并行、技能库、工具目录 introspection。
abstract final class AgentMetaTools {
  AgentMetaTools._();

  static const maxPlanSteps = 10;
  static const maxBatchCalls = 6;

  static const _names = {
    'run_plan',
    'batch_call',
    'save_skill',
    'list_skills',
    'run_skill',
    'delete_skill',
    'get_tool_catalog',
    'repeat_call',
    'list_tool_recipes',
    'compose_plan',
  };

  static bool isMetaTool(String name) => _names.contains(name);

  static bool isLeafTool(String name) =>
      !isMetaTool(name) &&
      (AgentAppTools.isAppTool(name) || _dataToolNames.contains(name));

  static const _dataToolNames = {
    'list_followed_bars',
    'get_bar_posts',
    'get_post_detail',
    'read_post',
    'get_post_replies',
    'get_sub_replies',
    'list_favorites',
    'search_threads',
    'discover_posts',
    'search_forums',
    'get_forum_info',
    'get_recommend_feed',
    'find_video_posts',
    'get_my_profile',
    'get_user_posts',
    'list_at_me',
    'list_reply_me',
    'sign_bar',
    'follow_bar',
    'unfollow_bar',
    'web_search',
    'draw_figlet',
    'draw_pixel_art',
    'draw_ascii_grid',
    'style_unicode_text',
  };

  static List<Map<String, dynamic>> get definitions => [
    ...apiDefinitions,
    ..._skillDefinitions,
    _composePlanDefinition,
  ];

  /// 暴露给模型的元工具：不含 compose_plan / 技能库（易编造工具名、引用失败）。
  static List<Map<String, dynamic>> get apiDefinitions => [
    _runPlanDefinition,
    _batchCallDefinition,
    _repeatCallDefinition,
    _getToolCatalogDefinition,
    _listToolRecipesDefinition,
  ];

  static const _toolAliases = {
    'get_post': 'get_post_detail',
    'post_detail': 'get_post_detail',
    'read_thread': 'read_post',
    'get_thread': 'read_post',
    'search_post': 'search_threads',
    'search_posts': 'search_threads',
    'find_posts': 'discover_posts',
    'discover': 'discover_posts',
    'open_thread': 'open_post',
    'ui_context': 'get_ui_context',
    'get_context': 'get_ui_context',
    'video_posts': 'find_video_posts',
    'find_video': 'find_video_posts',
  };

  static String _normalizeLeafTool(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    return _toolAliases[t] ?? t;
  }

  static Map<String, dynamic> get _runPlanDefinition => _tool(
    'run_plan',
    '多步且步骤明确时用：按顺序执行 leaf 工具。'
        '单步任务请直接调 discover_posts / search_threads / read_post 等，不要包一层 run_plan。'
        '每步用已有 leaf 工具名；下一步 args 可用 \$prev.xxx 引用上一步结果'
        '（如 \$prev.posts.0.tid）。',
    {
      'steps': {
        'type': 'array',
        'description': '步骤列表，每步 {tool, args?, label?, optional?}',
        'items': {
          'type': 'object',
          'properties': {
            'tool': _str('工具名，必须是已有 leaf 工具'),
            'args': {'type': 'object', 'description': '该步参数'},
            'label': _str('可选，步骤说明，便于结果里识别'),
            'optional': {
              'type': 'boolean',
              'description': '可选步骤；失败时跳过而不中断（默认 false）',
            },
          },
          'required': ['tool'],
        },
      },
      'stop_on_error': {
        'type': 'boolean',
        'description': '某步失败是否中止后续（默认 true；optional 步骤除外）',
      },
    },
    ['steps'],
  );

  static Map<String, dynamic> get _batchCallDefinition => _tool(
    'batch_call',
    '并行调用多个互不依赖的 leaf 工具（如同时查多个吧的帖子）',
    {
      'calls': {
        'type': 'array',
        'description': '调用列表，每项 {tool, args?, label?}',
        'items': {
          'type': 'object',
          'properties': {
            'tool': _str('leaf 工具名'),
            'args': {'type': 'object'},
            'label': _str('可选标签'),
          },
          'required': ['tool'],
        },
      },
    },
    ['calls'],
  );

  static Map<String, dynamic> get _repeatCallDefinition => _tool(
    'repeat_call',
    '对同一 leaf 工具按不同参数重复调用（如多个吧名、多个关键词）',
    {
      'tool': _str('要重复调用的 leaf 工具名'),
      'arg_sets': {
        'type': 'array',
        'description': '参数列表，每项为一组 args',
        'items': {'type': 'object'},
      },
      'parallel': {'type': 'boolean', 'description': '是否并行（默认 true）'},
    },
    ['tool', 'arg_sets'],
  );

  static Map<String, dynamic> get _getToolCatalogDefinition => _tool(
    'get_tool_catalog',
    '不确定用哪个 leaf 工具时先查目录（不要编造工具名）',
    {'category': _str('可选过滤：data | app | art | all，默认 all')},
  );

  static Map<String, dynamic> get _listToolRecipesDefinition =>
      _tool('list_tool_recipes', '查看内置多步搭配配方（仅真正多步时参考）');

  static List<Map<String, dynamic>> get _skillDefinitions => [
    _tool(
      'save_skill',
      '把常用工具编排保存为技能，下次用 run_skill 一键执行',
      {
        'name': _str('技能名，唯一，建议简短英文或拼音'),
        'description': _str('这个技能做什么'),
        'steps': {
          'type': 'array',
          'description': '与 run_plan 相同格式的 steps',
          'items': {'type': 'object'},
        },
      },
      ['name', 'steps'],
    ),
    _tool('list_skills', '列出已保存的技能名与说明'),
    _tool(
      'run_skill',
      '按名称执行已保存技能',
      {
        'name': _str('技能名'),
        'stop_on_error': {'type': 'boolean', 'description': '失败是否中止（默认 true）'},
      },
      ['name'],
    ),
    _tool('delete_skill', '删除已保存技能', {'name': _str('技能名')}, ['name']),
  ];

  static Map<String, dynamic> get _composePlanDefinition => _tool(
    'compose_plan',
    '根据用户目标自动搭配工具链并执行。多步任务（找→读/打开、搜→总结等）'
        '优先用它或 run_plan，不要分多轮单步调。会参考内置配方库。',
    {
      'goal': _str('要完成什么，自然语言描述'),
      'bar_name': _str('可选，限定在某个吧内'),
      'execute': {
        'type': 'boolean',
        'description': '是否立即执行（默认 true）；false 时只返回 steps 供 run_plan',
      },
      'stop_on_error': {
        'type': 'boolean',
        'description': '执行时某步失败是否中止（默认 true）',
      },
    },
    ['goal'],
  );

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

  static String describeCall(String name, Map<String, dynamic> args) {
    return switch (name) {
      'run_plan' => '编排执行 ${_stepCount(args['steps'])} 步',
      'batch_call' => '并行 ${_stepCount(args['calls'])} 个工具',
      'repeat_call' =>
        '重复「${args['tool'] ?? '工具'}」${_stepCount(args['arg_sets'])} 次',
      'save_skill' => '保存技能「${args['name'] ?? ''}」',
      'list_skills' => '查看技能列表',
      'run_skill' => '运行技能「${args['name'] ?? ''}」',
      'delete_skill' => '删除技能「${args['name'] ?? ''}」',
      'get_tool_catalog' => '查看工具目录',
      'list_tool_recipes' => '查看工具搭配配方',
      'compose_plan' => '智能编排：${args['goal'] ?? ''}',
      _ => name,
    };
  }

  static int _stepCount(dynamic raw) {
    if (raw is List) return raw.length;
    return 0;
  }

  static Future<String> execute(String name, Map<String, dynamic> args) async {
    try {
      return switch (name) {
        'run_plan' => jsonEncode(await _runPlan(args)),
        'batch_call' => jsonEncode(await _batchCall(args)),
        'repeat_call' => jsonEncode(await _repeatCall(args)),
        'save_skill' => jsonEncode(await _saveSkill(args)),
        'list_skills' => jsonEncode(await _listSkills()),
        'run_skill' => jsonEncode(await _runSkill(args)),
        'delete_skill' => jsonEncode(await _deleteSkill(args)),
        'get_tool_catalog' => jsonEncode(_getToolCatalog(args)),
        'list_tool_recipes' => jsonEncode(_listToolRecipes()),
        'compose_plan' => jsonEncode(await _composePlan(args)),
        _ => jsonEncode({'error': '未知元工具: $name'}),
      };
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  static Future<Map<String, dynamic>> _runPlan(
    Map<String, dynamic> args,
  ) async {
    final steps = _parseSteps(args['steps']);
    if (steps.isEmpty) return {'error': 'steps 不能为空'};
    if (steps.length > maxPlanSteps) {
      return {'error': '最多 $maxPlanSteps 步，请精简或拆成多次 run_plan'};
    }

    final validation = AgentPlanValidator.validatePlan(steps);
    if (!validation.ok) {
      return {
        'error': '计划校验未通过',
        'issues': validation.errors,
        'hint':
            '请修正上述问题后重试（检查工具名是否可用、必填参数是否齐全、'
            '\$prev 引用顺序是否正确）',
      };
    }

    final stopOnError = args['stop_on_error'] != false;
    final results = <Map<String, dynamic>>[];
    var completed = 0;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final tool = _normalizeLeafTool(step['tool']?.toString() ?? '');
      final optional = step['optional'] == true;
      final label = step['label']?.toString();
      final stepArgs = _resolveStepArgs(_mapArgs(step['args']), results);
      final unresolvedRef = _findUnresolvedRef(stepArgs);
      if (unresolvedRef != null) {
        final err =
            '无法解析引用 $unresolvedRef（上一步可能失败，或字段路径不对；'
            'get_ui_context 的 tid 在 foreground.detail.tid）';
        results.add(
          _stepResult(
            index: i,
            tool: tool,
            label: label,
            ok: false,
            error: err,
          ),
        );
        if (stopOnError && !optional) {
          return _planResponse(results, completed: completed, aborted: true);
        }
        continue;
      }

      if (!isLeafTool(tool)) {
        final err = '第 ${i + 1} 步工具「$tool」不可用（元工具不能嵌套，请用 leaf 工具）';
        results.add(
          _stepResult(
            index: i,
            tool: tool,
            label: label,
            ok: false,
            error: err,
          ),
        );
        if (stopOnError && !optional) {
          return _planResponse(results, completed: completed, aborted: true);
        }
        continue;
      }

      final raw = await AgentTools.invokeTool(tool, stepArgs);
      final parsed = _parseJsonMap(raw);
      final ok = _isToolResultOk(parsed);
      results.add(
        _stepResult(
          index: i,
          tool: tool,
          label: label,
          ok: ok,
          result: parsed,
          error: ok ? null : _toolResultError(parsed),
        ),
      );
      if (ok) completed++;
      if (!ok && stopOnError && !optional) {
        return _planResponse(results, completed: completed, aborted: true);
      }
    }

    return _planResponse(results, completed: completed, aborted: false);
  }

  static Map<String, dynamic> _listToolRecipes() {
    return {
      'count': AgentToolRecipes.listForApi().length,
      'catalog_hint': AgentToolRecipes.catalogPrompt,
      'recipes': AgentToolRecipes.listForApi(),
    };
  }

  static Future<Map<String, dynamic>> _composePlan(
    Map<String, dynamic> args,
  ) async {
    final goal = args['goal']?.toString().trim() ?? '';
    if (goal.isEmpty) return {'error': '请提供 goal'};
    final execute = args['execute'] != false;
    final barName = args['bar_name']?.toString().trim();
    final openPost = RegExp(r'打开|带我去|点开|跳转|看看').hasMatch(goal);

    // 只用内置配方，不再二次 LLM 编排（易编造工具名、写错 $prev）。
    final steps =
        AgentToolRecipes.suggestSteps(
          goal,
          openPost: openPost,
          barName: barName,
        ) ??
        const <Map<String, dynamic>>[];

    if (steps.isEmpty) {
      return {'error': '未能为「$goal」生成步骤，可 list_tool_recipes 查看配方或手动 run_plan'};
    }

    for (var i = 0; i < steps.length; i++) {
      final tool = _normalizeLeafTool(steps[i]['tool']?.toString() ?? '');
      if (!isLeafTool(tool)) {
        return {'error': '第 ${i + 1} 步工具「$tool」无效（只能用 leaf 工具）'};
      }
    }

    if (!execute) {
      return {
        'action': 'compose_plan',
        'goal': goal,
        'executed': false,
        'step_count': steps.length,
        'proposed_steps': steps,
        'message': '已生成 $goal 的 ${steps.length} 步编排，可用 run_plan 执行',
      };
    }

    final plan = await _runPlan({
      'steps': steps,
      'stop_on_error': args['stop_on_error'] ?? true,
    });
    return {'action': 'compose_plan', 'goal': goal, 'executed': true, ...plan};
  }

  static Map<String, dynamic> _resolveStepArgs(
    Map<String, dynamic> args,
    List<Map<String, dynamic>> priorResults,
  ) {
    dynamic resolve(dynamic value) {
      if (value is String && value.startsWith(r'$')) {
        return _resolveRefString(value, priorResults) ?? value;
      }
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), resolve(v)));
      }
      if (value is List) {
        return value.map(resolve).toList();
      }
      return value;
    }

    final resolved = resolve(args);
    if (resolved is Map) return Map<String, dynamic>.from(resolved);
    return args;
  }

  static dynamic _resolveRefString(
    String ref,
    List<Map<String, dynamic>> priorResults,
  ) {
    String path;
    Map<String, dynamic>? root;

    if (ref.startsWith(r'$prev.')) {
      path = ref.substring(6);
      root = _lastOkResult(priorResults);
    } else {
      final match = RegExp(r'^\$step(\d+)\.(.+)$').firstMatch(ref);
      if (match == null) return null;
      final idx = int.tryParse(match.group(1)!);
      path = match.group(2)!;
      if (idx == null || idx < 0 || idx >= priorResults.length) return null;
      final step = priorResults[idx];
      if (step['ok'] != true || step['result'] is! Map) return null;
      root = Map<String, dynamic>.from(step['result'] as Map);
    }

    if (root == null) return null;
    return _digPath(root, path);
  }

  static Map<String, dynamic>? _lastOkResult(
    List<Map<String, dynamic>> priorResults,
  ) {
    for (var i = priorResults.length - 1; i >= 0; i--) {
      final step = priorResults[i];
      if (step['ok'] == true && step['result'] is Map) {
        return Map<String, dynamic>.from(step['result'] as Map);
      }
    }
    return null;
  }

  static bool _isToolResultOk(Map<String, dynamic> parsed) {
    if (parsed['error'] != null) return false;
    if (parsed.containsKey('signed') && parsed['signed'] != true) return false;
    if (parsed.containsKey('followed') && parsed['followed'] != true) {
      return false;
    }
    if (parsed.containsKey('unfollowed') && parsed['unfollowed'] != true) {
      return false;
    }
    return true;
  }

  static String _toolResultError(Map<String, dynamic> parsed) {
    final err = parsed['error']?.toString();
    if (err != null && err.isNotEmpty) return err;
    if (parsed.containsKey('signed') && parsed['signed'] != true) {
      return parsed['message']?.toString() ?? '签到失败或今日已签';
    }
    if (parsed.containsKey('followed') && parsed['followed'] != true) {
      return parsed['message']?.toString() ?? '关注操作失败';
    }
    if (parsed.containsKey('unfollowed') && parsed['unfollowed'] != true) {
      return parsed['message']?.toString() ?? '取消关注失败';
    }
    return '工具执行未成功';
  }

  static String? _findUnresolvedRef(dynamic value) {
    if (value is String && value.startsWith(r'$')) return value;
    if (value is Map) {
      for (final v in value.values) {
        final found = _findUnresolvedRef(v);
        if (found != null) return found;
      }
    }
    if (value is List) {
      for (final v in value) {
        final found = _findUnresolvedRef(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  static dynamic _digPath(Map<String, dynamic> root, String path) {
    final direct = _digPathRaw(root, path);
    if (direct != null) return direct;

    const uiFields = {'tid', 'title', 'bar_name', 'author', 'reply_count'};
    final head = path.split('.').first;
    if (uiFields.contains(head)) {
      for (final alt in [
        'foreground.detail.$path',
        'foreground.$path',
        'detail.$path',
      ]) {
        final hit = _digPathRaw(root, alt);
        if (hit != null) return hit;
      }
    }

    if (path.startsWith('posts.0.')) {
      final tail = path.substring('posts.0.'.length);
      final hit = _digPathRaw(root, tail);
      if (hit != null) return hit;
    }

    return null;
  }

  static dynamic _digPathRaw(Map<String, dynamic> root, String path) {
    final parts = path.split('.');
    dynamic cur = root;
    for (final part in parts) {
      if (cur == null) return null;
      if (cur is Map) {
        if (cur.containsKey(part)) {
          cur = cur[part];
          continue;
        }
      }
      if (cur is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx >= 0 && idx < cur.length) {
          cur = cur[idx];
          continue;
        }
      }
      return null;
    }
    return cur;
  }

  static Future<Map<String, dynamic>> _batchCall(
    Map<String, dynamic> args,
  ) async {
    final calls = _parseSteps(args['calls']);
    if (calls.isEmpty) return {'error': 'calls 不能为空'};
    if (calls.length > maxBatchCalls) {
      return {'error': '最多并行 $maxBatchCalls 个调用'};
    }

    final futures = <Future<Map<String, dynamic>>>[];
    for (var i = 0; i < calls.length; i++) {
      futures.add(_executeCallEntry(i, calls[i]));
    }
    final results = await Future.wait(futures);
    final okCount = results.where((r) => r['ok'] == true).length;
    return {
      'action': 'batch_call',
      'total': results.length,
      'ok_count': okCount,
      'results': results,
    };
  }

  static Future<Map<String, dynamic>> _repeatCall(
    Map<String, dynamic> args,
  ) async {
    final tool = _normalizeLeafTool(args['tool']?.toString() ?? '');
    if (!isLeafTool(tool)) {
      return {'error': 'tool 必须是 leaf 工具名'};
    }
    final argSets = _parseArgSets(args['arg_sets']);
    if (argSets.isEmpty) return {'error': 'arg_sets 不能为空'};
    if (argSets.length > maxBatchCalls) {
      return {'error': '最多 $maxBatchCalls 组参数'};
    }

    final parallel = args['parallel'] != false;
    final entries = argSets
        .asMap()
        .entries
        .map((e) => {'tool': tool, 'args': e.value, 'label': '#${e.key + 1}'})
        .toList();

    if (parallel) {
      final futures = <Future<Map<String, dynamic>>>[];
      for (var i = 0; i < entries.length; i++) {
        futures.add(_executeCallEntry(i, entries[i]));
      }
      final results = await Future.wait(futures);
      return {
        'action': 'repeat_call',
        'tool': tool,
        'total': results.length,
        'ok_count': results.where((r) => r['ok'] == true).length,
        'results': results,
      };
    }

    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < entries.length; i++) {
      results.add(await _executeCallEntry(i, entries[i]));
    }
    return {
      'action': 'repeat_call',
      'tool': tool,
      'total': results.length,
      'ok_count': results.where((r) => r['ok'] == true).length,
      'results': results,
    };
  }

  static Future<Map<String, dynamic>> _saveSkill(
    Map<String, dynamic> args,
  ) async {
    final name = args['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'error': '请提供 name'};
    final steps = _parseSteps(args['steps']);
    if (steps.isEmpty) return {'error': 'steps 不能为空'};

    for (var i = 0; i < steps.length; i++) {
      final tool = _normalizeLeafTool(steps[i]['tool']?.toString() ?? '');
      if (!isLeafTool(tool)) {
        return {'error': '第 ${i + 1} 步工具「$tool」无效'};
      }
    }

    final skill = AgentSkill(
      name: name,
      description: args['description']?.toString().trim() ?? '',
      steps: steps,
      updatedAt: DateTime.now(),
    );
    await AgentSkillStore.save(skill);
    return {
      'ok': true,
      'action': 'save_skill',
      'name': name,
      'step_count': steps.length,
      'message': '已保存技能「$name」',
    };
  }

  static Future<Map<String, dynamic>> _listSkills() async {
    final skills = await AgentSkillStore.list();
    return {
      'count': skills.length,
      'skills': skills
          .map(
            (s) => {
              'name': s.name,
              'description': s.description,
              'step_count': s.steps.length,
              'updated_at': s.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _runSkill(
    Map<String, dynamic> args,
  ) async {
    final name = args['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'error': '请提供 name'};
    final skill = await AgentSkillStore.get(name);
    if (skill == null) return {'error': '技能「$name」不存在，可用 list_skills 查看'};

    final plan = await _runPlan({
      'steps': skill.steps,
      'stop_on_error': args['stop_on_error'] ?? true,
    });
    return {
      'action': 'run_skill',
      'skill': name,
      'description': skill.description,
      ...plan,
    };
  }

  static Future<Map<String, dynamic>> _deleteSkill(
    Map<String, dynamic> args,
  ) async {
    final name = args['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'error': '请提供 name'};
    final ok = await AgentSkillStore.delete(name);
    if (!ok) return {'error': '技能「$name」不存在'};
    return {
      'ok': true,
      'action': 'delete_skill',
      'name': name,
      'message': '已删除技能「$name」',
    };
  }

  static Map<String, dynamic> _getToolCatalog(Map<String, dynamic> args) {
    final filter = args['category']?.toString().trim().toLowerCase() ?? 'all';
    final tools = <Map<String, dynamic>>[];

    void addFromDefs(List<Map<String, dynamic>> defs, String category) {
      if (filter != 'all' && filter != category) return;
      for (final def in defs) {
        final fn = def['function'];
        if (fn is! Map) continue;
        final name = fn['name']?.toString() ?? '';
        if (!isLeafTool(name)) continue;
        tools.add({
          'name': name,
          'category': category,
          'description': fn['description']?.toString() ?? '',
          if (fn['parameters'] is Map) 'parameters': fn['parameters'],
        });
      }
    }

    addFromDefs(AgentTools.dataToolDefinitions, 'data');
    addFromDefs(AgentAppTools.definitions, 'app');
    addFromDefs(AgentArtTools.definitions, 'art');

    return {'count': tools.length, 'tools': tools};
  }

  static Future<Map<String, dynamic>> _executeCallEntry(
    int index,
    Map<String, dynamic> entry,
  ) async {
    final tool = _normalizeLeafTool(entry['tool']?.toString() ?? '');
    final label = entry['label']?.toString();
    if (!isLeafTool(tool)) {
      return {
        'index': index,
        'tool': tool,
        'label': label,
        'ok': false,
        'error': '不可用工具: $tool',
      };
    }
    final raw = await AgentTools.invokeTool(tool, _mapArgs(entry['args']));
    final parsed = _parseJsonMap(raw);
    final ok = _isToolResultOk(parsed);
    return {
      'index': index,
      'tool': tool,
      'label': ?label,
      'ok': ok,
      if (!ok) 'error': _toolResultError(parsed),
      'result': parsed,
    };
  }

  static Map<String, dynamic> _planResponse(
    List<Map<String, dynamic>> steps, {
    required int completed,
    required bool aborted,
  }) {
    return {
      'action': 'run_plan',
      'total': steps.length,
      'completed': completed,
      'aborted': aborted,
      'steps': steps,
    };
  }

  static Map<String, dynamic> _stepResult({
    required int index,
    required String tool,
    String? label,
    required bool ok,
    Map<String, dynamic>? result,
    String? error,
  }) {
    return {
      'index': index,
      'tool': tool,
      'label': ?((label != null && label.isNotEmpty) ? label : null),
      'ok': ok,
      'error': ?error,
      'result': ?result,
    };
  }

  static List<Map<String, dynamic>> _parseSteps(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((m) => m['tool']?.toString().trim().isNotEmpty == true)
        .toList();
  }

  static List<Map<String, dynamic>> _parseArgSets(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  static Map<String, dynamic> _mapArgs(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static Map<String, dynamic> _parseJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {
      'error': '工具返回非 JSON',
      'raw': raw.length > 200 ? '${raw.substring(0, 200)}…' : raw,
    };
  }

  /// 从元工具结果里提取嵌套步骤，供 UI 渲染与 open_post 检测。
  static Iterable<MapEntry<String, Map<String, dynamic>>> nestedStepResults(
    String toolName,
    Map<String, dynamic> json,
  ) sync* {
    if (json['error'] != null) return;

    Iterable<Map<String, dynamic>> entries;
    switch (toolName) {
      case 'run_plan':
      case 'run_skill':
      case 'compose_plan':
        final steps = json['steps'];
        entries = steps is List
            ? steps.whereType<Map>().map((m) => Map<String, dynamic>.from(m))
            : const [];
      case 'batch_call':
      case 'repeat_call':
        final results = json['results'];
        entries = results is List
            ? results.whereType<Map>().map((m) => Map<String, dynamic>.from(m))
            : const [];
      default:
        return;
    }

    for (final entry in entries) {
      if (entry['ok'] != true) continue;
      final tool = entry['tool']?.toString();
      final result = entry['result'];
      if (tool == null || result is! Map) continue;
      yield MapEntry(tool, Map<String, dynamic>.from(result));
    }
  }

  static bool nestedInvokedOpenPost(Map<String, dynamic> json) {
    for (final steps in [json['steps'], json['results']]) {
      if (steps is! List) continue;
      for (final s in steps.whereType<Map>()) {
        if (s['tool'] == 'open_post' && s['ok'] == true) return true;
      }
    }
    return false;
  }
}
