import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 省流模式：降低图片质量、减少 API 批量与预加载。
class DataSaverService extends ChangeNotifier {
  DataSaverService._();

  static final DataSaverService instance = DataSaverService._();

  static const _prefKey = 'data_saver_enabled';

  bool _enabled = false;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}
