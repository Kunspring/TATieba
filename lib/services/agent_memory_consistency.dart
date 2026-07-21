import '../models/agent_memory_entry.dart';

/// 记忆检索相关性与冲突检测（纯函数，无向量库依赖，低成本可用）。
///
/// 相关性打分组成：查询-内容关键词重叠（主） + 类别权重（profile/fact 略加权）
/// + 新鲜度衰减。冲突检测：同一 slot 且规范化内容不同即视为冲突。
/// 二者共同支撑「长对话/多步骤任务的信息一致性」维度。
abstract final class AgentMemoryConsistency {
  AgentMemoryConsistency._();

  /// 查询与记忆条目的相关性得分（0 表示不相关）。
  static double relevanceScore(String query, AgentMemoryEntry entry) {
    final qTokens = _tokenize(query);
    if (qTokens.isEmpty) return 0;
    final eTokens = _tokenize(entry.content);
    var overlap = 0;
    for (final t in eTokens) {
      if (qTokens.contains(t)) overlap++;
    }
    if (overlap == 0) return 0;

    var score = overlap.toDouble();
    if (entry.category == AgentMemoryCategory.profile) score *= 1.2;
    if (entry.category == AgentMemoryCategory.fact) score *= 1.1;

    final ageDays = DateTime.now().difference(entry.updatedAt).inDays;
    score *= (1 - ageDays.clamp(0, 7) * 0.03);
    return score;
  }

  /// 在已有记忆中找与 candidate 冲突的条目。
  /// 冲突定义：同一 slot 且规范化内容不同。返回第一个冲突条目；无冲突返回 null。
  static AgentMemoryEntry? detectConflict({
    required String content,
    required AgentMemoryCategory category,
    String? slot,
    required List<AgentMemoryEntry> existing,
  }) {
    if (slot == null || slot.isEmpty) return null;
    final norm = _normalize(content);
    for (final e in existing) {
      if (!e.isActive) continue;
      if (e.slot == slot && _normalize(e.content) != norm) return e;
    }
    return null;
  }

  /// 按相关性降序排序，返回前 [limit] 条相关记忆。
  static List<AgentMemoryEntry> rankByRelevance(
    String query,
    List<AgentMemoryEntry> entries, {
    int limit = 10,
  }) {
    final scored =
        entries
            .where((e) => e.isActive)
            .map((e) => MapEntry(e, relevanceScore(query, e)))
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static Set<String> _tokenize(String text) {
    final tokens = <String>{};
    for (final m in RegExp(r'[a-z0-9]{2,}').allMatches(text.toLowerCase())) {
      tokens.add(m.group(0)!);
    }
    final chinese = text.replaceAll(RegExp(r'[^一-龥]'), '');
    for (var i = 0; i + 2 <= chinese.length; i++) {
      tokens.add(chinese.substring(i, i + 2));
    }
    if (chinese.length == 1) tokens.add(chinese);
    return tokens;
  }
}
