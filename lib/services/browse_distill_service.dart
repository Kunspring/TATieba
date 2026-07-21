import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browse_distill_entry.dart';
import '../models/tieba_post.dart';
import 'agent_config_service.dart';

/// 浏览帖子的本地蒸馏 + 可选极少量 LLM 润色，供陪聊上下文使用。
class BrowseDistillService {
  BrowseDistillService._();

  static final BrowseDistillService instance = BrowseDistillService._();

  static const _prefKey = 'browse_distill_v1';
  static const _enabledKey = 'browse_distill_enabled';
  static const _llmPolishKey = 'browse_distill_llm_polish';

  static const _maxStored = 12;
  static const _maxPromptItems = 5;
  static const _maxPromptChars = 720;
  static const _maxHookChars = 96;
  static const _llmBatchSize = 2;

  final List<BrowseDistillEntry> _entries = [];
  bool _loaded = false;
  bool _dirty = false;

  bool _enabled = true;
  bool _llmPolish = true;

  bool get enabled => _enabled;
  bool get llmPolishEnabled => _llmPolish;

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _llmPolish = prefs.getBool(_llmPolishKey) ?? true;
    await _loadEntries(prefs);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setLlmPolish(bool value) async {
    _llmPolish = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_llmPolishKey, value);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    _llmPolish = prefs.getBool(_llmPolishKey) ?? true;
    await _loadEntries(prefs);
  }

  Future<void> _loadEntries(SharedPreferences prefs) async {
    _entries.clear();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list.whereType<Map>()) {
          final entry = BrowseDistillEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (entry.tid.isNotEmpty) _entries.add(entry);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    if (!_dirty) return;
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    final payload = _entries.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKey, jsonEncode(payload));
  }

  void recordPreview(TiebaPost post) {
    if (!_enabled || post.id.isEmpty) return;
    _ensureLoaded().then(
      (_) => _upsert(
        tid: post.id,
        title: post.title,
        barName: post.barName,
        localHook: _previewHook(post),
        dwellMs: 0,
      ),
    );
  }

  void recordDetail(TiebaPostDetail detail, {int dwellMs = 0}) {
    if (!_enabled) return;
    final post = detail.post;
    if (post.id.isEmpty) return;
    _ensureLoaded().then(
      (_) => _upsert(
        tid: post.id,
        title: post.title,
        barName: post.barName,
        localHook: _localDistill(post, detail.comments),
        dwellMs: dwellMs,
        preserveLlmHook: true,
      ),
    );
  }

  void _upsert({
    required String tid,
    required String title,
    required String barName,
    required String localHook,
    required int dwellMs,
    bool preserveLlmHook = false,
  }) {
    final now = DateTime.now();
    final existingIndex = _entries.indexWhere((e) => e.tid == tid);
    String? llmHook;
    if (existingIndex >= 0 && preserveLlmHook) {
      final old = _entries[existingIndex];
      if (old.localHook == localHook) {
        llmHook = old.llmHook;
      }
    }
    final entry = BrowseDistillEntry(
      tid: tid,
      title: title,
      barName: barName,
      localHook: _clip(localHook, _maxHookChars),
      llmHook: llmHook,
      viewedAt: now,
      dwellMs: dwellMs,
    );

    if (existingIndex >= 0) {
      _entries.removeAt(existingIndex);
    }
    _entries.insert(0, entry);
    while (_entries.length > _maxStored) {
      _entries.removeLast();
    }
    _dirty = true;
    _persist();
  }

  /// 聊天前构建注入块；可选一次 LLM 润色（最多 2 条，低 token）。
  Future<String?> buildChatContext(AgentConfig config) async {
    await _ensureLoaded();
    if (!_enabled || _entries.isEmpty) return null;

    if (_llmPolish && config.isConfigured) {
      await _polishBatch(config);
    }

    return _formatPromptBlock();
  }

  String? _formatPromptBlock() {
    if (_entries.isEmpty) return null;

    final now = DateTime.now();
    final sorted = [..._entries]
      ..sort((a, b) {
        final dwellCmp = b.dwellMs.compareTo(a.dwellMs);
        if (dwellCmp != 0) return dwellCmp;
        return b.viewedAt.compareTo(a.viewedAt);
      });

    final lines = <String>[];
    var used = 0;
    for (final entry in sorted.take(_maxPromptItems)) {
      final age = _ageLabel(now, entry.viewedAt);
      final bar = entry.barName.isNotEmpty ? entry.barName : '未知吧';
      final line = '- [$age] $bar · ${entry.hook}';
      if (used + line.length > _maxPromptChars) break;
      lines.add(line);
      used += line.length;
    }
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  static String _ageLabel(DateTime now, DateTime viewedAt) {
    final diff = now.difference(viewedAt);
    if (diff.inMinutes < 3) return '刚看';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '较早';
  }

  Future<void> _polishBatch(AgentConfig config) async {
    final now = DateTime.now();
    final candidates = _entries
        .where((e) => e.needsLlmPolish(now))
        .take(_llmBatchSize)
        .toList();
    if (candidates.isEmpty) return;

    final input = candidates
        .map((e) {
          final bar = e.barName.isNotEmpty ? e.barName : '?';
          return '${e.tid}|$bar|${_clip(e.title, 36)}|${_clip(e.localHook, 80)}';
        })
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
                      '把用户刚看过的贴吧帖子压成聊天切入点。输入每行：tid|吧|标题|摘要。'
                      '输出每行：tid|一句口语化切入点（12～22字），方便陪聊接话。只输出行，不要解释。',
                },
                {'role': 'user', 'content': input},
              ],
              'temperature': 0.35,
              'max_tokens': 96,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map;
      final choice = (body['choices'] as List?)?.first;
      if (choice is! Map) return;
      final message = choice['message'];
      if (message is! Map) return;
      final content = message['content']?.toString() ?? '';
      _applyPolishLines(content);
    } catch (_) {}
  }

  void _applyPolishLines(String raw) {
    final lines = raw.split('\n');
    var changed = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.contains('|')) continue;
      final parts = trimmed.split('|');
      if (parts.length < 2) continue;
      final tid = parts.first.trim();
      final hook = parts.sublist(1).join('|').trim();
      if (tid.isEmpty || hook.isEmpty) continue;
      final index = _entries.indexWhere((e) => e.tid == tid);
      if (index < 0) continue;
      _entries[index] = _entries[index].copyWith(
        llmHook: _clip(hook, _maxHookChars),
      );
      changed = true;
    }
    if (changed) {
      _dirty = true;
      _persist();
    }
  }

  static String _previewHook(TiebaPost post) {
    final title = _plain(post.title, max: 40);
    if (title.isEmpty) return '无标题帖';
    final bar = post.barName.trim();
    return bar.isNotEmpty ? '《$title》' : title;
  }

  static String _localDistill(TiebaPost post, List<TiebaComment> comments) {
    final title = _plain(post.title, max: 36);
    final content = _plain(post.content, max: 72);
    final sorted = [...comments]..sort((a, b) => b.likes.compareTo(a.likes));
    final hot = sorted
        .where((c) => _plain(c.content, max: 200).trim().isNotEmpty)
        .take(2)
        .map((c) => '${c.floor}楼${_plain(c.content, max: 36)}')
        .join('；');

    final bits = <String>[];
    if (title.isNotEmpty) bits.add('《$title》');
    if (content.isNotEmpty) bits.add(content);
    if (hot.isNotEmpty) bits.add('热评$hot');
    return bits.isEmpty ? '无标题帖' : bits.join('·');
  }

  static String _plain(String raw, {int? max}) {
    var text = raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (max != null && text.length > max) {
      text = '${text.substring(0, max)}…';
    }
    return text;
  }

  static String _clip(String raw, int max) {
    final text = raw.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    _dirty = true;
    await _persist();
  }
}
