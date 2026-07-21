import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tieba_post.dart';
import '../utils/agent_post_reader.dart';
import 'agent_config_service.dart';
import 'tieba_client.dart';

/// 按用户自然语言需求找帖（多关键词 + 扫流 + 语义排序）。
abstract final class AgentPostDiscovery {
  AgentPostDiscovery._();

  static const _maxQueries = 5;
  static const _maxCandidates = 48;
  static const _maxRankBatch = 28;
  static const _minPresentScore = 15;
  static const _goodMatchScore = 28;

  static Future<Map<String, dynamic>> discover({
    required String intent,
    String? barName,
    int limit = 5,
    int page = 1,
    String? bduss,
  }) async {
    final need = intent.trim();
    if (need.isEmpty) {
      return {'error': '缺少 intent（用户想找什么样的帖）'};
    }
    final cap = limit.clamp(1, 10);
    final bar = barName?.trim();
    if (bar != null && bar.isEmpty) {
      return {'error': 'bar_name 不能为空字符串'};
    }

    final config = await AgentConfigService.load();
    final plan = config.isConfigured
        ? await _planWithLlm(need, bar: bar, config: config)
        : _planHeuristic(need);

    final queries = plan.queries.take(_maxQueries).toList();
    if (queries.isEmpty) {
      queries.add(_clipQuery(need));
    }

    final candidates = <String, _Candidate>{};
    void absorb(Iterable<TiebaPost> posts, {required String source}) {
      for (final post in posts) {
        if (post.id.isEmpty) continue;
        final preview = AgentPostReader.clip(
          AgentPostReader.plainText(post.content),
          120,
        );
        final existing = candidates[post.id];
        if (existing == null) {
          candidates[post.id] = _Candidate(
            post: post,
            preview: preview,
            sources: {source},
          );
        } else {
          existing.sources.add(source);
          if (preview.length > existing.preview.length) {
            existing.preview = preview;
          }
        }
        if (candidates.length >= _maxCandidates) return;
      }
    }

    for (final q in queries) {
      if (q.isEmpty) continue;
      final found = await TiebaClient.searchThreads(
        query: q,
        barName: bar,
        page: page,
        bduss: bduss,
      );
      absorb(found, source: '搜「$q」');
      if (candidates.length >= _maxCandidates) break;
    }

    final searchOnlyCount = candidates.length;
    var ranked = await _rankCandidates(
      need,
      candidates.values.toList(),
      plan: plan,
      config: config,
    );
    var top = _pickPresentable(ranked, cap);
    if (_hasStrongMatches(top, cap)) {
      return _buildResponse(
        need: need,
        bar: bar,
        page: page,
        cap: cap,
        queries: queries,
        candidates: candidates,
        top: top,
      );
    }

    final needFallback =
        searchOnlyCount == 0 ||
        top.isEmpty ||
        (top.isNotEmpty && top.first.score < _goodMatchScore);
    if (needFallback) {
      if (plan.scanBarFeed && bar != null && bar.isNotEmpty) {
        var barPosts = await TiebaClient.fetchBarThreads(
          bar,
          page: page,
          bduss: bduss,
        );
        if (barPosts.isEmpty) {
          barPosts = await TiebaClient.fetchBarThreadsForm(
            bar,
            page: page,
            bduss: bduss,
          );
        }
        absorb(barPosts, source: '浏览「$bar」');
      }

      if (plan.scanFeed && bar == null) {
        final loadType = page == 1 ? 1 : 2;
        final feed = await TiebaClient.fetchPersonalized(
          loadType: loadType,
          page: page == 1 ? 1 : page - 1,
          bduss: bduss,
        );
        absorb(feed.posts, source: '推荐流');
      }

      ranked = await _rankCandidates(
        need,
        candidates.values.toList(),
        plan: plan,
        config: config,
      );
      top = _pickPresentable(ranked, cap);
    }

    if (top.isEmpty) {
      return {
        'error': bar != null && bar.isNotEmpty
            ? '「$bar」内按需求「$need」暂未找到相关帖，可换说法或换吧试试'
            : '按需求「$need」暂未找到相关帖，可描述得更具体些',
        'intent': need,
        'bar_name': ?bar,
        'queries_tried': queries,
        'candidates_scanned': candidates.length,
      };
    }

    return _buildResponse(
      need: need,
      bar: bar,
      page: page,
      cap: cap,
      queries: queries,
      candidates: candidates,
      top: top,
    );
  }

  static Map<String, dynamic> _buildResponse({
    required String need,
    required String? bar,
    required int page,
    required int cap,
    required List<String> queries,
    required Map<String, _Candidate> candidates,
    required List<_RankedCandidate> top,
  }) {
    return {
      'intent': need,
      if (bar != null && bar.isNotEmpty) 'bar_name': bar,
      'page': page,
      'limit': cap,
      'queries_tried': queries,
      'candidates_scanned': candidates.length,
      'posts': top
          .map(
            (r) => {
              'tid': r.post.id,
              'title': r.post.title,
              'author': r.post.author,
              'reply_count': r.post.replyCount,
              'bar_name': r.post.barName,
              'has_video': r.post.video != null && r.post.video!.src.isNotEmpty,
              if (r.post.cover?.isNotEmpty == true) 'cover': r.post.cover,
              'match_score': r.score,
              'match_reason': r.reason,
              if (r.preview.isNotEmpty) 'preview': r.preview,
            },
          )
          .toList(),
    };
  }

  static Future<List<_RankedCandidate>> _rankCandidates(
    String need,
    List<_Candidate> items, {
    required _DiscoveryPlan plan,
    required AgentConfig config,
  }) async {
    if (items.isEmpty) return const [];
    return config.isConfigured
        ? await _rankWithLlm(need, items, config: config)
        : _rankHeuristic(need, plan.mustHave, items);
  }

  static List<_RankedCandidate> _pickPresentable(
    List<_RankedCandidate> ranked,
    int cap,
  ) {
    return ranked.where((r) => r.score >= _minPresentScore).take(cap).toList();
  }

  static bool _hasStrongMatches(List<_RankedCandidate> top, int cap) {
    if (top.isEmpty) return false;
    if (top.length >= cap && top.first.score >= _goodMatchScore) return true;
    return top.length >= 2 && top.first.score >= _goodMatchScore + 8;
  }

  static _DiscoveryPlan _planHeuristic(String intent) {
    final tokens = _keywordsFromIntent(intent);
    final queries = <String>{_clipQuery(intent)};
    for (final t in tokens.take(4)) {
      queries.add(t);
    }
    for (var i = 0; i < tokens.length - 1; i++) {
      queries.add('${tokens[i]} ${tokens[i + 1]}');
      if (queries.length >= _maxQueries) break;
    }
    return _DiscoveryPlan(
      queries: queries.where((q) => q.trim().length >= 2).toList(),
      mustHave: tokens,
      scanBarFeed: false,
      scanFeed: true,
    );
  }

  static Future<_DiscoveryPlan> _planWithLlm(
    String intent, {
    String? bar,
    required AgentConfig config,
  }) async {
    try {
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
                      '你是贴吧找帖助手。用户用自然语言描述想找的帖子，贴吧搜索只认关键词。'
                      '请把需求拆成多种**简短搜索词**（同义、近义、相关梗、上位/下位词），'
                      '不要只复述用户原话。'
                      '只输出 JSON：'
                      '{"queries":["词1","词2",...],"must_have":["核心概念"],"scan_feed":true/false,"scan_bar_feed":true/false}'
                      'queries 3~6 条，每条 2~8 字为宜。',
                },
                {
                  'role': 'user',
                  'content':
                      '需求：$intent'
                      '${bar != null && bar.isNotEmpty ? '\n限定吧：$bar' : ''}',
                },
              ],
              'temperature': 0.35,
              'max_tokens': 180,
            }),
          )
          .timeout(const Duration(seconds: 16));

      if (resp.statusCode != 200) {
        return _planHeuristic(intent);
      }
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return _planHeuristic(intent);
      final message = choice['message'];
      if (message is! Map) return _planHeuristic(intent);
      final raw = message['content']?.toString().trim() ?? '';
      final jsonText = _extractJsonObject(raw);
      if (jsonText == null) return _planHeuristic(intent);

      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      final queries =
          (map['queries'] as List?)
              ?.map((e) => _clipQuery(e.toString()))
              .where((q) => q.length >= 2)
              .take(_maxQueries)
              .toList() ??
          <String>[];
      final mustHave =
          (map['must_have'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.length >= 2)
              .toList() ??
          _keywordsFromIntent(intent);

      if (queries.isEmpty) return _planHeuristic(intent);

      return _DiscoveryPlan(
        queries: queries,
        mustHave: mustHave,
        scanFeed: map['scan_feed'] != false,
        scanBarFeed: map['scan_bar_feed'] == true,
      );
    } catch (_) {
      return _planHeuristic(intent);
    }
  }

  static List<_RankedCandidate> _rankHeuristic(
    String intent,
    List<String> mustHave,
    List<_Candidate> items,
  ) {
    final intentTokens = {..._keywordsFromIntent(intent), ...mustHave};
    final scored = items.map((item) {
      final hay = _normalize(
        '${item.post.title} ${item.preview} ${item.post.barName}',
      );
      var score = 0;
      for (final token in intentTokens) {
        final nt = _normalize(token);
        if (nt.length < 2) continue;
        if (hay.contains(nt)) score += nt.length >= 4 ? 14 : 10;
      }
      if (item.post.replyCount > 20) score += 4;
      if (item.sources.length > 1) score += 6;
      final fromSearch = item.sources.any((s) => s.startsWith('搜'));
      if (!fromSearch) score = (score * 0.55).round();
      final reason = score >= 20
          ? '标题/摘要与需求关键词较吻合'
          : score >= 10
          ? '部分相关，建议点开看看'
          : fromSearch
          ? '搜索命中，建议点开看看'
          : '浏览流中筛出的候选';
      return _RankedCandidate(
        post: item.post,
        preview: item.preview,
        score: score.clamp(1, 100),
        reason: reason,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  static Future<List<_RankedCandidate>> _rankWithLlm(
    String intent,
    List<_Candidate> items, {
    required AgentConfig config,
  }) async {
    final batch = items.take(_maxRankBatch).toList();
    final lines = batch
        .map(
          (c) =>
              'tid=${c.post.id};吧=${c.post.barName};标题=${c.post.title};摘要=${c.preview.isNotEmpty ? c.preview : "（无）"};回复=${c.post.replyCount}',
        )
        .join('\n');

    try {
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
                      '用户想找符合需求的帖子。下面候选可能标题不含原搜索词但内容相关。'
                      '请按契合度打分并简短说明理由。'
                      '只输出 JSON 数组：[{"tid":"","score":0-100,"reason":"8~20字"}]'
                      '按 score 降序；不相关的 score<30 可省略。',
                },
                {'role': 'user', 'content': '需求：$intent\n\n候选：\n$lines'},
              ],
              'temperature': 0.25,
              'max_tokens': 420,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
      }
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) {
        return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
      }
      final message = choice['message'];
      if (message is! Map) {
        return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
      }
      final raw = message['content']?.toString().trim() ?? '';
      final jsonText = _extractJsonArray(raw);
      if (jsonText == null) {
        return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
      }

      final arr = jsonDecode(jsonText) as List<dynamic>;
      final byId = {for (final c in batch) c.post.id: c};
      final ranked = <_RankedCandidate>[];

      for (final item in arr.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final tid = map['tid']?.toString().trim();
        if (tid == null || tid.isEmpty) continue;
        final candidate = byId[tid];
        if (candidate == null) continue;
        final score = _parseScore(map['score']);
        if (score < 25) continue;
        ranked.add(
          _RankedCandidate(
            post: candidate.post,
            preview: candidate.preview,
            score: score,
            reason: _clipReason(map['reason']?.toString() ?? '与需求较相关'),
          ),
        );
        byId.remove(tid);
      }

      if (ranked.isEmpty) {
        return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
      }

      for (final rest in byId.values) {
        ranked.add(
          _RankedCandidate(
            post: rest.post,
            preview: rest.preview,
            score: 20,
            reason: '未强匹配，作备选',
          ),
        );
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
      return ranked;
    } catch (_) {
      return _rankHeuristic(intent, _keywordsFromIntent(intent), items);
    }
  }

  static List<String> _keywordsFromIntent(String intent) {
    final stop = RegExp(
      r'^(我|你|他|她|想|要|找|看|有|没|吗|呢|吧|帖|帖子|帮我|给我|能不能|可不可以|一下|一个|那种|这种|相关|关于|的|了|啊|呀|哦|嗯|什么|怎么|如何|请问)$',
    );
    final raw = intent
        .replaceAll(RegExp(r'[^\u4e00-\u9fffA-Za-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.length >= 2 && !stop.hasMatch(s))
        .toList();

    final merged = <String>[];
    for (var i = 0; i < raw.length; i++) {
      merged.add(raw[i]);
      if (i + 1 < raw.length && raw[i].length <= 2 && raw[i + 1].length <= 4) {
        merged.add('${raw[i]}${raw[i + 1]}');
      }
    }
    return merged.toSet().toList();
  }

  static String _clipQuery(String raw) {
    final t = raw.trim();
    if (t.length <= 12) return t;
    return t.substring(0, 12);
  }

  static String _clipReason(String raw) {
    final t = raw.trim();
    if (t.length <= 24) return t;
    return '${t.substring(0, 24)}…';
  }

  static String _normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s，,。！？!?；;：:""（）()\[\]]'), '');

  static int _parseScore(dynamic raw) {
    if (raw is int) return raw.clamp(0, 100);
    return int.tryParse(raw?.toString() ?? '')?.clamp(0, 100) ?? 0;
  }

  static String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }

  static String? _extractJsonArray(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }
}

class _DiscoveryPlan {
  final List<String> queries;
  final List<String> mustHave;
  final bool scanFeed;
  final bool scanBarFeed;

  const _DiscoveryPlan({
    required this.queries,
    required this.mustHave,
    this.scanFeed = true,
    this.scanBarFeed = false,
  });
}

class _Candidate {
  final TiebaPost post;
  String preview;
  final Set<String> sources;

  _Candidate({
    required this.post,
    required this.preview,
    required Set<String> sources,
  }) : sources = Set<String>.from(sources);
}

class _RankedCandidate {
  final TiebaPost post;
  final String preview;
  final int score;
  final String reason;

  const _RankedCandidate({
    required this.post,
    required this.preview,
    required this.score,
    required this.reason,
  });
}
