import 'package:flutter/material.dart';

/// 仅双指捏合时触发缩放，单指拖动不参与手势竞技场，避免与滚动/翻页冲突。
class TwoFingerScaleDetector extends StatefulWidget {
  final Widget child;
  final double scale;
  final ValueChanged<double> onScaleChanged;
  final double minScale;
  final double maxScale;

  const TwoFingerScaleDetector({
    super.key,
    required this.child,
    required this.scale,
    required this.onScaleChanged,
    this.minScale = 0.8,
    this.maxScale = 2.5,
  });

  @override
  State<TwoFingerScaleDetector> createState() => _TwoFingerScaleDetectorState();
}

class _TwoFingerScaleDetectorState extends State<TwoFingerScaleDetector> {
  final Map<int, Offset> _pointers = {};
  double? _initialDistance;
  double _baseScale = 1.0;
  double _lastNotifiedScale = 1.0;
  DateTime? _lastNotifyAt;

  static const _notifyScaleEpsilon = 0.03;
  static const _notifyMinGap = Duration(milliseconds: 48);

  double get _currentDistance {
    final points = _pointers.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  void _beginPinch() {
    _initialDistance = _currentDistance;
    _baseScale = widget.scale;
  }

  void _resetPinch() {
    _initialDistance = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _beginPinch();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (_pointers.length < 2) return;

    final distance = _currentDistance;
    if (distance <= 0) return;

    _initialDistance ??= distance;
    final ratio = distance / _initialDistance!;
    final next = (_baseScale * ratio).clamp(widget.minScale, widget.maxScale);
    final now = DateTime.now();
    if ((next - _lastNotifiedScale).abs() < _notifyScaleEpsilon &&
        _lastNotifyAt != null &&
        now.difference(_lastNotifyAt!) < _notifyMinGap) {
      return;
    }
    _lastNotifiedScale = next;
    _lastNotifyAt = now;
    widget.onScaleChanged(next);
  }

  void _handlePointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2) {
      _resetPinch();
    } else {
      _beginPinch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (event) => _handlePointerUp(event.pointer),
      onPointerCancel: (event) => _handlePointerUp(event.pointer),
      child: widget.child,
    );
  }
}
