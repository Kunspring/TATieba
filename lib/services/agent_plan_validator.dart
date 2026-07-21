import 'agent_tools.dart';

/// 多步计划的静态校验（不执行，只检查可执行性）。
///
/// 覆盖：
/// - 工具存在性（不能用元工具、不能编造工具名）；
/// - 必填参数齐备，或经 `$prev.xxx` / `$stepN.xxx` 引用提供；
/// - 引用顺序合法（不能引用「未来的步骤」，无前向依赖/环路）。
///
/// 这是「任务拆解自检」与「调用链路编排校验」的纯逻辑实现，
/// 可在 run_plan 执行前调用，把问题直接反馈给 LLM 以触发自我纠错。
abstract final class AgentPlanValidator {
  AgentPlanValidator._();

  static const Set<String> _metaNames = {
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

  static PlanValidation validatePlan(
    List<Map<String, dynamic>> steps, {
    int maxSteps = 10,
  }) {
    final issues = <PlanIssue>[];

    if (steps.isEmpty) {
      return PlanValidation(const [
        PlanIssue(step: 0, code: 'empty', message: '计划不能为空'),
      ]);
    }
    if (steps.length > maxSteps) {
      issues.add(
        PlanIssue(
          step: steps.length,
          code: 'too_many_steps',
          message: '最多 $maxSteps 步，当前 ${steps.length} 步',
        ),
      );
    }

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final tool = (step['tool']?.toString() ?? '').trim();

      if (tool.isEmpty) {
        issues.add(
          PlanIssue(
            step: i,
            code: 'missing_tool',
            message: '第 ${i + 1} 步缺少 tool',
          ),
        );
        continue;
      }
      if (_metaNames.contains(tool)) {
        issues.add(
          PlanIssue(
            step: i,
            code: 'meta_in_plan',
            message: '第 ${i + 1} 步「$tool」是元工具，plan 内只能用 leaf 工具',
          ),
        );
        continue;
      }
      if (!_isLeafTool(tool)) {
        issues.add(
          PlanIssue(
            step: i,
            code: 'unknown_tool',
            message: '第 ${i + 1} 步工具「$tool」不存在或不可用',
          ),
        );
        continue;
      }

      final args = step['args'];
      final argMap = args is Map
          ? Map<String, dynamic>.from(args)
          : <String, dynamic>{};
      final required = _requiredParams(tool);

      for (final req in required) {
        final raw = argMap[req];
        final provided =
            raw != null && (raw is! String || raw.toString().trim().isNotEmpty);
        if (provided) continue;
        if (_hasRefValue(argMap[req])) continue; // 通过引用提供，执行时解析
        issues.add(
          PlanIssue(
            step: i,
            code: 'missing_param',
            message: '第 ${i + 1} 步「$tool」缺少必填参数「$req」',
          ),
        );
      }

      // 引用顺序：不允许引用「未来的步骤 / 自身」
      for (final ref in _collectRefs(argMap)) {
        final targetIdx = _refStepIndex(ref);
        if (targetIdx != null && targetIdx >= i) {
          issues.add(
            PlanIssue(
              step: i,
              code: 'bad_order',
              message:
                  '第 ${i + 1} 步引用了 $ref，但它指向第 ${targetIdx + 1} 步'
                  '（不能引用未来/自身的步骤）',
            ),
          );
        }
      }
    }

    return PlanValidation(issues);
  }

  static bool _isLeafTool(String name) {
    for (final def in AgentTools.definitions) {
      final fn = def['function'];
      if (fn is Map && fn['name'] == name) return true;
    }
    return false;
  }

  static List<String> _requiredParams(String name) {
    for (final def in AgentTools.definitions) {
      final fn = def['function'];
      if (fn is! Map || fn['name'] != name) continue;
      final params = fn['parameters'];
      if (params is Map && params['required'] is List) {
        return (params['required'] as List).map((e) => e.toString()).toList();
      }
      return const [];
    }
    return const [];
  }

  static bool _hasRefValue(dynamic value) {
    if (value is String && value.trim().startsWith(r'$')) return true;
    if (value is Map) return value.values.any(_hasRefValue);
    if (value is List) return value.any(_hasRefValue);
    return false;
  }

  static List<String> _collectRefs(dynamic value) {
    final refs = <String>[];
    void walk(dynamic v) {
      if (v is String && v.trim().startsWith(r'$')) refs.add(v.trim());
      if (v is Map) v.values.forEach(walk);
      if (v is List) v.forEach(walk);
    }

    walk(value);
    return refs;
  }

  static int? _refStepIndex(String ref) {
    final m = RegExp(r'^\$step(\d+)\.').firstMatch(ref);
    if (m == null) return null; // $prev 不检查序号
    return int.tryParse(m.group(1)!);
  }
}

class PlanIssue {
  final int step;
  final String code;
  final String message;
  const PlanIssue({
    required this.step,
    required this.code,
    required this.message,
  });
}

class PlanValidation {
  final List<PlanIssue> issues;
  const PlanValidation(this.issues);
  bool get ok => issues.isEmpty;
  List<String> get errors => issues.map((i) => i.message).toList();
}
