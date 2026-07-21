import 'agent_result_block.dart';

enum AgentMessageRole { user, assistant, system }

enum AgentAttachmentKind { none, image, file }

class AgentMessage {
  final String id;
  final AgentMessageRole role;
  final String content;
  final DateTime createdAt;
  final bool isError;
  final List<AgentResultBlock> blocks;
  final String? reasoning;
  final List<String> thinkingSteps;
  final int? thinkingDurationMs;
  final String? imageMimeType;
  final String? imageBase64;
  final bool hadImage;
  final AgentAttachmentKind attachmentKind;
  final String? attachmentName;
  final String? attachmentMimeType;
  final String? attachmentExtract;
  final bool hadAttachment;

  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
    this.blocks = const [],
    this.reasoning,
    this.thinkingSteps = const [],
    this.thinkingDurationMs,
    this.imageMimeType,
    this.imageBase64,
    this.hadImage = false,
    this.attachmentKind = AgentAttachmentKind.none,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentExtract,
    this.hadAttachment = false,
  });

  bool get hasThinking =>
      (reasoning != null && reasoning!.trim().isNotEmpty) ||
      thinkingSteps.isNotEmpty;

  bool get hasImage =>
      imageBase64 != null &&
      imageBase64!.isNotEmpty &&
      imageMimeType != null &&
      imageMimeType!.isNotEmpty;

  bool get showImageBubble =>
      attachmentKind == AgentAttachmentKind.image && (hasImage || hadImage);

  bool get showFileBubble =>
      attachmentKind == AgentAttachmentKind.file &&
      ((attachmentName != null && attachmentName!.trim().isNotEmpty) ||
          hadAttachment);

  bool get hasFileAttachment =>
      attachmentKind == AgentAttachmentKind.file &&
      attachmentName != null &&
      attachmentName!.trim().isNotEmpty;

  AgentMessage copyWith({
    String? id,
    AgentMessageRole? role,
    String? content,
    DateTime? createdAt,
    bool? isError,
    List<AgentResultBlock>? blocks,
    String? reasoning,
    List<String>? thinkingSteps,
    int? thinkingDurationMs,
    String? imageMimeType,
    String? imageBase64,
    bool? hadImage,
    AgentAttachmentKind? attachmentKind,
    String? attachmentName,
    String? attachmentMimeType,
    String? attachmentExtract,
    bool? hadAttachment,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isError: isError ?? this.isError,
      blocks: blocks ?? this.blocks,
      reasoning: reasoning ?? this.reasoning,
      thinkingSteps: thinkingSteps ?? this.thinkingSteps,
      thinkingDurationMs: thinkingDurationMs ?? this.thinkingDurationMs,
      imageMimeType: imageMimeType ?? this.imageMimeType,
      imageBase64: imageBase64 ?? this.imageBase64,
      hadImage: hadImage ?? this.hadImage,
      attachmentKind: attachmentKind ?? this.attachmentKind,
      attachmentName: attachmentName ?? this.attachmentName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
      attachmentExtract: attachmentExtract ?? this.attachmentExtract,
      hadAttachment: hadAttachment ?? this.hadAttachment,
    );
  }

  factory AgentMessage.user(String content) {
    return AgentMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: AgentMessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  factory AgentMessage.userWithImage({
    required String content,
    required String imageMimeType,
    required String imageBase64,
  }) {
    return AgentMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: AgentMessageRole.user,
      content: content,
      createdAt: DateTime.now(),
      imageMimeType: imageMimeType,
      imageBase64: imageBase64,
      attachmentKind: AgentAttachmentKind.image,
    );
  }

  factory AgentMessage.userWithFile({
    required String content,
    required String fileName,
    required String mimeType,
    required String extract,
    bool extractOk = true,
    String? extractError,
  }) {
    return AgentMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: AgentMessageRole.user,
      content: content,
      createdAt: DateTime.now(),
      attachmentKind: AgentAttachmentKind.file,
      attachmentName: fileName,
      attachmentMimeType: mimeType,
      attachmentExtract: extractOk
          ? extract
          : (extractError != null ? '[读取失败：$extractError]' : ''),
    );
  }

  factory AgentMessage.assistant(
    String content, {
    bool isError = false,
    List<AgentResultBlock> blocks = const [],
    String? reasoning,
    List<String> thinkingSteps = const [],
    int? thinkingDurationMs,
  }) {
    return AgentMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: AgentMessageRole.assistant,
      content: content,
      createdAt: DateTime.now(),
      isError: isError,
      blocks: blocks,
      reasoning: reasoning,
      thinkingSteps: thinkingSteps,
      thinkingDurationMs: thinkingDurationMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'is_error': isError,
    if (blocks.isNotEmpty) 'blocks': blocks.map((b) => b.toJson()).toList(),
    if (reasoning != null && reasoning!.trim().isNotEmpty)
      'reasoning': reasoning,
    if (thinkingSteps.isNotEmpty) 'thinking_steps': thinkingSteps,
    if (thinkingDurationMs != null) 'thinking_duration_ms': thinkingDurationMs,
    if (imageMimeType != null) 'image_mime_type': imageMimeType,
    if (imageBase64 != null) 'image_base64': imageBase64,
    if (hadImage) 'had_image': true,
    if (attachmentKind != AgentAttachmentKind.none)
      'attachment_kind': attachmentKind.name,
    if (attachmentName != null) 'attachment_name': attachmentName,
    if (attachmentMimeType != null) 'attachment_mime_type': attachmentMimeType,
    if (attachmentExtract != null && attachmentExtract!.isNotEmpty)
      'attachment_extract': attachmentExtract,
    if (hadAttachment) 'had_attachment': true,
  };

  /// 持久化时不写入 base64，避免 SharedPreferences 膨胀导致对话页卡死。
  Map<String, dynamic> toStorageJson() {
    final json = toJson();
    json.remove('image_base64');
    if (hasImage || hadImage) {
      json['had_image'] = true;
    }
    if (attachmentKind == AgentAttachmentKind.file ||
        (attachmentName != null && attachmentName!.isNotEmpty)) {
      json['had_attachment'] = true;
    }
    if (attachmentExtract != null && attachmentExtract!.length > 12000) {
      json['attachment_extract'] = attachmentExtract!.substring(0, 12000);
    }
    return json;
  }

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks
              .whereType<Map>()
              .map(
                (e) => AgentResultBlock.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const <AgentResultBlock>[];
    final rawSteps = json['thinking_steps'];
    final thinkingSteps = rawSteps is List
        ? rawSteps.map((e) => e.toString()).toList()
        : const <String>[];
    return AgentMessage(
      id: json['id']?.toString() ?? '',
      role: AgentMessageRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => AgentMessageRole.assistant,
      ),
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isError: json['is_error'] == true,
      blocks: blocks,
      reasoning: json['reasoning']?.toString(),
      thinkingSteps: thinkingSteps,
      thinkingDurationMs: _parseThinkingDurationMs(
        json['thinking_duration_ms'],
      ),
      imageMimeType: json['image_mime_type']?.toString(),
      imageBase64: _loadImageBase64(json),
      hadImage:
          json['had_image'] == true ||
          (json['image_base64']?.toString().isNotEmpty ?? false),
      attachmentKind: _parseAttachmentKind(json['attachment_kind']),
      attachmentName: json['attachment_name']?.toString(),
      attachmentMimeType: json['attachment_mime_type']?.toString(),
      attachmentExtract: json['attachment_extract']?.toString(),
      hadAttachment:
          json['had_attachment'] == true ||
          json['attachment_kind']?.toString() == 'file',
    );
  }

  static AgentAttachmentKind _parseAttachmentKind(Object? raw) {
    return switch (raw?.toString()) {
      'image' => AgentAttachmentKind.image,
      'file' => AgentAttachmentKind.file,
      _ => AgentAttachmentKind.none,
    };
  }

  static int? _parseThinkingDurationMs(Object? raw) {
    if (raw is int) return raw >= 0 ? raw : null;
    if (raw is num) {
      final value = raw.round();
      return value >= 0 ? value : null;
    }
    return null;
  }

  static String? _loadImageBase64(Map<String, dynamic> json) {
    final raw = json['image_base64']?.toString();
    if (raw == null || raw.isEmpty) return null;
    // 旧版本可能已写入超大 base64，加载时丢弃以免 OOM / 卡死。
    if (raw.length > 200000) return null;
    return raw;
  }
}
