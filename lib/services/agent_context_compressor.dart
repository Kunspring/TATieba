import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_config_service.dart';

/// 五阶段上下文压缩引擎。
/// 当对话历史估算 token 数超过模型窗口 75% 时触发，
/// 生成结构化摘要替代被压缩的消息段，保护关键上下文不被截断。
abstract final class AgentContextCompressor {
  AgentContextCompressor._();

  /// 保守估计的模型上下文窗口（token）。
  static const _modelContextTokens = 16000;

  /// token 使用率触发阈值。
  static const _triggerRatio = 0.75;

  /// 头部始终保护的消息条数（system + 前几条 user/assistant）。
  static const _headProtect = 3;

  /// 尾部保护的 token 预算占比。
  static const _tailBudgetRatio = 0.20;

  static final _chineseCharRe = RegExp(r'[一-鿿㐀-䶿]');

  // ── Token 估算 ───────────────────────────────────────────

  /// 粗略估算文本 token 数：中文 ~1.2 token/字，英文 ~0.25 token/字。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    final chinese = _chineseCharRe.allMatches(text).length;
    final other = text.length - chinese;
    return (chinese * 1.2 + other * 0.25).ceil();
  }

  /// 估算消息列表的总 token 数。
  static int estimateMessagesTokens(List<Map<String, dynamic>> messages) {
    var total = 0;
    for (final m in messages) {
      final content = m['content'];
      if (content is String) {
        total += estimateTokens(content);
      } else if (content is List) {
        for (final part in content) {
          if (part is Map) {
            total += estimateTokens(part['text']?.toString() ?? '');
          }
        }
      }
      // 每条消息 ~4 token 的 role 开销
      total += 4;
    }
    return total;
  }

  /// 是否需要压缩。
  static bool needsCompression(List<Map<String, dynamic>> messages) {
    return estimateMessagesTokens(messages) >
        (_modelContextTokens * _triggerRatio).ceil();
  }

  // ── Phase 1: 廉价预清理（无 LLM 调用）───────────────────

  static List<Map<String, dynamic>> _phase1PreClean(
    List<Map<String, dynamic>> messages,
  ) {
    final cleaned = <Map<String, dynamic>>[];
    final seenFileReads = <String>{};

    for (final m in messages) {
      final role = m['role']?.toString() ?? '';
      final content = m['content']?.toString() ?? '';

      // 去重连续相同的文件读取
      if (role == 'tool' && content.length < 200) {
        final hash = '$role|$content';
        if (seenFileReads.contains(hash)) continue;
        seenFileReads.add(hash);
      }

      // 工具调用参数超过 500 字节则截短
      var msg = m;
      if (role == 'assistant' && m['tool_calls'] is List) {
        final calls = List<Map<String, dynamic>>.from(m['tool_calls'] as List);
        var modified = false;
        for (var i = 0; i < calls.length; i++) {
          final fn = calls[i]['function'];
          if (fn is Map) {
            final args = fn['arguments']?.toString() ?? '';
            if (args.length > 500) {
              try {
                final parsed = jsonDecode(args) as Map;
                final truncated = _truncateMapValues(
                  Map<String, dynamic>.from(parsed),
                  120,
                );
                calls[i] = {
                  ...calls[i],
                  'function': {
                    ...Map<String, dynamic>.from(fn),
                    'arguments': jsonEncode(truncated),
                  },
                };
                modified = true;
              } catch (_) {
                calls[i] = {
                  ...calls[i],
                  'function': {
                    ...Map<String, dynamic>.from(fn),
                    'arguments': '${args.substring(0, 500)}…',
                  },
                };
                modified = true;
              }
            }
          }
        }
        if (modified) {
          msg = Map<String, dynamic>.from(m);
          msg['tool_calls'] = calls;
        }
      }

      // 旧工具结果模板化缩减
      if (role == 'tool' && content.length > 600) {
        final summary = _summarizeToolOutput(content, role);
        msg = {'role': role, 'tool_call_id': m['tool_call_id'], 'content': summary};
      }

      cleaned.add(msg);
    }
    return cleaned;
  }

  static String _summarizeToolOutput(String content, String role) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json.containsKey('posts')) {
        final posts = json['posts'];
        final count = posts is List ? posts.length : 0;
        return '[工具返回 $count 条帖子，详细内容已压缩]';
      }
      if (json.containsKey('comments')) {
        final comments = json['comments'];
        final count = comments is List ? comments.length : 0;
        return '[工具返回 $count 条评论，详细内容已压缩]';
      }
      if (json.containsKey('results')) {
        final results = json['results'];
        final count = results is List ? results.length : 0;
        return '[搜索结果 $count 条，详细内容已压缩]';
      }
      if (json.containsKey('items')) {
        final items = json['items'];
        final count = items is List ? items.length : 0;
        return '[列表 $count 项，详细内容已压缩]';
      }
      if (json.containsKey('error')) {
        return '[工具错误] ${json['error']}';
      }
      if (content.length <= 200) return content;
      return '[工具输出 ${content.length} 字符，已压缩]';
    } catch (_) {
      if (content.length <= 200) return content;
      return '[工具输出 ${content.length} 字符，已压缩]';
    }
  }

  static Map<String, dynamic> _truncateMapValues(Map<String, dynamic> map, int maxLen) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final v = entry.value;
      if (v is String && v.length > maxLen) {
        result[entry.key] = '${v.substring(0, maxLen)}…';
      } else if (v is Map) {
        result[entry.key] = _truncateMapValues(Map<String, dynamic>.from(v), maxLen);
      } else if (v is List && v.isNotEmpty && v.first is Map) {
        result[entry.key] = '[${v.length} items]';
      } else {
        result[entry.key] = v;
      }
    }
    return result;
  }

  // ── Phase 2: 划定压缩边界 ────────────────────────────────

  /// 返回 (startIdx, endIdx)：需要被摘要替换的消息范围。
  static (int, int) _phase2Boundaries(List<Map<String, dynamic>> messages) {
    final total = estimateMessagesTokens(messages);
    final tailBudget = (total * _tailBudgetRatio).ceil();

    // 从尾部倒数，保留 tail budget 内最近的消息
    var tailTokens = 0;
    var tailStart = messages.length;
    for (var i = messages.length - 1; i >= _headProtect; i--) {
      final content = messages[i]['content']?.toString() ?? '';
      tailTokens += estimateTokens(content) + 4;
      if (tailTokens > tailBudget) {
        tailStart = i + 1;
        break;
      }
      tailStart = i;
    }

    if (tailStart <= _headProtect + 2) {
      // 消息太少，不值得压缩；压缩中间段
      return (_headProtect, messages.length - 3);
    }

    return (_headProtect, tailStart - 1);
  }

  // ── Phase 3: 结构化摘要生成（LLM 调用）───────────────────

  static Future<String> _phase3GenerateSummary({
    required List<Map<String, dynamic>> messages,
    required int start,
    required int end,
    required AgentConfig config,
    String? previousSummary,
  }) async {
    if (!config.isConfigured || end <= start) {
      return _fallbackSummary(messages, start, end);
    }

    final segment = messages.sublist(start, end + 1);
    final segmentText = _messagesToText(segment);

    final prompt = previousSummary != null
        ? '基于以下旧摘要和新对话，生成更新的结构化对话摘要。只输出摘要，不要其他文字。\n'
              '旧摘要：\n$previousSummary\n\n新对话：\n$segmentText'
        : '为以下对话生成结构化摘要。只输出摘要，不要其他文字。\n\n$segmentText';

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
                  'content': _summaryTemplate,
                },
                {'role': 'user', 'content': _clip(prompt, 6000)},
              ],
              'temperature': 0.2,
              'max_tokens': 300,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        return _fallbackSummary(messages, start, end);
      }
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return _fallbackSummary(messages, start, end);
      final msg = choice['message'];
      if (msg is! Map) return _fallbackSummary(messages, start, end);
      final text = msg['content']?.toString().trim() ?? '';
      if (text.isEmpty) return _fallbackSummary(messages, start, end);
      return text;
    } catch (_) {
      return _fallbackSummary(messages, start, end);
    }
  }

  static const _summaryTemplate =
      '你是对话摘要器。将给定对话压缩为以下格式的结构化摘要：\n'
      '- 任务目标：用户在做什么/想达成什么\n'
      '- 已完成：已成功完成的操作\n'
      '- 关键发现：重要的帖子/信息/数据\n'
      '- 当前状态：现在进行到哪一步\n'
      '- 待处理：用户还没得到答复的事项\n'
      '- 重要上下文：影响后续回复的关键信息\n'
      '用中文，简洁。';

  static String _fallbackSummary(
    List<Map<String, dynamic>> messages,
    int start,
    int end,
  ) {
    final userMessages = <String>[];
    for (var i = start; i <= end && i < messages.length; i++) {
      final m = messages[i];
      final role = m['role']?.toString() ?? '';
      final content = m['content']?.toString() ?? '';
      if (role == 'user' && content.isNotEmpty) {
        userMessages.add('- 用户：${_clip(content, 120)}');
      }
    }
    if (userMessages.isEmpty) return '[对话已压缩]';
    return '对话摘要：\n${userMessages.join('\n')}';
  }

  // ── Phase 4: 装配新消息列表 ─────────────────────────────

  static List<Map<String, dynamic>> _phase4Reassemble({
    required List<Map<String, dynamic>> messages,
    required int start,
    required int end,
    required String summary,
  }) {
    final result = <Map<String, dynamic>>[];

    // 保留头部
    for (var i = 0; i < start && i < messages.length; i++) {
      result.add(messages[i]);
    }

    // 注入摘要围栏
    result.add({
      'role': 'user',
      'content':
          '[系统] 以下为历史对话的压缩摘要（非当前消息，仅供参考）：\n$summary'
              '\n[系统] 以上为历史摘要。请基于摘要和后续最新消息继续回复。',
    });

    // 保留尾部
    for (var i = end + 1; i < messages.length; i++) {
      result.add(messages[i]);
    }

    return result;
  }

  // ── Phase 5: 清理孤儿 tool_call/tool_result ──────────────

  static List<Map<String, dynamic>> _phase5CleanOrphans(
    List<Map<String, dynamic>> messages,
  ) {
    final result = <Map<String, dynamic>>[];
    final pendingCalls = <String>{};
    final orphanResults = <String>{};

    // First pass: identify orphans
    for (final m in messages) {
      final role = m['role']?.toString() ?? '';
      if (role == 'assistant' && m['tool_calls'] is List) {
        for (final call in (m['tool_calls'] as List)) {
          if (call is Map) {
            final id = call['id']?.toString() ?? '';
            if (id.isNotEmpty) pendingCalls.add(id);
          }
        }
      }
      if (role == 'tool') {
        final id = m['tool_call_id']?.toString() ?? '';
        if (id.isNotEmpty) {
          if (pendingCalls.contains(id)) {
            pendingCalls.remove(id);
          } else {
            orphanResults.add(id);
          }
        }
      }
    }

    // Second pass: filter
    for (final m in messages) {
      final role = m['role']?.toString() ?? '';
      if (role == 'tool') {
        final id = m['tool_call_id']?.toString() ?? '';
        if (orphanResults.contains(id)) continue;
      }
      if (role == 'assistant' && m['tool_calls'] is List) {
        final calls = (m['tool_calls'] as List).whereType<Map>().where((c) {
          final id = c['id']?.toString() ?? '';
          return !orphanResults.contains(id);
        }).toList();
        if (calls.isEmpty && !m.containsKey('content')) continue;
        if (calls.length != (m['tool_calls'] as List).length) {
          final cleaned = Map<String, dynamic>.from(m);
          cleaned['tool_calls'] = calls;
          result.add(cleaned);
          continue;
        }
      }
      result.add(m);
    }

    // Strip orphan pending calls (no matching tool result)
    return result.where((m) {
      if (m['role'] != 'assistant' || m['tool_calls'] is! List) return true;
      final calls = m['tool_calls'] as List;
      if (calls.isEmpty) return true;
      // Check if ANY call in this message has a matching result
      for (final c in calls.whereType<Map>()) {
        final id = c['id']?.toString() ?? '';
        if (pendingCalls.contains(id)) return false;
      }
      return true;
    }).toList();
  }

  // ── Public API ───────────────────────────────────────────

  /// 完整压缩流程。返回压缩后的消息列表。
  /// 如果不需要压缩则返回原始列表。
  static Future<List<Map<String, dynamic>>> compress({
    required List<Map<String, dynamic>> messages,
    required AgentConfig config,
    String? previousSummary,
  }) async {
    if (!needsCompression(messages)) return messages;
    if (messages.length < 6) return messages;

    // Phase 1
    var cleaned = _phase1PreClean(messages);

    // Phase 2
    final (start, end) = _phase2Boundaries(cleaned);
    if (end - start < 3) return messages; // 不值得压缩的短段

    // Phase 3
    final summary = await _phase3GenerateSummary(
      messages: cleaned,
      start: start,
      end: end,
      config: config,
      previousSummary: previousSummary,
    );

    // Phase 4
    var reassembled = _phase4Reassemble(
      messages: cleaned,
      start: start,
      end: end,
      summary: summary,
    );

    // Phase 5
    reassembled = _phase5CleanOrphans(reassembled);

    return reassembled;
  }

  // ── Utils ────────────────────────────────────────────────

  static String _messagesToText(List<Map<String, dynamic>> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final role = m['role']?.toString() ?? '?';
      final content = m['content']?.toString() ?? '';
      if (content.isNotEmpty) {
        buf.writeln('[$role] ${_clip(content, 200)}');
      }
      if (m['tool_calls'] is List) {
        for (final call in (m['tool_calls'] as List).whereType<Map>()) {
          final fn = call['function'];
          if (fn is Map) {
            buf.writeln('[tool] ${fn['name']}');
          }
        }
      }
    }
    return buf.toString();
  }

  static String _clip(String raw, int max) {
    final text = raw.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }
}
