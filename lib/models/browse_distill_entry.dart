class BrowseDistillEntry {
  final String tid;
  final String title;
  final String barName;
  final String localHook;
  final String? llmHook;
  final DateTime viewedAt;
  final int dwellMs;

  const BrowseDistillEntry({
    required this.tid,
    required this.title,
    required this.barName,
    required this.localHook,
    this.llmHook,
    required this.viewedAt,
    this.dwellMs = 0,
  });

  String get hook =>
      (llmHook?.trim().isNotEmpty == true) ? llmHook!.trim() : localHook;

  bool get rich => localHook.length > title.length + 8;

  bool needsLlmPolish(DateTime now) {
    if (!rich || llmHook?.isNotEmpty == true) return false;
    return now.difference(viewedAt).inHours < 48;
  }

  Map<String, dynamic> toJson() => {
    'tid': tid,
    'title': title,
    'bar_name': barName,
    'local_hook': localHook,
    if (llmHook != null) 'llm_hook': llmHook,
    'viewed_at': viewedAt.toIso8601String(),
    'dwell_ms': dwellMs,
  };

  factory BrowseDistillEntry.fromJson(Map<String, dynamic> json) {
    return BrowseDistillEntry(
      tid: json['tid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      barName: json['bar_name']?.toString() ?? '',
      localHook: json['local_hook']?.toString() ?? '',
      llmHook: json['llm_hook']?.toString(),
      viewedAt:
          DateTime.tryParse(json['viewed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dwellMs: json['dwell_ms'] is int
          ? json['dwell_ms'] as int
          : int.tryParse(json['dwell_ms']?.toString() ?? '') ?? 0,
    );
  }

  BrowseDistillEntry copyWith({
    String? localHook,
    String? llmHook,
    DateTime? viewedAt,
    int? dwellMs,
  }) {
    return BrowseDistillEntry(
      tid: tid,
      title: title,
      barName: barName,
      localHook: localHook ?? this.localHook,
      llmHook: llmHook ?? this.llmHook,
      viewedAt: viewedAt ?? this.viewedAt,
      dwellMs: dwellMs ?? this.dwellMs,
    );
  }
}
