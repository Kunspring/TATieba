import 'dart:async';

import 'package:flutter/services.dart';

/// 监听音量减键（Android 原生拦截 + Flutter 键盘兜底）。
class VolumeKeyService {
  VolumeKeyService._();

  static const _channel = EventChannel('tieba_app/volume_down');
  static const _dedupeWindow = Duration(milliseconds: 320);

  static DateTime? _lastVolumeDownAt;

  static Stream<void> get volumeDownStream =>
      _channel.receiveBroadcastStream().map((_) {});

  static bool handleVolumeDownKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.audioVolumeDown) return false;
    return true;
  }

  /// 原生通道与 [HardwareKeyboard] 可能同时上报，去重后返回 true 表示应处理。
  static bool consumeVolumeDownEvent() {
    final now = DateTime.now();
    final last = _lastVolumeDownAt;
    if (last != null && now.difference(last) < _dedupeWindow) {
      return false;
    }
    _lastVolumeDownAt = now;
    return true;
  }
}
