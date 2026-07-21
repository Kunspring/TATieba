enum AgentMemoryCategory {
  habit,
  preference,
  emphasis,
  fact,
  profile,
  emotional,
}

extension AgentMemoryCategoryLabel on AgentMemoryCategory {
  String get label => switch (this) {
    AgentMemoryCategory.habit => '习惯',
    AgentMemoryCategory.preference => '偏好',
    AgentMemoryCategory.emphasis => '强调',
    AgentMemoryCategory.fact => '事实',
    AgentMemoryCategory.profile => '个人信息',
    AgentMemoryCategory.emotional => '情感',
  };

  static AgentMemoryCategory? parse(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'habit' || '习惯' => AgentMemoryCategory.habit,
      'preference' || '偏好' || '喜欢' => AgentMemoryCategory.preference,
      'emphasis' || '强调' || '雷区' => AgentMemoryCategory.emphasis,
      'fact' || '事实' => AgentMemoryCategory.fact,
      'profile' || '个人信息' || '个人' => AgentMemoryCategory.profile,
      'emotional' || '情感' || '情绪' => AgentMemoryCategory.emotional,
      _ => null,
    };
  }
}

class AgentMemoryEntry {
  final String id;
  final String content;
  final AgentMemoryCategory category;
  final int importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int hitCount;

  /// 0~100，越高越可信；≤0 视为已作废，不注入 prompt。
  final int confidence;

  /// 个人信息槽位，如 birthday / age / location，用于冲突合并。
  final String? slot;

  const AgentMemoryEntry({
    required this.id,
    required this.content,
    required this.category,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
    this.hitCount = 0,
    this.confidence = 70,
    this.slot,
  });

  bool get isActive => confidence > 0;

  String get trustHint {
    if (confidence >= 85) return '较可信';
    if (confidence >= 55) return '一般';
    return '存疑';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'category': category.name,
    'importance': importance,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'hit_count': hitCount,
    'confidence': confidence,
    if (slot != null && slot!.isNotEmpty) 'slot': slot,
  };

  factory AgentMemoryEntry.fromJson(Map<String, dynamic> json) {
    return AgentMemoryEntry(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      category: AgentMemoryCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => AgentMemoryCategory.fact,
      ),
      importance: json['importance'] is int
          ? json['importance'] as int
          : int.tryParse(json['importance']?.toString() ?? '') ?? 2,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      hitCount: json['hit_count'] is int
          ? json['hit_count'] as int
          : int.tryParse(json['hit_count']?.toString() ?? '') ?? 0,
      confidence: json['confidence'] is int
          ? (json['confidence'] as int).clamp(0, 100)
          : int.tryParse(json['confidence']?.toString() ?? '')?.clamp(0, 100) ??
                70,
      slot: json['slot']?.toString(),
    );
  }

  AgentMemoryEntry copyWith({
    String? content,
    AgentMemoryCategory? category,
    int? importance,
    DateTime? updatedAt,
    int? hitCount,
    int? confidence,
    String? slot,
  }) {
    return AgentMemoryEntry(
      id: id,
      content: content ?? this.content,
      category: category ?? this.category,
      importance: importance ?? this.importance,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hitCount: hitCount ?? this.hitCount,
      confidence: confidence ?? this.confidence,
      slot: slot ?? this.slot,
    );
  }
}
