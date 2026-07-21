import '../services/tieba_account_service.dart';

/// 吧名分区键：数字 → 0-9，拉丁字母 → A-Z，汉字 → 首字，其余 → #。
String forumSectionKey(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '#';
  final char = trimmed[0];
  final code = char.codeUnitAt(0);
  if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
    return char.toUpperCase();
  }
  if (code >= 0x30 && code <= 0x39) return '0-9';
  if (code > 0x7F) return char;
  return '#';
}

int _sectionKeyRank(String key) {
  if (key == '0-9') return 0;
  if (key.length == 1) {
    final code = key.codeUnitAt(0);
    if (code >= 0x41 && code <= 0x5A) return 100 + code;
  }
  if (key == '#') return 2000;
  return 500 + key.codeUnitAt(0);
}

int compareForumSectionKeys(String a, String b) {
  final rank = _sectionKeyRank(a).compareTo(_sectionKeyRank(b));
  if (rank != 0) return rank;
  return a.compareTo(b);
}

Map<String, List<FollowedBar>> groupFollowedBarsBySection(
  List<FollowedBar> bars,
) {
  final grouped = <String, List<FollowedBar>>{};
  for (final bar in bars) {
    grouped.putIfAbsent(forumSectionKey(bar.name), () => []).add(bar);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.name.compareTo(b.name));
  }
  return grouped;
}

List<String> sortedForumSectionKeys(Map<String, List<FollowedBar>> grouped) {
  return grouped.keys.toList()..sort(compareForumSectionKeys);
}

List<FollowedBar> filterFollowedBars(List<FollowedBar> bars, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return bars;
  return bars.where((b) => b.name.toLowerCase().contains(q)).toList();
}

List<FollowedBar> recentFollowedBars({
  required List<String> recentNames,
  required List<FollowedBar> followed,
}) {
  if (recentNames.isEmpty || followed.isEmpty) return const [];
  final byName = {for (final bar in followed) bar.name: bar};
  final out = <FollowedBar>[];
  for (final name in recentNames) {
    final bar = byName[name];
    if (bar != null) out.add(bar);
  }
  return out;
}

String formatForumCount(dynamic raw) {
  final value = switch (raw) {
    int v => v,
    num v => v.toInt(),
    _ => int.tryParse(raw?.toString() ?? ''),
  };
  if (value == null || value <= 0) return '';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return value.toString();
}
