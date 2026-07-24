import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/browse_history_entry.dart';
import '../models/tieba_post.dart';

class BrowseHistoryService {
  BrowseHistoryService._();

  static final BrowseHistoryService instance = BrowseHistoryService._();

  static const _prefKey = 'browse_history_v1';
  static const _maxStored = 100;

  final List<BrowseHistoryEntry> _entries = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list.whereType<Map>()) {
          final entry = BrowseHistoryEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (entry.tid.isNotEmpty) _entries.add(entry);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _entries.map((e) => e.toJson()).toList();
    await prefs.setString(_prefKey, jsonEncode(payload));
  }

  Future<void> recordView(TiebaPost post) async {
    if (post.id.isEmpty) return;
    await _ensureLoaded();

    final existingIndex = _entries.indexWhere((e) => e.tid == post.id);
    if (existingIndex >= 0) {
      _entries.removeAt(existingIndex);
    }

    _entries.insert(
      0,
      BrowseHistoryEntry(
        tid: post.id,
        title: post.title,
        barName: post.barName,
        author: post.author,
        authorAvatar: post.authorAvatar,
        cover: post.cover,
        viewedAt: DateTime.now(),
      ),
    );

    while (_entries.length > _maxStored) {
      _entries.removeLast();
    }

    await _persist();
  }

  Future<List<BrowseHistoryEntry>> getEntries() async {
    await _ensureLoaded();
    return List.unmodifiable(_entries);
  }

  Future<void> removeEntry(String tid) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.tid == tid);
    await _persist();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    await _persist();
  }
}
