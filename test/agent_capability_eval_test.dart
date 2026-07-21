// ignore_for_file: avoid_print // 评测脚本用 print 输出 scorecard，属预期行为
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba_app/models/agent_memory_entry.dart';
import 'package:tieba_app/services/agent_error_explainer.dart';
import 'package:tieba_app/services/agent_memory_consistency.dart';
import 'package:tieba_app/services/agent_plan_validator.dart';
import 'package:tieba_app/services/agent_tool_validator.dart';
import 'package:tieba_app/services/agent_tools.dart';

/// Agent 能力量化评测基座。
///
/// 目标：用固定场景集 + 确定性断言，对四大能力维度给出可复现的数值指标，
/// 使"能力提升"可被度量而非凭感觉。全部为纯逻辑，不依赖真实模型/网络。
///
/// 指标明细见末尾 scorecard 打印与各项 expect 阈值。
void main() {
  test('Agent 能力量化评测（四维）', () {
    final rows = <_MetricRow>[];

    // ───────────────────────────────────────────────────────────
    // 维度 2a：工具选择准确性（top-1 命中率）
    // ───────────────────────────────────────────────────────────
    final selectionGold = <String, String>{
      '帮我搜一下Python爬虫相关的帖': 'search_threads',
      '给我推荐点搞笑的帖': 'discover_posts',
      '读一下这篇帖，看看评论区在吵什么': 'read_post',
      '签到孙笑川吧': 'sign_bar',
      '关注一下某某吧': 'follow_bar',
      '查查今天天气': 'web_search',
      '找几个带视频的沙雕帖': 'find_video_posts',
      '看看我关注的吧': 'list_followed_bars',
      '查查我收藏的帖子': 'list_favorites',
    };
    var selCorrect = 0;
    selectionGold.forEach((msg, expected) {
      final got = AgentToolValidator.topTool(msg);
      if (got == expected) selCorrect++;
      print('  [选择] "$msg" -> ${got ?? 'null'} (期望 $expected)');
    });
    final selAcc = selCorrect / selectionGold.length;
    rows.add(_MetricRow('维度2 工具选择', 'top-1 准确率', selAcc, 0.85));

    // ───────────────────────────────────────────────────────────
    // 维度 2b：参数填充正确率（validateArgs 能否识别缺参/空参）
    // ───────────────────────────────────────────────────────────
    final paramChecks = <Map<String, Object>>[
      {'tool': 'search_threads', 'args': <String, dynamic>{}, 'valid': false},
      {
        'tool': 'search_threads',
        'args': <String, dynamic>{'query': 'python'},
        'valid': true,
      },
      {
        'tool': 'read_post',
        'args': <String, dynamic>{'tid': ''},
        'valid': false,
      },
      {
        'tool': 'read_post',
        'args': <String, dynamic>{'tid': '12345'},
        'valid': true,
      },
      {
        'tool': 'get_bar_posts',
        'args': <String, dynamic>{'bar_name': '孙笑川'},
        'valid': true,
      },
      {'tool': 'sign_bar', 'args': <String, dynamic>{}, 'valid': false},
      {
        'tool': 'web_search',
        'args': <String, dynamic>{'query': 'x'},
        'valid': true,
      },
      {'tool': 'discover_posts', 'args': <String, dynamic>{}, 'valid': false},
      {'tool': 'find_video_posts', 'args': <String, dynamic>{}, 'valid': true},
      {'tool': 'get_my_profile', 'args': <String, dynamic>{}, 'valid': true},
    ];
    var paramPass = 0;
    for (final c in paramChecks) {
      final errors = AgentTools.validateArgs(
        c['tool'] as String,
        c['args'] as Map<String, dynamic>,
      );
      final valid = errors.isEmpty;
      if (valid == c['valid']) paramPass++;
      print(
        '  [参数] ${c['tool']} valid=$valid (期望 ${c['valid']}) '
        '${valid ? '' : errors}',
      );
    }
    final paramAcc = paramPass / paramChecks.length;
    rows.add(_MetricRow('维度2 参数填充', '正确率', paramAcc, 1.0));

    // ───────────────────────────────────────────────────────────
    // 维度 1+2：计划校验（任务拆解自检 + 链路编排合法性）
    // ───────────────────────────────────────────────────────────
    final planScenarios = <_PlanScenario>[
      _PlanScenario('valid discover→read', [
        {
          'tool': 'discover_posts',
          'args': {'intent': '搞笑帖'},
        },
        {
          'tool': 'read_post',
          'args': {'tid': r'$prev.posts.0.tid'},
        },
      ], expectOk: true),
      _PlanScenario(
        'missing param',
        [
          {'tool': 'search_threads', 'args': <String, dynamic>{}},
        ],
        expectOk: false,
        codes: ['missing_param'],
      ),
      _PlanScenario(
        'unknown tool',
        [
          {'tool': 'fetch_magic', 'args': <String, dynamic>{}},
        ],
        expectOk: false,
        codes: ['unknown_tool'],
      ),
      _PlanScenario(
        'bad order',
        [
          {
            'tool': 'read_post',
            'args': {'tid': r'$step1.posts.0.tid'},
          },
          {
            'tool': 'discover_posts',
            'args': {'intent': 'x'},
          },
        ],
        expectOk: false,
        codes: ['bad_order'],
      ),
      _PlanScenario(
        'meta in plan',
        [
          {
            'tool': 'run_plan',
            'args': {'steps': []},
          },
        ],
        expectOk: false,
        codes: ['meta_in_plan'],
      ),
      _PlanScenario(
        'too many steps',
        List.generate(
          11,
          (_) => {
            'tool': 'sign_bar',
            'args': {'bar_name': 'x'},
          },
        ),
        expectOk: false,
        codes: ['too_many_steps'],
      ),
    ];
    var planPass = 0;
    for (final s in planScenarios) {
      final v = AgentPlanValidator.validatePlan(s.steps);
      final okMatch = v.ok == s.expectOk;
      final codeMatch =
          !s.expectOk || s.codes.every((c) => v.issues.any((i) => i.code == c));
      if (okMatch && codeMatch) planPass++;
      print('  [计划] ${s.name}: ok=${v.ok} issues=${v.errors}');
    }
    final planAcc = planPass / planScenarios.length;
    rows.add(_MetricRow('维度1+2 计划校验', '问题检出准确率', planAcc, 1.0));

    // ───────────────────────────────────────────────────────────
    // 维度 3：错误分类与可重试判定
    // ───────────────────────────────────────────────────────────
    final errCases = <Map<String, Object>>[
      {'raw': '429 Too Many Requests', 'kind': AgentErrorKind.rateLimit},
      {
        'raw': 'SocketException: network is unreachable',
        'kind': AgentErrorKind.network,
      },
      {'raw': '401 unauthorized', 'kind': AgentErrorKind.auth},
      {'raw': '帖子不存在或加载失败', 'kind': AgentErrorKind.notFound},
      {'raw': '参数校验失败：缺少必填参数「query」', 'kind': AgentErrorKind.param},
      {'raw': '模型返回空内容', 'kind': AgentErrorKind.model},
      {'raw': '完全不认识的奇怪错误xyz', 'kind': AgentErrorKind.unknown},
      {'raw': '请求超时了', 'kind': AgentErrorKind.network},
      {'raw': '未登录贴吧，请先扫码', 'kind': AgentErrorKind.auth},
    ];
    var errPass = 0;
    for (final c in errCases) {
      final kind = AgentErrorDiagnostics.classify(c['raw'] as String);
      if (kind == c['kind']) errPass++;
      print(
        '  [错误] "${c['raw']}" -> ${kind.label}'
        ' (期望 ${(c['kind'] as AgentErrorKind).label})',
      );
    }
    final errAcc = errPass / errCases.length;
    rows.add(_MetricRow('维度3 错误分类', '分类准确率', errAcc, 0.85));

    // 可重试判定抽样
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.rateLimit), isTrue);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.network), isTrue);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.model), isTrue);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.auth), isFalse);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.notFound), isFalse);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.param), isFalse);
    expect(AgentErrorDiagnostics.isRetryable(AgentErrorKind.unknown), isFalse);

    // ───────────────────────────────────────────────────────────
    // 维度 4：记忆检索相关性与冲突检测
    // ───────────────────────────────────────────────────────────
    final coffee = AgentMemoryEntry(
      id: '1',
      content: '用户喜欢喝咖啡',
      category: AgentMemoryCategory.preference,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final cat = AgentMemoryEntry(
      id: '2',
      content: '用户养了一只猫',
      category: AgentMemoryCategory.fact,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final irrelevant = AgentMemoryEntry(
      id: '3',
      content: '今天天气不错',
      category: AgentMemoryCategory.emphasis,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final beijing = AgentMemoryEntry(
      id: '4',
      content: '用户的城市是北京',
      category: AgentMemoryCategory.profile,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 相关性：相关 > 0，无关 == 0
    final relCoffee = AgentMemoryConsistency.relevanceScore('我喜欢喝咖啡', coffee);
    final relCat = AgentMemoryConsistency.relevanceScore('我喜欢喝咖啡', cat);
    final relBj = AgentMemoryConsistency.relevanceScore('我在北京上班', beijing);
    final relIrrel = AgentMemoryConsistency.relevanceScore(
      '我喜欢喝咖啡',
      irrelevant,
    );
    expect(relCoffee, greaterThan(0));
    expect(relCat, 0);
    expect(relBj, greaterThan(0));
    expect(relIrrel, 0);

    // 检索 hit@1
    final retrievalQueries = <String, String>{'我喜欢喝咖啡': '咖啡', '我在北京上班': '北京'};
    var hit = 0;
    retrievalQueries.forEach((q, needle) {
      final top = AgentMemoryConsistency.rankByRelevance(q, [
        cat,
        coffee,
        irrelevant,
        beijing,
      ]).firstOrNull;
      final ok = top != null && top.content.contains(needle);
      if (ok) hit++;
      print('  [检索] "$q" -> ${top?.content} (命中 $needle: $ok)');
    });
    final hitRate = hit / retrievalQueries.length;
    rows.add(_MetricRow('维度4 记忆检索', 'hit@1 命中率', hitRate, 0.8));

    // 冲突检测
    final ageOld = AgentMemoryEntry(
      id: '5',
      content: '30',
      category: AgentMemoryCategory.profile,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      slot: 'age',
    );
    final ageSame = AgentMemoryEntry(
      id: '6',
      content: '25',
      category: AgentMemoryCategory.profile,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      slot: 'age',
    );
    final cityOther = AgentMemoryEntry(
      id: '7',
      content: '北京',
      category: AgentMemoryCategory.profile,
      importance: 5,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      slot: 'city',
    );
    final conflictDiff = AgentMemoryConsistency.detectConflict(
      content: '25',
      category: AgentMemoryCategory.profile,
      slot: 'age',
      existing: [ageOld],
    );
    final conflictSame = AgentMemoryConsistency.detectConflict(
      content: '25',
      category: AgentMemoryCategory.profile,
      slot: 'age',
      existing: [ageSame],
    );
    final conflictOtherSlot = AgentMemoryConsistency.detectConflict(
      content: '25',
      category: AgentMemoryCategory.profile,
      slot: 'age',
      existing: [cityOther],
    );
    expect(conflictDiff, isNotNull);
    expect(conflictSame, isNull);
    expect(conflictOtherSlot, isNull);
    // 冲突检测 3/3 计数
    final conflictResults = [
      conflictDiff != null,
      conflictSame == null,
      conflictOtherSlot == null,
    ];
    final conflictOk = conflictResults.where((b) => b).length;
    rows.add(
      _MetricRow('维度4 冲突检测', '准确率', conflictOk / conflictResults.length, 1.0),
    );
    print(
      '  [冲突] diff=${conflictDiff != null} same=${conflictSame == null} otherSlot=${conflictOtherSlot == null}',
    );

    // ───────────────────────────────────────────────────────────
    // 汇总 scorecard
    // ───────────────────────────────────────────────────────────
    print('\n══════════════════════════════════════════════════════');
    print(' Agent 能力量化评测 Scorecard');
    print('══════════════════════════════════════════════════════');
    var allPass = true;
    for (final r in rows) {
      final pct = (r.value * 100).toStringAsFixed(1);
      final pass = r.value >= r.threshold;
      allPass = allPass && pass;
      print(
        '  ${r.dimension.padRight(14)} | ${r.metric.padRight(10)} '
        '| $pct%  (阈值 ≥ ${(r.threshold * 100).toStringAsFixed(0)}%) '
        '| ${pass ? 'PASS' : 'FAIL'}',
      );
    }
    print('══════════════════════════════════════════════════════');

    for (final r in rows) {
      expect(
        r.value,
        greaterThanOrEqualTo(r.threshold),
        reason: '${r.dimension}/${r.metric} 未达阈值',
      );
    }
  });
}

class _MetricRow {
  final String dimension;
  final String metric;
  final double value;
  final double threshold;
  _MetricRow(this.dimension, this.metric, this.value, this.threshold);
}

class _PlanScenario {
  final String name;
  final List<Map<String, dynamic>> steps;
  final bool expectOk;
  final List<String> codes;
  _PlanScenario(
    this.name,
    this.steps, {
    required this.expectOk,
    this.codes = const [],
  });
}
