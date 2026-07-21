enum AgentResultType {
  bars,
  posts,
  postDetail,
  favorites,
  error,
  webSearch,
  art,
}

class AgentResultItem {
  final String? tid;
  final String? title;
  final String? barName;
  final String? author;
  final int? replyCount;
  final String? content;
  final String? avatar;
  final String? url;
  final int? floor;
  final bool hasVideo;
  final List<AgentResultItem> comments;
  final int? artWidth;
  final int? artHeight;
  final List<String>? artPixels;

  const AgentResultItem({
    this.tid,
    this.title,
    this.barName,
    this.author,
    this.replyCount,
    this.content,
    this.avatar,
    this.url,
    this.floor,
    this.hasVideo = false,
    this.comments = const [],
    this.artWidth,
    this.artHeight,
    this.artPixels,
  });

  Map<String, dynamic> toJson() => {
    if (tid != null) 'tid': tid,
    if (title != null) 'title': title,
    if (barName != null) 'bar_name': barName,
    if (author != null) 'author': author,
    if (replyCount != null) 'reply_count': replyCount,
    if (content != null) 'content': content,
    if (avatar != null) 'avatar': avatar,
    if (url != null) 'url': url,
    if (floor != null) 'floor': floor,
    if (hasVideo) 'has_video': true,
    if (comments.isNotEmpty)
      'comments': comments.map((c) => c.toJson()).toList(),
    if (artWidth != null) 'art_width': artWidth,
    if (artHeight != null) 'art_height': artHeight,
    if (artPixels != null && artPixels!.isNotEmpty) 'art_pixels': artPixels,
  };

  factory AgentResultItem.fromJson(Map<String, dynamic> json) {
    return AgentResultItem(
      tid: json['tid']?.toString(),
      title: json['title']?.toString(),
      barName: json['bar_name']?.toString(),
      author: json['author']?.toString(),
      replyCount: _parseInt(json['reply_count']),
      content: json['content']?.toString(),
      avatar: json['avatar']?.toString(),
      url: json['url']?.toString(),
      floor: _parseInt(json['floor']),
      hasVideo: json['has_video'] == true || json['has_video'] == 1,
      comments:
          (json['comments'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => AgentResultItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
      artWidth: _parseInt(json['art_width']),
      artHeight: _parseInt(json['art_height']),
      artPixels: (json['art_pixels'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}

class AgentResultBlock {
  final AgentResultType type;
  final String label;
  final List<AgentResultItem> items;

  const AgentResultBlock({
    required this.type,
    required this.label,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'label': label,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory AgentResultBlock.fromJson(Map<String, dynamic> json) {
    return AgentResultBlock(
      type: AgentResultType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AgentResultType.posts,
      ),
      label: json['label']?.toString() ?? '',
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => AgentResultItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
    );
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
