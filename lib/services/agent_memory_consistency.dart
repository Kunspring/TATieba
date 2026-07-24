import '../models/agent_memory_entry.dart';

/// 记忆检索相关性与冲突检测。
///
/// 相关性打分：BM25 风格的关键词加权 + 类别权重 + 新鲜度衰减。
/// 中文使用 trigram 分词保证精度，英文使用 2-gram 前缀匹配。
/// 冲突检测：同一 slot 且规范化内容不同即视为冲突。
abstract final class AgentMemoryConsistency {
  AgentMemoryConsistency._();

  // ── 相关性 ───────────────────────────────────────────────

  /// 为所有活跃记忆建立倒排索引，计算 IDF 加权得分。
  static double relevanceScore(String query, AgentMemoryEntry entry) {
    return _relevanceScore(query, entry, _emptyIdf());
  }

  /// 批量打分：先对整个记忆库建 IDF，再逐条算分（更准确）。
  static List<AgentMemoryEntry> rankByRelevance(
    String query,
    List<AgentMemoryEntry> entries, {
    int limit = 10,
  }) {
    final active = entries.where((e) => e.isActive).toList();
    if (active.isEmpty) return [];

    final idf = _buildIdf(active);
    final scored = active
        .map((e) => MapEntry(e, _relevanceScore(query, e, idf)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  static double _relevanceScore(
    String query,
    AgentMemoryEntry entry,
    Map<String, double> idf,
  ) {
    final qTokens = _tokenize(query);
    if (qTokens.isEmpty) return 0;

    final eTokens = _tokenize(entry.content);
    if (eTokens.isEmpty) return 0;

    // BM25 风格：每个命中 token 的权重 = IDF * (词频在内容中的占比)
    var score = 0.0;
    final eTokenCounts = _countTokens(eTokens);
    final eLen = eTokens.length;

    for (final t in qTokens) {
      final tf = eTokenCounts[t] ?? 0;
      if (tf == 0) continue;
      final idfVal = idf[t] ?? _smoothIdf(1, 1); // 不在索引中的视为 IDF≈1
      // TF component: saturated term frequency
      final tfNorm = tf / (tf + 1.5 + 0.5 * eLen / _avgDocLen);
      score += idfVal * tfNorm;
    }

    if (score == 0) return 0;

    // 类别加权
    score *= switch (entry.category) {
      AgentMemoryCategory.profile => 1.25,
      AgentMemoryCategory.fact => 1.15,
      AgentMemoryCategory.emphasis => 1.10,
      _ => 1.0,
    };

    // 置信度加权
    score *= (0.6 + entry.confidence / 250); // 0.6~1.0

    // 新鲜度衰减（7天窗口）
    final ageDays = DateTime.now().difference(entry.updatedAt).inHours / 24;
    score *= (1 - ageDays.clamp(0, 14) * 0.025);

    return score;
  }

  static const _avgDocLen = 5.0; // 平均每条记忆 ~5 个 token

  static double _smoothIdf(int docCount, int docFreq) {
    return (1 + docCount - docFreq + 0.5) / (docFreq + 0.5);
  }

  static Map<String, double> _buildIdf(List<AgentMemoryEntry> entries) {
    final docFreq = <String, int>{};
    var docCount = 0;
    for (final e in entries) {
      if (!e.isActive) continue;
      docCount++;
      final seen = <String>{};
      for (final t in _tokenize(e.content)) {
        if (seen.add(t)) {
          docFreq[t] = (docFreq[t] ?? 0) + 1;
        }
      }
    }
    final idf = <String, double>{};
    for (final entry in docFreq.entries) {
      idf[entry.key] = _smoothIdf(docCount, entry.value);
    }
    return idf;
  }

  static Map<String, double> _emptyIdf() => {};

  static Map<String, int> _countTokens(List<String> tokens) {
    final counts = <String, int>{};
    for (final t in tokens) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }

  // ── 分词 ─────────────────────────────────────────────────

  static List<String> _tokenize(String text) {
    final tokens = <String>[];
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return tokens;

    // 英文 / 数字：2-gram 前缀
    final alphaNumRe = RegExp(r'[a-z0-9]+');
    for (final m in alphaNumRe.allMatches(lower)) {
      final word = m.group(0)!;
      if (word.length <= 2) {
        tokens.add(word);
      } else {
        // 前缀 3-gram 保证部分匹配
        for (var i = 0; i + 3 <= word.length; i++) {
          tokens.add(word.substring(i, i + 3));
        }
        if (word.length % 3 != 0) {
          tokens.add(word.substring(word.length - 3));
        }
      }
    }

    // 中文：trigram 为主 + bigram 兜底
    final chinese = text.replaceAll(RegExp(r'[^一-龥]'), '');
    if (chinese.length == 1) {
      tokens.add(chinese);
    } else if (chinese.length == 2) {
      tokens.add(chinese);
    } else {
      for (var i = 0; i + 3 <= chinese.length; i++) {
        tokens.add(chinese.substring(i, i + 3));
      }
      // 尾部 bigram 兜底
      if (chinese.length % 3 != 0 && chinese.length >= 2) {
        tokens.add(chinese.substring(chinese.length - 2));
      }
    }

    return tokens;
  }

  // ── 冲突检测 ─────────────────────────────────────────────

  /// 在已有记忆中找与 candidate 冲突的条目。
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

  // ── 语义分组 ─────────────────────────────────────────────

  /// 将相关记忆归组，方便上下文注入时避免碎片化。
  static List<List<AgentMemoryEntry>> groupRelated(
    String query,
    List<AgentMemoryEntry> entries, {
    int maxGroups = 3,
    int perGroup = 3,
  }) {
    final ranked = rankByRelevance(query, entries, limit: maxGroups * perGroup);
    if (ranked.isEmpty) return [];

    final groups = <List<AgentMemoryEntry>>[];
    final used = <int>{};

    for (var i = 0; i < ranked.length && groups.length < maxGroups; i++) {
      if (used.contains(i)) continue;
      final group = <AgentMemoryEntry>[ranked[i]];
      used.add(i);

      for (var j = i + 1; j < ranked.length && group.length < perGroup; j++) {
        if (used.contains(j)) continue;
        if (ranked[i].category == ranked[j].category ||
            ranked[i].slot == ranked[j].slot) {
          group.add(ranked[j]);
          used.add(j);
        }
      }
      groups.add(group);
    }

    return groups;
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
