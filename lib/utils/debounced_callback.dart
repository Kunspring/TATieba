import 'dart:async';

import 'package:flutter/scheduler.dart';

/// 合并短时间内的多次调用，只执行最后一次。
class DebouncedCallback {
  DebouncedCallback({
    required this.callback,
    this.delay = const Duration(milliseconds: 32),
  });

  final VoidCallback callback;
  final Duration delay;

  Timer? _timer;
  bool _frameScheduled = false;

  void call() {
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  void _run() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      callback();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _frameScheduled = false;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _frameScheduled = false;
  }
}
