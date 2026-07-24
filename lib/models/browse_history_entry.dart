class BrowseHistoryEntry {
  final String tid;
  final String title;
  final String barName;
  final String author;
  final String? authorAvatar;
  final String? cover;
  final DateTime viewedAt;

  const BrowseHistoryEntry({
    required this.tid,
    required this.title,
    required this.barName,
    required this.author,
    this.authorAvatar,
    this.cover,
    required this.viewedAt,
  });

  Map<String, dynamic> toJson() => {
        'tid': tid,
        'title': title,
        'bar_name': barName,
        'author': author,
        if (authorAvatar != null) 'author_avatar': authorAvatar,
        if (cover != null) 'cover': cover,
        'viewed_at': viewedAt.toIso8601String(),
      };

  factory BrowseHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BrowseHistoryEntry(
      tid: json['tid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      barName: json['bar_name']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      authorAvatar: json['author_avatar']?.toString(),
      cover: json['cover']?.toString(),
      viewedAt: DateTime.tryParse(json['viewed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  BrowseHistoryEntry copyWith({DateTime? viewedAt}) {
    return BrowseHistoryEntry(
      tid: tid,
      title: title,
      barName: barName,
      author: author,
      authorAvatar: authorAvatar,
      cover: cover,
      viewedAt: viewedAt ?? this.viewedAt,
    );
  }
}
