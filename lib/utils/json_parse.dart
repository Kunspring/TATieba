String? parseOptionalString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  if (value is Map) {
    for (final key in const [
      'url',
      'path',
      'avatar',
      'filename',
      'thumb',
      'cover_thumb',
      'cover',
      'name',
      'nickname',
    ]) {
      final nested = value[key];
      if (nested is String && nested.isNotEmpty) return nested;
    }
  }
  return null;
}

int? parseOptionalInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> parseStringList(dynamic value) {
  if (value is! List) return [];
  return value
      .map((e) => parseOptionalString(e) ?? e?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toList();
}

String? parseAvatarFromMap(Map<String, dynamic> avatars, String key) {
  if (key.isEmpty) return null;
  return parseOptionalString(avatars[key]);
}

String? parseCommentField(dynamic value) {
  final direct = parseOptionalString(value);
  if (direct != null) return direct;
  if (value is Map) {
    for (final key in const [
      'text',
      'quote',
      'selectedText',
      'snippet',
      'id',
      'anchor',
    ]) {
      final nested = parseOptionalString(value[key]);
      if (nested != null) return nested;
    }
  }
  return null;
}
