import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_memory_entry.dart';
import 'agent_config_service.dart';
import 'agent_memory_consistency.dart';

class _ExtractRule {
  final RegExp pattern;
  final AgentMemoryCategory category;
  final int importance;
  final String? slot;
  final int confidence;

  const _ExtractRule(
    this.pattern,
    this.category,
    this.importance, {
    this.slot,
    this.confidence = 78,
  });
}

class _ExtractHit {
  final String content;
  final AgentMemoryCategory category;
  final int importance;
  final int confidence;
  final String? slot;

  const _ExtractHit({
    required this.content,
    required this.category,
    required this.importance,
    required this.confidence,
    this.slot,
  });
}

/// 从对话中自动提取、校验并持久化用户长期记忆。
class AgentMemoryService {
  AgentMemoryService._();

  static final AgentMemoryService instance = AgentMemoryService._();

  static const _prefKey = 'agent_memory_v1';
  static const _enabledKey = 'agent_memory_enabled';
  static const _llmExtractKey = 'agent_memory_llm_extract';
  static const _turnCounterKey = 'agent_memory_turn_counter';

  static const _maxStored = 40;
  static const _maxPromptItems = 10;
  static const _maxPromptChars = 640;
  static const _maxContentChars = 72;
  static const _maintenanceEveryTurns = 5;

  final List<AgentMemoryEntry> _entries = [];
  final List<String> _recentUserMessages = [];
  bool _loaded = false;
  bool _dirty = false;
  int _turnCounter = 0;

  bool _enabled = true;
  bool _llmExtract = true;

  bool get enabled => _enabled;
  bool get llmExtractEnabled => _llmExtract;
  List<AgentMemoryEntry> get entries =>
      List.unmodifiable(_entries.where((e) => e.isActive));

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _llmExtract = prefs.getBool(_llmExtractKey) ?? true;
    _turnCounter = prefs.getInt(_turnCounterKey) ?? 0;
    await _loadEntries(prefs);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setLlmExtract(bool value) async {
    _llmExtract = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_llmExtractKey, value);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _llmExtract = prefs.getBool(_llmExtractKey) ?? true;
    _turnCounter = prefs.getInt(_turnCounterKey) ?? 0;
    await _loadEntries(prefs);
  }

  Future<void> _loadEntries(SharedPreferences prefs) async {
    _entries.clear();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list.whereType<Map>()) {
          final entry = AgentMemoryEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (entry.content.trim().isNotEmpty) _entries.add(entry);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    if (!_dirty) return;
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
    await prefs.setInt(_turnCounterKey, _turnCounter);
  }

  Future<String?> buildChatContext({String? query}) async {
    await _ensureLoaded();
    final active = _entries.where((e) => e.isActive).toList();
    if (!_enabled || active.isEmpty) return null;

    final sorted = [...active];
    if (query != null && query.trim().isNotEmpty) {
      sorted.sort(
        (a, b) => AgentMemoryConsistency.relevanceScore(
          query,
          b,
        ).compareTo(AgentMemoryConsistency.relevanceScore(query, a)),
      );
    } else {
      sorted.sort((a, b) {
        final profileBoost = (b.category == AgentMemoryCategory.profile ? 1 : 0)
            .compareTo(a.category == AgentMemoryCategory.profile ? 1 : 0);
        if (profileBoost != 0) return profileBoost;
        final conf = b.confidence.compareTo(a.confidence);
        if (conf != 0) return conf;
        final imp = b.importance.compareTo(a.importance);
        if (imp != 0) return imp;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    }

    final lines = <String>[];
    var used = 0;
    for (final entry in sorted.take(_maxPromptItems)) {
      final trust = entry.confidence < 85 ? '·${entry.trustHint}' : '';
      final line = '- [${entry.category.label}$trust] ${entry.content}';
      if (used + line.length > _maxPromptChars) break;
      lines.add(line);
      used += line.length;
    }
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  /// 对话结束后异步观察用户发言，提取/修正记忆（不阻塞回复）。
  Future<void> observeTurn({
    required String userMessage,
    required AgentConfig config,
    String? assistantReply,
  }) async {
    await _ensureLoaded();
    if (!_enabled) return;

    final text = userMessage.trim();
    if (text.isEmpty || _isTrivial(text)) return;

    _pushRecent(text);
    _turnCounter++;

    var changed = false;
    changed = await _applyLocalCorrections(text) || changed;

    final local = _extractLocal(text);
    for (final item in local) {
      changed =
          await _upsert(
            content: item.content,
            category: item.category,
            importance: item.importance,
            confidence: item.confidence,
            slot: item.slot,
          ) ||
          changed;
    }

    final needsReconcile = _needsReconcile(text);
    final periodic = _turnCounter % _maintenanceEveryTurns == 0;

    if (needsReconcile || periodic) {
      changed =
          await _reconcileWithLlm(
            userMessage: text,
            assistantReply: assistantReply,
            config: config,
            periodic: periodic && !needsReconcile,
          ) ||
          changed;
    }

    if (local.isEmpty &&
        !needsReconcile &&
        _llmExtract &&
        config.isConfigured &&
        text.length >= 12) {
      changed = await _extractWithLlm(text, config) || changed;
    }

    if (changed) {
      _dirty = true;
      await _persist();
    } else {
      await _persistTurnCounter();
    }
  }

  Future<void> remember({
    required String content,
    AgentMemoryCategory category = AgentMemoryCategory.emphasis,
    int importance = 5,
    int confidence = 85,
    String? slot,
  }) async {
    await _ensureLoaded();
    if (!_enabled) return;
    await _upsert(
      content: content,
      category: category,
      importance: importance,
      confidence: confidence,
      slot: slot,
    );
  }

  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.id == id);
    _dirty = true;
    await _persist();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    _dirty = true;
    await _persist();
  }

  Future<bool> _upsert({
    required String content,
    required AgentMemoryCategory category,
    required int importance,
    int confidence = 72,
    String? slot,
  }) async {
    final normalized = _clip(content.trim(), _maxContentChars);
    if (normalized.length < 2) return false;

    var effectiveConfidence = confidence;
    if (slot != null && slot.isNotEmpty) {
      final conflict = AgentMemoryConsistency.detectConflict(
        content: normalized,
        category: category,
        slot: slot,
        existing: _entries,
      );
      if (conflict != null) {
        // 与已有同槽位记忆冲突：降权而非盲目覆盖，避免信息前后矛盾
        effectiveConfidence = (confidence * 0.6).round().clamp(0, 100);
      }
    }

    final now = DateTime.now();
    final slotIndex = slot != null && slot.isNotEmpty
        ? _entries.indexWhere((e) => e.isActive && e.slot == slot)
        : -1;
    final duplicateIndex = slotIndex >= 0
        ? slotIndex
        : _entries.indexWhere(
            (e) => e.isActive && _isDuplicate(e.content, normalized),
          );

    if (duplicateIndex >= 0) {
      final old = _entries[duplicateIndex];
      final sameContent = _normalize(old.content) == _normalize(normalized);
      _entries[duplicateIndex] = old.copyWith(
        content: normalized.length >= old.content.length
            ? normalized
            : old.content,
        category: importance >= old.importance ? category : old.category,
        importance: old.importance > importance ? old.importance : importance,
        confidence: sameContent
            ? (old.confidence + 8).clamp(0, 100)
            : _mergeConfidence(old.confidence, confidence, slot != null),
        updatedAt: now,
        hitCount: old.hitCount + 1,
        slot: slot ?? old.slot,
      );
    } else if (slot != null && slot.isNotEmpty) {
      _entries.insert(
        0,
        AgentMemoryEntry(
          id: '${now.microsecondsSinceEpoch}',
          content: normalized,
          category: category,
          importance: importance,
          confidence: effectiveConfidence.clamp(0, 100),
          slot: slot,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      _entries.insert(
        0,
        AgentMemoryEntry(
          id: '${now.microsecondsSinceEpoch}',
          content: normalized,
          category: category,
          importance: importance,
          confidence: effectiveConfidence.clamp(0, 100),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    _trimAndSort();
    _dirty = true;
    await _persist();
    return true;
  }

  int _mergeConfidence(int oldConf, int newConf, bool sameSlot) {
    if (sameSlot) {
      // 同槽位新说法：新信息略占优，旧置信下降
      return newConf.clamp(0, 100);
    }
    return newConf > oldConf ? newConf : oldConf;
  }

  void _trimAndSort() {
    final cutoff = DateTime.now().subtract(const Duration(days: 5));
    _entries.removeWhere((e) => !e.isActive && e.updatedAt.isBefore(cutoff));
    _entries.sort((a, b) {
      final imp = b.importance.compareTo(a.importance);
      if (imp != 0) return imp;
      final conf = b.confidence.compareTo(a.confidence);
      if (conf != 0) return conf;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    while (_entries.length > _maxStored) {
      _entries.removeLast();
    }
  }

  Future<bool> _applyLocalCorrections(String text) async {
    var changed = false;
    final now = DateTime.now();

    if (_deceptionPattern.hasMatch(text)) {
      for (var i = 0; i < _entries.length; i++) {
        final e = _entries[i];
        if (!e.isActive) continue;
        if (e.category != AgentMemoryCategory.profile &&
            e.category != AgentMemoryCategory.fact) {
          continue;
        }
        final recent = now.difference(e.updatedAt).inHours < 48;
        if (!recent) continue;
        final lowered = (e.confidence - 45).clamp(0, 100);
        if (lowered != e.confidence) {
          _entries[i] = e.copyWith(confidence: lowered, updatedAt: now);
          changed = true;
        }
      }
    }

    for (final slot in _profileSlots) {
      final pattern = _slotRetractionPattern(slot);
      if (!pattern.hasMatch(text)) continue;
      final idx = _entries.indexWhere((e) => e.isActive && e.slot == slot);
      if (idx >= 0) {
        _entries[idx] = _entries[idx].copyWith(confidence: 0, updatedAt: now);
        changed = true;
      }
    }

    final correction = _extractCorrection(text);
    if (correction != null) {
      changed =
          await _upsert(
            content: correction.content,
            category: correction.category,
            importance: correction.importance,
            confidence: correction.confidence,
            slot: correction.slot,
          ) ||
          changed;
    }

    return changed;
  }

  static bool _needsReconcile(String text) {
    return _deceptionPattern.hasMatch(text) ||
        _correctionPattern.hasMatch(text) ||
        RegExp(r'(?:其实|更正|说错了|准确说|真正)').hasMatch(text);
  }

  Future<bool> _reconcileWithLlm({
    required String userMessage,
    required AgentConfig config,
    String? assistantReply,
    bool periodic = false,
  }) async {
    if (!config.isConfigured) return false;
    final active = _entries.where((e) => e.isActive).toList();
    if (active.isEmpty && !periodic) return false;

    try {
      final memoryLines = active
          .take(16)
          .map(
            (e) =>
                'id=${e.id};类别=${e.category.label};置信=${e.confidence};槽位=${e.slot ?? "-"};内容=${e.content}',
          )
          .join('\n');
      final recent = _recentUserMessages.take(4).join('\n---\n');

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
                      '你是记忆管理员。根据最新对话检查用户长期记忆是否准确。'
                      '用户可能开玩笑、撒谎、更正之前的话。'
                      '只输出 JSON 数组，不要其它文字。'
                      '每条指令格式：{"action":"update|delete|confidence","id":"记忆id","content":"新内容可选","confidence":0-100可选,"reason":"原因"}'
                      '无变更输出 []。'
                      '规则：'
                      '- 用户明确更正/撤回 → update 或 delete 或 confidence 降到 0~25'
                      '- 明显玩笑/骗你 → 相关记忆 confidence 降到 20~40'
                      '- 多次一致陈述 → confidence 升到 85~95'
                      '- 矛盾时保留更可信、更新或降低旧条',
                },
                {
                  'role': 'user',
                  'content':
                      '现有记忆：\n${memoryLines.isEmpty ? "（空）" : memoryLines}\n\n'
                      '最近用户发言：\n$recent\n\n'
                      '本轮用户：$userMessage\n'
                      '${assistantReply != null && assistantReply.trim().isNotEmpty ? "本轮助手：${_clip(assistantReply, 120)}\n" : ""}'
                      '${periodic ? "（定期整理，顺便合并重复、降低不可信条目）" : "（检测到可能更正/玩笑，请重点核对）"}',
                },
              ],
              'temperature': 0.15,
              'max_tokens': 280,
            }),
          )
          .timeout(const Duration(seconds: 18));

      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return false;
      final message = choice['message'];
      if (message is! Map) return false;
      final raw = message['content']?.toString().trim() ?? '';
      if (raw.isEmpty) return false;

      return _applyReconcileActions(raw);
    } catch (_) {
      return false;
    }
  }

  bool _applyReconcileActions(String raw) {
    final jsonText = _extractJsonArray(raw);
    if (jsonText == null) return false;

    List<dynamic> actions;
    try {
      actions = jsonDecode(jsonText) as List<dynamic>;
    } catch (_) {
      return false;
    }

    var changed = false;
    final now = DateTime.now();

    for (final item in actions.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final action = map['action']?.toString().trim().toLowerCase();
      final id = map['id']?.toString().trim();
      if (action == null || id == null || id.isEmpty) continue;

      final idx = _entries.indexWhere((e) => e.id == id);
      if (idx < 0) continue;
      final old = _entries[idx];

      switch (action) {
        case 'delete':
          _entries[idx] = old.copyWith(confidence: 0, updatedAt: now);
          changed = true;
        case 'confidence':
          final conf = _parseConfidence(map['confidence']);
          if (conf != null && conf != old.confidence) {
            _entries[idx] = old.copyWith(confidence: conf, updatedAt: now);
            changed = true;
          }
        case 'update':
          final content = map['content']?.toString().trim();
          final conf = _parseConfidence(map['confidence']);
          if (content != null && content.isNotEmpty) {
            _entries[idx] = old.copyWith(
              content: _clip(content, _maxContentChars),
              confidence: conf ?? (old.confidence + 10).clamp(0, 100),
              updatedAt: now,
            );
            changed = true;
          } else if (conf != null && conf != old.confidence) {
            _entries[idx] = old.copyWith(confidence: conf, updatedAt: now);
            changed = true;
          }
      }
    }

    if (changed) {
      _dirty = true;
    }
    return changed;
  }

  static int? _parseConfidence(dynamic raw) {
    if (raw is int) return raw.clamp(0, 100);
    return int.tryParse(raw?.toString() ?? '')?.clamp(0, 100);
  }

  static String? _extractJsonArray(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }

  _ExtractHit? _extractCorrection(String text) {
    final match = _correctionPattern.firstMatch(text);
    if (match == null) return null;
    final body = match.group(1)?.trim() ?? '';
    if (body.length < 2) return null;

    for (final rule in _profileRules) {
      final m = rule.pattern.firstMatch(body);
      if (m == null) continue;
      final content = _formatProfile(rule, m, body);
      if (content == null) continue;
      return _ExtractHit(
        content: content,
        category: AgentMemoryCategory.profile,
        importance: rule.importance,
        confidence: 88,
        slot: rule.slot,
      );
    }

    return _ExtractHit(
      content: _clip(body, _maxContentChars),
      category: AgentMemoryCategory.fact,
      importance: 4,
      confidence: 82,
    );
  }

  static final _deceptionPattern = RegExp(
    r'(?:骗你的|逗你的|开玩笑|闹着玩|忽悠你|假的啦|骗你呢|整你的)',
  );

  static final _correctionPattern = RegExp(
    r'(?:其实|更正(?:一下)?|说错了|准确(?:来)?说|真正(?:的)?是|刚才(?:说)?错)[：:，,\s]*(.+)',
  );

  static const _profileSlots = [
    'birthday',
    'age',
    'location',
    'job',
    'nickname',
  ];

  static RegExp _slotRetractionPattern(String slot) {
    return switch (slot) {
      'birthday' => RegExp(r'生日.*(?:骗|假|逗|没有|不是)'),
      'age' => RegExp(r'(?:年龄|岁).*(?:骗|假|逗|没有|不是)'),
      'location' => RegExp(r'(?:住|在).*(?:骗|假|逗|没有|不是)'),
      'job' => RegExp(r'(?:工作|职业|上班).*(?:骗|假|逗|没有|不是)'),
      'nickname' => RegExp(r'(?:叫我|名字).*(?:骗|假|逗|不是)'),
      _ => RegExp(r'$a'),
    };
  }

  static final _rules = [
    _ExtractRule(
      RegExp(r'(?:记住|别忘了|要记得|务必记住|帮我记(?:住|一下))[：:，,\s]*(.+)'),
      AgentMemoryCategory.emphasis,
      5,
      confidence: 90,
    ),
    _ExtractRule(
      RegExp(r'我的生日是(.+)'),
      AgentMemoryCategory.profile,
      5,
      slot: 'birthday',
      confidence: 88,
    ),
    _ExtractRule(
      RegExp(r'我生日是(.+)'),
      AgentMemoryCategory.profile,
      5,
      slot: 'birthday',
      confidence: 88,
    ),
    _ExtractRule(
      RegExp(r'我(?:今年)?(\d{1,3})岁'),
      AgentMemoryCategory.profile,
      4,
      slot: 'age',
      confidence: 86,
    ),
    _ExtractRule(
      RegExp(r'我(?:住在|在)([^，,。！!？?\s]{2,16})(?:住|生活|读书|工作)?'),
      AgentMemoryCategory.profile,
      4,
      slot: 'location',
      confidence: 82,
    ),
    _ExtractRule(
      RegExp(r'我是(?:做|干|从事)?([^，,。！!？?\s]{2,16})(?:的|工作)?'),
      AgentMemoryCategory.profile,
      4,
      slot: 'job',
      confidence: 80,
    ),
    _ExtractRule(
      RegExp(r'(?:千万别|一定不要|别(?:再)?|禁止)[：:，,\s]*(.+)'),
      AgentMemoryCategory.emphasis,
      4,
    ),
    _ExtractRule(
      RegExp(r'我(?:一直)?习惯[：:，,\s]*(.+)'),
      AgentMemoryCategory.habit,
      4,
    ),
    _ExtractRule(
      RegExp(r'我(?:一般|通常|平时)[：:，,\s]*(.+)'),
      AgentMemoryCategory.habit,
      3,
    ),
    _ExtractRule(
      RegExp(r'我(?:很)?讨厌[：:，,\s]*(.+)'),
      AgentMemoryCategory.preference,
      4,
    ),
    _ExtractRule(
      RegExp(r'我不(?:太)?喜欢[：:，,\s]*(.+)'),
      AgentMemoryCategory.preference,
      4,
    ),
    _ExtractRule(
      RegExp(r'我(?:很)?喜欢[：:，,\s]*(.+)'),
      AgentMemoryCategory.preference,
      3,
    ),
    _ExtractRule(
      RegExp(r'(?:叫我|你可以叫我)[：:，,\s]*(.+)'),
      AgentMemoryCategory.profile,
      4,
      slot: 'nickname',
      confidence: 86,
    ),
    _ExtractRule(RegExp(r'别叫我[：:，,\s]*(.+)'), AgentMemoryCategory.emphasis, 4),
    _ExtractRule(
      RegExp(r'(?:我强调|重要的是|重点(?:是)?)[：:，,\s]*(.+)'),
      AgentMemoryCategory.emphasis,
      4,
    ),
    _ExtractRule(
      RegExp(r'(?:别(?:给我)?|不要|不想)(?:再)?(?:讲|说|搬)?(?:道理|大道理|教做人|上课|说教)'),
      AgentMemoryCategory.emotional,
      4,
    ),
    _ExtractRule(
      RegExp(r'(?:吐槽|一起骂|跟我骂|陪我骂|想骂)'),
      AgentMemoryCategory.emotional,
      3,
    ),
    _ExtractRule(
      RegExp(
        r'(?:我(?:很)?(?:容易|会)|(?:一)?(?:提到|说到))[：:，,\s]*(.+?)(?:就|会)(?:破防|难受|绷不住|崩溃)',
      ),
      AgentMemoryCategory.emotional,
      5,
    ),
    _ExtractRule(
      RegExp(r'(?:我(?:比较|更)?喜欢|想要)(?:你)?(?:一起|跟我)?(?:吐槽|安慰|陪着)(?:$|[：:，,\s])'),
      AgentMemoryCategory.emotional,
      3,
    ),
  ];

  static final _profileRules = _rules
      .where((r) => r.category == AgentMemoryCategory.profile)
      .toList();

  static List<_ExtractHit> _extractLocal(String text) {
    final results = <_ExtractHit>[];
    final seen = <String>{};

    for (final rule in _rules) {
      final match = rule.pattern.firstMatch(text);
      if (match == null) continue;

      String content;
      if (rule.category == AgentMemoryCategory.profile && rule.slot != null) {
        content = _formatProfile(rule, match, text) ?? '';
      } else {
        final captured = match.groupCount >= 1
            ? (match.group(1)?.trim() ?? '')
            : match.group(0)?.trim() ?? '';
        content = captured.isNotEmpty
            ? captured
            : switch (rule.category) {
                AgentMemoryCategory.emotional
                    when text.contains('说教') || text.contains('道理') =>
                  '讨厌被说教/讲道理',
                AgentMemoryCategory.emotional
                    when RegExp(r'吐槽|一起骂|跟我骂').hasMatch(text) =>
                  '喜欢一起吐槽',
                AgentMemoryCategory.emotional => _clip(text, _maxContentChars),
                _ => _clip(text, _maxContentChars),
              };
      }

      if (content.length < 2) continue;
      final key = '${rule.slot ?? rule.category.name}|${_normalize(content)}';
      if (!seen.add(key)) continue;

      results.add(
        _ExtractHit(
          content: content,
          category: rule.category,
          importance: rule.importance,
          confidence: rule.confidence,
          slot: rule.slot,
        ),
      );
    }
    return results;
  }

  static String? _formatProfile(
    _ExtractRule rule,
    RegExpMatch match,
    String text,
  ) {
    return switch (rule.slot) {
      'birthday' => '生日：${_clip(match.group(1)?.trim() ?? '', 24)}',
      'age' => '年龄：${match.group(1)?.trim()}岁',
      'location' => '所在地：${_clip(match.group(1)?.trim() ?? '', 20)}',
      'job' => '职业：${_clip(match.group(1)?.trim() ?? '', 20)}',
      'nickname' => '称呼：${_clip(match.group(1)?.trim() ?? '', 16)}',
      _ => _clip(match.group(1)?.trim() ?? text, _maxContentChars),
    };
  }

  Future<bool> _extractWithLlm(String userMessage, AgentConfig config) async {
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
                      '从用户话里提取0或1条值得长期记住的信息。'
                      '没有则只输出 NONE。有则输出：类别|内容（8～24字）|置信度(0-100)。'
                      '类别只能是：习惯、偏好、强调、事实、个人信息、情感。'
                      '个人信息含生日/年龄/所在地/职业/称呼等；'
                      '用户明显开玩笑时输出 NONE 或置信度≤35。',
                },
                {'role': 'user', 'content': _clip(userMessage, 200)},
              ],
              'temperature': 0.2,
              'max_tokens': 64,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return false;
      final message = choice['message'];
      if (message is! Map) return false;
      final raw = message['content']?.toString().trim() ?? '';
      if (raw.isEmpty || raw.toUpperCase() == 'NONE') return false;

      final parts = raw.split('|');
      if (parts.length < 2) return false;
      final category =
          AgentMemoryCategoryLabel.parse(parts.first) ??
          AgentMemoryCategory.fact;
      final content = parts[1].trim();
      if (content.length < 2) return false;
      final confidence = parts.length >= 3
          ? (_parseConfidence(parts[2]) ?? 65)
          : (category == AgentMemoryCategory.profile ? 72 : 60);

      if (confidence <= 20) return false;

      await _upsert(
        content: content,
        category: category,
        importance: category == AgentMemoryCategory.profile ? 4 : 2,
        confidence: confidence,
        slot: _inferSlot(content, category),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _inferSlot(String content, AgentMemoryCategory category) {
    if (category != AgentMemoryCategory.profile) return null;
    if (content.startsWith('生日')) return 'birthday';
    if (content.startsWith('年龄')) return 'age';
    if (content.startsWith('所在地') || content.startsWith('住在')) {
      return 'location';
    }
    if (content.startsWith('职业') || content.startsWith('工作')) return 'job';
    if (content.startsWith('称呼') || content.startsWith('叫我')) {
      return 'nickname';
    }
    return null;
  }

  void _pushRecent(String text) {
    _recentUserMessages.insert(0, _clip(text, 160));
    if (_recentUserMessages.length > 6) {
      _recentUserMessages.removeLast();
    }
  }

  Future<void> _persistTurnCounter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_turnCounterKey, _turnCounter);
  }

  static bool _isTrivial(String text) {
    final t = text.trim();
    if (t.length <= 4) return true;
    return RegExp(
      r'^(嗨|你好|在吗|哈喽|hello|hi|嗯+|[哦啊]+)[\?？!！。~\s]*$',
      caseSensitive: false,
    ).hasMatch(t);
  }

  static bool _isDuplicate(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na == nb) return true;
    if (na.length >= 4 && nb.length >= 4) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }

  static String _normalize(String raw) {
    return raw.toLowerCase().replaceAll(
      RegExp(r'[\s，,。！？!?；;：:""（）()\[\]【】]'),
      '',
    );
  }

  static String _clip(String raw, int max) {
    final text = raw.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }
}
