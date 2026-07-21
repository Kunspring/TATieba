import 'package:shared_preferences/shared_preferences.dart';

/// 最近进入的吧（进吧页「最近」分区与排序参考）。
class ForumRecentService {
  ForumRecentService._();

  static const _prefKey = 'forum_recent_visits_v1';
  static const maxCount = 16;

  static Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_prefKey) ?? const []);
  }

  static Future<void> recordVisit(String barName) async {
    final name = barName.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = List<String>.from(
      prefs.getStringList(_prefKey) ?? const [],
    );
    current.remove(name);
    current.insert(0, name);
    if (current.length > maxCount) {
      current.removeRange(maxCount, current.length);
    }
    await prefs.setStringList(_prefKey, current);
  }
}
