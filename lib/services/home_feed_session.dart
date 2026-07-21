import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tieba_post.dart';

Map<String, dynamic> _decodeHomeFeedJson(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

String _encodeHomeFeedJson(Map<String, dynamic> json) => jsonEncode(json);

class HomeFeedSnapshot {
  final List<TiebaPost> posts;
  final bool hasMore;
  final int barPage;
  final double scrollOffset;
  final Map<String, dynamic>? crawlerState;

  const HomeFeedSnapshot({
    required this.posts,
    required this.hasMore,
    required this.barPage,
    required this.scrollOffset,
    this.crawlerState,
  });

  factory HomeFeedSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPosts = json['posts'] as List? ?? [];
    return HomeFeedSnapshot(
      posts: rawPosts
          .whereType<Map>()
          .map((e) => TiebaPost.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      hasMore: json['has_more'] != false,
      barPage: json['bar_page'] is int
          ? json['bar_page'] as int
          : int.tryParse(json['bar_page']?.toString() ?? '') ?? 0,
      scrollOffset: json['scroll_offset'] is num
          ? (json['scroll_offset'] as num).toDouble()
          : double.tryParse(json['scroll_offset']?.toString() ?? '') ?? 0,
      crawlerState: json['crawler_state'] is Map
          ? Map<String, dynamic>.from(json['crawler_state'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'posts': posts.map((p) => p.toJson()).toList(),
    'has_more': hasMore,
    'bar_page': barPage,
    'scroll_offset': scrollOffset,
    if (crawlerState != null) 'crawler_state': crawlerState,
  };
}

/// 首页/吧内列表的会话缓存，避免每次打开都重新请求。
class HomeFeedSession {
  HomeFeedSession._();

  static const _prefsPrefix = 'home_feed_v1_';
  static const _persistPostLimit = 20;
  static const _maxMemoryKeys = 8;
  static const _debounceDelay = Duration(seconds: 2);

  static final Map<String, HomeFeedSnapshot> _memory = {};
  static final Map<String, Timer> _debounceTimers = {};
  static final Map<String, HomeFeedSnapshot> _pendingDisk = {};
  static final Set<String> _flushInFlight = {};

  static String _key(String? bar) => bar ?? '__home__';

  static void _evictMemoryIfNeeded() {
    while (_memory.length > _maxMemoryKeys) {
      final oldest = _memory.keys.first;
      _memory.remove(oldest);
      _debounceTimers.remove(oldest)?.cancel();
      _pendingDisk.remove(oldest);
      unawaited(_removeDiskKey(oldest));
    }
  }

  static Future<void> _removeDiskKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$key');
    } catch (_) {}
  }

  static HomeFeedSnapshot? readMemory(String? bar) => _memory[_key(bar)];

  static Future<HomeFeedSnapshot?> load(String? bar) async {
    final key = _key(bar);
    final cached = _memory[key];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsPrefix$key');
    if (raw == null) return null;
    try {
      final decoded = await compute(_decodeHomeFeedJson, raw);
      final snapshot = HomeFeedSnapshot.fromJson(decoded);
      _memory[key] = snapshot;
      _evictMemoryIfNeeded();
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static void save(String? bar, HomeFeedSnapshot snapshot) {
    if (snapshot.posts.isEmpty) return;
    final key = _key(bar);
    final trimmed = HomeFeedSnapshot(
      posts: snapshot.posts.length > _persistPostLimit
          ? snapshot.posts.take(_persistPostLimit).toList()
          : snapshot.posts,
      hasMore: snapshot.hasMore,
      barPage: snapshot.barPage,
      scrollOffset: snapshot.scrollOffset,
      crawlerState: snapshot.crawlerState,
    );
    _memory[key] = trimmed;
    _evictMemoryIfNeeded();
    _pendingDisk[key] = trimmed;
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(_debounceDelay, () {
      _debounceTimers.remove(key);
      unawaited(_persistToDisk(key));
    });
  }

  /// 取消 debounce 并立即落盘（如页面 dispose 时）。
  static Future<void> flush(String? bar) async {
    final key = _key(bar);
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);
    await _persistToDisk(key);
  }

  static Future<void> _persistToDisk(String key) async {
    final snapshot = _pendingDisk.remove(key) ?? _memory[key];
    if (snapshot == null || snapshot.posts.isEmpty) return;
    if (_flushInFlight.contains(key)) {
      _pendingDisk[key] = snapshot;
      return;
    }
    _flushInFlight.add(key);
    try {
      final encoded = await compute(_encodeHomeFeedJson, snapshot.toJson());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$key', encoded);
    } catch (_) {
      _pendingDisk[key] = snapshot;
    } finally {
      _flushInFlight.remove(key);
    }
  }
}
