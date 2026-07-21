import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 检测设备摇一摇，用于打开 AI 快捷输入。
class ShakeDetectorService {
  ShakeDetectorService._();

  static final ShakeDetectorService instance = ShakeDetectorService._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 单帧加速度变化下限（越大越难误触）。
  static const _shakeDeltaThreshold = 24.0;

  /// 单轴至少要有这么大幅度的变化，且至少两轴同时动。
  static const _minAxisDelta = 9.0;
  static const _minActiveAxes = 2;

  /// 连续有效晃动次数（ deliberate shake 通常 3+ 次振荡）。
  static const _minPeaksRequired = 3;
  static const _peakWindow = Duration(milliseconds: 650);
  static const _minPeakGap = Duration(milliseconds: 75);
  static const _cooldown = Duration(milliseconds: 1800);
  static const _sampleGap = Duration(milliseconds: 48);

  final _controller = StreamController<void>.broadcast();
  StreamSubscription<AccelerometerEvent>? _subscription;
  var _listening = false;
  DateTime? _lastShakeAt;
  DateTime? _lastPeakAt;
  DateTime? _lastSampleAt;
  final List<DateTime> _peakTimes = [];
  double _lastX = 0;
  double _lastY = 0;
  double _lastZ = 0;
  var _hasBaseline = false;

  Stream<void> get onShake => _controller.stream;

  bool get isListening => _listening;

  void pause() {
    if (!_listening) return;
    _subscription?.pause();
  }

  void resume() {
    if (!_listening) return;
    _subscription?.resume();
  }

  void start() {
    if (!supported || _listening) return;
    _listening = true;
    _hasBaseline = false;
    _peakTimes.clear();
    _lastPeakAt = null;
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccelerometer, onError: (_) => stop());
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _listening = false;
    _hasBaseline = false;
    _peakTimes.clear();
    _lastPeakAt = null;
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final now = DateTime.now();
    if (_lastSampleAt != null && now.difference(_lastSampleAt!) < _sampleGap) {
      return;
    }
    _lastSampleAt = now;

    if (!_hasBaseline) {
      _lastX = event.x;
      _lastY = event.y;
      _lastZ = event.z;
      _hasBaseline = true;
      return;
    }

    final dx = (event.x - _lastX).abs();
    final dy = (event.y - _lastY).abs();
    final dz = (event.z - _lastZ).abs();
    _lastX = event.x;
    _lastY = event.y;
    _lastZ = event.z;

    final delta = dx + dy + dz;
    if (delta < _shakeDeltaThreshold) return;

    final activeAxes =
        (dx >= _minAxisDelta ? 1 : 0) +
        (dy >= _minAxisDelta ? 1 : 0) +
        (dz >= _minAxisDelta ? 1 : 0);
    if (activeAxes < _minActiveAxes) return;

    // 过滤重力缓慢倾斜：总加速度仍接近 1g 且只有单轴突变。
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (magnitude < 7 || magnitude > 28) return;

    if (_lastPeakAt != null && now.difference(_lastPeakAt!) < _minPeakGap) {
      return;
    }
    _lastPeakAt = now;

    _peakTimes.add(now);
    _peakTimes.removeWhere((t) => now.difference(t) > _peakWindow);
    if (_peakTimes.length < _minPeaksRequired) return;

    if (_lastShakeAt != null && now.difference(_lastShakeAt!) < _cooldown) {
      return;
    }

    _lastShakeAt = now;
    _peakTimes.clear();
    _lastPeakAt = null;
    _controller.add(null);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
