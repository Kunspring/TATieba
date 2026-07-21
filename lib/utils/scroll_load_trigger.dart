import 'dart:async';

import 'package:flutter/material.dart';

import 'app_lifecycle_gate.dart';

/// 滚动接近底部时触发加载，带节流与重复触发保护。
class ScrollLoadTrigger {
  ScrollLoadTrigger({
    required this.onNearEnd,
    this.threshold = 400,
    this.throttle = const Duration(milliseconds: 400),
  });

  final VoidCallback onNearEnd;
  final double threshold;
  final Duration throttle;

  ScrollController? _controller;
  Timer? _throttleTimer;
  bool _nearEndArmed = true;
  bool _pendingCheck = false;
  bool _frameCheckScheduled = false;

  void attach(ScrollController controller) {
    if (_controller == controller) return;
    detach();
    _controller = controller;
    controller.addListener(_onScroll);
  }

  void detach() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _controller?.removeListener(_onScroll);
    _controller = null;
    _pendingCheck = false;
  }

  void reset() {
    _nearEndArmed = true;
  }

  /// 列表变短或刚加载完一页后，补一次检测（仅一帧）。
  void checkAfterLayout() {
    if (!AppLifecycleGate.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller?.hasClients ?? false) {
        _evaluate();
      }
    });
  }

  void _onScroll() {
    if (!AppLifecycleGate.isActive) return;
    if (_frameCheckScheduled) return;
    _frameCheckScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _frameCheckScheduled = false;
      _scheduleThrottledEvaluate();
    });
  }

  void _scheduleThrottledEvaluate() {
    if (_throttleTimer?.isActive ?? false) {
      _pendingCheck = true;
      return;
    }
    _evaluate();
    _throttleTimer = Timer(throttle, () {
      if (_pendingCheck) {
        _pendingCheck = false;
        _evaluate();
      }
    });
  }

  void _evaluate() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;

    final nearEnd = position.extentAfter < threshold;
    if (nearEnd && _nearEndArmed) {
      _nearEndArmed = false;
      onNearEnd();
    } else if (!nearEnd) {
      _nearEndArmed = true;
    }
  }

  void dispose() {
    detach();
  }
}
